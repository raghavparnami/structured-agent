"""Configuration for the GraphRAG SQL Agent."""

from dataclasses import dataclass, field
from typing import Literal


@dataclass
class DBConfig:
    db_type: Literal["postgresql", "mysql", "sqlserver", "sqlite"] = "postgresql"
    host: str = "localhost"
    port: int = 5432
    database: str = ""
    user: str = ""
    password: str = ""

    @property
    def connection_string(self) -> str:
        schemes = {
            "postgresql": "postgresql",
            "mysql": "mysql",
            "sqlserver": "mssql+pyodbc",
            "sqlite": "sqlite",
        }
        scheme = schemes.get(self.db_type, "postgresql")
        if self.db_type == "sqlite":
            return f"sqlite:///{self.database}"
        return f"{scheme}://{self.user}:{self.password}@{self.host}:{self.port}/{self.database}"


@dataclass
class LLMConfig:
    provider: Literal["openai", "gemini"] = "openai"
    # OpenAI models
    openai_api_key: str = ""
    openai_fast_model: str = "gpt-4o-mini"
    openai_strong_model: str = "gpt-4o"
    openai_deep_model: str = "gpt-4o"           # used for complex queries (6+ tables)
    openai_embedding_model: str = "text-embedding-3-small"
    # Gemini models
    gemini_api_key: str = ""
    gemini_fast_model: str = "gemini-2.0-flash"
    gemini_strong_model: str = "gemini-2.5-flash"
    gemini_deep_model: str = "gemini-2.5-pro"   # used for complex queries (6+ tables)
    gemini_embedding_model: str = "gemini-embedding-001"


@dataclass
class AgentConfig:
    max_repair_attempts: int = 3
    query_timeout_seconds: int = 30
    max_result_rows: int = 1000
    confidence_threshold: float = 0.7
    cache_enabled: bool = True
    # Schema linking
    max_tables_in_context: int = 10
    max_columns_per_table: int = 50
    sample_values_per_column: int = 10
    # Few-shot
    max_few_shot_examples: int = 3
    few_shot_similarity_threshold: float = 0.75
    # Token budget — controls total prompt size
    max_context_tokens: int = 3000      # schema + joins + business terms
    max_few_shot_tokens: int = 800      # few-shot examples
    max_total_prompt_tokens: int = 5000  # hard ceiling for entire user prompt
    # Example store management
    max_stored_examples: int = 100       # prune oldest unverified beyond this
    example_dedup_threshold: float = 0.95  # merge examples above this similarity


@dataclass
class AppConfig:
    db: DBConfig = field(default_factory=DBConfig)
    llm: LLMConfig = field(default_factory=LLMConfig)
    agent: AgentConfig = field(default_factory=AgentConfig)
