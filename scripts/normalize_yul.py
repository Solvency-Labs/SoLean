#!/usr/bin/env python3
"""Normalize Yul-like text for simple prototype comparisons."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def normalize_text(text: str) -> str:
    """Strip comments and blank lines, then collapse whitespace.

    This is only a textual normalizer. It does not parse Yul, preserve source
    mappings, alpha-rename variables, or prove semantic equivalence.
    """

    without_block_comments = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    lines: list[str] = []
    for raw_line in without_block_comments.splitlines():
        line = raw_line.split("//", 1)[0].strip()
        if line:
            lines.append(" ".join(line.split()))
    return "\n".join(lines) + ("\n" if lines else "")


def read_input(path: Path | None) -> str:
    if path is None:
        return sys.stdin.read()
    return path.read_text()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, help="Yul file, or stdin")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write normalized text to this file instead of stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    normalized = normalize_text(read_input(args.input))
    if args.output:
        args.output.write_text(normalized)
    else:
        print(normalized, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
