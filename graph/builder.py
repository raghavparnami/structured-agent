"""
Graph Builder: Automatically constructs the knowledge graph from a database.

Supports PostgreSQL, MySQL, SQL Server, and SQLite via the DBAdapter layer.

Pipeline:
1. Introspect schema (tables, columns, foreign keys, constraints)
2. Sample values per column (for value catalog / enum matching)
3. Generate descriptions via LLM
4. Generate business terms via LLM
5. Compute embeddings for all nodes
6. Build NetworkX graph with all nodes and edges
"""

from __future__ import annotations

import json
import logging
import os
import pickle
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Any

import networkx as nx

from config import AppConfig
from core.db_adapter import DBAdapter
from core.llm_provider import LLMProvider
from core.models import (
    BusinessTerm,
    ColumnNode,
    ForeignKey,
    QueryPattern,
    TableNode,
)

logger = logging.getLogger(__name__)


class GraphBuilder:
    def __init__(self, config: AppConfig, llm: LLMProvider, adapter: DBAdapter):
        self.config = config
        self.llm = llm
        self.adapter = adapter
        self.tables: list[TableNode] = []
        self.columns: list[ColumnNode] = []
        self.foreign_keys: list[ForeignKey] = []
        self.business_terms: list[BusinessTerm] = []
        self.query_patterns: list[QueryPattern] = []
        self.graph: nx.DiGraph = nx.DiGraph()

    def build(self, progress_callback=None) -> nx.DiGraph:
        """
        Run the full graph build pipeline with parallelism.

        Dependency graph:
          introspect_schema (must be first)
              → sample_values (needs tables/columns)
                  → [descriptions, business_terms, query_patterns] (all independent — run in parallel)
                      → compute_embeddings (needs all nodes)
                          → build_networkx_graph
        """
        step_count = 7
        current_step = [0]  # mutable for closure

        def _progress(msg):
            current_step[0] += 1
            if progress_callback:
                progress_callback(msg, current_step[0] / step_count)
            logger.info(msg)

        # Phase 1: Sequential — DB introspection (needs connection)
        _progress("Introspecting database schema...")
        self._introspect_schema()

        _progress("Sampling column values...")
        self._sample_values()

        # Phase 2: Parallel — LLM calls (all independent, biggest time save)
        _progress("Generating descriptions, business terms & patterns (parallel)...")
        errors = []
        with ThreadPoolExecutor(max_workers=3) as pool:
            futures = {
                pool.submit(self._generate_descriptions): "descriptions",
                pool.submit(self._generate_business_terms): "business_terms",
                pool.submit(self._generate_query_patterns): "query_patterns",
            }
            for future in as_completed(futures):
                name = futures[future]
                try:
                    future.result()
                    logger.info(f"Completed: {name}")
                except Exception as e:
                    logger.error(f"Failed: {name}: {e}")
                    errors.append(f"{name}: {e}")

        if errors:
            logger.warning(f"Some parallel steps had errors: {errors}")

        # Phase 3: Sequential — needs all nodes from phase 2
        _progress("Computing embeddings...")
        self._compute_embeddings()

        _progress("Building graph structure...")
        self._build_networkx_graph()

        if progress_callback:
            progress_callback("Graph build complete!", 1.0)
        return self.graph

    # ── Step 1: Schema Introspection ──────────────────────────────

    def _introspect_schema(self):
        conn = self.adapter.connect()
        try:
            # Use dict cursor for PostgreSQL, regular cursor for others
            if hasattr(self.adapter, '_dict_cursor'):
                cur = self.adapter._dict_cursor(conn)
            else:
                cur = conn.cursor()

            # Get tables
            table_rows = self.adapter.get_tables(cur)
            self.tables = []
            for row in table_rows:
                self.tables.append(TableNode(
                    name=row["table_name"],
                    schema=row.get("table_schema", "public"),
                    row_count=row.get("row_count", 0),
                ))

            # Get columns
            col_rows = self.adapter.get_columns(cur)
            self.columns = []
            for row in col_rows:
                is_nullable = row.get("is_nullable", "YES")
                if isinstance(is_nullable, str):
                    is_nullable = is_nullable.upper() == "YES"
                self.columns.append(ColumnNode(
                    name=row["column_name"],
                    table_name=row["table_name"],
                    data_type=row.get("data_type", "text"),
                    is_primary_key=bool(row.get("is_pk", False)),
                    is_nullable=is_nullable,
                ))

            # Get foreign keys
            fk_rows = self.adapter.get_foreign_keys(cur)
            self.foreign_keys = []
            for row in fk_rows:
                fk = ForeignKey(
                    source_table=row["source_table"],
                    source_column=row["source_column"],
                    target_table=row["target_table"],
                    target_column=row["target_column"],
                )
                self.foreign_keys.append(fk)
                for col in self.columns:
                    if col.table_name == fk.source_table and col.name == fk.source_column:
                        col.is_foreign_key = True

            cur.close()
        finally:
            conn.close()

        # Get distinct counts — parallelized per table (separate connections)
        table_schema_map = {t.name: t.schema for t in self.tables}
        table_columns_map: dict[str, list[ColumnNode]] = {}
        for col in self.columns:
            table_columns_map.setdefault(col.table_name, []).append(col)

        def _count_distinct_for_table(table_name: str, cols: list[ColumnNode]):
            tconn = self.adapter.connect()
            try:
                tcur = tconn.cursor()
                schema = table_schema_map[table_name]
                for col in cols:
                    try:
                        col.distinct_count = self.adapter.get_distinct_count(
                            tcur, schema, table_name, col.name
                        )
                    except Exception:
                        col.distinct_count = 0
                        tconn.rollback()
                tcur.close()
            finally:
                tconn.close()

        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = {
                pool.submit(_count_distinct_for_table, tname, cols): tname
                for tname, cols in table_columns_map.items()
            }
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    logger.warning(f"Distinct count failed for {futures[future]}: {e}")

        # Assign columns to tables
        for table in self.tables:
            table.columns = [c for c in self.columns if c.table_name == table.name]

        logger.info(
            f"Introspected {len(self.tables)} tables, {len(self.columns)} columns, "
            f"{len(self.foreign_keys)} foreign keys"
        )

    # ── Step 2: Sample Values ─────────────────────────────────────

    def _sample_values(self):
        """
        Sample distinct values for each column — critical for value catalog.
        Parallelized: each table's columns are sampled in a separate thread
        with its own DB connection.
        """
        n_samples = self.config.agent.sample_values_per_column

        # Group columns by table
        table_columns: dict[str, list[ColumnNode]] = {}
        for col in self.columns:
            table_columns.setdefault(col.table_name, []).append(col)

        def _sample_table(table_name: str, cols: list[ColumnNode]):
            """Sample all columns for one table using a dedicated connection."""
            conn = self.adapter.connect()
            try:
                cur = conn.cursor()
                for col in cols:
                    try:
                        limit = 50 if col.distinct_count <= 50 else n_samples
                        col.sample_values = self.adapter.get_sample_values(
                            cur, col.table_name, col.name, limit
                        )
                    except Exception:
                        conn.rollback()
                        col.sample_values = []
                cur.close()
            finally:
                conn.close()

        # Run tables in parallel (cap at 8 concurrent connections)
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = {
                pool.submit(_sample_table, tname, cols): tname
                for tname, cols in table_columns.items()
            }
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    logger.warning(f"Failed sampling table {futures[future]}: {e}")

        logger.info("Sampled values for all columns")

    # ── Step 3: Generate Descriptions ─────────────────────────────

    def _generate_descriptions(self):
        """Use LLM to generate human-readable descriptions for tables and columns."""
        schema_text = self._schema_to_text()
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a database documentation expert. Generate clear, concise descriptions "
                    "for each table and column based on the schema and sample values. "
                    "Output valid JSON."
                ),
            },
            {
                "role": "user",
                "content": f"""Analyze this database schema and generate descriptions.

{schema_text}

Return JSON in this exact format:
{{
  "tables": {{
    "table_name": "description of what this table stores",
    ...
  }},
  "columns": {{
    "table_name.column_name": "description of what this column represents",
    ...
  }}
}}

Be specific about business meaning. For example, don't say "stores data" — say "stores customer purchase orders with line items".
Include every table and column.""",
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.fast_model, json_mode=True, stage="description_gen"
        )

        try:
            data = json.loads(response)
            for table in self.tables:
                table.description = data.get("tables", {}).get(table.name, "")
            for col in self.columns:
                key = f"{col.table_name}.{col.name}"
                col.description = data.get("columns", {}).get(key, "")
        except json.JSONDecodeError:
            logger.error("Failed to parse description JSON from LLM")

    # ── Step 4: Generate Business Terms ───────────────────────────

    def _generate_business_terms(self):
        """Use LLM to discover business terms from the schema."""
        schema_text = self._schema_to_text(include_descriptions=True)
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a business intelligence expert. Analyze the database schema and "
                    "identify all business terms, metrics, KPIs, and domain-specific vocabulary "
                    "that users might use when asking questions about this data. "
                    "Map each term to its SQL expression. Output valid JSON."
                ),
            },
            {
                "role": "user",
                "content": f"""Analyze this database schema:

{schema_text}

Generate ALL possible business terms that users might ask about. Include:
1. Metrics and KPIs (revenue, count, average, etc.)
2. Time-based terms (last quarter, YTD, month-over-month, etc.)
3. Status/category terms (active users, churned, enterprise, etc.)
4. Derived concepts (growth rate, retention, conversion, etc.)
5. Common filter terms (recent, top, bottom, etc.)

Return JSON array:
[
  {{
    "term": "the business term as users would say it",
    "sql_expression": "exact SQL expression or WHERE clause",
    "tables_involved": ["table1", "table2"],
    "description": "what this term means in business context"
  }}
]

IMPORTANT:
- Use ONLY tables and columns that exist in the schema above
- For date terms, use {self.adapter.date_functions_hint}
- For metrics, include the aggregation (SUM, COUNT, AVG, etc.)
- Generate at least 15-20 terms
- Be exhaustive — cover every reasonable business term a user might use""",
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.strong_model, json_mode=True, stage="business_term_gen"
        )

        try:
            terms_data = json.loads(response)
            if isinstance(terms_data, dict) and "terms" in terms_data:
                terms_data = terms_data["terms"]
            if not isinstance(terms_data, list):
                terms_data = []

            self.business_terms = []
            for item in terms_data:
                if isinstance(item, dict) and "term" in item and "sql_expression" in item:
                    self.business_terms.append(BusinessTerm(
                        term=item["term"],
                        sql_expression=item["sql_expression"],
                        tables_involved=item.get("tables_involved", []),
                        description=item.get("description", ""),
                        source="auto",
                        confidence=0.8,
                    ))
        except json.JSONDecodeError:
            logger.error("Failed to parse business terms JSON from LLM")
            self.business_terms = []

        logger.info(f"Generated {len(self.business_terms)} business terms")

    # ── Step 5: Generate Query Patterns ───────────────────────────

    def _generate_query_patterns(self):
        """Generate reusable SQL patterns based on the schema."""
        schema_text = self._schema_to_text(include_descriptions=True)
        messages = [
            {
                "role": "system",
                "content": (
                    "You are a SQL expert. Generate reusable query patterns/templates "
                    "for common analytical questions on this database. Output valid JSON."
                ),
            },
            {
                "role": "user",
                "content": f"""Schema:
{schema_text}

Generate reusable SQL query patterns. Examples of pattern types:
- Top N by group (using window functions)
- Year-over-year comparison (using CTEs)
- Running totals / cumulative sums
- Period-over-period growth
- Cohort analysis
- Ranking within categories

Return JSON array:
[
  {{
    "name": "pattern name",
    "description": "when to use this pattern",
    "template_sql": "SQL template with {{placeholders}}",
    "use_case": "example question this pattern answers",
    "tables_involved": ["table1"]
  }}
]

Use ONLY tables/columns from the schema. Generate 5-10 patterns.""",
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.strong_model, json_mode=True, stage="pattern_gen"
        )

        try:
            data = json.loads(response)
            if isinstance(data, dict):
                data = data.get("patterns", data.get("query_patterns", []))
            if not isinstance(data, list):
                data = []

            self.query_patterns = []
            for item in data:
                if isinstance(item, dict) and "name" in item:
                    self.query_patterns.append(QueryPattern(
                        name=item["name"],
                        description=item.get("description", ""),
                        template_sql=item.get("template_sql", ""),
                        use_case=item.get("use_case", ""),
                        tables_involved=item.get("tables_involved", []),
                    ))
        except json.JSONDecodeError:
            logger.error("Failed to parse query patterns from LLM")
            self.query_patterns = []

        logger.info(f"Generated {len(self.query_patterns)} query patterns")

    # ── Step 6: Compute Embeddings ────────────────────────────────

    def _compute_embeddings(self):
        """Compute embeddings for all graph nodes."""
        # Collect all texts to embed in one batch
        texts = []
        sources: list[tuple[str, int]] = []  # (type, index)

        for i, table in enumerate(self.tables):
            text = f"Table: {table.name}. {table.description}. Columns: {', '.join(c.name for c in table.columns)}"
            texts.append(text)
            sources.append(("table", i))

        for i, col in enumerate(self.columns):
            sample_str = f" Values: {', '.join(col.sample_values[:5])}" if col.sample_values else ""
            text = f"Column: {col.full_name} ({col.data_type}). {col.description}.{sample_str}"
            texts.append(text)
            sources.append(("column", i))

        for i, bt in enumerate(self.business_terms):
            text = f"Business term: {bt.term}. {bt.description}. SQL: {bt.sql_expression}"
            texts.append(text)
            sources.append(("business_term", i))

        for i, qp in enumerate(self.query_patterns):
            text = f"Query pattern: {qp.name}. {qp.description}. Use case: {qp.use_case}"
            texts.append(text)
            sources.append(("query_pattern", i))

        if not texts:
            return

        # Batch embed
        embeddings = self.llm.embed(texts)

        # Assign back
        for (src_type, idx), emb in zip(sources, embeddings):
            if src_type == "table":
                self.tables[idx].embedding = emb
            elif src_type == "column":
                self.columns[idx].embedding = emb
            elif src_type == "business_term":
                self.business_terms[idx].embedding = emb
            elif src_type == "query_pattern":
                self.query_patterns[idx].embedding = emb

        logger.info(f"Computed {len(texts)} embeddings")

    # ── Step 7: Build NetworkX Graph ──────────────────────────────

    def _build_networkx_graph(self):
        """Assemble all nodes and edges into a NetworkX graph."""
        G = nx.DiGraph()

        # Table nodes
        for table in self.tables:
            G.add_node(
                f"table:{table.name}",
                type="table",
                data=table,
            )

        # Column nodes
        for col in self.columns:
            G.add_node(
                f"col:{col.full_name}",
                type="column",
                data=col,
            )
            # Edge: table -> column
            G.add_edge(
                f"table:{col.table_name}",
                f"col:{col.full_name}",
                relation="HAS_COLUMN",
            )

        # Foreign key edges
        for fk in self.foreign_keys:
            G.add_edge(
                f"col:{fk.source_table}.{fk.source_column}",
                f"col:{fk.target_table}.{fk.target_column}",
                relation="FOREIGN_KEY",
                data=fk,
            )
            # Table-level join edge
            G.add_edge(
                f"table:{fk.source_table}",
                f"table:{fk.target_table}",
                relation="JOINS_TO",
                join_sql=fk.join_sql,
            )

        # Business term nodes
        for bt in self.business_terms:
            node_id = f"term:{bt.term}"
            G.add_node(node_id, type="business_term", data=bt)
            for table_name in bt.tables_involved:
                if f"table:{table_name}" in G:
                    G.add_edge(node_id, f"table:{table_name}", relation="REQUIRES_TABLE")

        # Query pattern nodes
        for qp in self.query_patterns:
            node_id = f"pattern:{qp.name}"
            G.add_node(node_id, type="query_pattern", data=qp)
            for table_name in qp.tables_involved:
                if f"table:{table_name}" in G:
                    G.add_edge(node_id, f"table:{table_name}", relation="USES_TABLE")

        self.graph = G
        logger.info(
            f"Graph built: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges"
        )

    # ── Helpers ────────────────────────────────────────────────────

    def _schema_to_text(self, include_descriptions: bool = False) -> str:
        """Convert schema to text format for LLM prompts."""
        parts = []
        for table in self.tables:
            desc = f" -- {table.description}" if include_descriptions and table.description else ""
            parts.append(f"\nTABLE: {table.name} (~{table.row_count:,} rows){desc}")

            table_cols = [c for c in self.columns if c.table_name == table.name]
            for col in table_cols:
                flags = []
                if col.is_primary_key:
                    flags.append("PK")
                if col.is_foreign_key:
                    flags.append("FK")
                if not col.is_nullable:
                    flags.append("NOT NULL")
                flag_str = f" [{', '.join(flags)}]" if flags else ""
                sample_str = ""
                if col.sample_values:
                    vals = col.sample_values[:5]
                    sample_str = f"  -- e.g.: {', '.join(str(v) for v in vals)}"
                col_desc = f" -- {col.description}" if include_descriptions and col.description else ""
                parts.append(f"  {col.name} {col.data_type}{flag_str}{col_desc}{sample_str}")

        # Foreign keys
        if self.foreign_keys:
            parts.append("\nFOREIGN KEYS:")
            for fk in self.foreign_keys:
                parts.append(
                    f"  {fk.source_table}.{fk.source_column} -> "
                    f"{fk.target_table}.{fk.target_column}"
                )

        return "\n".join(parts)

    def add_business_term(self, term: BusinessTerm):
        """Add a new business term to the graph (used by feedback loop)."""
        self.business_terms.append(term)

        # Embed the new term
        text = f"Business term: {term.term}. {term.description}. SQL: {term.sql_expression}"
        term.embedding = self.llm.embed_single(text)

        # Add to graph
        node_id = f"term:{term.term}"
        self.graph.add_node(node_id, type="business_term", data=term)
        for table_name in term.tables_involved:
            if f"table:{table_name}" in self.graph:
                self.graph.add_edge(node_id, f"table:{table_name}", relation="REQUIRES_TABLE")

    def add_default_filter(self, table_name: str, filter_sql: str):
        """Add a default filter to a table (used by feedback loop)."""
        for table in self.tables:
            if table.name == table_name:
                if filter_sql not in table.default_filters:
                    table.default_filters.append(filter_sql)
                    # Update graph node
                    node_id = f"table:{table_name}"
                    if node_id in self.graph:
                        self.graph.nodes[node_id]["data"] = table
                break

    # ── Cache: Save / Load ────────────────────────────────────────

    def _cache_path(self) -> str:
        """Return the cache file path based on db name."""
        db_name = self.config.db.database or "default"
        # Sanitize for filename
        safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in db_name)
        cache_dir = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
        os.makedirs(cache_dir, exist_ok=True)
        return os.path.join(cache_dir, f"graph_cache_{safe_name}.pkl")

    def save_cache(self):
        """Save the built graph and all metadata to disk."""
        cache_data = {
            "tables": self.tables,
            "columns": self.columns,
            "foreign_keys": self.foreign_keys,
            "business_terms": self.business_terms,
            "query_patterns": self.query_patterns,
            "graph": self.graph,
        }
        path = self._cache_path()
        with open(path, "wb") as f:
            pickle.dump(cache_data, f)
        logger.info(f"Graph cache saved to {path}")

    def load_cache(self) -> bool:
        """
        Load a previously saved graph from disk.
        Returns True if cache was loaded, False if no cache exists.
        """
        path = self._cache_path()
        if not os.path.exists(path):
            return False

        try:
            with open(path, "rb") as f:
                cache_data = pickle.load(f)
            self.tables = cache_data["tables"]
            self.columns = cache_data["columns"]
            self.foreign_keys = cache_data["foreign_keys"]
            self.business_terms = cache_data["business_terms"]
            self.query_patterns = cache_data["query_patterns"]
            self.graph = cache_data["graph"]
            logger.info(
                f"Graph cache loaded: {len(self.tables)} tables, "
                f"{self.graph.number_of_nodes()} nodes"
            )
            return True
        except Exception as e:
            logger.warning(f"Failed to load graph cache: {e}")
            return False

    def delete_cache(self):
        """Delete the cached graph file."""
        path = self._cache_path()
        if os.path.exists(path):
            os.remove(path)
            logger.info(f"Graph cache deleted: {path}")
