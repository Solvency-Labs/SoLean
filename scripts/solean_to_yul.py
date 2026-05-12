#!/usr/bin/env python3
"""Structured placeholder SoLean-to-Yul emitter for Counter."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    from .yul_subset import counter_object, object_from_data, render_object
except ImportError:  # Allows `python scripts/solean_to_yul.py ...`.
    from yul_subset import counter_object, object_from_data, render_object


PYTHON_HEADER = """// Deterministic placeholder Yul-like output for SoLean.Examples.Counter.inc.
// This is not generated from Lean and is not bytecode-ready Yul.
// It mirrors the current checked-arithmetic intent for the Counter case study.
"""

LEAN_ARTIFACT_HEADER = """// Deterministic Yul-like output rendered from SoLean's Lean-owned Counter Yul artifact.
// This is not bytecode-ready Yul and is still limited to the Counter restricted subset.
// The source artifact is SoLean.Examples.CounterYul.counterProgram.
"""


def lake_command() -> str:
    if lake := shutil.which("lake"):
        return lake
    elan_lake = Path.home() / ".elan" / "bin" / "lake"
    if elan_lake.exists():
        return str(elan_lake)
    return "lake"


def lean_counter_object():
    result = subprocess.run(
        [
            lake_command(),
            "env",
            "lean",
            "--run",
            "SoLean/CounterArtifactsMain.lean",
            "yul-json",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return object_from_data(json.loads(result.stdout))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--example",
        default="counter",
        choices=["counter"],
        help="Example model to emit",
    )
    parser.add_argument(
        "--source",
        choices=["python", "lean-artifact"],
        default="python",
        help="Render from the Python placeholder AST or the Lean-exported Yul artifact",
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

    try:
        obj = lean_counter_object() if args.source == "lean-artifact" else counter_object()
    except subprocess.CalledProcessError as exc:
        print(
            f"error: Lean artifact export failed with exit code {exc.returncode}",
            file=sys.stderr,
        )
        return 2

    header = LEAN_ARTIFACT_HEADER if args.source == "lean-artifact" else PYTHON_HEADER
    output = header + render_object(obj)
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
