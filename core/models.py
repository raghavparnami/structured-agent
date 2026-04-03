"""Data models for the GraphRAG SQL Agent."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any


# ── Graph Node Models ──────────────────────────────────────────────


@dataclass
class TableNode:
    name: str
    schema: str = "public"
    description: str = ""
    row_count: int = 0
    columns: list[ColumnNode] = field(default_factory=list)
    default_filters: list[str] = field(default_factory=list)
    embedding: list[float] = field(default_factory=list)

    @property
    def full_name(self) -> str:
        return f"{self.schema}.{self.name}" if self.schema != "public" else self.name


@dataclass
class ColumnNode:
    name: str
    table_name: str
    data_type: str
    is_primary_key: bool = False
    is_foreign_key: bool = False
    is_nullable: bool = True
    description: str = ""
    sample_values: list[str] = field(default_factory=list)
    distinct_count: int = 0
    embedding: list[float] = field(default_factory=list)

    @property
    def full_name(self) -> str:
        return f"{self.table_name}.{self.name}"


@dataclass
class ForeignKey:
    source_table: str
    source_column: str
    target_table: str
    target_column: str

    @property
    def join_sql(self) -> str:
        return f"{self.source_table}.{self.source_column} = {self.target_table}.{self.target_column}"


@dataclass
class BusinessTerm:
    term: str
    sql_expression: str
    tables_involved: list[str] = field(default_factory=list)
    description: str = ""
    source: str = "auto"  # auto, user, doc
    confidence: float = 0.8
    embedding: list[float] = field(default_factory=list)


@dataclass
class QueryPattern:
    name: str
    description: str
    template_sql: str
    use_case: str = ""
    tables_involved: list[str] = field(default_factory=list)
    embedding: list[float] = field(default_factory=list)


@dataclass
class FewShotExample:
    question: str
    sql: str
    tables_used: list[str] = field(default_factory=list)
    verified: bool = False
    embedding: list[float] = field(default_factory=list)


# ── Agent State Models ─────────────────────────────────────────────


class AgentState(Enum):
    DECOMPOSE = "decompose"
    RETRIEVE = "retrieve"
    PLAN = "plan"
    GENERATE = "generate"
    VALIDATE = "validate"
    REPAIR = "repair"
    EXECUTE = "execute"
    SYNTHESIZE = "synthesize"
    CLARIFY = "clarify"
    DONE = "done"
    FAILED = "failed"


class QueryIntent(Enum):
    SIMPLE = "simple"
    MULTI_STEP = "multi_step"
    AMBIGUOUS = "ambiguous"


@dataclass
class RetrievedContext:
    tables: list[TableNode] = field(default_factory=list)
    columns: list[ColumnNode] = field(default_factory=list)
    foreign_keys: list[ForeignKey] = field(default_factory=list)
    join_paths: list[str] = field(default_factory=list)
    business_terms: list[BusinessTerm] = field(default_factory=list)
    query_patterns: list[QueryPattern] = field(default_factory=list)
    few_shot_examples: list[FewShotExample] = field(default_factory=list)
    value_matches: dict[str, list[str]] = field(default_factory=dict)

    def to_context_string(self) -> str:
        parts = []

        # Tables and columns
        if self.tables:
            parts.append("=== TABLES AND COLUMNS ===")
            for table in self.tables:
                cols = [c for c in self.columns if c.table_name == table.name]
                col_defs = []
                for c in cols:
                    flags = []
                    if c.is_primary_key:
                        flags.append("PK")
                    if c.is_foreign_key:
                        flags.append("FK")
                    if not c.is_nullable:
                        flags.append("NOT NULL")
                    flag_str = f" [{', '.join(flags)}]" if flags else ""
                    sample_str = ""
                    if c.sample_values:
                        sample_str = f" -- samples: {', '.join(str(v) for v in c.sample_values[:5])}"
                    col_defs.append(f"    {c.name} {c.data_type}{flag_str}{sample_str}")

                desc = f" -- {table.description}" if table.description else ""
                row_info = f" (~{table.row_count:,} rows)" if table.row_count else ""
                parts.append(f"\n  TABLE: {table.name}{row_info}{desc}")
                if table.default_filters:
                    parts.append(f"    DEFAULT FILTERS: {'; '.join(table.default_filters)}")
                parts.append("\n".join(col_defs))

        # Foreign keys / join paths
        if self.foreign_keys:
            parts.append("\n=== JOIN RELATIONSHIPS ===")
            for fk in self.foreign_keys:
                parts.append(f"  {fk.source_table}.{fk.source_column} → {fk.target_table}.{fk.target_column}")

        if self.join_paths:
            parts.append("\n=== JOIN PATHS ===")
            for jp in self.join_paths:
                parts.append(f"  {jp}")

        # Business terms
        if self.business_terms:
            parts.append("\n=== BUSINESS TERM DEFINITIONS ===")
            for bt in self.business_terms:
                parts.append(f'  "{bt.term}" = {bt.sql_expression}')
                if bt.description:
                    parts.append(f"    ({bt.description})")

        # Value matches (fuzzy matched enum values)
        if self.value_matches:
            parts.append("\n=== MATCHED VALUES ===")
            for term, matches in self.value_matches.items():
                parts.append(f'  "{term}" matches: {", ".join(matches)}')

        # Few-shot examples
        if self.few_shot_examples:
            parts.append("\n=== SIMILAR QUESTION EXAMPLES ===")
            for ex in self.few_shot_examples:
                parts.append(f"  Q: {ex.question}")
                parts.append(f"  SQL: {ex.sql}")
                parts.append("")

        # Query patterns
        if self.query_patterns:
            parts.append("\n=== QUERY PATTERNS ===")
            for qp in self.query_patterns:
                parts.append(f"  Pattern: {qp.name} -- {qp.description}")
                parts.append(f"  Template: {qp.template_sql}")
                parts.append("")

        return "\n".join(parts)


@dataclass
class ValidationResult:
    syntax_ok: bool = False
    tables_exist: bool = False
    explain_ok: bool = False
    error_message: str | None = None
    explain_output: str | None = None

    @property
    def is_valid(self) -> bool:
        return self.syntax_ok and self.tables_exist and self.explain_ok


@dataclass
class LLMCallLog:
    stage: str
    model: str
    tokens_in: int
    tokens_out: int
    latency_ms: int


@dataclass
class AgentContext:
    original_question: str
    state: AgentState = AgentState.DECOMPOSE
    intent: QueryIntent = QueryIntent.SIMPLE
    sub_questions: list[str] = field(default_factory=list)
    clarification_question: str | None = None
    retrieved_context: RetrievedContext = field(default_factory=RetrievedContext)
    sql_plan: str | None = None
    generated_sql: str = ""
    validation_result: ValidationResult = field(default_factory=ValidationResult)
    repair_attempts: int = 0
    query_result: Any = None
    query_result_columns: list[str] = field(default_factory=list)
    row_count: int = 0
    final_answer: str = ""
    error: str | None = None
    is_complex: bool = False
    llm_calls: list[LLMCallLog] = field(default_factory=list)

    @property
    def total_latency_ms(self) -> int:
        return sum(c.latency_ms for c in self.llm_calls)

    @property
    def total_cost_estimate(self) -> float:
        cost = 0.0
        for c in self.llm_calls:
            if "gpt-4o-mini" in c.model or "flash" in c.model:
                cost += (c.tokens_in * 0.15 + c.tokens_out * 0.60) / 1_000_000
            elif "gpt-4o" in c.model or "pro" in c.model:
                cost += (c.tokens_in * 2.50 + c.tokens_out * 10.0) / 1_000_000
        return cost
