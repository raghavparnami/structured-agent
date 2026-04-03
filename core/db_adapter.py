"""
Database adapter layer — abstracts PostgreSQL, MySQL, SQL Server, and SQLite
behind a unified interface.
"""

from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from typing import Any

import pandas as pd

logger = logging.getLogger(__name__)


class DBAdapter(ABC):
    """Abstract database adapter."""

    dialect: str  # sqlglot dialect name
    date_functions_hint: str  # hint for LLM prompts

    @abstractmethod
    def connect(self):
        """Return a raw DB-API connection."""

    @abstractmethod
    def test_connection(self) -> bool:
        """Quick connection test. Returns True on success."""

    @abstractmethod
    def get_tables(self, cursor) -> list[dict]:
        """Return [{table_name, table_schema, row_count}, ...]."""

    @abstractmethod
    def get_columns(self, cursor) -> list[dict]:
        """Return [{table_name, column_name, data_type, is_nullable, is_pk}, ...]."""

    @abstractmethod
    def get_foreign_keys(self, cursor) -> list[dict]:
        """Return [{source_table, source_column, target_table, target_column}, ...]."""

    @abstractmethod
    def get_distinct_count(self, cursor, schema: str, table: str, column: str) -> int:
        """Return count of distinct values for a column."""

    @abstractmethod
    def get_sample_values(self, cursor, table: str, column: str, limit: int) -> list[str]:
        """Return sample distinct values as strings."""

    @abstractmethod
    def explain(self, sql: str) -> str:
        """Run an EXPLAIN dry-run and return the plan as text."""

    @abstractmethod
    def execute(self, sql: str, timeout_seconds: int) -> tuple[pd.DataFrame, list[str]]:
        """Execute a query and return (DataFrame, column_names)."""

    def quote_identifier(self, name: str) -> str:
        """Quote a table/column identifier for this dialect."""
        return f'"{name}"'


# ── PostgreSQL ───────────────────────────────────────────────────

class PostgreSQLAdapter(DBAdapter):
    dialect = "postgres"
    date_functions_hint = "Use PostgreSQL functions: DATE_TRUNC, EXTRACT, INTERVAL, CURRENT_DATE"

    def __init__(self, host: str, port: int, database: str, user: str, password: str):
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password

    def connect(self):
        import psycopg2
        return psycopg2.connect(
            host=self.host, port=self.port, database=self.database,
            user=self.user, password=self.password,
        )

    def test_connection(self) -> bool:
        conn = self.connect()
        conn.close()
        return True

    def get_tables(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                t.table_name,
                t.table_schema,
                COALESCE(s.n_live_tup, 0) as row_count
            FROM information_schema.tables t
            LEFT JOIN pg_stat_user_tables s
                ON t.table_name = s.relname
                AND t.table_schema = s.schemaname
            WHERE t.table_schema NOT IN ('pg_catalog', 'information_schema')
                AND t.table_type = 'BASE TABLE'
            ORDER BY t.table_name
        """)
        return [dict(r) for r in cursor.fetchall()]

    def get_columns(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                c.table_name,
                c.column_name,
                c.data_type,
                c.is_nullable,
                CASE WHEN pk.column_name IS NOT NULL THEN true ELSE false END as is_pk
            FROM information_schema.columns c
            LEFT JOIN (
                SELECT kcu.table_name, kcu.column_name
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                WHERE tc.constraint_type = 'PRIMARY KEY'
            ) pk ON c.table_name = pk.table_name AND c.column_name = pk.column_name
            WHERE c.table_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY c.table_name, c.ordinal_position
        """)
        return [dict(r) for r in cursor.fetchall()]

    def get_foreign_keys(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                kcu.table_name AS source_table,
                kcu.column_name AS source_column,
                ccu.table_name AS target_table,
                ccu.column_name AS target_column
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
            JOIN information_schema.constraint_column_usage ccu
                ON tc.constraint_name = ccu.constraint_name
            WHERE tc.constraint_type = 'FOREIGN KEY'
                AND tc.table_schema NOT IN ('pg_catalog', 'information_schema')
        """)
        return [dict(r) for r in cursor.fetchall()]

    def get_distinct_count(self, cursor, schema: str, table: str, column: str) -> int:
        cursor.execute(f'SELECT COUNT(DISTINCT "{column}") FROM "{schema}"."{table}"')
        result = cursor.fetchone()
        return result["count"] if result else 0

    def get_sample_values(self, cursor, table: str, column: str, limit: int) -> list[str]:
        cursor.execute(
            f'SELECT DISTINCT "{column}"::text FROM "{table}" '
            f'WHERE "{column}" IS NOT NULL ORDER BY 1 LIMIT %s',
            (limit,),
        )
        return [row[0] for row in cursor.fetchall()]

    def explain(self, sql: str) -> str:
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                cur.execute(f"EXPLAIN {sql}")
                return "\n".join(row[0] for row in cur.fetchall())
        finally:
            conn.close()

    def execute(self, sql: str, timeout_seconds: int) -> tuple[pd.DataFrame, list[str]]:
        import psycopg2
        import psycopg2.extras
        conn = psycopg2.connect(
            host=self.host, port=self.port, database=self.database,
            user=self.user, password=self.password,
            options=f"-c statement_timeout={timeout_seconds * 1000}",
        )
        try:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(sql)
                rows = cur.fetchall()
                if not rows:
                    return pd.DataFrame(), []
                columns = list(rows[0].keys())
                return pd.DataFrame(rows, columns=columns), columns
        finally:
            conn.close()

    def _dict_cursor(self, conn):
        import psycopg2.extras
        return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


# ── MySQL ────────────────────────────────────────────────────────

class MySQLAdapter(DBAdapter):
    dialect = "mysql"
    date_functions_hint = "Use MySQL functions: DATE_FORMAT, YEAR(), MONTH(), CURDATE(), DATE_SUB(), INTERVAL"

    def __init__(self, host: str, port: int, database: str, user: str, password: str):
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password

    def connect(self):
        import mysql.connector
        return mysql.connector.connect(
            host=self.host, port=self.port, database=self.database,
            user=self.user, password=self.password,
        )

    def test_connection(self) -> bool:
        conn = self.connect()
        conn.close()
        return True

    def get_tables(self, cursor) -> list[dict]:
        cursor.execute(f"""
            SELECT
                t.TABLE_NAME as table_name,
                t.TABLE_SCHEMA as table_schema,
                COALESCE(t.TABLE_ROWS, 0) as row_count
            FROM information_schema.TABLES t
            WHERE t.TABLE_SCHEMA = %s
                AND t.TABLE_TYPE = 'BASE TABLE'
            ORDER BY t.TABLE_NAME
        """, (self.database,))
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_columns(self, cursor) -> list[dict]:
        cursor.execute(f"""
            SELECT
                c.TABLE_NAME as table_name,
                c.COLUMN_NAME as column_name,
                c.DATA_TYPE as data_type,
                c.IS_NULLABLE as is_nullable,
                CASE WHEN c.COLUMN_KEY = 'PRI' THEN 1 ELSE 0 END as is_pk
            FROM information_schema.COLUMNS c
            WHERE c.TABLE_SCHEMA = %s
            ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION
        """, (self.database,))
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_foreign_keys(self, cursor) -> list[dict]:
        cursor.execute(f"""
            SELECT
                kcu.TABLE_NAME AS source_table,
                kcu.COLUMN_NAME AS source_column,
                kcu.REFERENCED_TABLE_NAME AS target_table,
                kcu.REFERENCED_COLUMN_NAME AS target_column
            FROM information_schema.KEY_COLUMN_USAGE kcu
            WHERE kcu.TABLE_SCHEMA = %s
                AND kcu.REFERENCED_TABLE_NAME IS NOT NULL
        """, (self.database,))
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_distinct_count(self, cursor, schema: str, table: str, column: str) -> int:
        cursor.execute(f"SELECT COUNT(DISTINCT `{column}`) as cnt FROM `{table}`")
        row = cursor.fetchone()
        return row[0] if row else 0

    def get_sample_values(self, cursor, table: str, column: str, limit: int) -> list[str]:
        cursor.execute(
            f"SELECT DISTINCT CAST(`{column}` AS CHAR) FROM `{table}` "
            f"WHERE `{column}` IS NOT NULL ORDER BY 1 LIMIT %s",
            (limit,),
        )
        return [str(row[0]) for row in cursor.fetchall()]

    def explain(self, sql: str) -> str:
        conn = self.connect()
        try:
            cur = conn.cursor()
            cur.execute(f"EXPLAIN {sql}")
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            return "\n".join(str(dict(zip(cols, row))) for row in rows)
        finally:
            conn.close()

    def execute(self, sql: str, timeout_seconds: int) -> tuple[pd.DataFrame, list[str]]:
        conn = self.connect()
        try:
            cur = conn.cursor()
            cur.execute(f"SET SESSION MAX_EXECUTION_TIME = {timeout_seconds * 1000}")
            cur.execute(sql)
            rows = cur.fetchall()
            if not rows:
                return pd.DataFrame(), []
            columns = [d[0] for d in cur.description]
            return pd.DataFrame(rows, columns=columns), columns
        finally:
            conn.close()

    def quote_identifier(self, name: str) -> str:
        return f"`{name}`"


# ── SQL Server ───────────────────────────────────────────────────

class SQLServerAdapter(DBAdapter):
    dialect = "tsql"
    date_functions_hint = "Use SQL Server functions: DATEPART, DATEDIFF, DATEADD, GETDATE(), FORMAT, YEAR(), MONTH()"

    def __init__(self, host: str, port: int, database: str, user: str, password: str):
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password = password

    def connect(self):
        import pyodbc
        conn_str = (
            f"DRIVER={{ODBC Driver 18 for SQL Server}};"
            f"SERVER={self.host},{self.port};"
            f"DATABASE={self.database};"
            f"UID={self.user};PWD={self.password};"
            f"TrustServerCertificate=yes"
        )
        return pyodbc.connect(conn_str)

    def test_connection(self) -> bool:
        conn = self.connect()
        conn.close()
        return True

    def get_tables(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                t.TABLE_NAME as table_name,
                t.TABLE_SCHEMA as table_schema,
                COALESCE(p.rows, 0) as row_count
            FROM INFORMATION_SCHEMA.TABLES t
            LEFT JOIN sys.partitions p
                ON OBJECT_ID(t.TABLE_SCHEMA + '.' + t.TABLE_NAME) = p.object_id
                AND p.index_id IN (0, 1)
            WHERE t.TABLE_TYPE = 'BASE TABLE'
                AND t.TABLE_SCHEMA != 'sys'
            ORDER BY t.TABLE_NAME
        """)
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_columns(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                c.TABLE_NAME as table_name,
                c.COLUMN_NAME as column_name,
                c.DATA_TYPE as data_type,
                c.IS_NULLABLE as is_nullable,
                CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END as is_pk
            FROM INFORMATION_SCHEMA.COLUMNS c
            LEFT JOIN (
                SELECT kcu.TABLE_NAME, kcu.COLUMN_NAME
                FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
                JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
                    ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
                WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
            ) pk ON c.TABLE_NAME = pk.TABLE_NAME AND c.COLUMN_NAME = pk.COLUMN_NAME
            WHERE c.TABLE_SCHEMA != 'sys'
            ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION
        """)
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_foreign_keys(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT
                fk_col.TABLE_NAME AS source_table,
                fk_col.COLUMN_NAME AS source_column,
                pk_col.TABLE_NAME AS target_table,
                pk_col.COLUMN_NAME AS target_column
            FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE fk_col
                ON rc.CONSTRAINT_NAME = fk_col.CONSTRAINT_NAME
            JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE pk_col
                ON rc.UNIQUE_CONSTRAINT_NAME = pk_col.CONSTRAINT_NAME
        """)
        cols = [d[0] for d in cursor.description]
        return [dict(zip(cols, row)) for row in cursor.fetchall()]

    def get_distinct_count(self, cursor, schema: str, table: str, column: str) -> int:
        cursor.execute(f"SELECT COUNT(DISTINCT [{column}]) FROM [{schema}].[{table}]")
        row = cursor.fetchone()
        return row[0] if row else 0

    def get_sample_values(self, cursor, table: str, column: str, limit: int) -> list[str]:
        cursor.execute(
            f"SELECT DISTINCT TOP {limit} CAST([{column}] AS NVARCHAR(MAX)) "
            f"FROM [{table}] WHERE [{column}] IS NOT NULL ORDER BY 1"
        )
        return [str(row[0]) for row in cursor.fetchall()]

    def explain(self, sql: str) -> str:
        conn = self.connect()
        try:
            cur = conn.cursor()
            cur.execute(f"SET SHOWPLAN_TEXT ON")
            cur.execute(sql)
            rows = cur.fetchall()
            cur.execute(f"SET SHOWPLAN_TEXT OFF")
            return "\n".join(str(row[0]) for row in rows)
        finally:
            conn.close()

    def execute(self, sql: str, timeout_seconds: int) -> tuple[pd.DataFrame, list[str]]:
        conn = self.connect()
        conn.timeout = timeout_seconds
        try:
            cur = conn.cursor()
            cur.execute(sql)
            rows = cur.fetchall()
            if not rows:
                return pd.DataFrame(), []
            columns = [d[0] for d in cur.description]
            return pd.DataFrame.from_records(rows, columns=columns), columns
        finally:
            conn.close()

    def quote_identifier(self, name: str) -> str:
        return f"[{name}]"


# ── SQLite ───────────────────────────────────────────────────────

class SQLiteAdapter(DBAdapter):
    dialect = "sqlite"
    date_functions_hint = "Use SQLite functions: DATE(), TIME(), DATETIME(), STRFTIME(), 'now', date modifiers like '-30 days'"

    def __init__(self, database: str, **kwargs):
        self.database = database

    def connect(self):
        import sqlite3
        conn = sqlite3.connect(self.database)
        conn.row_factory = sqlite3.Row
        return conn

    def test_connection(self) -> bool:
        conn = self.connect()
        conn.close()
        return True

    def get_tables(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT name as table_name, 'main' as table_schema
            FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """)
        rows = cursor.fetchall()
        result = []
        for row in rows:
            name = row["table_name"] if isinstance(row, dict) else row[0]
            schema = row["table_schema"] if isinstance(row, dict) else row[1]
            # Get row count
            cursor.execute(f'SELECT COUNT(*) as cnt FROM "{name}"')
            cnt_row = cursor.fetchone()
            count = cnt_row["cnt"] if isinstance(cnt_row, dict) else cnt_row[0]
            result.append({"table_name": name, "table_schema": schema, "row_count": count})
        return result

    def get_columns(self, cursor) -> list[dict]:
        # Get all tables first
        cursor.execute("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """)
        tables = [row[0] if not isinstance(row, dict) else row["name"] for row in cursor.fetchall()]

        columns = []
        for table in tables:
            cursor.execute(f"PRAGMA table_info('{table}')")
            for row in cursor.fetchall():
                if isinstance(row, dict):
                    columns.append({
                        "table_name": table,
                        "column_name": row["name"],
                        "data_type": row["type"] or "TEXT",
                        "is_nullable": "YES" if not row["notnull"] else "NO",
                        "is_pk": bool(row["pk"]),
                    })
                else:
                    columns.append({
                        "table_name": table,
                        "column_name": row[1],
                        "data_type": row[2] or "TEXT",
                        "is_nullable": "YES" if not row[3] else "NO",
                        "is_pk": bool(row[5]),
                    })
        return columns

    def get_foreign_keys(self, cursor) -> list[dict]:
        cursor.execute("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        """)
        tables = [row[0] if not isinstance(row, dict) else row["name"] for row in cursor.fetchall()]

        fks = []
        for table in tables:
            cursor.execute(f"PRAGMA foreign_key_list('{table}')")
            for row in cursor.fetchall():
                if isinstance(row, dict):
                    fks.append({
                        "source_table": table,
                        "source_column": row["from"],
                        "target_table": row["table"],
                        "target_column": row["to"],
                    })
                else:
                    fks.append({
                        "source_table": table,
                        "source_column": row[3],
                        "target_table": row[2],
                        "target_column": row[4],
                    })
        return fks

    def get_distinct_count(self, cursor, schema: str, table: str, column: str) -> int:
        cursor.execute(f'SELECT COUNT(DISTINCT "{column}") as cnt FROM "{table}"')
        row = cursor.fetchone()
        if isinstance(row, dict):
            return row.get("cnt", 0)
        return row[0] if row else 0

    def get_sample_values(self, cursor, table: str, column: str, limit: int) -> list[str]:
        cursor.execute(
            f'SELECT DISTINCT CAST("{column}" AS TEXT) FROM "{table}" '
            f'WHERE "{column}" IS NOT NULL ORDER BY 1 LIMIT ?',
            (limit,),
        )
        return [str(row[0]) for row in cursor.fetchall()]

    def explain(self, sql: str) -> str:
        conn = self.connect()
        try:
            cur = conn.cursor()
            cur.execute(f"EXPLAIN QUERY PLAN {sql}")
            rows = cur.fetchall()
            return "\n".join(str(row) for row in rows)
        finally:
            conn.close()

    def execute(self, sql: str, timeout_seconds: int) -> tuple[pd.DataFrame, list[str]]:
        import sqlite3
        conn = sqlite3.connect(self.database, timeout=timeout_seconds)
        conn.row_factory = sqlite3.Row
        try:
            cur = conn.cursor()
            cur.execute(sql)
            rows = cur.fetchall()
            if not rows:
                return pd.DataFrame(), []
            columns = rows[0].keys()
            data = [dict(row) for row in rows]
            return pd.DataFrame(data, columns=columns), list(columns)
        finally:
            conn.close()

    def quote_identifier(self, name: str) -> str:
        return f'"{name}"'


# ── Factory ──────────────────────────────────────────────────────

DB_TYPE_DEFAULTS = {
    "postgresql": {"port": 5432, "driver": "psycopg2-binary"},
    "mysql": {"port": 3306, "driver": "mysql-connector-python"},
    "sqlserver": {"port": 1433, "driver": "pyodbc"},
    "sqlite": {"port": 0, "driver": "sqlite3 (built-in)"},
}


def create_adapter(db_type: str, **kwargs) -> DBAdapter:
    """Factory to create the right adapter based on db_type."""
    if db_type == "postgresql":
        return PostgreSQLAdapter(**kwargs)
    elif db_type == "mysql":
        return MySQLAdapter(**kwargs)
    elif db_type == "sqlserver":
        return SQLServerAdapter(**kwargs)
    elif db_type == "sqlite":
        return SQLiteAdapter(**kwargs)
    else:
        raise ValueError(f"Unsupported database type: {db_type}. Supported: {list(DB_TYPE_DEFAULTS.keys())}")
