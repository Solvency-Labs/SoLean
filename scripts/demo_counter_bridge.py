#!/usr/bin/env python3
"""Run the presentation-grade Counter bridge demo checks.

This command is intentionally Counter-only. It does not require solc in CI:
when local solc IR is absent, it runs the Lean/Python checks and reports the
real-solc boundary as skipped with reproduction instructions.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]


def lake_command() -> str:
    if lake := shutil.which("lake"):
        return lake
    elan_lake = Path.home() / ".elan" / "bin" / "lake"
    if elan_lake.exists():
        return str(elan_lake)
    return "lake"


def run_step(name: str, command: list[str]) -> int:
    print(f"## {name}")
    print("`" + " ".join(command) + "`")
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode == 0:
        print(f"{name}: PASS\n")
    else:
        print(f"{name}: FAIL ({result.returncode})\n")
    return result.returncode


def smoke_lean_artifact(kind: str) -> int:
    command = [
        lake_command(),
        "env",
        "lean",
        "--run",
        "SoLean/CounterArtifactsMain.lean",
        kind,
    ]
    print(f"## Lean artifact smoke: {kind}")
    print("`" + " ".join(command) + "`")
    result = subprocess.run(command, cwd=REPO_ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="", file=sys.stderr)
        print(f"Lean artifact smoke {kind}: FAIL ({result.returncode})\n")
        return result.returncode
    try:
        json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(f"Lean artifact smoke {kind}: FAIL (invalid JSON: {exc})\n")
        return 1
    print(f"Lean artifact smoke {kind}: PASS\n")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--solidity",
        type=Path,
        default=Path("examples/Counter.sol"),
        help="Counter Solidity source to use in the bridge report",
    )
    parser.add_argument(
        "--solc-yul",
        type=Path,
        default=Path("build/Counter.solc.yul"),
        help="Optional local solc 0.8.35 --ir output for Counter",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    print("# SoLean Counter Bridge Demo\n")

    steps = [
        (
            "Lean build",
            [lake_command(), "build"],
        ),
        (
            "Bridge-focused Python tests",
            [
                sys.executable,
                "-m",
                "unittest",
                "tests.test_yul_tools.YulSubsetTests",
                "tests.test_yul_tools.ClassifyYulTests",
                "tests.test_yul_tools.CounterBridgeTests",
            ],
        ),
    ]

    for name, command in steps:
        code = run_step(name, command)
        if code != 0:
            return code

    for kind in (
        "source-json",
        "source-certificate-json",
        "yul-json",
        "trace-skeleton-json",
        "bridge-json",
    ):
        code = smoke_lean_artifact(kind)
        if code != 0:
            return code

    solc_yul = args.solc_yul
    if not solc_yul.is_absolute():
        solc_yul = REPO_ROOT / solc_yul
    solidity = args.solidity
    if not solidity.is_absolute():
        solidity = REPO_ROOT / solidity

    if not solc_yul.exists():
        print("## Real solc boundary")
        print("SKIPPED: local solc IR was not found.")
        print(
            "Generate it with: "
            "python3 scripts/solc_to_yul.py examples/Counter.sol "
            "-o build/Counter.solc.yul"
        )
        print("The demo passed the Lean/Python checks that do not require solc.\n")
        return 0

    return run_step(
        "Counter bridge report",
        [
            sys.executable,
            "scripts/check_counter_bridge.py",
            "--format",
            "markdown",
            "--solidity",
            str(solidity),
            "--solc-yul",
            str(solc_yul),
        ],
    )


if __name__ == "__main__":
    raise SystemExit(main())
