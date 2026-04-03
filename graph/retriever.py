"""
GraphRAG Retriever: Schema linking + value matching + few-shot retrieval.

This is the core accuracy driver. It:
1. Embeds the user question
2. Finds relevant tables/columns via embedding similarity
3. Expands context via graph traversal (join paths, related columns)
4. Fuzzy matches user terms against the value catalog
5. Matches business terms
6. Retrieves similar few-shot examples
"""

from __future__ import annotations

import logging
import re
from concurrent.futures import ThreadPoolExecutor, as_completed
from difflib import SequenceMatcher
from typing import Any

import networkx as nx

from config import AgentConfig
from core.llm_provider import LLMProvider, cosine_similarity
from core.models import (
    BusinessTerm,
    ColumnNode,
    FewShotExample,
    ForeignKey,
    QueryPattern,
    RetrievedContext,
    TableNode,
)

logger = logging.getLogger(__name__)


class GraphRetriever:
    def __init__(
        self,
        graph: nx.DiGraph,
        llm: LLMProvider,
        config: AgentConfig,
        few_shot_store: list[FewShotExample] | None = None,
    ):
        self.graph = graph
        self.llm = llm
        self.config = config
        self.few_shot_store = few_shot_store or []

    def retrieve(self, question: str, sub_questions: list[str] | None = None) -> RetrievedContext:
        """
        Main retrieval pipeline: schema linking + value matching + few-shot.

        Parallelization strategy:
        - Steps 1-3 are sequential (each depends on previous)
        - Steps 4, 5, 6, 7 are independent — run in parallel via ThreadPool
        """
        all_questions = [question] + (sub_questions or [])
        combined_query = " ".join(all_questions)

        # Embed the question
        query_embedding = self.llm.embed_single(combined_query)

        # Phase 1: Sequential — schema linking (each step depends on previous)
        tables = self._find_relevant_tables(query_embedding, combined_query)
        columns = self._find_relevant_columns(tables, query_embedding, combined_query)
        tables, columns, foreign_keys, join_paths = self._expand_via_graph(tables, columns)

        # Phase 2: Parallel — independent matching tasks
        business_terms = []
        value_matches = {}
        query_patterns = []
        few_shot_examples = []

        with ThreadPoolExecutor(max_workers=4) as pool:
            future_terms = pool.submit(self._match_business_terms, query_embedding, combined_query)
            future_values = pool.submit(self._fuzzy_match_values, combined_query, columns)
            future_patterns = pool.submit(self._match_query_patterns, query_embedding)
            future_fewshot = pool.submit(self._retrieve_few_shot, query_embedding)

            business_terms = future_terms.result()
            value_matches = future_values.result()
            query_patterns = future_patterns.result()
            few_shot_examples = future_fewshot.result()

        # Add tables required by matched business terms
        for bt in business_terms:
            for table_name in bt.tables_involved:
                existing_names = {t.name for t in tables}
                if table_name not in existing_names:
                    table_node = self._get_table_node(table_name)
                    if table_node:
                        tables.append(table_node)
                        table_cols = self._get_table_columns(table_name)
                        columns.extend(table_cols)

        ctx = RetrievedContext(
            tables=tables,
            columns=columns,
            foreign_keys=foreign_keys,
            join_paths=join_paths,
            business_terms=business_terms,
            query_patterns=query_patterns,
            few_shot_examples=few_shot_examples,
            value_matches=value_matches,
        )

        # Trim to fit token budget
        ctx = self.trim_context_to_budget(ctx)
        return ctx

    # ── Step 1: Table Retrieval ───────────────────────────────────

    def _find_relevant_tables(
        self, query_embedding: list[float], query_text: str
    ) -> list[TableNode]:
        """Find tables relevant to the query using embedding + keyword matching."""
        table_nodes = [
            (node_id, data["data"])
            for node_id, data in self.graph.nodes(data=True)
            if data.get("type") == "table"
        ]

        scored: list[tuple[float, TableNode]] = []
        query_lower = query_text.lower()

        for node_id, table in table_nodes:
            # Embedding similarity
            emb_score = 0.0
            if table.embedding:
                emb_score = cosine_similarity(query_embedding, table.embedding)

            # Keyword matching bonus: table name appears in question
            keyword_score = 0.0
            table_name_lower = table.name.lower().replace("_", " ")
            if table_name_lower in query_lower or table.name.lower() in query_lower:
                keyword_score = 0.3
            # Partial match
            elif any(word in query_lower for word in table_name_lower.split()):
                keyword_score = 0.15

            # Description keyword match
            if table.description:
                desc_words = set(table.description.lower().split())
                query_words = set(query_lower.split())
                overlap = len(desc_words & query_words) / max(len(query_words), 1)
                keyword_score = max(keyword_score, overlap * 0.2)

            combined = emb_score * 0.7 + keyword_score * 0.3
            scored.append((combined, table))

        scored.sort(key=lambda x: x[0], reverse=True)

        # Take top N tables above threshold
        threshold = 0.3
        max_tables = self.config.max_tables_in_context
        result = [t for score, t in scored if score > threshold][:max_tables]

        # Always include at least top 2
        if len(result) < 2 and scored:
            result = [t for _, t in scored[:2]]

        logger.info(f"Retrieved {len(result)} relevant tables: {[t.name for t in result]}")
        return result

    # ── Step 2: Column Retrieval ──────────────────────────────────

    def _find_relevant_columns(
        self,
        tables: list[TableNode],
        query_embedding: list[float],
        query_text: str,
    ) -> list[ColumnNode]:
        """Get columns from matched tables, ranked by relevance."""
        table_names = {t.name for t in tables}
        all_columns: list[ColumnNode] = []

        for node_id, data in self.graph.nodes(data=True):
            if data.get("type") == "column":
                col: ColumnNode = data["data"]
                if col.table_name in table_names:
                    all_columns.append(col)

        # Score columns by relevance
        query_lower = query_text.lower()
        scored: list[tuple[float, ColumnNode]] = []

        for col in all_columns:
            score = 0.0

            # Embedding similarity
            if col.embedding:
                score = cosine_similarity(query_embedding, col.embedding) * 0.5

            # Keyword match
            col_name_clean = col.name.lower().replace("_", " ")
            if col_name_clean in query_lower or col.name.lower() in query_lower:
                score += 0.4

            # PK/FK always included
            if col.is_primary_key or col.is_foreign_key:
                score += 0.2

            scored.append((score, col))

        scored.sort(key=lambda x: x[0], reverse=True)

        # Include all PKs/FKs plus top scoring columns per table
        result = []
        per_table_count: dict[str, int] = {}
        max_per_table = self.config.max_columns_per_table

        # First pass: PKs and FKs
        for _, col in scored:
            if col.is_primary_key or col.is_foreign_key:
                result.append(col)
                per_table_count[col.table_name] = per_table_count.get(col.table_name, 0) + 1

        # Second pass: top relevant columns
        for _, col in scored:
            if col not in result:
                count = per_table_count.get(col.table_name, 0)
                if count < max_per_table:
                    result.append(col)
                    per_table_count[col.table_name] = count + 1

        return result

    # ── Step 3: Graph Expansion ───────────────────────────────────

    def _expand_via_graph(
        self, tables: list[TableNode], columns: list[ColumnNode]
    ) -> tuple[list[TableNode], list[ColumnNode], list[ForeignKey], list[str]]:
        """Expand context by traversing graph edges — find join paths."""
        table_names = {t.name for t in tables}
        foreign_keys: list[ForeignKey] = []
        join_paths: list[str] = []

        # Find all FK edges between the selected tables
        for u, v, edge_data in self.graph.edges(data=True):
            if edge_data.get("relation") == "FOREIGN_KEY":
                fk: ForeignKey = edge_data.get("data")
                if fk and fk.source_table in table_names and fk.target_table in table_names:
                    foreign_keys.append(fk)
                    join_paths.append(
                        f"JOIN {fk.target_table} ON {fk.join_sql}"
                    )

        # If we have disconnected tables, try to find bridge tables
        if len(tables) > 1:
            for t1 in tables:
                for t2 in tables:
                    if t1.name != t2.name:
                        # Check if there's a path in the graph
                        try:
                            path = nx.shortest_path(
                                self.graph,
                                f"table:{t1.name}",
                                f"table:{t2.name}",
                            )
                            # Add intermediate tables
                            for node_id in path:
                                if node_id.startswith("table:"):
                                    tname = node_id.split(":", 1)[1]
                                    if tname not in table_names:
                                        bridge = self._get_table_node(tname)
                                        if bridge:
                                            tables.append(bridge)
                                            table_names.add(tname)
                                            bridge_cols = self._get_table_columns(tname)
                                            columns.extend(bridge_cols)
                                            # Add FKs for bridge
                                            for uu, vv, ed in self.graph.edges(data=True):
                                                if ed.get("relation") == "FOREIGN_KEY":
                                                    fk2 = ed.get("data")
                                                    if fk2 and (
                                                        fk2.source_table == tname
                                                        or fk2.target_table == tname
                                                    ):
                                                        if fk2 not in foreign_keys:
                                                            foreign_keys.append(fk2)
                                                            join_paths.append(
                                                                f"JOIN {fk2.target_table} ON {fk2.join_sql}"
                                                            )
                        except (nx.NetworkXNoPath, nx.NodeNotFound):
                            pass

        return tables, columns, foreign_keys, join_paths

    # ── Step 4: Business Term Matching ────────────────────────────

    def _match_business_terms(
        self, query_embedding: list[float], query_text: str
    ) -> list[BusinessTerm]:
        """Find business terms relevant to the question."""
        term_nodes = [
            data["data"]
            for _, data in self.graph.nodes(data=True)
            if data.get("type") == "business_term"
        ]

        scored: list[tuple[float, BusinessTerm]] = []
        query_lower = query_text.lower()

        for bt in term_nodes:
            # Exact match
            if bt.term.lower() in query_lower:
                scored.append((1.0, bt))
                continue

            # Embedding similarity
            emb_score = 0.0
            if bt.embedding:
                emb_score = cosine_similarity(query_embedding, bt.embedding)

            # Fuzzy string match on term
            fuzzy_score = SequenceMatcher(None, bt.term.lower(), query_lower).ratio() * 0.5

            combined = max(emb_score, fuzzy_score)
            if combined > 0.5:
                scored.append((combined, bt))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [bt for _, bt in scored[:10]]

    # ── Step 5: Value Catalog Fuzzy Matching ──────────────────────

    def _fuzzy_match_values(
        self, query_text: str, columns: list[ColumnNode]
    ) -> dict[str, list[str]]:
        """
        Match terms in the question against column sample values.
        This is critical for filters like "enterprise" → customer_tier = 'Enterprise'.
        """
        matches: dict[str, list[str]] = {}
        query_lower = query_text.lower()

        # Extract potential filter terms from the question
        # (words/phrases that might be enum values)
        query_words = set(re.findall(r'\b\w+\b', query_lower))

        for col in columns:
            if not col.sample_values:
                continue

            # Only fuzzy match on low-cardinality columns (likely enums)
            if col.distinct_count > 50:
                continue

            for sample_val in col.sample_values:
                sample_lower = sample_val.lower()

                # Exact match
                if sample_lower in query_lower:
                    key = f"{col.full_name}"
                    if key not in matches:
                        matches[key] = []
                    if sample_val not in matches[key]:
                        matches[key].append(sample_val)
                    continue

                # Fuzzy match for each query word
                for qword in query_words:
                    if len(qword) < 3:
                        continue
                    ratio = SequenceMatcher(None, qword, sample_lower).ratio()
                    if ratio > 0.8:
                        key = f"{col.full_name}"
                        if key not in matches:
                            matches[key] = []
                        if sample_val not in matches[key]:
                            matches[key].append(sample_val)

        return matches

    # ── Step 6: Query Pattern Matching ────────────────────────────

    def _match_query_patterns(self, query_embedding: list[float]) -> list[QueryPattern]:
        """Find relevant query patterns."""
        pattern_nodes = [
            data["data"]
            for _, data in self.graph.nodes(data=True)
            if data.get("type") == "query_pattern"
        ]

        scored: list[tuple[float, QueryPattern]] = []
        for qp in pattern_nodes:
            if qp.embedding:
                score = cosine_similarity(query_embedding, qp.embedding)
                if score > 0.5:
                    scored.append((score, qp))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [qp for _, qp in scored[:3]]

    # ── Step 7: Few-Shot Retrieval (Token-Budget Aware) ─────────

    def _retrieve_few_shot(self, query_embedding: list[float]) -> list[FewShotExample]:
        """
        Retrieve similar past question-SQL pairs, respecting token budget.

        Instead of blindly taking top-N, we:
        1. Rank by similarity
        2. Add examples one-by-one until token budget is exhausted
        3. Prefer verified examples over unverified
        4. Prefer shorter SQL (same info, fewer tokens)
        """
        if not self.few_shot_store:
            return []

        scored: list[tuple[float, FewShotExample]] = []
        for ex in self.few_shot_store:
            if ex.embedding:
                score = cosine_similarity(query_embedding, ex.embedding)
                if score > self.config.few_shot_similarity_threshold:
                    # Boost verified examples
                    boost = 0.05 if ex.verified else 0.0
                    scored.append((score + boost, ex))

        scored.sort(key=lambda x: x[0], reverse=True)

        # Fill within token budget
        token_budget = self.config.max_few_shot_tokens
        max_examples = self.config.max_few_shot_examples
        selected: list[FewShotExample] = []
        tokens_used = 0

        for _, ex in scored:
            if len(selected) >= max_examples:
                break
            # Estimate tokens: ~4 chars per token
            ex_tokens = (len(ex.question) + len(ex.sql)) // 4 + 20  # 20 for formatting
            if tokens_used + ex_tokens > token_budget:
                continue  # skip this one, try a shorter one
            selected.append(ex)
            tokens_used += ex_tokens

        return selected

    # ── Token Budget for Context ──────────────────────────────────

    def trim_context_to_budget(self, ctx: RetrievedContext) -> RetrievedContext:
        """
        Trim the retrieved context to fit within token budget.
        Priority: tables > columns > FKs > business terms > patterns.
        """
        budget = self.config.max_context_tokens
        tokens_used = 0

        def estimate_tokens(text: str) -> int:
            return len(text) // 4

        # Tables are always included (most critical)
        # but trim columns per table if over budget
        for table in ctx.tables:
            tokens_used += estimate_tokens(
                f"TABLE: {table.name} {table.description}"
            )

        # Columns — keep PKs/FKs, then top relevant until budget
        essential_cols = [c for c in ctx.columns if c.is_primary_key or c.is_foreign_key]
        other_cols = [c for c in ctx.columns if c not in essential_cols]

        kept_columns = list(essential_cols)
        for col in essential_cols:
            tokens_used += estimate_tokens(f"{col.name} {col.data_type}")

        for col in other_cols:
            col_tokens = estimate_tokens(
                f"{col.name} {col.data_type} {' '.join(col.sample_values[:3])}"
            )
            if tokens_used + col_tokens > budget * 0.6:  # 60% budget for schema
                break
            kept_columns.append(col)
            tokens_used += col_tokens

        ctx.columns = kept_columns

        # Business terms — keep up to budget
        kept_terms = []
        for bt in ctx.business_terms:
            bt_tokens = estimate_tokens(f"{bt.term} = {bt.sql_expression}")
            if tokens_used + bt_tokens > budget * 0.85:  # 85% for schema + terms
                break
            kept_terms.append(bt)
            tokens_used += bt_tokens
        ctx.business_terms = kept_terms

        # Query patterns — keep only if budget allows
        kept_patterns = []
        for qp in ctx.query_patterns:
            qp_tokens = estimate_tokens(f"{qp.name} {qp.template_sql}")
            if tokens_used + qp_tokens > budget:
                break
            kept_patterns.append(qp)
            tokens_used += qp_tokens
        ctx.query_patterns = kept_patterns

        return ctx

    # ── Helpers ────────────────────────────────────────────────────

    def _get_table_node(self, table_name: str) -> TableNode | None:
        node_id = f"table:{table_name}"
        if node_id in self.graph:
            return self.graph.nodes[node_id].get("data")
        return None

    def _get_table_columns(self, table_name: str) -> list[ColumnNode]:
        cols = []
        for node_id, data in self.graph.nodes(data=True):
            if data.get("type") == "column":
                col: ColumnNode = data["data"]
                if col.table_name == table_name:
                    cols.append(col)
        return cols
