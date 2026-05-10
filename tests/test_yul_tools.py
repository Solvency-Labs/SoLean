from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from scripts.check_equiv import main as check_equiv_main
from scripts.normalize_yul import normalize_text
from scripts.solidity_to_solean import is_supported_counter, main as solidity_to_solean_main
from scripts.solean_to_yul import main as solean_to_yul_main
from scripts.yul_subset import counter_object, parse_object, render_object


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


class CheckEquivTests(unittest.TestCase):
    def test_equivalent_subset_ast(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text("// comment\n" + render_object(counter_object()))

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("restricted Yul subset AST checker", output.getvalue())

    def test_difference_returns_nonzero_and_explains_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text(render_object(counter_object()))
            right.write_text(render_object(counter_object()).replace("old_x", "old_y"))

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

    def test_counter_script_outputs_model_reference(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = solidity_to_solean_main(["examples/Counter.sol"])

        self.assertEqual(code, 0)
        self.assertIn("SoLean.Examples.Counter.incProgram", output.getvalue())

    def test_unsupported_solidity_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "Unsupported.sol"
            source.write_text("pragma solidity ^0.8.20; contract NotCounter {}\n")

            error = io.StringIO()
            with contextlib.redirect_stderr(error):
                code = solidity_to_solean_main([str(source)])

        self.assertEqual(code, 2)
        self.assertIn("unsupported Solidity input", error.getvalue())


if __name__ == "__main__":
    unittest.main()
