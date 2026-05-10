#!/usr/bin/env python3
"""Counter-only Solidity-to-SoLean sketch.

This is not a Solidity parser. It recognizes the exact Counter example shape
used by the prototype and rejects everything else.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


COUNTER_SNIPPET = """-- Counter-only sketch generated from examples/Counter.sol.
-- This references the hand-written model; it is not a verified Solidity parser.
import SoLean.Examples.Counter

#check SoLean.Examples.Counter.incProgram
#check SoLean.Examples.Counter.inc_assertion_safe
"""


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    source = re.sub(r"//.*", " ", source)
    return source


def normalize_solidity(source: str) -> str:
    return " ".join(strip_comments(source).split())


def is_supported_counter(source: str) -> bool:
    normalized = normalize_solidity(source)
    pattern = re.compile(
        r"pragma solidity \^0\.8\.20; "
        r"contract Counter \{ "
        r"uint256 public x; "
        r"function inc\(uint256 amount\) public \{ "
        r"require\(amount > 0\); "
        r"x \+= amount; "
        r"assert\(x >= amount\); "
        r"\} "
        r"\}"
    )
    return pattern.fullmatch(normalized) is not None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Solidity source file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write the generated Lean sketch to this file instead of stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.source.exists():
        print(f"error: source file not found: {args.source}", file=sys.stderr)
        return 2

    source = args.source.read_text()
    if not is_supported_counter(source):
        print(
            "unsupported Solidity input: this prototype only recognizes the "
            "exact Counter contract shape in examples/Counter.sol",
            file=sys.stderr,
        )
        return 2

    if args.output:
        args.output.write_text(COUNTER_SNIPPET)
    else:
        print(COUNTER_SNIPPET, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
