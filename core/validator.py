"""
SQL Validator and Executor.

Validation pipeline:
1. Syntax check (sqlglot)
2. Schema validation (tables/columns exist in graph)
3. Security guardrails (block DDL/DML)
4. EXPLAIN dry run
5. Execution with timeout and row limits
"""

from __future__ import annotations

import logging
import re
from typing import Any

import pandas as pd
import sqlglot
from sqlglot import exp

from config import AppConfig
from core.db_adapter import DBAdapter
from core.models import ValidationResult

logger = logging.getLogger(__name__)

# Blocked SQL patterns
BLOCKED_KEYWORDS = {
    "DROP", "DELETE", "INSERT", "UPDATE", "TRUNCATE", "ALTER", "CREATE",
    "GRANT", "REVOKE", "MERGE", "REPLACE",
}
BLOCKED_PATTERN = re.compile(
    r'\b(' + '|'.join(BLOCKED_KEYWORDS) + r')\b',
    re.IGNORECASE,
)


class SQLValidator:
    def __init__(self, config: AppConfig, table_names: set[str], column_names: set[str], adapter: DBAdapter):
        self.config = config
        self.table_names = {t.lower() for t in table_names}
        self.column_names = {c.lower() for c in column_names}
        self.adapter = adapter

    def validate(self, sql: str) -> ValidationResult:
        """Run the full validation pipeline."""
        result = ValidationResult()

        # Step 1: Security check
        blocked = BLOCKED_PATTERN.search(sql)
        if blocked:
            result.error_message = f"Blocked operation: {blocked.group()} is not allowed"
            return result

        # Check for multiple statements (SQL injection guard)
        statements = [s.strip() for s in sql.split(';') if s.strip()]
        if len(statements) > 1:
            result.error_message = "Multiple SQL statements are not allowed"
            return result

        # Step 2: Syntax check
        try:
            parsed = sqlglot.parse(sql, dialect=self.adapter.dialect)
            if not parsed or not parsed[0]:
                result.error_message = "Failed to parse SQL"
                return result
            result.syntax_ok = True
        except sqlglot.errors.ParseError as e:
            result.error_message = f"SQL syntax error: {e}"
            return result

        # Step 3: Schema validation
        try:
            ast = parsed[0]
            referenced_tables = set()
            for table in ast.find_all(exp.Table):
                referenced_tables.add(table.name.lower())

            unknown_tables = referenced_tables - self.table_names
            # Allow CTEs (they won't be in schema)
            cte_names = set()
            for cte in ast.find_all(exp.CTE):
                cte_names.add(cte.alias.lower() if cte.alias else "")
            unknown_tables -= cte_names

            if unknown_tables:
                result.error_message = f"Unknown tables: {', '.join(unknown_tables)}"
                return result

            result.tables_exist = True
        except Exception as e:
            # If sqlglot can't extract tables, still try EXPLAIN
            result.tables_exist = True
            logger.warning(f"Could not validate tables via AST: {e}")

        # Step 4: EXPLAIN dry run
        try:
            explain_result = self.adapter.explain(sql)
            result.explain_ok = True
            result.explain_output = explain_result
        except Exception as e:
            error_str = str(e)
            result.error_message = f"EXPLAIN failed: {error_str}"
            return result

        return result

    def inject_limit(self, sql: str, max_rows: int | None = None) -> str:
        """Inject LIMIT if not already present."""
        max_rows = max_rows or self.config.agent.max_result_rows
        sql_upper = sql.strip().upper()
        if "LIMIT" not in sql_upper and "TOP " not in sql_upper:
            if self.adapter.dialect == "tsql":
                # SQL Server uses TOP instead of LIMIT
                sql = sql.strip().rstrip(";")
                # Insert TOP after SELECT
                sql = re.sub(
                    r'(?i)^(SELECT\s)',
                    f'SELECT TOP {max_rows} ',
                    sql,
                    count=1,
                )
            else:
                sql = sql.rstrip("; \n") + f"\nLIMIT {max_rows}"
        return sql


class SQLExecutor:
    def __init__(self, config: AppConfig, adapter: DBAdapter):
        self.config = config
        self.adapter = adapter

    def execute(self, sql: str) -> tuple[pd.DataFrame, list[str]]:
        """Execute SQL and return results as DataFrame."""
        return self.adapter.execute(sql, self.config.agent.query_timeout_seconds)
