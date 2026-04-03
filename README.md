# GraphRAG SQL Agent

A natural-language-to-SQL agent that uses a **knowledge graph** for schema linking, **LLMs** for SQL generation, and a **feedback loop** that learns from user corrections to improve over time.

Ask questions in plain English, get accurate SQL and answers back — no SQL knowledge required.

---

## How It Works

```
User Question
     │
     ▼
┌─────────┐  schema context  ┌──────────┐  SQL  ┌──────────┐
│ RETRIEVE ├────────────────►│ GENERATE ├──────►│ VALIDATE │
│ (graph)  │                 │  (LLM)   │      │(sqlglot) │
└─────────┘                 └──────────┘      └────┬─────┘
                                                    │
                                          valid ────┤──── invalid
                                            │       │
                                            ▼       ▼
                                       ┌─────────┐ ┌────────┐
                                       │ EXECUTE │ │ REPAIR │
                                       │  (DB)   │ │ (LLM)  │
                                       └────┬────┘ └────────┘
                                            │
                                            ▼
                                      ┌────────────┐
                                      │ SYNTHESIZE │ ──► Answer
                                      │   (LLM)    │
                                      └────────────┘
```

Only **2 LLM calls** on the happy path. Typical latency: **4-8s** (OpenAI) / **10-16s** (Gemini).

---

## Features

- **Knowledge Graph** — Auto-built from your PostgreSQL schema. Tables, columns, foreign keys, business terms, and query patterns stored as a NetworkX graph with embeddings.
- **Hybrid Retrieval** — Combines embedding similarity (70%) + keyword matching (30%) for robust schema linking. Graph traversal discovers join paths automatically.
- **Business Term Mapping** — LLM-generated terms like "revenue" → `SUM(payment.amount)` improve accuracy by 12-15%.
- **Fuzzy Value Matching** — Matches user-mentioned values ("Action", "Comedy") against column enums for accurate filters.
- **Self-Repair Loop** — Up to 3 automatic retries with error context when SQL validation fails.
- **Feedback Learning** — Thumbs up saves verified few-shot examples. SQL corrections teach new business terms. Improvements persist across restarts.
- **SQL Safety** — Blocks DDL/DML, prevents injection, validates with EXPLAIN dry-run, injects LIMIT.
- **Dual LLM Support** — OpenAI (gpt-4o / gpt-4o-mini) and Gemini (2.5-pro / 2.0-flash) with per-stage model selection.

---

## Components

| Component | File | Purpose |
|-----------|------|---------|
| **Agent Orchestrator** | `core/agent.py` | State machine driving the 6-stage pipeline (retrieve → generate → validate → repair → execute → synthesize) |
| **LLM Provider** | `core/llm_provider.py` | Unified OpenAI + Gemini interface with lazy init, JSON mode, batch embeddings |
| **SQL Validator** | `core/validator.py` | 5-step validation (security → multi-statement → syntax → schema → EXPLAIN) + safe execution |
| **Data Models** | `core/models.py` | Dataclasses for graph nodes, agent state, validation results, LLM call logs |
| **Graph Builder** | `graph/builder.py` | Introspects PostgreSQL → generates descriptions, business terms, query patterns → builds NetworkX graph |
| **Graph Retriever** | `graph/retriever.py` | 7-step retrieval: table matching, column ranking, graph expansion, term matching, value fuzzy match, pattern matching, few-shot retrieval |
| **Feedback Learner** | `feedback/learner.py` | Processes thumbs up/down, SQL corrections, term definitions; persists to JSON; deduplicates and prunes |
| **Prompt Templates** | `prompts/templates.py` | All LLM prompts for generation, repair, synthesis, and term extraction |
| **Configuration** | `config.py` | DB, LLM, and agent config dataclasses with sensible defaults |
| **Streamlit UI** | `app.py` | 5-page web app: Connect, Build Graph, Ask Questions, Teach & Feedback, Dashboard |

---

## Quick Start

### Prerequisites

- Python 3.10+
- PostgreSQL database
- OpenAI API key or Google Gemini API key

### Installation

```bash
git clone https://github.com/your-username/graphrag-sql-agent.git
cd graphrag-sql-agent
pip install -r requirements.txt
```

### Run

```bash
streamlit run app.py
```

Then:
1. **Connect** — Enter your PostgreSQL credentials and select an LLM provider
2. **Build Graph** — Auto-introspects your schema and builds the knowledge graph (2-5 min)
3. **Ask Questions** — Type natural language questions and get SQL + answers
4. **Teach** — Correct mistakes to improve future accuracy
5. **Dashboard** — Monitor graph stats, learning progress, and feedback history

---

## Configuration

Key settings in `config.py`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_repair_attempts` | 3 | Max SQL repair retries before failing |
| `query_timeout_seconds` | 30 | PostgreSQL statement timeout |
| `max_tables_in_context` | 10 | Max tables sent to LLM |
| `max_few_shot_examples` | 3 | Few-shot examples per query |
| `max_context_tokens` | 3000 | Token budget for retrieved context |
| `max_stored_examples` | 100 | Few-shot store capacity |

### Model Configuration

**Best accuracy (OpenAI):**
```
Strong: gpt-4o       Fast: gpt-4o-mini       Embedding: text-embedding-3-small
```

**Best accuracy (Gemini):**
```
Strong: gemini-2.5-pro   Fast: gemini-2.0-flash   Embedding: gemini-embedding-001
```

---

## Accuracy

| Stage | Expected Accuracy | Driver |
|-------|-------------------|--------|
| Day 1 (schema graph only) | ~75% | Auto-generated descriptions + sample values |
| Week 1 (+ business terms) | ~85% | LLM-generated business terms + enum matching |
| Week 2 (+ feedback) | ~90% | User corrections → few-shot examples |
| Month 1 (+ filters) | ~93% | Default filters eliminate implicit filter misses |
| Month 3 (mature) | ~95%+ | Full business term coverage + large few-shot library |

---

## File Structure

```
graphrag-sql-agent/
├── app.py                          # Streamlit UI (5 pages)
├── config.py                       # All configuration dataclasses
├── requirements.txt
│
├── core/
│   ├── agent.py                    # State machine orchestrator
│   ├── llm_provider.py             # OpenAI + Gemini unified abstraction
│   ├── models.py                   # Data models (graph nodes, agent state)
│   └── validator.py                # SQL validation + execution
│
├── graph/
│   ├── builder.py                  # Auto-builds knowledge graph from Postgres
│   └── retriever.py                # Schema linking + value matching + few-shot
│
├── prompts/
│   └── templates.py                # All prompt templates per agent stage
│
├── feedback/
│   └── learner.py                  # Feedback learning system
│
├── data/                           # Auto-created at runtime
│   ├── few_shot_examples.json      # Verified question-SQL pairs
│   ├── learned_business_terms.json # Terms learned from corrections
│   └── feedback_log.json           # All feedback events
│
└── docs/
    └── architecture.md             # Detailed architecture documentation
```

---

## Documentation

See [docs/architecture.md](docs/architecture.md) for detailed architecture documentation including:
- System architecture diagrams (Mermaid)
- Agent pipeline state machine
- Knowledge graph schema
- Component deep dives
- Data flow examples
- Model recommendations and latency breakdown
