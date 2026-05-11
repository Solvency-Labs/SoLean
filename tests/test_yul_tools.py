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
)
from scripts.check_equiv import main as check_equiv_main
from scripts.normalize_yul import normalize_text
from scripts.solidity_to_solean import (
    contract_to_source_data,
    is_supported_counter,
    main as solidity_to_solean_main,
    parse_counter,
)
from scripts.solean_to_yul import main as solean_to_yul_main
from scripts.yul_subset import (
    UINT256_MAX,
    TraceCase,
    compare_counter_traces,
    compare_symbolic_summaries,
    counter_object,
    object_to_data,
    parse_object,
    render_object,
    run_counter_trace,
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
        require_helper(expr_9)
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

    def test_counter_object_matches_lean_exported_counter_yul_shape(self) -> None:
        self.assertEqual(object_to_data(counter_object()), lean_artifact("yul-json"))

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
        self.assertIn("0x00", inspection.message)

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
