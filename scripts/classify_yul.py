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


@dataclass(frozen=True)
class SolcObjectBlock:
    name: str
    start_line: int
    end_line: int
    depth: int
    text: str


@dataclass(frozen=True)
class SolcInspection:
    kind: str
    message: str
    objects: tuple[SolcObjectBlock, ...]
    selected_object: SolcObjectBlock | None
    selected_classification: Classification | None

    @property
    def is_supported(self) -> bool:
        return (
            self.selected_classification is not None
            and self.selected_classification.is_supported
        )


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
OBJECT_HEADER_RE = re.compile(r'object "([^"]+)" \{')


def classify_text(text: str) -> Classification:
    try:
        obj = parse_object(text)
    except UnsupportedYulError as exc:
        return _classify_unsupported(text, exc)

    return Classification(
        "supported-subset",
        f"supported restricted subset: object {obj.name}, function {obj.function.name}",
    )


def inspect_solc_text(text: str) -> SolcInspection:
    """Inspect solc-style IR and classify the selected runtime object.

    This is a trusted extraction aid, not a verified solc parser. It identifies
    object blocks by brace matching after textual normalization, prefers a
    deployed/runtime object, and then runs the normal restricted-subset
    classifier on that block.
    """

    objects = find_object_blocks(text)
    if not objects:
        return SolcInspection(
            "parse-shape-failure",
            "no Yul object blocks found in solc output",
            (),
            None,
            None,
        )

    selected = select_runtime_object(objects)
    classification = classify_text(selected.text)
    return SolcInspection(
        classification.kind,
        (
            f"selected object {selected.name} at normalized lines "
            f"{selected.start_line}-{selected.end_line}: {classification.message}"
        ),
        tuple(objects),
        selected,
        classification,
    )


def find_object_blocks(text: str) -> list[SolcObjectBlock]:
    lines = normalize_text(text).splitlines()
    stack: list[tuple[str, int, int]] = []
    blocks: list[SolcObjectBlock] = []
    depth = 0

    for index, line in enumerate(lines, start=1):
        object_match = OBJECT_HEADER_RE.fullmatch(line)
        if object_match is not None:
            stack.append((object_match.group(1), index, depth))

        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][2]:
            name, start_line, object_depth = stack.pop()
            block_text = "\n".join(lines[start_line - 1 : index]) + "\n"
            blocks.append(
                SolcObjectBlock(
                    name=name,
                    start_line=start_line,
                    end_line=index,
                    depth=object_depth,
                    text=block_text,
                )
            )

    return sorted(blocks, key=lambda block: (block.start_line, block.depth))


def select_runtime_object(objects: list[SolcObjectBlock]) -> SolcObjectBlock:
    deployed = [block for block in objects if "deployed" in block.name.lower()]
    if deployed:
        return deployed[0]
    return max(objects, key=lambda block: (block.depth, block.start_line))


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
    parser.add_argument(
        "--inspect-solc",
        action="store_true",
        help="Classify the selected runtime/deployed object inside solc-style IR",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.source.exists():
        print(f"parse-shape-failure: source file not found: {args.source}")
        return 2

    text = args.source.read_text()
    if args.inspect_solc:
        inspection = inspect_solc_text(text)
        print(f"{inspection.kind}: {inspection.message}")
        if inspection.objects:
            objects = ", ".join(
                f"{block.name}@{block.start_line}-{block.end_line}"
                for block in inspection.objects
            )
            print(f"objects: {objects}")
        return 0 if inspection.is_supported else 2

    classification = classify_text(text)
    print(f"{classification.kind}: {classification.message}")
    return 0 if classification.is_supported else 2


if __name__ == "__main__":
    raise SystemExit(main())
