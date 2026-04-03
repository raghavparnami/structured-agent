"""
Accuracy Test Suite for GraphRAG SQL Agent.

Runs 100 questions against the agent, evaluates correctness, and generates a report.

Evaluation criteria:
1. EXECUTION: Did the SQL execute without errors?
2. TABLES: Did it use the expected tables?
3. RESULT: Did it return non-empty results (where expected)?
4. GROUND TRUTH: Does a key value in the result match expected?

Usage:
    python scripts/accuracy_test.py --provider gemini --api-key YOUR_KEY
"""

import argparse
import json
import os
import signal
import sys
import time
from dataclasses import dataclass, field

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pandas as pd
from config import AppConfig, DBConfig, LLMConfig
from core.db_adapter import create_adapter
from core.llm_provider import LLMProvider
from core.agent import SQLAgent
from core.validator import SQLValidator, SQLExecutor
from graph.builder import GraphBuilder
from graph.retriever import GraphRetriever
from feedback.learner import FeedbackLearner


# ── Test Case Definition ─────────────────────────────────────────

@dataclass
class TestCase:
    id: int
    question: str
    category: str                           # e.g., "simple", "medium", "hard", "brutal"
    expected_tables: list[str]              # tables that MUST appear in the SQL
    expect_results: bool = True             # should return non-empty results?
    expected_min_rows: int = 0              # minimum expected row count
    expected_max_rows: int = 99999          # maximum expected row count
    ground_truth_check: str = ""            # optional: a value that MUST appear in results
    notes: str = ""


@dataclass
class TestResult:
    test_id: int
    question: str
    category: str
    passed: bool = False
    sql_generated: str = ""
    execution_ok: bool = False
    tables_ok: bool = False
    results_ok: bool = False
    ground_truth_ok: bool = True            # default True if no check
    row_count: int = 0
    latency_ms: int = 0
    repairs: int = 0
    error: str = ""
    missing_tables: list[str] = field(default_factory=list)


# ── Test Cases (100 questions) ───────────────────────────────────

TEST_CASES = [
    # ═══════════════════════════════════════════════════════════
    # SIMPLE: Single table, basic filter/aggregation (1-2 tables)
    # ═══════════════════════════════════════════════════════════
    TestCase(1, "How many products do we have?", "simple", ["product"], expected_min_rows=1),
    TestCase(2, "List all active products", "simple", ["product"], expected_min_rows=1),
    TestCase(3, "How many employees are there?", "simple", ["employee"], expected_min_rows=1),
    TestCase(4, "Show all suppliers", "simple", ["supplier"], expected_min_rows=1),
    TestCase(5, "How many batches were produced in 2025?", "simple", ["batch"], expected_min_rows=1),
    TestCase(6, "List all rejected batches", "simple", ["batch"], expected_min_rows=1, ground_truth_check="BN-2025-005"),
    TestCase(7, "How many scrap events happened?", "simple", ["scrap_event"], expected_min_rows=1),
    TestCase(8, "Show all equipment types", "simple", ["equipment_type"], expected_min_rows=1),
    TestCase(9, "List all dosage forms", "simple", ["dosage_form"], expected_min_rows=1),
    TestCase(10, "How many raw materials are there?", "simple", ["raw_material"], expected_min_rows=1),
    TestCase(11, "Show all defect types with severity critical", "simple", ["defect_type"], expected_min_rows=1),
    TestCase(12, "List all sites", "simple", ["site"], expected_min_rows=1, ground_truth_check="US-01"),
    TestCase(13, "How many production lines are active?", "simple", ["production_line"], expected_min_rows=1),
    TestCase(14, "Show all scrap reasons in the equipment category", "simple", ["scrap_reason"], expected_min_rows=1),
    TestCase(15, "What are the different shift types?", "simple", ["shift_type"], expected_min_rows=3, expected_max_rows=3),
    TestCase(16, "How many open deviations are there?", "simple", ["deviation"], expected_min_rows=1),
    TestCase(17, "List all waste categories", "simple", ["waste_category"], expected_min_rows=1),
    TestCase(18, "Show batches with yield below 90%", "simple", ["batch"], expected_min_rows=1, ground_truth_check="BN-2025-005"),
    TestCase(19, "How many customers do we have?", "simple", ["customer"], expected_min_rows=1),
    TestCase(20, "What is the total number of test types?", "simple", ["test_type"], expected_min_rows=1),

    # ═══════════════════════════════════════════════════════════
    # MEDIUM: 2-3 table joins, moderate filters
    # ═══════════════════════════════════════════════════════════
    TestCase(21, "Show all batches with their product names", "medium", ["batch", "product"], expected_min_rows=1),
    TestCase(22, "List employees and their departments", "medium", ["employee", "department"], expected_min_rows=1),
    TestCase(23, "Show scrap events with their reason names", "medium", ["scrap_event", "scrap_reason"], expected_min_rows=1),
    TestCase(24, "Which products are in the Analgesic category?", "medium", ["product", "product_category"], expected_min_rows=1, ground_truth_check="Paracetamol"),
    TestCase(25, "Show equipment with their type names", "medium", ["equipment", "equipment_type"], expected_min_rows=1),
    TestCase(26, "List all suppliers from India", "medium", ["supplier", "country"], expected_min_rows=1, ground_truth_check="IndoPharma"),
    TestCase(27, "Show batches with their production line names", "medium", ["batch", "production_line"], expected_min_rows=1),
    TestCase(28, "What is the total scrap cost per batch?", "medium", ["scrap_event"], expected_min_rows=1),
    TestCase(29, "Show deviations with their type names and severity", "medium", ["deviation", "deviation_type"], expected_min_rows=1),
    TestCase(30, "List all GMP certified suppliers with their country", "medium", ["supplier", "country"], expected_min_rows=1),
    TestCase(31, "Show batch yield by product name", "medium", ["batch", "product"], expected_min_rows=1),
    TestCase(32, "Which raw materials are classified as API?", "medium", ["raw_material", "material_class"], expected_min_rows=1, ground_truth_check="Paracetamol"),
    TestCase(33, "Show all approved material lots with their material names", "medium", ["material_lot", "raw_material"], expected_min_rows=1),
    TestCase(34, "List QC test results that failed", "medium", ["qc_test_result"], expected_min_rows=1),
    TestCase(35, "Show production orders with their product names", "medium", ["production_order", "product"], expected_min_rows=1),
    TestCase(36, "What is the average batch yield per product?", "medium", ["batch", "product"], expected_min_rows=1),
    TestCase(37, "List all CAPAs that are still open", "medium", ["capa"], expected_min_rows=1),
    TestCase(38, "Show equipment maintenance records with equipment names", "medium", ["equipment_maintenance", "equipment"], expected_min_rows=1),
    TestCase(39, "Which batches were supervised by John Anderson?", "medium", ["batch", "employee"], expected_min_rows=1),
    TestCase(40, "Show total scrap quantity by scrap reason", "medium", ["scrap_event", "scrap_reason"], expected_min_rows=1),

    # ═══════════════════════════════════════════════════════════
    # HARD: 3-5 table joins, multiple filters
    # ═══════════════════════════════════════════════════════════
    TestCase(41, "Show scrap events from the Morning shift with reason names and batch numbers", "hard",
             ["scrap_event", "scrap_reason", "batch", "shift_type"], expected_min_rows=1),
    TestCase(42, "List all batches of Paracetamol 500mg with their yield and production line", "hard",
             ["batch", "product", "production_line"], expected_min_rows=1),
    TestCase(43, "Show equipment downtime with equipment name and type", "hard",
             ["equipment_downtime", "equipment", "equipment_type"], expected_min_rows=1),
    TestCase(44, "Which suppliers provided materials used in rejected batches?", "hard",
             ["batch", "batch_material_usage", "material_lot", "supplier"], expected_min_rows=1),
    TestCase(45, "Show scrap events where the reason category is equipment and batch yield was below 95%", "hard",
             ["scrap_event", "scrap_reason", "batch"], expected_min_rows=1),
    TestCase(46, "List deviations with their CAPA status and batch product name", "hard",
             ["deviation", "capa", "batch", "product"], expected_min_rows=1),
    TestCase(47, "Show all batches produced at the US site with their product names and yields", "hard",
             ["batch", "product", "site"], expected_min_rows=1),
    TestCase(48, "What is the scrap cost by production line and product?", "hard",
             ["scrap_event", "batch", "production_line", "product"], expected_min_rows=1),
    TestCase(49, "Show QC test results for batch BN-2025-001 with test type names", "hard",
             ["qc_test_result", "qc_sample", "test_type"], expected_min_rows=1, ground_truth_check="99.2"),
    TestCase(50, "List employees who performed equipment maintenance and their department", "hard",
             ["equipment_maintenance", "employee", "department"], expected_min_rows=1),
    TestCase(51, "Show material lots that were rejected with supplier names and material names", "hard",
             ["material_lot", "raw_material", "supplier"], expected_min_rows=1),
    TestCase(52, "What is the total scrap cost per site?", "hard",
             ["scrap_event", "batch", "site"], expected_min_rows=1),
    TestCase(53, "Show batches with their BOM details and product names", "hard",
             ["batch", "bill_of_materials", "product"], expected_min_rows=1),
    TestCase(54, "List all environmental monitoring readings that were out of spec with area names", "hard",
             ["environmental_monitoring", "production_area"], expected_min_rows=1),
    TestCase(55, "Show OEE records for Tablet Line 1 with equipment names", "hard",
             ["oee_record", "production_line"], expected_min_rows=1),
    TestCase(56, "Which operators ran batches on the Morning shift that had scrap events?", "hard",
             ["batch", "employee", "scrap_event", "shift_type"], expected_min_rows=1),
    TestCase(57, "Show all complaints with product and customer names", "hard",
             ["complaint", "product", "customer"], expected_min_rows=1),
    TestCase(58, "List batch costs broken down by cost type for rejected batches", "hard",
             ["batch_cost", "batch"], expected_min_rows=1),
    TestCase(59, "Show process steps for Paracetamol 500mg with their parameters", "hard",
             ["process_step", "process_parameter", "master_batch_record", "product"], expected_min_rows=1),
    TestCase(60, "What is the average OEE by production line?", "hard",
             ["oee_record", "production_line"], expected_min_rows=1),

    # ═══════════════════════════════════════════════════════════
    # BRUTAL: 5-8 table joins, complex filters, aggregations
    # ═══════════════════════════════════════════════════════════
    TestCase(61, "Show scrap events with batch number, product name, line name, shift type, and scrap reason category", "brutal",
             ["scrap_event", "batch", "product", "production_line", "shift_type", "scrap_reason"], expected_min_rows=1),
    TestCase(62, "For each supplier, show total quantity of materials received and how many lots were rejected", "brutal",
             ["supplier", "material_lot"], expected_min_rows=1),
    TestCase(63, "Show deviations that led to CAPAs with the batch product name, deviation type, and CAPA owner name", "brutal",
             ["deviation", "capa", "batch", "product", "deviation_type", "employee"], expected_min_rows=1),
    TestCase(64, "What is the scrap rate by product and site for Q1 2025?", "brutal",
             ["scrap_event", "batch", "product", "site"], expected_min_rows=1),
    TestCase(65, "Show equipment that had both downtime and maintenance in 2025 with their type and location", "brutal",
             ["equipment", "equipment_downtime", "equipment_maintenance", "equipment_type"], expected_min_rows=1),
    TestCase(66, "List all raw materials from approved Indian suppliers used in batches with yield below 96%", "brutal",
             ["raw_material", "supplier", "country", "batch_material_usage", "batch"], expected_min_rows=1),
    TestCase(67, "Show the full deviation-to-CAPA chain: deviation number, type, severity, batch, product, CAPA status, and owner", "brutal",
             ["deviation", "deviation_type", "capa", "batch", "product", "employee"], expected_min_rows=1),
    TestCase(68, "What is the total scrap cost by scrap reason category and production line name?", "brutal",
             ["scrap_event", "scrap_reason", "batch", "production_line"], expected_min_rows=1),
    TestCase(69, "Show batches where in-process checks failed with the test type, batch number, and product", "brutal",
             ["in_process_check", "batch", "product", "test_type"], expected_min_rows=1),
    TestCase(70, "For each site, show number of batches, number of scrap events, and total scrap cost in 2025", "brutal",
             ["site", "batch", "scrap_event"], expected_min_rows=1),
    TestCase(71, "Which production lines had the worst OEE and highest scrap rate?", "brutal",
             ["oee_record", "scrap_event", "batch", "production_line"], expected_min_rows=1),
    TestCase(72, "Show all material lots used in batch BN-2025-013 with material name, supplier, and lot status", "brutal",
             ["batch_material_usage", "material_lot", "raw_material", "supplier", "batch"], expected_min_rows=1),
    TestCase(73, "List open CAPAs with their deviation details, affected batch, product, and due date", "brutal",
             ["capa", "deviation", "batch", "product"], expected_min_rows=1),
    TestCase(74, "Show the top 5 scrap reasons by total cost with their category", "brutal",
             ["scrap_event", "scrap_reason"], expected_min_rows=1),
    TestCase(75, "For each product, show total batches produced, batches rejected, and average yield", "brutal",
             ["batch", "product"], expected_min_rows=1),
    TestCase(76, "Show sales orders with customer name, product name, and shipment status", "brutal",
             ["sales_order", "customer", "sales_order_line", "product"], expected_min_rows=1),
    TestCase(77, "Which equipment had calibration failures and what batches were running at the time?", "brutal",
             ["calibration_record", "equipment", "equipment_logbook"], expected_min_rows=0),
    TestCase(78, "Show scrap events caused by operator error with the operator name, batch, and product", "brutal",
             ["scrap_event", "scrap_reason", "employee", "batch", "product"], expected_min_rows=1),
    TestCase(79, "Compare yield trends between US and India sites by month in 2025", "brutal",
             ["batch", "site"], expected_min_rows=1),
    TestCase(80, "Show the complete batch cost breakdown for all rejected batches with product names", "brutal",
             ["batch_cost", "batch", "product"], expected_min_rows=1),

    # ═══════════════════════════════════════════════════════════
    # NIGHTMARE: 6-10 tables, complex logic, edge cases
    # ═══════════════════════════════════════════════════════════
    TestCase(81, "For each supplier, show materials supplied, lots rejected, batches affected by their material quality issues, and any open CAPAs", "nightmare",
             ["supplier", "material_lot", "batch_material_usage", "batch", "deviation", "capa"], expected_min_rows=0),
    TestCase(82, "Show the full traceability for batch BN-2025-001: materials used, QC results, yield at each stage, and total cost", "nightmare",
             ["batch", "batch_material_usage", "raw_material", "qc_test_result", "batch_yield", "batch_cost"], expected_min_rows=1),
    TestCase(83, "Which production areas had environmental excursions that coincided with batch scrap events?", "nightmare",
             ["environmental_monitoring", "production_area", "batch", "scrap_event"], expected_min_rows=0),
    TestCase(84, "Show a supplier quality scorecard: lots received, lots rejected, linked batch failures, and total scrap cost caused by their materials", "nightmare",
             ["supplier", "material_lot", "batch_material_usage", "batch", "scrap_event"], expected_min_rows=0),
    TestCase(85, "For each product, show the batch with the worst yield, its scrap reasons, deviations raised, and total cost impact", "nightmare",
             ["product", "batch", "scrap_event", "scrap_reason", "deviation", "batch_cost"], expected_min_rows=1),
    TestCase(86, "Show all employees involved in rejected batches: supervisors, operators who reported scrap, and QC analysts who found OOS results", "nightmare",
             ["batch", "employee", "scrap_event", "qc_oos_event"], expected_min_rows=1),
    TestCase(87, "Compare equipment OEE against scrap rate for each production line, including the most common scrap reason", "nightmare",
             ["oee_record", "scrap_event", "scrap_reason", "production_line", "batch"], expected_min_rows=1),
    TestCase(88, "Show the complete deviation history for Tablet Line 1: deviation type, severity, batch affected, root cause, CAPA status, and days to closure", "nightmare",
             ["deviation", "deviation_type", "batch", "production_line", "capa"], expected_min_rows=1),
    TestCase(89, "For batch BN-2025-013, show the complete failure chain: what went wrong at each process step, which materials were involved, which deviations were raised, and what the total financial impact was", "nightmare",
             ["batch", "scrap_event", "process_step", "deviation", "batch_cost"], expected_min_rows=1),
    TestCase(90, "Which raw materials have the highest scrap cost association across all batches?", "nightmare",
             ["raw_material", "batch_material_usage", "batch", "scrap_event"], expected_min_rows=0),

    # ═══════════════════════════════════════════════════════════
    # EDGE CASES: Tricky phrasing, empty results, ambiguity
    # ═══════════════════════════════════════════════════════════
    TestCase(91, "Are there any product recalls?", "edge", ["product_recall"], expect_results=False),
    TestCase(92, "Show me batches that have never had any scrap", "edge", ["batch"], expected_min_rows=1),
    TestCase(93, "What is our best performing product by yield?", "edge", ["batch", "product"], expected_min_rows=1),
    TestCase(94, "How much money did we waste on scrap in total?", "edge", ["scrap_event"], expected_min_rows=1),
    TestCase(95, "Which batch took the longest to produce?", "edge", ["batch"], expected_min_rows=1),
    TestCase(96, "Show me everything about batch BN-2025-005", "edge", ["batch"], expected_min_rows=1, ground_truth_check="rejected"),
    TestCase(97, "Are any material lots expiring in the next 6 months?", "edge", ["material_lot"], expected_min_rows=0),
    TestCase(98, "What percentage of batches were rejected?", "edge", ["batch"], expected_min_rows=1),
    TestCase(99, "Show me the most expensive scrap event", "edge", ["scrap_event"], expected_min_rows=1),
    TestCase(100, "Which site has the best batch approval rate?", "edge", ["batch", "site"], expected_min_rows=1),
]


# ── Test Runner ──────────────────────────────────────────────────

def _run_single_test(agent: SQLAgent, tc: TestCase, index: int, total: int) -> TestResult:
    """Run a single test case and return the result."""
    result = TestResult(
        test_id=tc.id,
        question=tc.question,
        category=tc.category,
    )

    try:
        start = time.time()
        ctx = agent.run(tc.question)
        elapsed = int((time.time() - start) * 1000)

        result.latency_ms = elapsed
        result.repairs = ctx.repair_attempts

        if ctx.generated_sql:
            result.sql_generated = ctx.generated_sql

        if ctx.state.value == "done":
            result.execution_ok = True
        else:
            result.error = ctx.error or "Agent did not reach DONE state"

        if result.sql_generated:
            sql_lower = result.sql_generated.lower()
            missing = [t for t in tc.expected_tables if t.lower() not in sql_lower]
            result.tables_ok = len(missing) == 0
            result.missing_tables = missing
        else:
            result.tables_ok = False

        if ctx.query_result is not None:
            result.row_count = len(ctx.query_result)
            if tc.expect_results:
                result.results_ok = result.row_count >= tc.expected_min_rows
            else:
                result.results_ok = True
        else:
            result.results_ok = not tc.expect_results

        if tc.ground_truth_check and ctx.query_result is not None and not ctx.query_result.empty:
            df_str = ctx.query_result.to_string()
            result.ground_truth_ok = tc.ground_truth_check.lower() in df_str.lower()
        elif tc.ground_truth_check:
            result.ground_truth_ok = False
        else:
            result.ground_truth_ok = True

        result.passed = (
            result.execution_ok
            and result.tables_ok
            and result.results_ok
            and result.ground_truth_ok
        )

        status = "PASS" if result.passed else "FAIL"
        fail_reasons = []
        if not result.execution_ok:
            fail_reasons.append("exec")
        if not result.tables_ok:
            fail_reasons.append(f"tables({','.join(result.missing_tables)})")
        if not result.results_ok:
            fail_reasons.append(f"rows({result.row_count})")
        if not result.ground_truth_ok:
            fail_reasons.append("ground_truth")

        reason_str = f" [{', '.join(fail_reasons)}]" if fail_reasons else ""
        print(f"  [{index+1}/{total}] {tc.category.upper()} | {tc.question[:50]}... → {status}{reason_str} | {elapsed}ms", flush=True)

    except Exception as e:
        result.error = str(e)
        print(f"  [{index+1}/{total}] {tc.category.upper()} | {tc.question[:50]}... → ERROR: {e}", flush=True)

    return result


def run_tests(agent: SQLAgent, test_cases: list[TestCase], batch_size: int = 3) -> list[TestResult]:
    """Run test cases in concurrent batches for speed."""
    from concurrent.futures import ThreadPoolExecutor, as_completed

    results: list[TestResult] = []
    total = len(test_cases)

    # Process in batches
    for batch_start in range(0, total, batch_size):
        batch = test_cases[batch_start:batch_start + batch_size]

        with ThreadPoolExecutor(max_workers=batch_size) as pool:
            futures = {
                pool.submit(_run_single_test, agent, tc, batch_start + i, total): tc
                for i, tc in enumerate(batch)
            }
            for future in as_completed(futures):
                results.append(future.result())

    # Sort by test_id for consistent reporting
    results.sort(key=lambda r: r.test_id)
    return results


# ── Report Generator ─────────────────────────────────────────────

def generate_report(results: list[TestResult]) -> str:
    """Generate a detailed accuracy report."""
    total = len(results)
    passed = sum(1 for r in results if r.passed)
    failed = total - passed

    # By category
    categories = {}
    for r in results:
        cat = r.category
        if cat not in categories:
            categories[cat] = {"total": 0, "passed": 0, "latency": []}
        categories[cat]["total"] += 1
        if r.passed:
            categories[cat]["passed"] += 1
        categories[cat]["latency"].append(r.latency_ms)

    # By failure type
    exec_failures = sum(1 for r in results if not r.execution_ok)
    table_failures = sum(1 for r in results if not r.tables_ok and r.execution_ok)
    result_failures = sum(1 for r in results if not r.results_ok and r.execution_ok and r.tables_ok)
    gt_failures = sum(1 for r in results if not r.ground_truth_ok and r.execution_ok and r.tables_ok and r.results_ok)

    total_latency = sum(r.latency_ms for r in results)
    avg_latency = total_latency / total if total > 0 else 0
    total_repairs = sum(r.repairs for r in results)

    lines = []
    lines.append("=" * 70)
    lines.append("  GRAPHRAG SQL AGENT — ACCURACY TEST REPORT")
    lines.append("=" * 70)
    lines.append("")
    lines.append(f"  Total Questions:    {total}")
    lines.append(f"  Passed:             {passed} ({passed/total*100:.1f}%)")
    lines.append(f"  Failed:             {failed} ({failed/total*100:.1f}%)")
    lines.append(f"  Average Latency:    {avg_latency:.0f}ms")
    lines.append(f"  Total Repairs:      {total_repairs}")
    lines.append(f"  Total Test Time:    {total_latency/1000:.1f}s")
    lines.append("")

    lines.append("-" * 70)
    lines.append("  ACCURACY BY CATEGORY")
    lines.append("-" * 70)
    lines.append(f"  {'Category':<15} {'Pass':>6} {'Total':>6} {'Rate':>8} {'Avg Latency':>12}")
    lines.append(f"  {'─'*15} {'─'*6} {'─'*6} {'─'*8} {'─'*12}")
    for cat in ["simple", "medium", "hard", "brutal", "nightmare", "edge"]:
        if cat in categories:
            c = categories[cat]
            rate = c["passed"] / c["total"] * 100 if c["total"] > 0 else 0
            avg_lat = sum(c["latency"]) / len(c["latency"]) if c["latency"] else 0
            lines.append(f"  {cat:<15} {c['passed']:>6} {c['total']:>6} {rate:>7.1f}% {avg_lat:>10.0f}ms")

    lines.append("")
    lines.append("-" * 70)
    lines.append("  FAILURE BREAKDOWN")
    lines.append("-" * 70)
    lines.append(f"  Execution failures (SQL error/timeout):   {exec_failures}")
    lines.append(f"  Wrong tables used:                        {table_failures}")
    lines.append(f"  Wrong result count:                       {result_failures}")
    lines.append(f"  Ground truth mismatch:                    {gt_failures}")

    # Failed questions detail
    failed_results = [r for r in results if not r.passed]
    if failed_results:
        lines.append("")
        lines.append("-" * 70)
        lines.append("  FAILED QUESTIONS")
        lines.append("-" * 70)
        for r in failed_results:
            reasons = []
            if not r.execution_ok:
                reasons.append("EXEC_FAIL")
            if not r.tables_ok:
                reasons.append(f"MISSING_TABLES: {','.join(r.missing_tables)}")
            if not r.results_ok:
                reasons.append(f"ROWS: {r.row_count}")
            if not r.ground_truth_ok:
                reasons.append("GROUND_TRUTH")
            lines.append(f"")
            lines.append(f"  #{r.test_id} [{r.category}] {r.question[:60]}...")
            lines.append(f"    Reason: {' | '.join(reasons)}")
            if r.error:
                lines.append(f"    Error:  {r.error[:100]}")

    lines.append("")
    lines.append("=" * 70)
    lines.append(f"  OVERALL ACCURACY: {passed/total*100:.1f}%")
    lines.append("=" * 70)

    return "\n".join(lines)


# ── Main ─────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Run accuracy tests on GraphRAG SQL Agent")
    parser.add_argument("--provider", default="gemini", choices=["openai", "gemini"])
    parser.add_argument("--api-key", required=True, help="LLM API key")
    parser.add_argument("--strong-model", default=None, help="Override strong model")
    parser.add_argument("--fast-model", default=None, help="Override fast model")
    parser.add_argument("--db-host", default="localhost")
    parser.add_argument("--db-port", type=int, default=5432)
    parser.add_argument("--db-name", default="pharma_manufacturing")
    parser.add_argument("--db-user", default=os.environ.get("USER", "postgres"))
    parser.add_argument("--db-pass", default="")
    parser.add_argument("--limit", type=int, default=100, help="Number of test cases to run")
    parser.add_argument("--category", default=None, help="Run only this category")
    parser.add_argument("--batch-size", type=int, default=3, help="Concurrent questions per batch")
    parser.add_argument("--output", default="scripts/accuracy_report.txt", help="Output file")
    args = parser.parse_args()

    # Config
    db_config = DBConfig(
        db_type="postgresql",
        host=args.db_host,
        port=args.db_port,
        database=args.db_name,
        user=args.db_user,
        password=args.db_pass,
    )
    llm_config = LLMConfig(provider=args.provider)
    if args.provider == "openai":
        llm_config.openai_api_key = args.api_key
        if args.strong_model:
            llm_config.openai_strong_model = args.strong_model
        if args.fast_model:
            llm_config.openai_fast_model = args.fast_model
    else:
        llm_config.gemini_api_key = args.api_key
        if args.strong_model:
            llm_config.gemini_strong_model = args.strong_model
        if args.fast_model:
            llm_config.gemini_fast_model = args.fast_model

    config = AppConfig(db=db_config, llm=llm_config)

    # Create adapter
    adapter = create_adapter(
        "postgresql",
        host=args.db_host, port=args.db_port,
        database=args.db_name, user=args.db_user, password=args.db_pass,
    )
    adapter.test_connection()
    print("DB connection OK")

    # LLM
    llm = LLMProvider(llm_config)
    print(f"LLM provider: {args.provider}")

    # Build or load graph
    builder = GraphBuilder(config, llm, adapter)
    if builder.load_cache():
        print("Graph loaded from cache")
    else:
        print("Building graph from scratch (this may take a while)...")
        builder.build()
        builder.save_cache()
        print("Graph built and cached")

    graph = builder.graph

    # Initialize agent
    table_names = {d["data"].name for _, d in graph.nodes(data=True) if d.get("type") == "table"}
    column_names = {d["data"].full_name for _, d in graph.nodes(data=True) if d.get("type") == "column"}

    feedback_learner = FeedbackLearner(config, llm, builder)
    feedback_learner.load_learned_terms_into_graph()

    retriever = GraphRetriever(graph, llm, config.agent, few_shot_store=feedback_learner.few_shot_store)
    validator = SQLValidator(config, table_names, column_names, adapter)
    executor = SQLExecutor(config, adapter)
    agent = SQLAgent(
        config, llm, retriever, validator, executor,
        few_shot_store=feedback_learner.few_shot_store,
        db_dialect=adapter.dialect,
        date_functions_hint=adapter.date_functions_hint,
    )

    print(f"Agent ready: {len(table_names)} tables, {graph.number_of_nodes()} graph nodes")

    # Filter test cases
    cases = TEST_CASES[:args.limit]
    if args.category:
        cases = [tc for tc in cases if tc.category == args.category]
    print(f"\nRunning {len(cases)} test cases...\n")

    # Run tests
    results = run_tests(agent, cases, batch_size=args.batch_size)

    # Generate report
    report = generate_report(results)
    print("\n" + report)

    # Save report
    with open(args.output, "w") as f:
        f.write(report)
    print(f"\nReport saved to {args.output}")

    # Save detailed results as JSON
    json_output = args.output.replace(".txt", ".json")
    json_data = []
    for r in results:
        json_data.append({
            "test_id": r.test_id,
            "question": r.question,
            "category": r.category,
            "passed": r.passed,
            "execution_ok": r.execution_ok,
            "tables_ok": r.tables_ok,
            "results_ok": r.results_ok,
            "ground_truth_ok": r.ground_truth_ok,
            "row_count": r.row_count,
            "latency_ms": r.latency_ms,
            "repairs": r.repairs,
            "sql": r.sql_generated,
            "error": r.error,
            "missing_tables": r.missing_tables,
        })
    with open(json_output, "w") as f:
        json.dump(json_data, f, indent=2)
    print(f"Detailed results saved to {json_output}")


if __name__ == "__main__":
    main()
