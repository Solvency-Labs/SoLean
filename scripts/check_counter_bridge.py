#!/usr/bin/env python3
"""Audit the current Counter bridge against Lean-owned artifacts.

This is a Counter-only trust-reduction checker. It does not verify Solidity
parsing, solc parsing, or semantic equivalence with real solc IR.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

try:
    from .classify_yul import (
        solc_function_summary_to_data,
        summarize_solc_function_text,
    )
    from .solidity_to_solean import contract_to_source_data, parse_counter
    from .solean_to_yul import main as solean_to_yul_main
    from .yul_subset import UnsupportedYulError, object_to_data, parse_object
except ImportError:  # Allows `python scripts/check_counter_bridge.py ...`.
    from classify_yul import solc_function_summary_to_data, summarize_solc_function_text
    from solidity_to_solean import contract_to_source_data, parse_counter
    from solean_to_yul import main as solean_to_yul_main
    from yul_subset import UnsupportedYulError, object_to_data, parse_object


LIMITATIONS = [
    "Counter-only bridge audit.",
    "Solidity parsing is trusted deterministic Python parsing for one tiny subset.",
    "Python Yul rendering is tested against Lean-owned artifacts, not verified.",
    "solc IR summarization is trusted Counter-specific pattern recognition.",
    "This report is not semantic equivalence against real solc Yul.",
]

REPORT_VERSION = 4


def stable_json(data: Any) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def artifact_hash(data: Any) -> str:
    return hashlib.sha256(stable_json(data).encode()).hexdigest()


def lake_command() -> str:
    if lake := shutil.which("lake"):
        return lake
    elan_lake = Path.home() / ".elan" / "bin" / "lake"
    if elan_lake.exists():
        return str(elan_lake)
    return "lake"


def lean_artifact(kind: str) -> dict[str, Any]:
    result = subprocess.run(
        [
            lake_command(),
            "env",
            "lean",
            "--run",
            "SoLean/CounterArtifactsMain.lean",
            kind,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def check_data(
    name: str,
    trust: str,
    actual: Any,
    expected: Any,
    pass_message: str,
    fail_message: str,
) -> dict[str, str]:
    if actual == expected:
        return {
            "name": name,
            "status": "passed",
            "trust": trust,
            "message": pass_message,
        }
    return {
        "name": name,
        "status": "failed",
        "trust": trust,
        "message": fail_message,
    }


def failed_check(name: str, trust: str, message: str) -> dict[str, str]:
    return {
        "name": name,
        "status": "failed",
        "trust": trust,
        "message": message,
    }


def lean_backed_rules(report: dict[str, Any]) -> list[dict[str, str]]:
    return [
        entry
        for entry in report.get("bridgeManifest", {}).get("bridgeRuleProofs", [])
        if entry.get("leanProof")
    ]


def pending_rules(report: dict[str, Any]) -> list[str]:
    return [
        entry["rule"]
        for entry in report.get("bridgeManifest", {}).get("bridgeRuleProofs", [])
        if not entry.get("leanProof")
    ]


def format_markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Counter Bridge Report",
        "",
        f"Status: **{report.get('status', 'failed')}**",
        f"Report version: `{report.get('reportVersion', REPORT_VERSION)}`",
        "",
        "## Proved In Lean",
        "",
    ]

    proof_refs = report.get("bridgeManifest", {}).get("proofReferences", [])
    if proof_refs:
        lines.extend(f"- `{proof}`" for proof in proof_refs)
    else:
        lines.append("- No proof references available; Lean artifact export may have failed.")

    lines.extend(["", "## Tested Against Lean Artifacts", ""])
    for check in report.get("checks", []):
        if check.get("trust") in {"tested", "trusted-summary-tested", "Lean-owned manifest"}:
            marker = "PASS" if check.get("status") == "passed" else "FAIL"
            lines.append(
                f"- **{marker}** `{check.get('name')}`: {check.get('message')}"
            )

    lines.extend(["", "## Solc Summary Trace", ""])
    trace = report.get("solc", {}).get("trace", [])
    if trace:
        for entry in trace:
            effect = json.dumps(entry.get("effect", {}), sort_keys=True)
            proof = entry.get("leanProof")
            proof_text = f"; proof `{proof}`" if proof else "; parser-level trust"
            lines.append(
                f"- line {entry.get('sourceLine')}: `{entry.get('source')}` "
                f"=> `{entry.get('rule')}`; effect `{effect}`{proof_text}"
            )
    else:
        lines.append("- No solc summary trace available.")

    lines.extend(["", "## Lean-Backed Adapter Rules", ""])
    backed = lean_backed_rules(report)
    if backed:
        lines.extend(
            f"- `{entry['rule']}` backed by `{entry['leanProof']}`"
            for entry in backed
        )
    else:
        lines.append("- No adapter rules currently have Lean-backed theorem references.")

    lines.extend(["", "## Still Trusted Boundaries", ""])
    for rule in pending_rules(report):
        if rule == "hexLiteralAsNat":
            lines.append(f"- `{rule}` remains trusted parser-level literal parsing.")
        else:
            lines.append(f"- `{rule}` remains trusted Python pattern recognition.")
    lines.extend(
        [
            "- The Solidity parser is Counter-only and trusted.",
            "- The Python solc IR recognizer is trusted parser-level code.",
            "- Real solc deployment wrappers, ABI dispatch, memory, and helper semantics remain outside the restricted model.",
        ]
    )

    lines.extend(["", "## Explicit Non-Claims", ""])
    for limitation in report.get("limitations", LIMITATIONS):
        lines.append(f"- {limitation}")
    lines.append("- This is not a proof that real solc Yul is semantically equivalent to SoLean-generated Yul.")

    return "\n".join(lines) + "\n"


def emitted_counter_yul_data() -> dict[str, Any]:
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        code = solean_to_yul_main(["--example", "counter"])
    if code != 0:
        raise RuntimeError(f"solean_to_yul.py returned {code}")
    return object_to_data(parse_object(output.getvalue()))


def build_counter_bridge_report(
    solidity_path: Path,
    solc_yul_path: Path,
    *,
    lean_source: dict[str, Any] | None = None,
    lean_yul: dict[str, Any] | None = None,
    lean_manifest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    lean_source = lean_source if lean_source is not None else lean_artifact("source-json")
    lean_yul = lean_yul if lean_yul is not None else lean_artifact("yul-json")
    lean_manifest = (
        lean_manifest if lean_manifest is not None else lean_artifact("bridge-json")
    )
    expected_rules = lean_manifest["expectedTrustedRules"]

    checks: list[dict[str, str]] = []
    solc_info: dict[str, Any] = {
        "sourceObject": None,
        "sourceFunction": None,
        "trustedRules": [],
        "trace": [],
    }
    solc_summary_rules: list[str] | None = None

    if solidity_path.exists():
        try:
            source_data = contract_to_source_data(parse_counter(solidity_path.read_text()))
            checks.append(
                check_data(
                    "soliditySourceToLeanSource",
                    "tested",
                    source_data,
                    lean_source,
                    "Counter Solidity source shape matches the Lean source artifact.",
                    "Counter Solidity source shape does not match the Lean source artifact.",
                )
            )
        except Exception as exc:
            checks.append(
                failed_check(
                    "soliditySourceToLeanSource",
                    "trusted-parser",
                    f"unsupported or unreadable Solidity source: {exc}",
                )
            )
    else:
        checks.append(
            failed_check(
                "soliditySourceToLeanSource",
                "trusted-parser",
                f"Solidity source file not found: {solidity_path}",
            )
        )

    try:
        yul_data = emitted_counter_yul_data()
        checks.append(
            check_data(
                "pythonYulEmitterToLeanYul",
                "tested",
                yul_data,
                lean_yul,
                "Python-emitted restricted Yul matches the Lean Yul artifact.",
                "Python-emitted restricted Yul does not match the Lean Yul artifact.",
            )
        )
    except Exception as exc:
        checks.append(
            failed_check(
                "pythonYulEmitterToLeanYul",
                "tested",
                f"Python Yul emitter failed: {exc}",
            )
        )

    if solc_yul_path.exists():
        try:
            summary = summarize_solc_function_text(solc_yul_path.read_text(), "inc")
            summary_data = solc_function_summary_to_data(summary)
            solc_info = {
                "sourceObject": summary_data["sourceObject"],
                "sourceFunction": summary_data["sourceFunction"],
                "trustedRules": summary_data["trustedRules"],
                "trace": summary_data["trace"],
            }
            solc_summary_rules = summary_data["trustedRules"]
            checks.append(
                check_data(
                    "solcFunctionSummaryToLeanYul",
                    "trusted-summary-tested",
                    summary_data["normalized"],
                    lean_yul,
                    "solc Counter function summary matches the Lean Yul artifact.",
                    "solc Counter function summary does not match the Lean Yul artifact.",
                )
            )
        except UnsupportedYulError as exc:
            checks.append(
                failed_check(
                    "solcFunctionSummaryToLeanYul",
                    "trusted-summary-tested",
                    f"unsupported solc Counter function summary: {exc}",
                )
            )
        except Exception as exc:
            checks.append(
                failed_check(
                    "solcFunctionSummaryToLeanYul",
                    "trusted-summary-tested",
                    f"solc Counter function summary failed: {exc}",
                )
            )
    else:
        checks.append(
            failed_check(
                "solcFunctionSummaryToLeanYul",
                "trusted-summary-tested",
                f"solc Yul file not found: {solc_yul_path}",
            )
        )

    if solc_summary_rules is None:
        checks.append(
            failed_check(
                "solcTrustedRulesToLeanManifest",
                "Lean-owned manifest",
                "solc summary did not produce trusted rules to compare",
            )
        )
    else:
        checks.append(
            check_data(
                "solcTrustedRulesToLeanManifest",
                "Lean-owned manifest",
                solc_summary_rules,
                expected_rules,
                "solc summary trusted rules match the Lean bridge manifest.",
                "solc summary trusted rules do not match the Lean bridge manifest.",
            )
        )

    status = "passed" if all(check["status"] == "passed" for check in checks) else "failed"
    return {
        "kind": "counterBridgeReport",
        "reportVersion": REPORT_VERSION,
        "status": status,
        "leanArtifacts": {
            "source": {
                "name": "SoLean.Examples.CounterCompiler.counterFunction",
                "sha256": artifact_hash(lean_source),
            },
            "yul": {
                "name": "SoLean.Examples.CounterYul.counterProgram",
                "sha256": artifact_hash(lean_yul),
            },
            "bridgeManifest": {
                "name": "SoLean.Artifacts.counterBridgeManifestJson",
                "sha256": artifact_hash(lean_manifest),
            },
        },
        "bridgeManifest": {
            "expectedTrustedRules": expected_rules,
            "bridgeRuleProofs": lean_manifest["bridgeRuleProofs"],
            "proofReferences": lean_manifest["proofReferences"],
        },
        "checks": checks,
        "solc": solc_info,
        "limitations": lean_manifest["limitations"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--solidity",
        required=True,
        type=Path,
        help="Counter Solidity source to project into the Lean source shape",
    )
    parser.add_argument(
        "--solc-yul",
        required=True,
        type=Path,
        help="Local solc 0.8.35 --ir output for Counter",
    )
    parser.add_argument(
        "--format",
        choices=["json", "markdown"],
        default="json",
        help="Output deterministic JSON or a human-readable Markdown report",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        report = build_counter_bridge_report(args.solidity, args.solc_yul)
    except subprocess.CalledProcessError as exc:
        report = {
            "kind": "counterBridgeReport",
            "reportVersion": REPORT_VERSION,
            "status": "failed",
            "checks": [
                failed_check(
                    "leanArtifactsLoaded",
                    "Lean exporter",
                    f"Lean artifact export failed with exit code {exc.returncode}",
                )
            ],
            "leanArtifacts": {},
            "solc": {
                "sourceObject": None,
                "sourceFunction": None,
                "trustedRules": [],
                "trace": [],
            },
            "limitations": LIMITATIONS,
        }
    except Exception as exc:
        report = {
            "kind": "counterBridgeReport",
            "reportVersion": REPORT_VERSION,
            "status": "failed",
            "checks": [
                failed_check(
                    "counterBridgeReportBuilt",
                    "bridge script",
                    f"Counter bridge report failed: {exc}",
                )
            ],
            "leanArtifacts": {},
            "solc": {
                "sourceObject": None,
                "sourceFunction": None,
                "trustedRules": [],
                "trace": [],
            },
            "limitations": LIMITATIONS,
        }

    output = stable_json(report) if args.format == "json" else format_markdown_report(report)
    print(output, end="")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
