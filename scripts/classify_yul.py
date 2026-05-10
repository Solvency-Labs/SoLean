#!/usr/bin/env python3
"""Classify Yul text against SoLean's current restricted subset."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re

try:
    from .normalize_yul import normalize_text
    from .yul_subset import UnsupportedYulError, parse_object
except ImportError:  # Allows `python scripts/classify_yul.py ...`.
    from normalize_yul import normalize_text
    from yul_subset import UnsupportedYulError, parse_object


@dataclass(frozen=True)
class Classification:
    kind: str
    message: str

    @property
    def is_supported(self) -> bool:
        return self.kind == "supported-subset"


UNSUPPORTED_STATEMENT_PREFIXES = (
    "case ",
    "default",
    "for ",
    "leave",
    "mstore(",
    "pop(",
    "return(",
    "revert(",
    "switch ",
)


def classify_text(text: str) -> Classification:
    try:
        obj = parse_object(text)
    except UnsupportedYulError as exc:
        return _classify_unsupported(text, exc)

    return Classification(
        "supported-subset",
        f"supported restricted subset: object {obj.name}, function {obj.function.name}",
    )


def _classify_unsupported(text: str, exc: UnsupportedYulError) -> Classification:
    lines = normalize_text(text).splitlines()
    if not lines:
        return Classification("parse-shape-failure", "empty Yul input")

    first_line = lines[0]
    if first_line.startswith("=======") or first_line in {"IR:", "Optimized IR:"}:
        return Classification(
            "unsupported-wrapper",
            f"solc output preamble is not supported: {first_line}",
        )

    object_lines = [line for line in lines if line.startswith("object ")]
    if len(object_lines) > 1:
        return Classification(
            "unsupported-wrapper",
            "multiple or nested object blocks are outside the restricted subset",
        )

    for line in lines:
        if line.startswith(UNSUPPORTED_STATEMENT_PREFIXES):
            return Classification(
                "unsupported-statement",
                f"unsupported statement form: {line}",
            )

    expression_match = re.search(
        r"unsupported expression function: ([A-Za-z_][A-Za-z0-9_]*)",
        str(exc),
    )
    if expression_match is not None:
        return Classification(
            "unsupported-expression",
            f"unsupported expression function: {expression_match.group(1)}",
        )

    if "unsupported statement:" in str(exc):
        return Classification("unsupported-statement", str(exc))

    return Classification("parse-shape-failure", str(exc))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Yul file to classify")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.source.exists():
        print(f"parse-shape-failure: source file not found: {args.source}")
        return 2

    classification = classify_text(args.source.read_text())
    print(f"{classification.kind}: {classification.message}")
    return 0 if classification.is_supported else 2


if __name__ == "__main__":
    raise SystemExit(main())
