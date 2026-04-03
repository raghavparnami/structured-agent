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
        tables, columns, foreign_keys, join_paths = self._expand_via_graph(tables, columns, combined_query)

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

        # Take tables above threshold — use a generous initial limit so the
        # Steiner tree has enough candidates to discover bridge tables.
        # Final trimming happens after Steiner tree + FK expansion.
        threshold = 0.25
        # Allow up to 2x max_tables as candidates for Steiner tree
        candidate_limit = self.config.max_tables_in_context * 2
        result = [t for score, t in scored if score > threshold][:candidate_limit]

        # Always include at least top 3
        if len(result) < 3 and scored:
            result = [t for _, t in scored[:3]]

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
        self, tables: list[TableNode], columns: list[ColumnNode], query_text: str = ""
    ) -> tuple[list[TableNode], list[ColumnNode], list[ForeignKey], list[str]]:
        """Expand context by traversing graph edges — find join paths."""
        query_lower = query_text.lower()
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

        # Auto-include FK neighbors using two process-driven strategies:
        #
        # Strategy A: If the question asks for names/labels/descriptions and a
        # selected table has an FK to a lookup table that has a "name" column,
        # include that lookup table. This is how "operator name" pulls in employee
        # and "line name" pulls in production_line — purely from FK structure.
        #
        # Strategy B: If a selected table FKs to a small reference table (<100 rows),
        # and the question mentions a value that exists in that table's sample_values,
        # include it. This is how "Morning" pulls in shift_type and "India" pulls
        # in country — from the value catalog, not hardcoded aliases.

        query_words = set(re.findall(r'\b\w+\b', query_lower))
        # Detect if question asks for names/labels/who
        wants_names = bool(query_words & {
            "name", "names", "who", "whom", "person", "people",
            "operator", "supervisor", "analyst", "manager", "owner",
        })

        for u, v, edge_data in self.graph.edges(data=True):
            if edge_data.get("relation") != "FOREIGN_KEY":
                continue
            fk: ForeignKey = edge_data.get("data")
            if not fk:
                continue

            # Only consider FKs FROM selected tables TO unselected tables
            if fk.source_table not in table_names or fk.target_table in table_names:
                continue

            target_node = self._get_table_node(fk.target_table)
            if not target_node:
                continue

            target_cols = self._get_table_columns(fk.target_table)
            target_col_names = {c.name.lower() for c in target_cols}
            should_include = False

            # Strategy A: question wants names and target has a name-like column
            if wants_names and target_col_names & {"name", "first_name", "last_name", "title", "full_name"}:
                should_include = True

            # Strategy B: target is a small lookup and question mentions one of its values
            if not should_include and target_node.row_count < 100:
                for col in target_cols:
                    if col.sample_values:
                        for val in col.sample_values:
                            val_lower = val.lower()
                            # Check if any query word matches a sample value
                            if len(val_lower) >= 3 and val_lower in query_lower:
                                should_include = True
                                break
                    if should_include:
                        break

            # Strategy C: FK column name contains a word from the question
            # e.g., batch.line_id and question mentions "line"
            if not should_include:
                fk_col_words = set(fk.source_column.lower().replace("_id", "").replace("_", " ").split())
                if fk_col_words & query_words:
                    should_include = True

            if should_include:
                tables.append(target_node)
                table_names.add(fk.target_table)
                columns.extend(target_cols)
                foreign_keys.append(fk)
                join_paths.append(f"JOIN {fk.target_table} ON {fk.join_sql}")

        # ── Bridge Table Auto-Discovery via Steiner Tree ─────────────
        #
        # Problem: given selected "terminal" tables {raw_material, batch,
        # scrap_event}, find the minimum-cost subgraph connecting ALL of
        # them simultaneously. Bridge/junction tables like batch_material_usage
        # emerge as "Steiner vertices" — intermediate nodes needed for
        # connectivity.
        #
        # Algorithm: KMB (Kou-Markowsky-Berman) 2-approximation
        #   1. Build weighted undirected table graph (hub tables get high weight)
        #   2. Compute metric closure on terminal nodes (shortest path between
        #      every pair of terminals)
        #   3. Find MST of the metric closure
        #   4. Expand MST edges back to original paths → Steiner vertices are
        #      the bridge tables
        #
        # Complexity: O(|T|² × |V|) where T=terminals, V=all tables
        # For 10 terminals, 119 tables: ~12,000 ops — instant.

        if len(tables) > 1:
            # Step 1: Build weighted undirected table graph
            table_graph = nx.Graph()
            raw_edges = []
            for u, v, ed in self.graph.edges(data=True):
                if ed.get("relation") == "JOINS_TO":
                    t1_name = u.split(":", 1)[1] if u.startswith("table:") else None
                    t2_name = v.split(":", 1)[1] if v.startswith("table:") else None
                    if t1_name and t2_name:
                        raw_edges.append((t1_name, t2_name))

            # Weight edges by degree: high-degree hub tables (unit_of_measure,
            # employee) get heavy weight → Steiner tree avoids routing through them
            degree: dict[str, int] = {}
            for t1_name, t2_name in raw_edges:
                degree[t1_name] = degree.get(t1_name, 0) + 1
                degree[t2_name] = degree.get(t2_name, 0) + 1

            for t1_name, t2_name in raw_edges:
                w = min(degree.get(t1_name, 1), 20) + min(degree.get(t2_name, 1), 20)
                if table_graph.has_edge(t1_name, t2_name):
                    w = min(w, table_graph[t1_name][t2_name]["weight"])
                table_graph.add_edge(t1_name, t2_name, weight=w)

            # Step 2: KMB Steiner Tree approximation
            # Terminal nodes = selected tables that exist in the table graph
            terminals = [t for t in table_names if t in table_graph]

            if len(terminals) >= 2:
                steiner_vertices = self._steiner_tree_kmb(table_graph, terminals)

                # Step 3: Add discovered Steiner vertices (bridge tables)
                for tname in steiner_vertices:
                    if tname not in table_names:
                        bridge = self._get_table_node(tname)
                        if bridge:
                            tables.append(bridge)
                            table_names.add(tname)
                            bridge_cols = self._get_table_columns(tname)
                            columns.extend(bridge_cols)

            # Step 3: Now collect ALL FK edges between the final set of tables
            # (including newly added bridges)
            foreign_keys = []
            join_paths = []
            seen_fks: set[tuple[str, str, str, str]] = set()

            for u, v, ed in self.graph.edges(data=True):
                if ed.get("relation") == "FOREIGN_KEY":
                    fk_obj: ForeignKey = ed.get("data")
                    if not fk_obj:
                        continue
                    if fk_obj.source_table in table_names and fk_obj.target_table in table_names:
                        fk_key = (fk_obj.source_table, fk_obj.source_column,
                                  fk_obj.target_table, fk_obj.target_column)
                        if fk_key not in seen_fks:
                            seen_fks.add(fk_key)
                            foreign_keys.append(fk_obj)
                            join_paths.append(
                                f"JOIN {fk_obj.target_table} ON {fk_obj.join_sql}"
                            )

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

        Three matching strategies:
        1. Exact: sample value appears in question ("Morning" in "Morning shift")
        2. Substring: query word is a prefix/substring of sample ("US" matches "US-01",
           "Paracetamol" matches "Paracetamol 500mg Tablets")
        3. Fuzzy: high SequenceMatcher ratio (>0.8) for close misspellings
        """
        matches: dict[str, list[str]] = {}
        query_lower = query_text.lower()
        query_words = set(re.findall(r'\b\w+\b', query_lower))

        # Also extract multi-word phrases (bigrams) for compound names
        words_list = re.findall(r'\b\w+\b', query_lower)
        query_phrases = set(query_words)
        for i in range(len(words_list) - 1):
            query_phrases.add(f"{words_list[i]} {words_list[i+1]}")
        for i in range(len(words_list) - 2):
            query_phrases.add(f"{words_list[i]} {words_list[i+1]} {words_list[i+2]}")

        def _add_match(col_fullname: str, val: str):
            if col_fullname not in matches:
                matches[col_fullname] = []
            if val not in matches[col_fullname]:
                matches[col_fullname].append(val)

        for col in columns:
            if not col.sample_values:
                continue
            if col.distinct_count > 50:
                continue

            key = col.full_name

            for sample_val in col.sample_values:
                sample_lower = sample_val.lower()

                # Strategy 1: Exact — sample appears in question
                if sample_lower in query_lower:
                    _add_match(key, sample_val)
                    continue

                # Strategy 2: Substring — query word/phrase is a prefix or
                # significant substring of the sample value
                matched = False
                for phrase in query_phrases:
                    if len(phrase) < 3:
                        continue
                    # Query phrase starts the sample: "Paracetamol" → "Paracetamol 500mg Tablets"
                    if sample_lower.startswith(phrase):
                        _add_match(key, sample_val)
                        matched = True
                        break
                    # Query phrase is a significant word in the sample
                    if phrase in sample_lower and len(phrase) >= len(sample_lower) * 0.3:
                        _add_match(key, sample_val)
                        matched = True
                        break
                if matched:
                    continue

                # Strategy 3: Fuzzy — close string match for typos/variations
                for qword in query_words:
                    if len(qword) < 3:
                        continue
                    ratio = SequenceMatcher(None, qword, sample_lower).ratio()
                    if ratio > 0.8:
                        _add_match(key, sample_val)
                        break

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
        Budget scales up for complex queries (more tables = more budget).
        """
        base_budget = self.config.max_context_tokens
        # Scale budget: +500 tokens for every table beyond 4
        extra = max(0, len(ctx.tables) - 4) * 500
        budget = min(base_budget + extra, self.config.max_total_prompt_tokens)
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

    def _steiner_tree_kmb(
        self, graph: nx.Graph, terminals: list[str]
    ) -> set[str]:
        """
        KMB 2-approximation for the Steiner tree problem.

        Given a weighted graph and a set of terminal nodes, find the
        minimum-cost set of intermediate (Steiner) vertices needed to
        connect all terminals.

        Algorithm:
        1. Compute shortest paths between all pairs of terminals
        2. Build a complete "metric closure" graph on terminals
        3. Find MST of the metric closure
        4. Expand MST edges back to original graph paths
        5. Return all non-terminal nodes on those paths (= Steiner vertices)

        Returns set of Steiner vertex names (bridge table names).
        """
        if len(terminals) < 2:
            return set()

        # Step 1: Compute shortest paths between all terminal pairs
        # Cache shortest paths from each terminal
        shortest_paths: dict[str, dict[str, list[str]]] = {}
        shortest_dists: dict[str, dict[str, float]] = {}

        for t in terminals:
            try:
                shortest_dists[t] = nx.single_source_dijkstra_path_length(
                    graph, t, weight="weight"
                )
                shortest_paths[t] = nx.single_source_dijkstra_path(
                    graph, t, weight="weight"
                )
            except nx.NodeNotFound:
                continue

        # Step 2: Build metric closure — complete graph on terminals
        metric_closure = nx.Graph()
        for i, t1 in enumerate(terminals):
            if t1 not in shortest_dists:
                continue
            for t2 in terminals[i + 1:]:
                if t2 in shortest_dists[t1]:
                    metric_closure.add_edge(
                        t1, t2,
                        weight=shortest_dists[t1][t2],
                        path=shortest_paths[t1][t2],
                    )

        if metric_closure.number_of_edges() == 0:
            return set()

        # Step 3: MST of metric closure
        try:
            mst = nx.minimum_spanning_tree(metric_closure, weight="weight")
        except Exception:
            return set()

        # Step 4: Expand MST edges back to original paths, collect Steiner vertices
        steiner_vertices: set[str] = set()
        terminal_set = set(terminals)

        for u, v, data in mst.edges(data=True):
            path = data.get("path", [])
            for node in path:
                if node not in terminal_set:
                    steiner_vertices.add(node)

        logger.info(
            f"Steiner tree: {len(terminals)} terminals → "
            f"{len(steiner_vertices)} bridge tables: {steiner_vertices}"
        )
        return steiner_vertices

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
