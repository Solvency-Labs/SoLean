#!/usr/bin/env python3
"""Placeholder SoLean-to-Yul emitter for the first Counter case study."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


COUNTER_YUL = """// Deterministic placeholder Yul-like output for SoLean.Examples.Counter.inc.
// This is not generated from Lean and is not bytecode-ready Yul.
// It mirrors the current checked-arithmetic intent for the Counter case study.
object "Counter" {
  code {
    // x is modeled at storage slot 0.
    function inc(amount) {
      if iszero(gt(amount, 0)) { revert(0, 0) }
      let old_x := sload(0)
      let new_x := add(old_x, amount)
      if lt(new_x, old_x) { revert(0, 0) }
      sstore(0, new_x)
      if lt(new_x, amount) { revert(0, 0) }
    }
  }
}
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

    if args.output:
        args.output.write_text(COUNTER_YUL)
    else:
        print(COUNTER_YUL, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
