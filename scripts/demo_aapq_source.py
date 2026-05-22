#!/usr/bin/env python3
"""Run the presentation-grade AA/PQ source-shape demo.

This command exercises the AA/PQ side of SoLean end-to-end without requiring
solc: `lake build`, AA/PQ-focused Python tests, the three Lean-owned source
artifacts, the markdown source-shape report, and a Trust Boundaries summary
sourced from the Lean-owned source certificate so the proved-vs-trusted
boundary is visible at a glance.
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
        "SoLean/AAPQArtifactsMain.lean",
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


def load_lean_certificate() -> dict:
    command = [
        lake_command(),
        "env",
        "lean",
        "--run",
        "SoLean/AAPQArtifactsMain.lean",
        "source-certificate-json",
    ]
    result = subprocess.run(
        command, cwd=REPO_ROOT, check=True, capture_output=True, text=True
    )
    return json.loads(result.stdout)


def print_trust_boundaries(certificate: dict) -> None:
    print("## Trust Boundaries\n")
    assumptions = certificate.get("assumptions", [])
    if assumptions:
        print("Assumptions (sourced from the Lean-owned source certificate):")
        for item in assumptions:
            print(f"- {item}")
        print()

    unsupported = certificate.get("unsupported", [])
    if unsupported:
        print("Out of scope for this audit boundary:")
        for item in unsupported:
            print(f"- {item}")
        print()

    proofs = certificate.get("proofReferences", [])
    if proofs:
        print("Lean theorems backing this boundary:")
        for item in proofs:
            print(f"- `{item}`")
        print()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--solidity",
        type=Path,
        default=Path("examples/AAPQIntegration.sol"),
        help="AA/PQ Solidity sketch to use in the source-shape report",
    )
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="Skip the AA/PQ-focused unittest step (useful for fast iteration)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    print("# SoLean AA/PQ Source-Shape Demo\n")

    steps: list[tuple[str, list[str]]] = [
        ("Lean build", [lake_command(), "build"]),
    ]
    if not args.skip_tests:
        steps.append(
            (
                "AA/PQ source-shape Python tests",
                [
                    sys.executable,
                    "-m",
                    "unittest",
                    "tests.test_aapq_source",
                ],
            )
        )

    for name, command in steps:
        code = run_step(name, command)
        if code != 0:
            return code

    for kind in (
        "source-json",
        "source-certificate-json",
        "behavior-summary-json",
    ):
        code = smoke_lean_artifact(kind)
        if code != 0:
            return code

    solidity = args.solidity
    if not solidity.is_absolute():
        solidity = REPO_ROOT / solidity

    code = run_step(
        "AA/PQ source-shape report",
        [
            sys.executable,
            "scripts/check_aapq_source.py",
            "--format",
            "markdown",
            "--solidity",
            str(solidity),
        ],
    )
    if code != 0:
        return code

    try:
        certificate = load_lean_certificate()
    except subprocess.CalledProcessError as exc:
        print(
            "Trust Boundaries: FAIL "
            f"(could not load source certificate, exit {exc.returncode})\n",
            file=sys.stderr,
        )
        return exc.returncode

    print_trust_boundaries(certificate)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
