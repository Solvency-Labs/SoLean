#!/usr/bin/env python3
"""Compare two Yul files using the current textual normalizer."""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path

try:
    from .normalize_yul import normalize_text
except ImportError:  # Allows `python scripts/check_equiv.py ...`.
    from normalize_yul import normalize_text


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path, help="First Yul file")
    parser.add_argument("right", type=Path, help="Second Yul file")
    parser.add_argument(
        "--diff",
        action="store_true",
        help="Print a unified diff when normalized text differs",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    left = normalize_text(args.left.read_text())
    right = normalize_text(args.right.read_text())

    if left == right:
        print("equivalent under the current normalized-text checker")
        return 0

    print(
        "not equivalent under the current normalized-text checker; semantic "
        "Yul equivalence is not implemented yet"
    )
    if args.diff:
        print(
            "".join(
                difflib.unified_diff(
                    left.splitlines(keepends=True),
                    right.splitlines(keepends=True),
                    fromfile=str(args.left),
                    tofile=str(args.right),
                )
            ),
            end="",
        )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
