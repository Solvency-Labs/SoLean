from __future__ import annotations

import contextlib
from functools import lru_cache
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.classify_yul import (
    classify_text,
    inspect_solc_function_text,
    inspect_solc_text,
    main as classify_yul_main,
    solc_function_summary_to_data,
    summarize_solc_function_text,
    summarize_require_helper,
    summarize_solc_inspection_line,
    summarize_transparent_helpers,
)
from scripts.check_equiv import main as check_equiv_main
from scripts.check_counter_bridge import (
    build_counter_bridge_report,
    main as check_counter_bridge_main,
)
from scripts.demo_counter_bridge import main as demo_counter_bridge_main
from scripts.normalize_yul import normalize_text
from scripts.solidity_to_solean import (
    contract_to_source_data,
    is_supported_counter,
    main as solidity_to_solean_main,
    parse_counter,
)
from scripts.solean_to_yul import main as solean_to_yul_main
from scripts.yul_subset import (
    SymCall,
    SymConst,
    UINT256_MAX,
    TraceCase,
    compare_counter_traces,
    compare_symbolic_summaries,
    counter_object,
    execute_object,
    object_to_data,
    object_from_data,
    parse_object,
    render_object,
    run_counter_trace,
    summarize_symbolic,
)


SOLC_COUNTER_IR_SAMPLE = """
IR:

object "Counter_26" {
  code {
    mstore(64, memoryguard(128))
  }
  object "Counter_26_deployed" {
    code {
      mstore(64, memoryguard(128))
      function fun_inc_25(var_amount_5) {
        let expr_9 := var_amount_5
        let expr_10 := 0x00
        let expr_11 := gt(cleanup_t_uint256(expr_9), expr_10)
        require_helper(expr_11)
        let _2 := var_amount_5
        let expr_15 := _2
        let _3 := read_from_storage_split_offset_0_t_uint256(0x00)
        let expr_16 := checked_add_t_uint256(_3, expr_15)
        update_storage_value_offset_0_t_uint256_to_t_uint256(0x00, expr_16)
        let _4 := read_from_storage_split_offset_0_t_uint256(0x00)
        let expr_19 := _4
        let _5 := var_amount_5
        let expr_20 := _5
        let expr_21 := iszero(lt(cleanup_t_uint256(expr_19), cleanup_t_uint256(expr_20)))
        assert_helper(expr_21)
      }
    }
  }
}
"""

SOLC_SUPPORTED_FUNCTION_SAMPLE = """
IR:

object "Counter_26" {
  code {
  }
  object "Counter_26_deployed" {
    code {
      function external_fun_inc_25() {
        external_call()
      }
      function fun_inc_25(amount) {
        if iszero(gt(amount, 0)) { revert(0, 0) }
        let old_x := sload(0)
        let new_x := add(old_x, amount)
        if lt(new_x, old_x) { revert(0, 0) }
        sstore(0, new_x)
        if lt(new_x, amount) { revert(0, 0) }
      }
    }
  }
}
"""

def lake_command() -> str:
    if lake := shutil.which("lake"):
        return lake
    elan_lake = Path.home() / ".elan" / "bin" / "lake"
    if elan_lake.exists():
        return str(elan_lake)
    return "lake"


def lean_artifact_text(kind: str) -> str:
    result = subprocess.run(
        [
            lake_command(),
            "env",
            "lean",
            "--run",
            "SoLean/CounterArtifactsMain.lean",
            kind,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


@lru_cache(maxsize=None)
def lean_artifact(kind: str) -> dict:
    return json.loads(lean_artifact_text(kind))


def expected_counter_summary_rules() -> list[str]:
    return lean_artifact("bridge-json")["expectedTrustedRules"]


def copied_json(data: dict) -> dict:
    return json.loads(json.dumps(data))


def check_named(report: dict, name: str) -> dict:
    for check in report["checks"]:
        if check["name"] == name:
            return check
    raise AssertionError(f"missing check: {name}")


class NormalizeYulTests(unittest.TestCase):
    def test_normalize_strips_comments_and_collapses_whitespace(self) -> None:
        source = """
        // leading comment
        object "Counter" {
          /* block comment */
          code {
            let x := add(1,   2) // trailing comment
          }
        }
        """

        self.assertEqual(
            normalize_text(source),
            'object "Counter" {\n'
            "code {\n"
            "let x := add(1, 2)\n"
            "}\n"
            "}\n",
        )

    def test_normalize_empty_input_returns_empty_string(self) -> None:
        self.assertEqual(normalize_text(" // just a comment\n"), "")


class YulSubsetTests(unittest.TestCase):
    def test_lean_counter_artifact_output_is_deterministic(self) -> None:
        self.assertEqual(
            lean_artifact_text("source-json"),
            lean_artifact_text("source-json"),
        )
        self.assertEqual(lean_artifact_text("yul-json"), lean_artifact_text("yul-json"))
        self.assertEqual(
            lean_artifact_text("bridge-json"),
            lean_artifact_text("bridge-json"),
        )

    def test_lean_bridge_manifest_exports_expected_boundary(self) -> None:
        manifest = lean_artifact("bridge-json")

        self.assertEqual(manifest["kind"], "counterBridgeManifest")
        self.assertEqual(manifest["sourceArtifact"]["export"], "source-json")
        self.assertEqual(manifest["yulArtifact"]["export"], "yul-json")
        self.assertIn(
            "SoLean.Examples.CounterCompiler.compiled_counter_success_assertion",
            manifest["proofReferences"],
        )
        self.assertEqual(
            manifest["expectedTrustedRules"],
            [
                "hexLiteralAsNat",
                "transparentValueHelper",
                "requireHelperAsRevertGuard",
                "storageReadSlot0AsSload",
                "checkedAddUInt256AsAddWithOverflowGuard",
                "storageUpdateSlot0AsSstore",
                "assertHelperAsRevertGuard",
            ],
        )

    def test_bridge_rule_proofs_align_with_expected_rules(self) -> None:
        manifest = lean_artifact("bridge-json")
        rule_proofs = manifest["bridgeRuleProofs"]
        proof_references = manifest["proofReferences"]

        # The rule list inside `bridgeRuleProofs` must be the same list, in the
        # same order, as the trusted-rule boundary itself. This keeps the two
        # views of the boundary from drifting.
        self.assertEqual(
            [entry["rule"] for entry in rule_proofs],
            manifest["expectedTrustedRules"],
        )

        # Every non-empty `leanProof` reference must also appear in the manifest's
        # `proofReferences` list, so a Lean-backed rule is always discoverable
        # from the audit's proof index.
        for entry in rule_proofs:
            if entry["leanProof"]:
                self.assertIn(entry["leanProof"], proof_references)

        # These rules have Lean-backed semantic translations. Make them
        # explicit so a regression is loud.
        require_entry = next(
            entry for entry in rule_proofs if entry["rule"] == "requireHelperAsRevertGuard"
        )
        self.assertEqual(
            require_entry["leanProof"],
            "SoLean.Bridge.RequireHelper.target_refines_source",
        )
        checked_add_entry = next(
            entry
            for entry in rule_proofs
            if entry["rule"] == "checkedAddUInt256AsAddWithOverflowGuard"
        )
        self.assertEqual(
            checked_add_entry["leanProof"],
            "SoLean.Bridge.CheckedAdd.counterTarget_refines_source",
        )
        assert_entry = next(
            entry for entry in rule_proofs if entry["rule"] == "assertHelperAsRevertGuard"
        )
        self.assertEqual(
            assert_entry["leanProof"],
            "SoLean.Bridge.AssertHelper.targetForIszero_refines_source",
        )

    def test_counter_object_matches_lean_exported_counter_yul_shape(self) -> None:
        self.assertEqual(object_to_data(counter_object()), lean_artifact("yul-json"))

    def test_counter_yul_can_render_from_lean_exported_artifact(self) -> None:
        obj = object_from_data(lean_artifact("yul-json"))

        self.assertEqual(obj, counter_object())
        self.assertEqual(parse_object(render_object(obj)), counter_object())

    def test_counter_render_round_trips_through_subset_parser(self) -> None:
        rendered = render_object(counter_object())
        self.assertEqual(parse_object(rendered), counter_object())
        self.assertIn("function inc(amount)", rendered)
        self.assertIn("if lt(new_x, old_x) { revert(0, 0) }", rendered)

    def test_solean_to_yul_emits_parseable_counter_subset(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solean_to_yul_main(["--example", "counter"])

        self.assertEqual(code, 0)
        self.assertEqual(parse_object(output.getvalue()), counter_object())
        self.assertEqual(
            object_to_data(parse_object(output.getvalue())),
            lean_artifact("yul-json"),
        )

    def test_solean_to_yul_matches_counter_golden_file(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solean_to_yul_main(["--example", "counter"])

        self.assertEqual(code, 0)
        self.assertEqual(output.getvalue(), Path("tests/golden/Counter.solean.yul").read_text())

    def test_solean_to_yul_can_render_from_lean_artifact(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solean_to_yul_main(["--example", "counter", "--source", "lean-artifact"])

        self.assertEqual(code, 0)
        self.assertIn("rendered from SoLean's Lean-owned Counter Yul artifact", output.getvalue())
        self.assertEqual(parse_object(output.getvalue()), counter_object())

    def test_store_parser_handles_nested_value_expression(self) -> None:
        source = """
        object "Nested" {
          code {
            function f(amount) {
              sstore(0, add(amount, 1))
            }
          }
        }
        """

        self.assertIn("add(amount, 1)", render_object(parse_object(source)))

    def test_hex_literals_parse_render_evaluate_and_summarize(self) -> None:
        source = """
        object "Hex" {
          code {
            function f(amount) {
              let x := 0x10
              let y := add(x, 0x02)
              sstore(0x00, y)
              if lt(y, 0x12) { revert(0, 0) }
            }
          }
        }
        """

        obj = parse_object(source)
        self.assertIn("let x := 16", render_object(obj))
        self.assertIn("sstore(0, y)", render_object(obj))

        result = execute_object(obj, {"amount": 0}, {})
        self.assertFalse(result.reverted)
        self.assertEqual(result.storage[0], 18)

        summary = summarize_symbolic(obj)
        self.assertEqual(
            summary.final_writes,
            ((0, SymCall("add", (SymConst(16), SymConst(2)))),),
        )
        self.assertEqual(
            summary.revert_conditions,
            (
                SymCall(
                    "lt",
                    (SymCall("add", (SymConst(16), SymConst(2))), SymConst(18)),
                ),
            ),
        )

    def test_counter_trace_interpreter_models_revert_success_and_overflow(self) -> None:
        obj = counter_object()

        self.assertEqual(run_counter_trace(obj, TraceCase(amount=0, slot0=0)).reverted, True)
        self.assertEqual(run_counter_trace(obj, TraceCase(amount=3, slot0=5)).slot0, 8)
        self.assertEqual(
            run_counter_trace(obj, TraceCase(amount=1, slot0=UINT256_MAX)).reverted,
            True,
        )

    def test_counter_trace_comparison_finds_removed_overflow_guard(self) -> None:
        left = counter_object()
        right = parse_object(
            render_object(counter_object()).replace(
                "      if lt(new_x, old_x) { revert(0, 0) }\n", ""
            )
        )

        diffs = compare_counter_traces(left, right)
        self.assertGreaterEqual(len(diffs), 1)

    def test_symbolic_summary_finds_removed_overflow_guard(self) -> None:
        left = counter_object()
        right = parse_object(
            render_object(counter_object()).replace(
                "      if lt(new_x, old_x) { revert(0, 0) }\n", ""
            )
        )

        diffs = compare_symbolic_summaries(left, right)
        self.assertEqual(len(diffs), 1)


class ClassifyYulTests(unittest.TestCase):
    def test_counter_subset_classifies_as_supported(self) -> None:
        classification = classify_text(render_object(counter_object()))

        self.assertEqual(classification.kind, "supported-subset")
        self.assertTrue(classification.is_supported)

    def test_solc_preamble_classifies_as_unsupported_wrapper(self) -> None:
        classification = classify_text(
            "======= examples/Counter.sol:Counter =======\n"
            "IR:\n"
            + render_object(counter_object())
        )

        self.assertEqual(classification.kind, "unsupported-wrapper")
        self.assertIn("solc output preamble", classification.message)

    def test_solc_inspection_selects_deployed_object_blocker(self) -> None:
        inspection = inspect_solc_text(SOLC_COUNTER_IR_SAMPLE)

        self.assertEqual(inspection.kind, "unsupported-statement")
        self.assertIsNotNone(inspection.selected_object)
        self.assertEqual(inspection.selected_object.name, "Counter_26_deployed")
        self.assertIn("mstore", inspection.message)

    def test_solc_function_inspection_selects_fun_inc_body(self) -> None:
        inspection = inspect_solc_function_text(SOLC_COUNTER_IR_SAMPLE, "inc")

        self.assertEqual(inspection.kind, "unsupported-expression")
        self.assertIsNotNone(inspection.selected_function)
        self.assertEqual(inspection.selected_function.name, "fun_inc_25")
        self.assertIn("read_from_storage_split_offset_0_t_uint256", inspection.message)

    def test_transparent_solc_value_helpers_are_summarized(self) -> None:
        self.assertEqual(
            summarize_transparent_helpers(
                "let expr_11 := "
                "gt(cleanup_t_uint256(expr_9), "
                "convert_t_rational_0_by_1_to_t_uint256(expr_10))"
            ),
            "let expr_11 := gt(expr_9, expr_10)",
        )
        self.assertEqual(
            summarize_transparent_helpers(
                "let x := cleanup_t_uint256(identity(cleanup_t_uint256(value)))"
            ),
            "let x := value",
        )

    def test_require_helper_is_summarized_as_revert_guard(self) -> None:
        self.assertEqual(
            summarize_require_helper("require_helper(expr_11)"),
            "if iszero(expr_11) { revert(0, 0) }",
        )
        self.assertEqual(
            summarize_solc_inspection_line(
                "require_helper(cleanup_t_uint256(expr_11))"
            ),
            "if iszero(expr_11) { revert(0, 0) }",
        )

    def test_solc_counter_function_summary_matches_lean_yul_shape(self) -> None:
        summary = summarize_solc_function_text(SOLC_COUNTER_IR_SAMPLE, "inc")
        summary_data = solc_function_summary_to_data(summary)

        self.assertEqual(
            summary_data["normalized"],
            lean_artifact("yul-json"),
        )
        self.assertEqual(
            summary_data["trustedRules"],
            expected_counter_summary_rules(),
        )

    def test_solc_counter_function_summary_cli_outputs_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "Counter.solc.yul"
            source.write_text(SOLC_COUNTER_IR_SAMPLE)

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = classify_yul_main(["--summarize-function", "inc", str(source)])

        self.assertEqual(code, 0)
        data = json.loads(output.getvalue())
        self.assertEqual(data["kind"], "solcFunctionSummary")
        self.assertEqual(data["normalized"], lean_artifact("yul-json"))
        self.assertEqual(data["trustedRules"], expected_counter_summary_rules())

    def test_solc_function_inspection_can_accept_supported_body(self) -> None:
        inspection = inspect_solc_function_text(SOLC_SUPPORTED_FUNCTION_SAMPLE, "inc")

        self.assertEqual(inspection.kind, "supported-subset")
        self.assertIsNotNone(inspection.selected_function)
        self.assertEqual(inspection.selected_function.name, "fun_inc_25")

    def test_unsupported_statement_classifies_distinctly(self) -> None:
        classification = classify_text(
            'object "Counter" {\n'
            "  code {\n"
            "    function inc(amount) {\n"
            "      mstore(0, amount)\n"
            "    }\n"
            "  }\n"
            "}\n"
        )

        self.assertEqual(classification.kind, "unsupported-statement")
        self.assertIn("mstore", classification.message)

    def test_classifier_cli_returns_zero_for_supported_subset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "Counter.yul"
            source.write_text(render_object(counter_object()))

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = classify_yul_main([str(source)])

        self.assertEqual(code, 0)
        self.assertIn("supported-subset", output.getvalue())


class CounterBridgeTests(unittest.TestCase):
    def write_bridge_inputs(self, tmp: str, solc_text: str = SOLC_COUNTER_IR_SAMPLE) -> tuple[Path, Path]:
        solidity = Path(tmp) / "Counter.sol"
        solc_yul = Path(tmp) / "Counter.solc.yul"
        solidity.write_text(Path("examples/Counter.sol").read_text())
        solc_yul.write_text(solc_text)
        return solidity, solc_yul

    def test_counter_bridge_report_passes_on_current_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)
            report = build_counter_bridge_report(
                solidity,
                solc_yul,
                lean_source=lean_artifact("source-json"),
                lean_yul=lean_artifact("yul-json"),
                lean_manifest=lean_artifact("bridge-json"),
            )

        self.assertEqual(report["kind"], "counterBridgeReport")
        self.assertEqual(report["status"], "passed")
        self.assertEqual(
            [check["status"] for check in report["checks"]],
            ["passed", "passed", "passed", "passed"],
        )
        self.assertEqual(report["solc"]["sourceFunction"], "fun_inc_25")
        self.assertEqual(report["solc"]["trustedRules"], expected_counter_summary_rules())
        self.assertEqual(
            report["bridgeManifest"]["expectedTrustedRules"],
            expected_counter_summary_rules(),
        )
        self.assertIn("bridgeManifest", report["leanArtifacts"])
        self.assertIn("not semantic equivalence", " ".join(report["limitations"]))

    def test_counter_bridge_cli_outputs_deterministic_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)
            args = [
                "--solidity",
                str(solidity),
                "--solc-yul",
                str(solc_yul),
            ]

            first = io.StringIO()
            with contextlib.redirect_stdout(first):
                first_code = check_counter_bridge_main(args)

            second = io.StringIO()
            with contextlib.redirect_stdout(second):
                second_code = check_counter_bridge_main(args)

        self.assertEqual(first_code, 0)
        self.assertEqual(second_code, 0)
        self.assertEqual(first.getvalue(), second.getvalue())
        self.assertEqual(json.loads(first.getvalue())["status"], "passed")

    def test_counter_bridge_cli_outputs_markdown_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_counter_bridge_main([
                    "--format",
                    "markdown",
                    "--solidity",
                    str(solidity),
                    "--solc-yul",
                    str(solc_yul),
                ])

        self.assertEqual(code, 0)
        report = output.getvalue()
        self.assertIn("## Proved In Lean", report)
        self.assertIn("## Tested Against Lean Artifacts", report)
        self.assertIn("## Lean-Backed Adapter Rules", report)
        self.assertIn("## Still Trusted Boundaries", report)
        self.assertIn("## Explicit Non-Claims", report)
        self.assertIn("SoLean.Bridge.CheckedAdd.counterTarget_refines_source", report)
        self.assertIn("SoLean.Bridge.AssertHelper.targetForIszero_refines_source", report)

    def test_counter_bridge_reports_source_shape_mismatch(self) -> None:
        bad_source = copied_json(lean_artifact("source-json"))
        bad_source["function"]["name"] = "dec"

        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)
            report = build_counter_bridge_report(
                solidity,
                solc_yul,
                lean_source=bad_source,
                lean_yul=lean_artifact("yul-json"),
                lean_manifest=lean_artifact("bridge-json"),
            )

        self.assertEqual(report["status"], "failed")
        self.assertEqual(
            check_named(report, "soliditySourceToLeanSource")["status"],
            "failed",
        )

    def test_counter_bridge_reports_python_emitter_mismatch(self) -> None:
        bad_yul = copied_json(lean_artifact("yul-json"))
        bad_yul["function"]["name"] = "dec"

        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)
            report = build_counter_bridge_report(
                solidity,
                solc_yul,
                lean_source=lean_artifact("source-json"),
                lean_yul=bad_yul,
                lean_manifest=lean_artifact("bridge-json"),
            )

        self.assertEqual(report["status"], "failed")
        self.assertEqual(
            check_named(report, "pythonYulEmitterToLeanYul")["status"],
            "failed",
        )

    def test_counter_bridge_reports_solc_summary_mismatch(self) -> None:
        changed_solc = SOLC_COUNTER_IR_SAMPLE.replace(
            "checked_add_t_uint256(_3, expr_15)",
            "checked_add_t_uint256(expr_15, _3)",
        )

        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp, changed_solc)
            report = build_counter_bridge_report(
                solidity,
                solc_yul,
                lean_source=lean_artifact("source-json"),
                lean_yul=lean_artifact("yul-json"),
                lean_manifest=lean_artifact("bridge-json"),
            )

        self.assertEqual(report["status"], "failed")
        self.assertEqual(
            check_named(report, "solcFunctionSummaryToLeanYul")["status"],
            "failed",
        )

    def test_counter_bridge_reports_trusted_rule_manifest_mismatch(self) -> None:
        bad_manifest = copied_json(lean_artifact("bridge-json"))
        bad_manifest["expectedTrustedRules"] = ["differentRule"]

        with tempfile.TemporaryDirectory() as tmp:
            solidity, solc_yul = self.write_bridge_inputs(tmp)
            report = build_counter_bridge_report(
                solidity,
                solc_yul,
                lean_source=lean_artifact("source-json"),
                lean_yul=lean_artifact("yul-json"),
                lean_manifest=bad_manifest,
            )

        self.assertEqual(report["status"], "failed")
        self.assertEqual(
            check_named(report, "solcTrustedRulesToLeanManifest")["status"],
            "failed",
        )


class DemoCounterBridgeTests(unittest.TestCase):
    def test_demo_command_succeeds_with_solc_fixture(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            solc_yul = Path(tmp) / "Counter.solc.yul"
            solc_yul.write_text(SOLC_COUNTER_IR_SAMPLE)

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = demo_counter_bridge_main(["--solc-yul", str(solc_yul)])

        self.assertEqual(code, 0)
        self.assertIn("# SoLean Counter Bridge Demo", output.getvalue())
        self.assertIn("Counter bridge report: PASS", output.getvalue())

    def test_demo_command_succeeds_and_skips_missing_solc_yul(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            missing = Path(tmp) / "missing.solc.yul"

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = demo_counter_bridge_main(["--solc-yul", str(missing)])

        self.assertEqual(code, 0)
        self.assertIn("SKIPPED: local solc IR was not found.", output.getvalue())
        self.assertIn("python3 scripts/solc_to_yul.py examples/Counter.sol", output.getvalue())


class CheckEquivTests(unittest.TestCase):
    def test_default_uses_symbolic_state_transform_checker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text("// comment\n" + render_object(counter_object()))

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("symbolic restricted-subset state-transform", output.getvalue())

    def test_bounded_trace_mode_remains_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text("// comment\n" + render_object(counter_object()))

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main(["--bounded-traces", str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("bounded restricted-subset trace checker", output.getvalue())

    def test_ast_mode_uses_strict_subset_ast(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text("// comment\n" + render_object(counter_object()))

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main(["--ast", str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("restricted Yul subset AST checker", output.getvalue())

    def test_difference_returns_nonzero_and_explains_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text(
                render_object(counter_object()).replace(
                    "      if lt(new_x, old_x) { revert(0, 0) }\n", ""
                )
            )

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 1)
        self.assertIn("semantic Yul equivalence is not implemented yet", output.getvalue())

    def test_unsupported_subset_returns_distinct_code(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text('object "X" {\n  code {\n    function f() {\n      mstore(0, 0)\n    }\n  }\n}\n')

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 2)
        self.assertIn("unsupported Yul subset", output.getvalue())

    def test_text_mode_keeps_normalized_text_comparison(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text("object X { code { let x := add(1, 2) } }\n")
            right.write_text("// comment\nobject X {   code { let x := add(1, 2) } }\n")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main(["--text", str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("normalized-text checker", output.getvalue())


class SolidityToSoLeanTests(unittest.TestCase):
    def test_counter_shape_is_supported(self) -> None:
        source = Path("examples/Counter.sol").read_text()
        self.assertTrue(is_supported_counter(source))
        self.assertEqual(
            contract_to_source_data(parse_counter(source)),
            lean_artifact("source-json"),
        )

    def test_counter_parser_allows_whitespace_and_comments(self) -> None:
        source = """
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.35;
        contract Counter {
            uint256 public x;

            function inc(uint256 amount) public {
                /* precondition */
                require(amount > 0);
                x += amount;
                assert(x >= amount);
            }
        }
        """
        self.assertTrue(is_supported_counter(source))
        self.assertEqual(
            contract_to_source_data(parse_counter(source)),
            lean_artifact("source-json"),
        )

    def test_counter_script_outputs_model_reference(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solidity_to_solean_main(["examples/Counter.sol"])

        self.assertEqual(code, 0)
        self.assertIn("SoLean.Examples.Counter.incProgram", output.getvalue())

    def test_counter_script_outputs_lean_exported_source_json(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solidity_to_solean_main([
                "--format",
                "source-json",
                "examples/Counter.sol",
            ])

        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue()), lean_artifact("source-json"))

    def test_unsupported_solidity_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "Unsupported.sol"
            source.write_text("pragma solidity ^0.8.35; contract NotCounter {}\n")

            error = io.StringIO()
            with contextlib.redirect_stderr(error):
                code = solidity_to_solean_main([str(source)])

        self.assertEqual(code, 2)
        self.assertIn("unsupported Solidity input", error.getvalue())


if __name__ == "__main__":
    unittest.main()
