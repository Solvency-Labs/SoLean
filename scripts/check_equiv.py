#!/usr/bin/env python3
"""Compare two Yul files in the current restricted prototype subset."""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path

try:
    from .normalize_yul import normalize_text
    from .yul_subset import UnsupportedYulError, parse_object
except ImportError:  # Allows `python scripts/check_equiv.py ...`.
    from normalize_yul import normalize_text
    from yul_subset import UnsupportedYulError, parse_object


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path, help="First Yul file")
    parser.add_argument("right", type=Path, help="Second Yul file")
    parser.add_argument(
        "--diff",
        action="store_true",
        help="Print a unified diff when comparison text differs",
    )
    parser.add_argument(
        "--text",
        action="store_true",
        help="Use the legacy normalized-text comparison instead of subset ASTs",
    )
    return parser


def compare_text(left_path: Path, right_path: Path, show_diff: bool) -> int:
    left = normalize_text(left_path.read_text())
    right = normalize_text(right_path.read_text())

    if left == right:
        print("equivalent under the normalized-text checker")
        return 0

    print(
        "not equivalent under the normalized-text checker; semantic Yul "
        "equivalence is not implemented yet"
    )
    if show_diff:
        print_diff(left, right, left_path, right_path)
    return 1


def compare_subset(left_path: Path, right_path: Path, show_diff: bool) -> int:
    left_text = left_path.read_text()
    right_text = right_path.read_text()
    try:
        left = parse_object(left_text)
        right = parse_object(right_text)
    except UnsupportedYulError as exc:
        print(
            "unsupported Yul subset: "
            f"{exc}. This checker is not semantic Yul equivalence."
        )
        return 2

    if left == right:
        print("equivalent under the restricted Yul subset AST checker")
        return 0

    print(
        "not equivalent under the restricted Yul subset AST checker; semantic "
        "Yul equivalence is not implemented yet"
    )
    if show_diff:
        print_diff(normalize_text(left_text), normalize_text(right_text), left_path, right_path)
    return 1


def print_diff(left: str, right: str, left_path: Path, right_path: Path) -> None:
    print(
        "".join(
            difflib.unified_diff(
                left.splitlines(keepends=True),
                right.splitlines(keepends=True),
                fromfile=str(left_path),
                tofile=str(right_path),
            )
        ),
        end="",
    )


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.text:
        return compare_text(args.left, args.right, args.diff)
    return compare_subset(args.left, args.right, args.diff)


if __name__ == "__main__":
    raise SystemExit(main())
