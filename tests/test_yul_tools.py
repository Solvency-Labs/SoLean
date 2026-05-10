from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from scripts.check_equiv import main as check_equiv_main
from scripts.normalize_yul import normalize_text


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


class CheckEquivTests(unittest.TestCase):
    def test_equivalent_after_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text("object X { code { let x := add(1, 2) } }\n")
            right.write_text("// comment\nobject X {   code { let x := add(1, 2) } }\n")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 0)
        self.assertIn("equivalent under the current normalized-text checker", output.getvalue())

    def test_difference_returns_nonzero_and_explains_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            left = Path(tmp) / "left.yul"
            right = Path(tmp) / "right.yul"
            left.write_text("object X { code { let x := 1 } }\n")
            right.write_text("object X { code { let x := 2 } }\n")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = check_equiv_main([str(left), str(right)])

        self.assertEqual(code, 1)
        self.assertIn("semantic Yul equivalence is not implemented yet", output.getvalue())


if __name__ == "__main__":
    unittest.main()
