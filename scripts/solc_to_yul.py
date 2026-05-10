#!/usr/bin/env python3
"""Compile Solidity to solc's Yul IR, if solc is available."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Solidity source file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write Yul IR to this file instead of stdout",
    )
    parser.add_argument(
        "--optimized",
        action="store_true",
        help="Use solc --ir-optimized instead of --ir",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    if not args.source.exists():
        print(f"error: source file not found: {args.source}", file=sys.stderr)
        return 2

    solc = shutil.which("solc")
    if solc is None:
        print(
            "error: solc was not found on PATH. Install solc 0.8.x to produce "
            "Yul IR for this prototype.",
            file=sys.stderr,
        )
        return 127

    ir_flag = "--ir-optimized" if args.optimized else "--ir"
    result = subprocess.run(
        [solc, ir_flag, str(args.source)],
        check=False,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        return result.returncode

    if args.output:
        args.output.write_text(result.stdout)
    else:
        print(result.stdout, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
