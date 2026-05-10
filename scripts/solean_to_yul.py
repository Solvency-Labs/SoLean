#!/usr/bin/env python3
"""Structured placeholder SoLean-to-Yul emitter for Counter."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from .yul_subset import counter_object, render_object
except ImportError:  # Allows `python scripts/solean_to_yul.py ...`.
    from yul_subset import counter_object, render_object


HEADER = """// Deterministic placeholder Yul-like output for SoLean.Examples.Counter.inc.
// This is not generated from Lean and is not bytecode-ready Yul.
// It mirrors the current checked-arithmetic intent for the Counter case study.
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--example",
        default="counter",
        choices=["counter"],
        help="Example model to emit",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write emitted Yul-like text to this file instead of stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.example != "counter":
        print(f"error: unsupported example: {args.example}", file=sys.stderr)
        return 2

    output = HEADER + render_object(counter_object())
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
