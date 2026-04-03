"""
Feedback Learning System.

Learns from every user interaction:
1. Positive feedback → stores question-SQL pair as verified few-shot example
2. SQL correction → extracts new business terms, updates few-shot store
3. Thumbs down → logs for review, attempts to learn what went wrong
4. Default filter suggestions → adds to graph

All learnings persist to disk (JSON) and are loaded on startup.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import datetime
from typing import Any

from config import AppConfig
from core.llm_provider import LLMProvider
from core.models import (
    AgentContext,
    BusinessTerm,
    FewShotExample,
)
from graph.builder import GraphBuilder
from prompts.templates import TERM_EXTRACTOR_SYSTEM, TERM_EXTRACTOR_USER

logger = logging.getLogger(__name__)

FEEDBACK_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data")
FEW_SHOT_FILE = os.path.join(FEEDBACK_DIR, "few_shot_examples.json")
BUSINESS_TERMS_FILE = os.path.join(FEEDBACK_DIR, "learned_business_terms.json")
FEEDBACK_LOG_FILE = os.path.join(FEEDBACK_DIR, "feedback_log.json")


class FeedbackLearner:
    def __init__(
        self,
        config: AppConfig,
        llm: LLMProvider,
        graph_builder: GraphBuilder,
    ):
        self.config = config
        self.llm = llm
        self.graph_builder = graph_builder
        self.few_shot_store: list[FewShotExample] = []
        self.feedback_log: list[dict] = []

        # Ensure data directory exists
        os.makedirs(FEEDBACK_DIR, exist_ok=True)

        # Load persisted data
        self._load_few_shot_store()
        self._load_feedback_log()

    # ── Public API ────────────────────────────────────────────────

    def on_positive_feedback(self, ctx: AgentContext):
        """User confirmed the result is correct → save as verified few-shot example."""
        example = FewShotExample(
            question=ctx.original_question,
            sql=ctx.generated_sql,
            tables_used=[t.name for t in ctx.retrieved_context.tables],
            verified=True,
        )
        # Embed the example
        example.embedding = self.llm.embed_single(
            f"Question: {example.question}"
        )

        # Check for exact or near-duplicate
        if self._deduplicate_and_store(example):
            logger.info(f"Updated existing few-shot example: {example.question[:50]}")
        else:
            logger.info(f"Saved new few-shot example: {example.question[:50]}")

        # Prune if store is too large
        self._prune_store()

        self._log_feedback("positive", ctx)

    def on_sql_correction(
        self,
        ctx: AgentContext,
        corrected_sql: str,
        explanation: str = "",
    ):
        """User provided a corrected SQL → learn from it."""
        # 1. Save corrected pair as verified few-shot
        example = FewShotExample(
            question=ctx.original_question,
            sql=corrected_sql,
            tables_used=[t.name for t in ctx.retrieved_context.tables],
            verified=True,
        )
        example.embedding = self.llm.embed_single(f"Question: {example.question}")

        # Replace existing or add new
        replaced = False
        for i, existing in enumerate(self.few_shot_store):
            if existing.question.lower().strip() == example.question.lower().strip():
                self.few_shot_store[i] = example
                replaced = True
                break
        if not replaced:
            self.few_shot_store.append(example)
        self._save_few_shot_store()

        # 2. Extract new business terms from the correction
        self._extract_and_learn_terms(ctx, corrected_sql, explanation)

        self._log_feedback("correction", ctx, {
            "corrected_sql": corrected_sql,
            "explanation": explanation,
        })
        logger.info(f"Learned from SQL correction: {ctx.original_question[:50]}")

    def on_negative_feedback(self, ctx: AgentContext, reason: str = ""):
        """User said the result is wrong but didn't provide correction."""
        self._log_feedback("negative", ctx, {"reason": reason})
        logger.info(f"Logged negative feedback: {ctx.original_question[:50]}")

    def on_default_filter_suggestion(self, table_name: str, filter_sql: str):
        """User suggests a default filter for a table."""
        self.graph_builder.add_default_filter(table_name, filter_sql)
        self._log_feedback("default_filter", None, {
            "table_name": table_name,
            "filter_sql": filter_sql,
        })
        logger.info(f"Added default filter for {table_name}: {filter_sql}")

    def on_business_term_correction(
        self,
        term: str,
        sql_expression: str,
        tables_involved: list[str],
        description: str = "",
    ):
        """User directly defines or corrects a business term."""
        bt = BusinessTerm(
            term=term,
            sql_expression=sql_expression,
            tables_involved=tables_involved,
            description=description,
            source="user",
            confidence=1.0,
        )
        self.graph_builder.add_business_term(bt)
        self._save_learned_term(bt)
        logger.info(f"Added user-defined business term: {term}")

    # ── Private: Term Extraction ──────────────────────────────────

    def _extract_and_learn_terms(
        self, ctx: AgentContext, corrected_sql: str, explanation: str
    ):
        """Use LLM to extract business terms from a user's SQL correction."""
        table_names = [
            data["data"].name
            for _, data in self.graph_builder.graph.nodes(data=True)
            if data.get("type") == "table"
        ]

        messages = [
            {"role": "system", "content": TERM_EXTRACTOR_SYSTEM},
            {
                "role": "user",
                "content": TERM_EXTRACTOR_USER.format(
                    question=ctx.original_question,
                    original_sql=ctx.generated_sql,
                    corrected_sql=corrected_sql,
                    explanation=explanation or "No explanation provided",
                    table_names=", ".join(table_names),
                ),
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.fast_model, json_mode=True, stage="term_extraction"
        )

        try:
            data = json.loads(response)

            # Add new business terms
            for term_data in data.get("terms", []):
                if term_data.get("term") and term_data.get("sql_expression"):
                    bt = BusinessTerm(
                        term=term_data["term"],
                        sql_expression=term_data["sql_expression"],
                        tables_involved=term_data.get("tables_involved", []),
                        description=term_data.get("description", ""),
                        source="learned",
                        confidence=0.9,
                    )
                    self.graph_builder.add_business_term(bt)
                    self._save_learned_term(bt)
                    logger.info(f"Learned new business term: {bt.term}")

            # Add default filters
            for filter_data in data.get("default_filters_to_add", []):
                if filter_data.get("table_name") and filter_data.get("filter_sql"):
                    self.graph_builder.add_default_filter(
                        filter_data["table_name"],
                        filter_data["filter_sql"],
                    )
                    logger.info(
                        f"Learned default filter for {filter_data['table_name']}: "
                        f"{filter_data['filter_sql']}"
                    )

        except json.JSONDecodeError:
            logger.warning("Failed to parse term extraction response")

    # ── Deduplication & Pruning ──────────────────────────────────

    def _deduplicate_and_store(self, new_example: FewShotExample) -> bool:
        """
        Check for duplicates before storing. Returns True if merged with existing.

        Dedup strategy:
        1. Exact question match → update SQL
        2. Embedding similarity > 0.95 → merge (keep the one with shorter SQL)
        3. Otherwise → add as new
        """
        from core.llm_provider import cosine_similarity

        threshold = self.config.agent.example_dedup_threshold if hasattr(self.config.agent, 'example_dedup_threshold') else 0.95

        # Exact match
        for existing in self.few_shot_store:
            if existing.question.lower().strip() == new_example.question.lower().strip():
                existing.sql = new_example.sql
                existing.verified = new_example.verified or existing.verified
                existing.embedding = new_example.embedding
                self._save_few_shot_store()
                return True

        # Semantic near-duplicate
        if new_example.embedding:
            for existing in self.few_shot_store:
                if existing.embedding:
                    sim = cosine_similarity(new_example.embedding, existing.embedding)
                    if sim > threshold:
                        # Keep the one with shorter SQL (less tokens)
                        if len(new_example.sql) < len(existing.sql):
                            existing.sql = new_example.sql
                        existing.verified = new_example.verified or existing.verified
                        existing.embedding = new_example.embedding
                        self._save_few_shot_store()
                        logger.info(
                            f"Merged near-duplicate (similarity={sim:.3f}): "
                            f"{new_example.question[:40]}"
                        )
                        return True

        # New unique example
        self.few_shot_store.append(new_example)
        self._save_few_shot_store()
        return False

    def _prune_store(self):
        """
        Keep the store from growing unbounded.

        Strategy:
        1. Never delete verified examples (user explicitly confirmed)
        2. If over max_stored_examples, remove lowest-value unverified ones
        3. "Value" = how often an example was retrieved (future: add hit counter)
           For now: keep newest unverified, drop oldest unverified
        """
        max_stored = self.config.agent.max_stored_examples if hasattr(self.config.agent, 'max_stored_examples') else 100

        if len(self.few_shot_store) <= max_stored:
            return

        verified = [ex for ex in self.few_shot_store if ex.verified]
        unverified = [ex for ex in self.few_shot_store if not ex.verified]

        # If verified alone exceeds limit, keep all verified (they're user-confirmed)
        if len(verified) >= max_stored:
            self.few_shot_store = verified
            self._save_few_shot_store()
            logger.info(f"Pruned store to {len(verified)} verified examples")
            return

        # Keep all verified + newest unverified up to limit
        slots_for_unverified = max_stored - len(verified)
        kept_unverified = unverified[-slots_for_unverified:]  # keep newest

        self.few_shot_store = verified + kept_unverified
        self._save_few_shot_store()
        logger.info(
            f"Pruned store: {len(verified)} verified + {len(kept_unverified)} unverified = "
            f"{len(self.few_shot_store)} total (removed {len(unverified) - len(kept_unverified)})"
        )

    # ── Persistence ───────────────────────────────────────────────

    def _load_few_shot_store(self):
        if os.path.exists(FEW_SHOT_FILE):
            try:
                with open(FEW_SHOT_FILE, "r") as f:
                    data = json.load(f)
                self.few_shot_store = [
                    FewShotExample(
                        question=item["question"],
                        sql=item["sql"],
                        tables_used=item.get("tables_used", []),
                        verified=item.get("verified", False),
                        embedding=item.get("embedding", []),
                    )
                    for item in data
                ]
                logger.info(f"Loaded {len(self.few_shot_store)} few-shot examples")
            except (json.JSONDecodeError, KeyError):
                self.few_shot_store = []

    def _save_few_shot_store(self):
        data = [
            {
                "question": ex.question,
                "sql": ex.sql,
                "tables_used": ex.tables_used,
                "verified": ex.verified,
                "embedding": ex.embedding,
            }
            for ex in self.few_shot_store
        ]
        with open(FEW_SHOT_FILE, "w") as f:
            json.dump(data, f, indent=2)

    def _save_learned_term(self, bt: BusinessTerm):
        existing = []
        if os.path.exists(BUSINESS_TERMS_FILE):
            try:
                with open(BUSINESS_TERMS_FILE, "r") as f:
                    existing = json.load(f)
            except json.JSONDecodeError:
                existing = []

        existing.append({
            "term": bt.term,
            "sql_expression": bt.sql_expression,
            "tables_involved": bt.tables_involved,
            "description": bt.description,
            "source": bt.source,
            "confidence": bt.confidence,
        })

        with open(BUSINESS_TERMS_FILE, "w") as f:
            json.dump(existing, f, indent=2)

    def load_learned_terms_into_graph(self):
        """Load previously learned terms back into the graph on startup."""
        if not os.path.exists(BUSINESS_TERMS_FILE):
            return

        try:
            with open(BUSINESS_TERMS_FILE, "r") as f:
                terms_data = json.load(f)

            for item in terms_data:
                bt = BusinessTerm(
                    term=item["term"],
                    sql_expression=item["sql_expression"],
                    tables_involved=item.get("tables_involved", []),
                    description=item.get("description", ""),
                    source=item.get("source", "learned"),
                    confidence=item.get("confidence", 0.9),
                )
                self.graph_builder.add_business_term(bt)

            logger.info(f"Loaded {len(terms_data)} learned business terms into graph")
        except (json.JSONDecodeError, KeyError) as e:
            logger.warning(f"Failed to load learned terms: {e}")

    def _load_feedback_log(self):
        if os.path.exists(FEEDBACK_LOG_FILE):
            try:
                with open(FEEDBACK_LOG_FILE, "r") as f:
                    self.feedback_log = json.load(f)
            except json.JSONDecodeError:
                self.feedback_log = []

    def _log_feedback(self, feedback_type: str, ctx: AgentContext | None, extra: dict | None = None):
        entry = {
            "timestamp": datetime.now().isoformat(),
            "type": feedback_type,
            "question": ctx.original_question if ctx else None,
            "generated_sql": ctx.generated_sql if ctx else None,
            **(extra or {}),
        }
        self.feedback_log.append(entry)

        with open(FEEDBACK_LOG_FILE, "w") as f:
            json.dump(self.feedback_log, f, indent=2)

    def get_stats(self) -> dict:
        """Get feedback statistics."""
        total = len(self.feedback_log)
        positive = sum(1 for f in self.feedback_log if f["type"] == "positive")
        negative = sum(1 for f in self.feedback_log if f["type"] == "negative")
        corrections = sum(1 for f in self.feedback_log if f["type"] == "correction")

        return {
            "total_interactions": total,
            "positive": positive,
            "negative": negative,
            "corrections": corrections,
            "accuracy_rate": positive / total if total > 0 else 0,
            "few_shot_examples": len(self.few_shot_store),
            "verified_examples": sum(1 for ex in self.few_shot_store if ex.verified),
        }
