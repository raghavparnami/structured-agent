"""
Agent Orchestrator: State machine that drives the full question-to-answer pipeline.

Optimized for latency:
- DECOMPOSE is eliminated — classification folded into GENERATE prompt
- PLAN is eliminated — planning instructions folded into GENERATE prompt
- Only 2 LLM calls on happy path: GENERATE (strong) + SYNTHESIZE (fast)
- RETRIEVE and VALIDATE are pure compute, no LLM
- REPAIR only fires on failure (strong model)

Flow: RETRIEVE → GENERATE → VALIDATE → EXECUTE → SYNTHESIZE
"""

from __future__ import annotations

import json
import logging
import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import pandas as pd

from config import AppConfig
from core.llm_provider import LLMProvider
from core.models import (
    AgentContext,
    AgentState,
    FewShotExample,
    QueryIntent,
    ValidationResult,
)
from core.validator import SQLExecutor, SQLValidator
from graph.retriever import GraphRetriever
from prompts.templates import (
    REPAIR_SYSTEM,
    REPAIR_USER,
    SQL_GENERATOR_SYSTEM,
    SQL_GENERATOR_USER,
    SYNTHESIZER_SYSTEM,
    SYNTHESIZER_USER,
)

logger = logging.getLogger(__name__)


class SQLAgent:
    # Dialect display names for LLM prompts
    DIALECT_NAMES = {
        "postgres": "PostgreSQL",
        "mysql": "MySQL",
        "tsql": "SQL Server",
        "sqlite": "SQLite",
    }

    def __init__(
        self,
        config: AppConfig,
        llm: LLMProvider,
        retriever: GraphRetriever,
        validator: SQLValidator,
        executor: SQLExecutor,
        few_shot_store: list[FewShotExample] | None = None,
        db_dialect: str = "postgres",
        date_functions_hint: str = "For date operations use PostgreSQL functions: DATE_TRUNC, EXTRACT, INTERVAL, CURRENT_DATE",
    ):
        self.config = config
        self.llm = llm
        self.retriever = retriever
        self.validator = validator
        self.executor = executor
        self.few_shot_store = few_shot_store or []
        self.db_dialect = self.DIALECT_NAMES.get(db_dialect, db_dialect)
        self.date_functions_hint = date_functions_hint

    def run(self, question: str, on_state_change=None) -> AgentContext:
        """Run the full agent pipeline on a question."""
        ctx = AgentContext(original_question=question)

        state_handlers = {
            AgentState.RETRIEVE: self._retrieve,
            AgentState.GENERATE: self._generate,
            AgentState.VALIDATE: self._validate,
            AgentState.REPAIR: self._repair,
            AgentState.EXECUTE: self._execute,
            AgentState.SYNTHESIZE: self._synthesize,
        }

        # Start directly at RETRIEVE — skip DECOMPOSE entirely
        ctx.state = AgentState.RETRIEVE

        while ctx.state not in (AgentState.DONE, AgentState.FAILED, AgentState.CLARIFY):
            handler = state_handlers.get(ctx.state)
            if not handler:
                ctx.state = AgentState.FAILED
                ctx.error = f"Unknown state: {ctx.state}"
                break

            if on_state_change:
                on_state_change(ctx.state.value, ctx)

            try:
                handler(ctx)
            except Exception as e:
                logger.exception(f"Error in state {ctx.state.value}")
                ctx.state = AgentState.FAILED
                ctx.error = str(e)

        if on_state_change:
            on_state_change(ctx.state.value, ctx)

        return ctx

    # ── State: RETRIEVE ───────────────────────────────────────────

    def _retrieve(self, ctx: AgentContext):
        """Retrieve relevant schema context via GraphRAG. No LLM call."""
        ctx.sub_questions = [ctx.original_question]
        ctx.retrieved_context = self.retriever.retrieve(
            ctx.original_question, ctx.sub_questions
        )
        ctx.state = AgentState.GENERATE

    # ── State: GENERATE ───────────────────────────────────────────

    def _generate(self, ctx: AgentContext):
        """Generate the SQL query. Single LLM call — includes planning inline."""
        context_str = ctx.retrieved_context.to_context_string()

        # Build few-shot section
        few_shot_section = ""
        if ctx.retrieved_context.few_shot_examples:
            examples = []
            for ex in ctx.retrieved_context.few_shot_examples:
                examples.append(f"Q: {ex.question}\nSQL: {ex.sql}")
            few_shot_section = "Similar examples:\n" + "\n\n".join(examples)

        messages = [
            {"role": "system", "content": SQL_GENERATOR_SYSTEM.format(
                db_dialect=self.db_dialect,
                date_functions_hint=self.date_functions_hint,
            )},
            {
                "role": "user",
                "content": SQL_GENERATOR_USER.format(
                    db_dialect=self.db_dialect,
                    question=ctx.original_question,
                    context=context_str,
                    plan_section="",  # Planning is now inline in the system prompt
                    few_shot_section=few_shot_section,
                ),
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.strong_model, stage="generate"
        )
        ctx.llm_calls.append(log)

        # Clean up response — remove markdown fences if present
        sql = response.strip()
        sql = re.sub(r'^```(?:sql)?\s*', '', sql)
        sql = re.sub(r'\s*```$', '', sql)
        ctx.generated_sql = sql.strip()

        ctx.state = AgentState.VALIDATE

    # ── State: VALIDATE ───────────────────────────────────────────

    def _validate(self, ctx: AgentContext):
        """Validate the generated SQL. No LLM call."""
        ctx.validation_result = self.validator.validate(ctx.generated_sql)

        if ctx.validation_result.is_valid:
            # Inject LIMIT for safety
            ctx.generated_sql = self.validator.inject_limit(ctx.generated_sql)
            ctx.state = AgentState.EXECUTE
        else:
            if ctx.repair_attempts < self.config.agent.max_repair_attempts:
                ctx.state = AgentState.REPAIR
            else:
                ctx.state = AgentState.FAILED
                ctx.error = f"SQL validation failed after {ctx.repair_attempts} repairs: {ctx.validation_result.error_message}"

    # ── State: REPAIR ─────────────────────────────────────────────

    def _repair(self, ctx: AgentContext):
        """Attempt to fix the SQL based on the error."""
        ctx.repair_attempts += 1
        context_str = ctx.retrieved_context.to_context_string()

        explain_section = ""
        if ctx.validation_result.explain_output:
            explain_section = f"EXPLAIN output:\n{ctx.validation_result.explain_output}"

        messages = [
            {"role": "system", "content": REPAIR_SYSTEM},
            {
                "role": "user",
                "content": REPAIR_USER.format(
                    question=ctx.original_question,
                    failed_sql=ctx.generated_sql,
                    error_message=ctx.validation_result.error_message or "Unknown error",
                    explain_section=explain_section,
                    context=context_str,
                    attempt=ctx.repair_attempts,
                    max_attempts=self.config.agent.max_repair_attempts,
                ),
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.strong_model, stage="repair"
        )
        ctx.llm_calls.append(log)

        sql = response.strip()
        sql = re.sub(r'^```(?:sql)?\s*', '', sql)
        sql = re.sub(r'\s*```$', '', sql)
        ctx.generated_sql = sql.strip()

        ctx.state = AgentState.VALIDATE

    # ── State: EXECUTE ────────────────────────────────────────────

    def _execute(self, ctx: AgentContext):
        """Execute the SQL query."""
        try:
            df, columns = self.executor.execute(ctx.generated_sql)
            ctx.query_result = df
            ctx.query_result_columns = columns
            ctx.row_count = len(df)
            ctx.state = AgentState.SYNTHESIZE
        except Exception as e:
            error_str = str(e)
            ctx.validation_result = ValidationResult(
                syntax_ok=True,
                tables_exist=True,
                explain_ok=True,
                error_message=f"Execution error: {error_str}",
            )
            if ctx.repair_attempts < self.config.agent.max_repair_attempts:
                ctx.state = AgentState.REPAIR
            else:
                ctx.state = AgentState.FAILED
                ctx.error = f"Query execution failed: {error_str}"

    # ── State: SYNTHESIZE ─────────────────────────────────────────

    def _synthesize(self, ctx: AgentContext):
        """Generate a natural language answer from the results."""
        if ctx.query_result is not None and not ctx.query_result.empty:
            display_df = ctx.query_result.head(50)
            results_str = display_df.to_markdown(index=False)
        else:
            results_str = "(No results returned)"

        messages = [
            {"role": "system", "content": SYNTHESIZER_SYSTEM},
            {
                "role": "user",
                "content": SYNTHESIZER_USER.format(
                    question=ctx.original_question,
                    sql=ctx.generated_sql,
                    row_count=ctx.row_count,
                    results=results_str,
                ),
            },
        ]

        response, log = self.llm.chat(
            messages, model=self.llm.fast_model, json_mode=True, stage="synthesize"
        )
        ctx.llm_calls.append(log)

        try:
            data = json.loads(response)
            ctx.final_answer = data.get("answer", response)
        except json.JSONDecodeError:
            ctx.final_answer = response

        ctx.state = AgentState.DONE
