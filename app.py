"""
Streamlit UI for GraphRAG SQL Agent.

Pages:
1. Connection Setup — DB credentials + LLM provider selection
2. Graph Builder — Build/rebuild the knowledge graph
3. QnA — Ask questions, get SQL + results
4. Feedback — Correct SQL, define terms, add default filters
5. Dashboard — View learning stats and graph info
"""

import json
import logging
import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import streamlit as st
import pandas as pd

from config import AppConfig, DBConfig, LLMConfig, AgentConfig
from core.db_adapter import create_adapter, DB_TYPE_DEFAULTS
from core.llm_provider import LLMProvider
from core.models import AgentState, FewShotExample
from core.agent import SQLAgent
from core.validator import SQLValidator, SQLExecutor
from graph.builder import GraphBuilder
from graph.retriever import GraphRetriever
from feedback.learner import FeedbackLearner

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ── Page Config ───────────────────────────────────────────────────

st.set_page_config(
    page_title="GraphRAG SQL Agent",
    page_icon="🔍",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── Session State Init ────────────────────────────────────────────


def init_session_state():
    defaults = {
        "config": None,
        "llm": None,
        "db_adapter": None,
        "graph_builder": None,
        "retriever": None,
        "validator": None,
        "executor": None,
        "agent": None,
        "feedback_learner": None,
        "graph_built": False,
        "connected": False,
        "chat_history": [],
        "current_ctx": None,
    }
    for key, val in defaults.items():
        if key not in st.session_state:
            st.session_state[key] = val


init_session_state()

# ── Sidebar ───────────────────────────────────────────────────────

st.sidebar.title("GraphRAG SQL Agent")

pages = ["1. Connect", "2. Build Graph", "3. Ask Questions", "4. Teach & Feedback", "5. Dashboard"]
default_idx = pages.index(st.session_state.get("current_page", "1. Connect")) if st.session_state.get("current_page") in pages else 0

page = st.sidebar.radio(
    "Navigate",
    pages,
    index=default_idx,
)

# Show status indicators
if st.session_state.connected:
    st.sidebar.success("DB Connected")
else:
    st.sidebar.warning("DB Not Connected")

if st.session_state.graph_built:
    st.sidebar.success("Graph Built")
else:
    st.sidebar.warning("Graph Not Built")

if st.session_state.feedback_learner:
    stats = st.session_state.feedback_learner.get_stats()
    st.sidebar.metric("Few-Shot Examples", stats["few_shot_examples"])
    st.sidebar.metric("Accuracy Rate", f"{stats['accuracy_rate']:.0%}")


# ── Helper: Initialize agent from a loaded/built GraphBuilder ────

def _init_agent_from_builder(builder: GraphBuilder, config, llm, adapter):
    """Initialize all agent components from a GraphBuilder and store in session state."""
    graph = builder.graph

    table_names = {
        data["data"].name
        for _, data in graph.nodes(data=True)
        if data.get("type") == "table"
    }
    column_names = {
        data["data"].full_name
        for _, data in graph.nodes(data=True)
        if data.get("type") == "column"
    }

    feedback_learner = FeedbackLearner(config, llm, builder)
    feedback_learner.load_learned_terms_into_graph()

    retriever = GraphRetriever(
        graph, llm, config.agent,
        few_shot_store=feedback_learner.few_shot_store,
    )
    validator = SQLValidator(config, table_names, column_names, adapter)
    executor = SQLExecutor(config, adapter)

    agent = SQLAgent(
        config, llm, retriever, validator, executor,
        few_shot_store=feedback_learner.few_shot_store,
        db_dialect=adapter.dialect,
        date_functions_hint=adapter.date_functions_hint,
    )

    st.session_state.graph_builder = builder
    st.session_state.retriever = retriever
    st.session_state.validator = validator
    st.session_state.executor = executor
    st.session_state.agent = agent
    st.session_state.feedback_learner = feedback_learner
    st.session_state.graph_built = True
    st.session_state.current_page = "3. Ask Questions"


# ── Page 1: Connection Setup ──────────────────────────────────────

def page_connect():
    st.header("Database & LLM Configuration")

    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Database Connection")
        db_type = st.selectbox(
            "Database Type",
            ["postgresql", "mysql", "sqlserver", "sqlite"],
            format_func=lambda x: {
                "postgresql": "PostgreSQL",
                "mysql": "MySQL",
                "sqlserver": "SQL Server",
                "sqlite": "SQLite",
            }[x],
        )

        if db_type == "sqlite":
            db_host = ""
            db_port = 0
            db_name = st.text_input("Database File Path", placeholder="/path/to/database.db")
            db_user = ""
            db_pass = ""
        else:
            default_port = DB_TYPE_DEFAULTS[db_type]["port"]
            db_host = st.text_input("Host", value="localhost")
            db_port = st.number_input("Port", value=default_port, min_value=1, max_value=65535)
            db_name = st.text_input("Database Name")
            db_user = st.text_input("Username")
            db_pass = st.text_input("Password", type="password")

        driver_info = DB_TYPE_DEFAULTS[db_type]["driver"]
        st.caption(f"Requires: `pip install {driver_info}`" if "built-in" not in driver_info else f"Driver: {driver_info}")

    with col2:
        st.subheader("LLM Provider")
        provider = st.selectbox("Provider", ["openai", "gemini"])

        if provider == "openai":
            api_key = st.text_input("OpenAI API Key", type="password")
            fast_model = st.selectbox(
                "Fast Model (decompose/synthesize)",
                ["gpt-4o-mini", "gpt-4.1-mini", "gpt-4.1-nano"],
            )
            strong_model = st.selectbox(
                "Strong Model (generate/repair)",
                ["gpt-4o", "gpt-4.1", "gpt-4.1-mini"],
            )
            embedding_model = st.selectbox(
                "Embedding Model",
                ["text-embedding-3-small", "text-embedding-3-large", "text-embedding-ada-002"],
            )
        else:
            api_key = st.text_input("Gemini API Key", type="password")
            fast_model = st.selectbox(
                "Fast Model",
                ["gemini-2.0-flash", "gemini-2.0-flash-lite"],
            )
            strong_model = st.selectbox(
                "Strong Model",
                ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
            )
            embedding_model = st.selectbox(
                "Embedding Model",
                ["gemini-embedding-001", "gemini-embedding-2-preview"],
            )

    if st.button("Connect & Initialize", type="primary"):
        if not db_name or not api_key:
            st.error("Please fill in all required fields")
            return

        with st.spinner("Connecting to database..."):
            try:
                db_config = DBConfig(
                    db_type=db_type,
                    host=db_host,
                    port=db_port,
                    database=db_name,
                    user=db_user,
                    password=db_pass,
                )
                llm_config = LLMConfig(provider=provider)

                if provider == "openai":
                    llm_config.openai_api_key = api_key
                    llm_config.openai_fast_model = fast_model
                    llm_config.openai_strong_model = strong_model
                    llm_config.openai_embedding_model = embedding_model
                else:
                    llm_config.gemini_api_key = api_key
                    llm_config.gemini_fast_model = fast_model
                    llm_config.gemini_strong_model = strong_model
                    llm_config.gemini_embedding_model = embedding_model

                config = AppConfig(db=db_config, llm=llm_config)

                # Create DB adapter and test connection
                adapter = create_adapter(
                    db_type,
                    host=db_host, port=db_port, database=db_name,
                    user=db_user, password=db_pass,
                )
                adapter.test_connection()

                # Initialize LLM provider
                llm = LLMProvider(llm_config)

                st.session_state.config = config
                st.session_state.llm = llm
                st.session_state.db_adapter = adapter
                st.session_state.connected = True
                st.session_state.current_page = "2. Build Graph"

                st.success("Connected! Redirecting to Graph Builder...")
                st.rerun()

            except Exception as e:
                st.error(f"Connection failed: {e}")


# ── Page 2: Build Graph ──────────────────────────────────────────

def page_build_graph():
    st.header("Knowledge Graph Builder")

    if not st.session_state.connected:
        st.warning("Please connect to the database first (Page 1)")
        return

    st.markdown("""
    The graph builder will:
    1. **Introspect** your database schema (tables, columns, foreign keys)
    2. **Sample values** from each column (for enum/filter matching)
    3. **Generate descriptions** for tables and columns using LLM
    4. **Discover business terms** (metrics, KPIs, domain vocabulary)
    5. **Create query patterns** (reusable SQL templates)
    6. **Compute embeddings** for semantic search
    """)

    # Try loading from cache first
    config = st.session_state.config
    llm = st.session_state.llm
    adapter = st.session_state.db_adapter

    if not st.session_state.graph_built:
        temp_builder = GraphBuilder(config, llm, adapter)
        if temp_builder.load_cache():
            st.info("Found cached graph! Loading...")
            _init_agent_from_builder(temp_builder, config, llm, adapter)
            st.success(
                f"Graph loaded from cache! {len(temp_builder.tables)} tables, "
                f"{temp_builder.graph.number_of_nodes()} nodes. Redirecting..."
            )
            import time
            time.sleep(1)
            st.rerun()

    # Show existing graph info if already built
    if st.session_state.graph_built and st.session_state.graph_builder:
        builder = st.session_state.graph_builder
        st.success(f"Graph already built! {len(builder.tables)} tables, {len(builder.business_terms)} business terms")
        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Tables", len(builder.tables))
        col2.metric("Columns", len(builder.columns))
        col3.metric("Business Terms", len(builder.business_terms))
        col4.metric("Query Patterns", len(builder.query_patterns))

        with st.expander("Tables Found", expanded=False):
            for t in builder.tables:
                st.markdown(f"**{t.name}** ({t.row_count:,} rows) — {t.description}")
        with st.expander("Business Terms Discovered", expanded=False):
            for bt in builder.business_terms:
                st.markdown(f"**\"{bt.term}\"** = `{bt.sql_expression}`")

        st.divider()
        st.caption("Click below to rebuild the graph (e.g. after schema changes)")

    if st.button("Build Knowledge Graph" if not st.session_state.graph_built else "Rebuild Knowledge Graph", type="primary"):

        progress_bar = st.progress(0)
        status_container = st.container()
        status_text = status_container.empty()
        detail_text = status_container.empty()

        # Step status tracking
        step_statuses = status_container.empty()
        completed_steps: list[str] = []

        def progress_callback(msg, progress):
            status_text.markdown(f"**{msg}**")
            progress_bar.progress(min(progress, 1.0))
            if msg and msg not in completed_steps and progress > 0:
                completed_steps.append(msg)
            # Render all steps with checkmarks
            steps_md = ""
            for step in completed_steps[:-1]:
                steps_md += f"- :white_check_mark: {step}\n"
            if completed_steps:
                steps_md += f"- :hourglass_flowing_sand: {completed_steps[-1]}\n"
            step_statuses.markdown(steps_md)

        try:
            adapter = st.session_state.db_adapter
            builder = GraphBuilder(config, llm, adapter)
            graph = builder.build(progress_callback=progress_callback)

            # Mark last step complete
            if completed_steps:
                steps_md = ""
                for step in completed_steps:
                    steps_md += f"- :white_check_mark: {step}\n"
                step_statuses.markdown(steps_md)

            detail_text.info(f"Initializing agent components...")

            # Save cache for instant reload next time
            builder.save_cache()

            # Initialize all agent components
            _init_agent_from_builder(builder, config, llm, adapter)

            detail_text.empty()
            status_text.empty()
            progress_bar.progress(1.0)

            st.success(
                f"Graph built! {graph.number_of_nodes()} nodes, "
                f"{graph.number_of_edges()} edges. Redirecting to Q&A..."
            )

            # Show summary before redirect
            col1, col2, col3, col4 = st.columns(4)
            col1.metric("Tables", len(builder.tables))
            col2.metric("Columns", len(builder.columns))
            col3.metric("Business Terms", len(builder.business_terms))
            col4.metric("Query Patterns", len(builder.query_patterns))

            import time
            time.sleep(2)
            st.rerun()

        except Exception as e:
            st.error(f"Graph build failed: {e}")
            import traceback
            with st.expander("Full error traceback"):
                st.code(traceback.format_exc())
            logger.exception("Graph build failed")


# ── Page 3: Ask Questions ─────────────────────────────────────────

def page_ask():
    st.header("Ask Questions About Your Data")

    if not st.session_state.graph_built:
        st.warning("Please build the knowledge graph first (Page 2)")
        return

    # Chat history
    for entry in st.session_state.chat_history:
        with st.chat_message("user"):
            st.write(entry["question"])
        with st.chat_message("assistant"):
            st.write(entry["answer"])
            if entry.get("sql"):
                with st.expander("SQL Query"):
                    st.code(entry["sql"], language="sql")
            if entry.get("data") is not None and not entry["data"].empty:
                with st.expander(f"Results ({entry.get('row_count', 0)} rows)"):
                    st.dataframe(entry["data"], use_container_width=True)
            if entry.get("latency_ms"):
                st.caption(
                    f"Latency: {entry['latency_ms']}ms | "
                    f"Cost: ${entry.get('cost', 0):.4f} | "
                    f"Repairs: {entry.get('repairs', 0)}"
                )

    # Input
    question = st.chat_input("Ask a question about your data...")

    if question:
        with st.chat_message("user"):
            st.write(question)

        with st.chat_message("assistant"):
            agent = st.session_state.agent

            # Status display with step-by-step progress
            status_container = st.empty()
            completed_states: list[str] = []

            state_labels = {
                "retrieve": ("Schema linking", "Finding relevant tables, columns, and business terms..."),
                "generate": ("Writing SQL", "Generating SQL query..."),
                "validate": ("Validating SQL", "Syntax check + EXPLAIN dry run..."),
                "repair": ("Fixing SQL", "Auto-repairing based on validation error..."),
                "execute": ("Running query", "Executing against database..."),
                "synthesize": ("Generating answer", "Summarizing results..."),
                "done": ("Complete", ""),
                "failed": ("Failed", ""),
            }

            def on_state_change(state: str, ctx):
                label, detail = state_labels.get(state, (state, ""))
                if state not in ("done", "failed", "clarify"):
                    completed_states.append(state)
                # Build status markdown
                md = ""
                for s in completed_states[:-1]:
                    l, _ = state_labels.get(s, (s, ""))
                    md += f":white_check_mark: **{l}**\n\n"
                if completed_states:
                    current = completed_states[-1]
                    cl, cd = state_labels.get(current, (current, ""))
                    md += f":hourglass_flowing_sand: **{cl}** — {cd}\n"
                status_container.markdown(md)

            ctx = agent.run(question, on_state_change=on_state_change)
            status_container.empty()

            st.session_state.current_ctx = ctx

            if ctx.state == AgentState.DONE:
                st.write(ctx.final_answer)

                with st.expander("SQL Query"):
                    st.code(ctx.generated_sql, language="sql")

                if ctx.query_result is not None and not ctx.query_result.empty:
                    with st.expander(f"Results ({ctx.row_count} rows)"):
                        st.dataframe(ctx.query_result, use_container_width=True)

                st.caption(
                    f"Latency: {ctx.total_latency_ms}ms | "
                    f"Cost: ${ctx.total_cost_estimate:.4f} | "
                    f"Repairs: {ctx.repair_attempts}"
                )

                # Feedback buttons
                col1, col2, col3 = st.columns([1, 1, 2])
                with col1:
                    if st.button("👍 Correct", key=f"pos_{len(st.session_state.chat_history)}"):
                        st.session_state.feedback_learner.on_positive_feedback(ctx)
                        st.success("Thanks! Saved as training example.")
                with col2:
                    if st.button("👎 Wrong", key=f"neg_{len(st.session_state.chat_history)}"):
                        st.session_state.feedback_learner.on_negative_feedback(ctx)
                        st.info("Got it. Use the 'Teach & Feedback' page to provide the correct SQL.")

                # Save to history
                st.session_state.chat_history.append({
                    "question": question,
                    "answer": ctx.final_answer,
                    "sql": ctx.generated_sql,
                    "data": ctx.query_result,
                    "row_count": ctx.row_count,
                    "latency_ms": ctx.total_latency_ms,
                    "cost": ctx.total_cost_estimate,
                    "repairs": ctx.repair_attempts,
                })

            elif ctx.state == AgentState.CLARIFY:
                st.warning(f"I need clarification: {ctx.clarification_question}")
                st.session_state.chat_history.append({
                    "question": question,
                    "answer": f"Need clarification: {ctx.clarification_question}",
                    "sql": None,
                    "data": None,
                })

            elif ctx.state == AgentState.FAILED:
                st.error(f"Failed: {ctx.error}")
                if ctx.generated_sql:
                    with st.expander("Attempted SQL"):
                        st.code(ctx.generated_sql, language="sql")
                st.session_state.chat_history.append({
                    "question": question,
                    "answer": f"Error: {ctx.error}",
                    "sql": ctx.generated_sql,
                    "data": None,
                })


# ── Page 4: Teach & Feedback ─────────────────────────────────────

def page_feedback():
    st.header("Teach the Agent")

    if not st.session_state.graph_built:
        st.warning("Please build the knowledge graph first (Page 2)")
        return

    feedback_learner = st.session_state.feedback_learner

    tab1, tab2, tab3, tab4 = st.tabs([
        "Correct SQL", "Define Business Terms", "Default Filters", "Add Examples"
    ])

    # Tab 1: Correct SQL
    with tab1:
        st.subheader("Correct a Query")
        st.markdown("If the agent generated wrong SQL, paste the correct version here.")

        ctx = st.session_state.current_ctx

        if ctx and ctx.generated_sql:
            st.markdown(f"**Last question:** {ctx.original_question}")
            st.markdown("**Agent's SQL:**")
            st.code(ctx.generated_sql, language="sql")

            corrected_sql = st.text_area(
                "Correct SQL",
                height=150,
                placeholder="Paste the correct SQL here...",
            )
            explanation = st.text_input(
                "Explanation (optional)",
                placeholder="Why was the original wrong? e.g., 'revenue means net_amount not gross_amount'",
            )

            if st.button("Submit Correction", type="primary"):
                if corrected_sql.strip():
                    feedback_learner.on_sql_correction(ctx, corrected_sql.strip(), explanation)
                    st.success(
                        "Correction saved! The agent will learn from this for future queries."
                    )
                else:
                    st.error("Please enter the corrected SQL")
        else:
            st.info("Ask a question first (Page 3), then come here to correct the SQL if needed.")

    # Tab 2: Define Business Terms
    with tab2:
        st.subheader("Define Business Terms")
        st.markdown(
            "Teach the agent what business terms mean in your domain. "
            "This dramatically improves accuracy."
        )

        term = st.text_input("Business Term", placeholder='e.g., "revenue", "active user", "churn rate"')
        sql_expr = st.text_area(
            "SQL Expression",
            height=100,
            placeholder='e.g., SUM(orders.total_amount) or WHERE last_login > CURRENT_DATE - INTERVAL \'30 days\'',
        )

        # Show available tables for reference
        if st.session_state.graph_builder:
            table_names = [t.name for t in st.session_state.graph_builder.tables]
            tables_involved = st.multiselect("Tables Involved", table_names)
        else:
            tables_involved = []

        description = st.text_input(
            "Description (optional)",
            placeholder="e.g., Total sales revenue excluding refunds",
        )

        if st.button("Save Business Term"):
            if term and sql_expr:
                feedback_learner.on_business_term_correction(
                    term=term.strip(),
                    sql_expression=sql_expr.strip(),
                    tables_involved=tables_involved,
                    description=description.strip(),
                )
                st.success(f'Business term "{term}" saved!')
            else:
                st.error("Please fill in term and SQL expression")

        # Show existing terms
        if st.session_state.graph_builder:
            with st.expander("Existing Business Terms"):
                for bt in st.session_state.graph_builder.business_terms:
                    source_badge = {
                        "auto": "🤖 Auto",
                        "user": "👤 User",
                        "learned": "📚 Learned",
                        "doc": "📄 Doc",
                    }.get(bt.source, bt.source)
                    st.markdown(
                        f"**\"{bt.term}\"** [{source_badge}] = `{bt.sql_expression}`"
                    )

    # Tab 3: Default Filters
    with tab3:
        st.subheader("Default Filters")
        st.markdown(
            "Add filters that should be automatically applied to every query on a table. "
            "e.g., always exclude test data or cancelled orders."
        )

        if st.session_state.graph_builder:
            table_names = [t.name for t in st.session_state.graph_builder.tables]
            filter_table = st.selectbox("Table", table_names)
            filter_sql = st.text_input(
                "Filter (WHERE clause without WHERE)",
                placeholder="e.g., status != 'cancelled' or is_test = false",
            )

            if st.button("Add Default Filter"):
                if filter_table and filter_sql:
                    feedback_learner.on_default_filter_suggestion(filter_table, filter_sql.strip())
                    st.success(f"Default filter added to {filter_table}!")
                else:
                    st.error("Please select a table and enter a filter")

            # Show existing default filters
            with st.expander("Existing Default Filters"):
                for t in st.session_state.graph_builder.tables:
                    if t.default_filters:
                        st.markdown(f"**{t.name}:**")
                        for f in t.default_filters:
                            st.markdown(f"  - `{f}`")

    # Tab 4: Add Examples
    with tab4:
        st.subheader("Add Question-SQL Examples")
        st.markdown(
            "Provide example question-SQL pairs. These serve as few-shot examples "
            "to guide the agent on similar future questions."
        )

        ex_question = st.text_input(
            "Question",
            placeholder="e.g., What are the top 5 customers by revenue this year?",
        )
        ex_sql = st.text_area(
            "SQL",
            height=150,
            placeholder="The correct SQL for this question...",
        )

        if st.button("Add Example"):
            if ex_question and ex_sql:
                example = FewShotExample(
                    question=ex_question.strip(),
                    sql=ex_sql.strip(),
                    verified=True,
                )
                example.embedding = st.session_state.llm.embed_single(
                    f"Question: {example.question}"
                )
                feedback_learner.few_shot_store.append(example)
                feedback_learner._save_few_shot_store()
                st.success("Example added!")
            else:
                st.error("Please fill in both question and SQL")

        # Show existing examples
        with st.expander(f"Existing Examples ({len(feedback_learner.few_shot_store)})"):
            for ex in feedback_learner.few_shot_store:
                verified = "✅" if ex.verified else "❓"
                st.markdown(f"{verified} **Q:** {ex.question}")
                st.code(ex.sql, language="sql")
                st.divider()


# ── Page 5: Dashboard ─────────────────────────────────────────────

def page_dashboard():
    st.header("Agent Dashboard")

    if not st.session_state.graph_built:
        st.warning("Please build the knowledge graph first (Page 2)")
        return

    builder = st.session_state.graph_builder
    feedback_learner = st.session_state.feedback_learner

    # Graph stats
    st.subheader("Knowledge Graph")
    col1, col2, col3, col4, col5 = st.columns(5)
    col1.metric("Tables", len(builder.tables))
    col2.metric("Columns", len(builder.columns))
    col3.metric("Foreign Keys", len(builder.foreign_keys))
    col4.metric("Business Terms", len(builder.business_terms))
    col5.metric("Query Patterns", len(builder.query_patterns))

    # Feedback stats
    st.subheader("Learning Statistics")
    stats = feedback_learner.get_stats()
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total Interactions", stats["total_interactions"])
    col2.metric("Positive Feedback", stats["positive"])
    col3.metric("Corrections", stats["corrections"])
    col4.metric("Accuracy Rate", f"{stats['accuracy_rate']:.0%}")

    col1, col2 = st.columns(2)
    col1.metric("Few-Shot Examples", stats["few_shot_examples"])
    col2.metric("Verified Examples", stats["verified_examples"])

    # Schema overview
    st.subheader("Schema Overview")
    schema_data = []
    for t in builder.tables:
        schema_data.append({
            "Table": t.name,
            "Columns": len(t.columns),
            "Rows": f"{t.row_count:,}",
            "Default Filters": len(t.default_filters),
            "Description": t.description[:80] + "..." if len(t.description) > 80 else t.description,
        })
    st.dataframe(pd.DataFrame(schema_data), use_container_width=True)

    # Business terms breakdown
    st.subheader("Business Terms by Source")
    term_sources = {}
    for bt in builder.business_terms:
        term_sources[bt.source] = term_sources.get(bt.source, 0) + 1
    if term_sources:
        st.bar_chart(pd.DataFrame(
            {"Source": list(term_sources.keys()), "Count": list(term_sources.values())}
        ).set_index("Source"))

    # Recent feedback log
    st.subheader("Recent Feedback")
    if feedback_learner.feedback_log:
        recent = feedback_learner.feedback_log[-10:][::-1]
        for entry in recent:
            icon = {"positive": "👍", "negative": "👎", "correction": "✏️", "default_filter": "🔧"}.get(
                entry["type"], "📝"
            )
            st.markdown(
                f"{icon} **{entry['type']}** — {entry.get('question', 'N/A')[:60]}... "
                f"({entry['timestamp'][:19]})"
            )
    else:
        st.info("No feedback yet. Start asking questions!")


# ── Router ────────────────────────────────────────────────────────

if page == "1. Connect":
    page_connect()
elif page == "2. Build Graph":
    page_build_graph()
elif page == "3. Ask Questions":
    page_ask()
elif page == "4. Teach & Feedback":
    page_feedback()
elif page == "5. Dashboard":
    page_dashboard()
