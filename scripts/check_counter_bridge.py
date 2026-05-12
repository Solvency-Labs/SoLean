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
    from .solidity_to_solean import (
        contract_to_source_certificate,
        contract_to_source_data,
        parse_counter,
    )
    from .solean_to_yul import main as solean_to_yul_main
    from .yul_subset import UnsupportedYulError, object_to_data, parse_object
except ImportError:  # Allows `python scripts/check_counter_bridge.py ...`.
    from classify_yul import solc_function_summary_to_data, summarize_solc_function_text
    from solidity_to_solean import (
        contract_to_source_certificate,
        contract_to_source_data,
        parse_counter,
    )
    from solean_to_yul import main as solean_to_yul_main
    from yul_subset import UnsupportedYulError, object_to_data, parse_object


LIMITATIONS = [
    "Counter-only bridge audit.",
    "Solidity parsing is trusted deterministic Python parsing for one tiny subset.",
    "Python Yul rendering is tested against Lean-owned artifacts, not verified.",
    "solc IR summarization is trusted Counter-specific pattern recognition.",
    "This report is not semantic equivalence against real solc Yul.",
]

REPORT_VERSION = 6


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


def check_groups(checks: list[dict[str, str]]) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {
        "leanOwned": [],
        "tested": [],
        "trusted": [],
    }
    for check in checks:
        name = check["name"]
        trust = check["trust"]
        if trust == "Lean-owned manifest":
            groups["leanOwned"].append(name)
        elif trust in {
            "tested",
            "trusted-summary-tested",
            "trace-replay-tested",
            "Lean-owned certificate",
            "Lean-owned trace skeleton",
        }:
            groups["tested"].append(name)
        else:
            groups["trusted"].append(name)
    return groups


def format_markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Counter Bridge Report",
        "",
        f"Status: **{report.get('status', 'failed')}**",
        f"Report version: `{report.get('reportVersion', REPORT_VERSION)}`",
        "",
        "## Bridge Certificate",
        "",
    ]

    certificate = report.get("certificate", {})
    if certificate:
        groups = certificate.get("checkGroups", {})
        lines.extend(
            [
                f"- Certificate kind: `{certificate.get('kind')}`",
                f"- Certificate version: `{certificate.get('version')}`",
                f"- Tested checks: `{len(groups.get('tested', []))}`",
                f"- Lean-owned manifest checks: `{len(groups.get('leanOwned', []))}`",
                f"- Trusted-boundary checks: `{len(groups.get('trusted', []))}`",
            ]
        )
    else:
        lines.append("- No certificate section available.")

    lines.extend([
        "",
        "## Proved In Lean",
        "",
    ])

    proof_refs = report.get("bridgeManifest", {}).get("proofReferences", [])
    if proof_refs:
        lines.extend(f"- `{proof}`" for proof in proof_refs)
    else:
        lines.append("- No proof references available; Lean artifact export may have failed.")

    lines.extend(["", "## Tested Against Lean Artifacts", ""])
    for check in report.get("checks", []):
        if check.get("trust") in {
            "tested",
            "trusted-summary-tested",
            "trace-replay-tested",
            "Lean-owned certificate",
            "Lean-owned trace skeleton",
            "Lean-owned manifest",
        }:
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

    lines.extend(["", "## Solc Trace Replay", ""])
    replay = report.get("solc", {}).get("traceReplay")
    replay_check = next(
        (
            check
            for check in report.get("checks", [])
            if check.get("name") == "solcTraceReplayToLeanYul"
        ),
        None,
    )
    if replay_check is not None:
        marker = "PASS" if replay_check.get("status") == "passed" else "FAIL"
        lines.append(f"- **{marker}** {replay_check.get('message')}")
    if replay is not None:
        body = replay.get("function", {}).get("body", [])
        lines.append(
            f"- Replayed trace emits `{len(body)}` restricted Yul statements."
        )
    else:
        lines.append("- No trace replay artifact available.")

    lines.extend(["", "## Lean-Owned Trace Skeleton", ""])
    skeleton_check = next(
        (
            check
            for check in report.get("checks", [])
            if check.get("name") == "solcTraceSkeletonToLeanManifest"
        ),
        None,
    )
    if skeleton_check is not None:
        marker = "PASS" if skeleton_check.get("status") == "passed" else "FAIL"
        lines.append(f"- **{marker}** {skeleton_check.get('message')}")
    skeleton = report.get("solc", {}).get("traceSkeleton")
    if skeleton is not None:
        lines.append(
            f"- Trace skeleton has `{len(skeleton)}` Lean-owned rule/effect entries."
        )
    else:
        lines.append("- No trace skeleton artifact available.")

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


def trace_to_skeleton(trace: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        trace_entry_to_skeleton(index, entry)
        for index, entry in enumerate(trace, start=1)
    ]


def trace_entry_to_skeleton(index: int, entry: dict[str, Any]) -> dict[str, Any]:
    effect = entry["effect"]
    kind = effect.get("kind")
    if kind == "emitStmt":
        emits = [effect["stmt"]]
    elif kind == "emitStmts":
        emits = effect["stmts"]
    else:
        emits = []
    return {
        "effectKind": kind,
        "emits": emits,
        "index": index,
        "leanProof": entry.get("leanProof", ""),
        "rule": entry["rule"],
    }


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
    expected_source_certificate = lean_manifest["sourceCertificate"]
    expected_trace_skeleton = lean_manifest["expectedTraceSkeleton"]

    checks: list[dict[str, str]] = []
    source_info: dict[str, Any] = {
        "certificate": None,
    }
    solc_info: dict[str, Any] = {
        "sourceObject": None,
        "sourceFunction": None,
        "trustedRules": [],
        "trace": [],
        "traceReplay": None,
        "traceSkeleton": None,
    }
    solc_summary_rules: list[str] | None = None
    solc_trace_skeleton: list[dict[str, Any]] | None = None

    if solidity_path.exists():
        try:
            contract = parse_counter(solidity_path.read_text())
            source_data = contract_to_source_data(contract)
            source_certificate = contract_to_source_certificate(contract)
            source_info["certificate"] = source_certificate
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
            checks.append(
                check_data(
                    "soliditySourceCertificateToLeanManifest",
                    "Lean-owned certificate",
                    source_certificate,
                    expected_source_certificate,
                    "Counter Solidity source certificate matches the Lean bridge manifest.",
                    "Counter Solidity source certificate does not match the Lean bridge manifest.",
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
            checks.append(
                failed_check(
                    "soliditySourceCertificateToLeanManifest",
                    "Lean-owned certificate",
                    "source parser did not produce a source certificate to compare",
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
        checks.append(
            failed_check(
                "soliditySourceCertificateToLeanManifest",
                "Lean-owned certificate",
                "source parser did not produce a source certificate to compare",
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
                "traceReplay": summary_data["traceReplay"],
                "traceReplayMatchesNormalized": summary_data[
                    "traceReplayMatchesNormalized"
                ],
                "traceSkeleton": trace_to_skeleton(summary_data["trace"]),
            }
            solc_summary_rules = summary_data["trustedRules"]
            solc_trace_skeleton = solc_info["traceSkeleton"]
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
            checks.append(
                check_data(
                    "solcTraceReplayToLeanYul",
                    "trace-replay-tested",
                    summary_data["traceReplay"],
                    lean_yul,
                    "solc summary trace replay matches the Lean Yul artifact.",
                    "solc summary trace replay does not match the Lean Yul artifact.",
                )
            )
            checks.append(
                check_data(
                    "solcTraceSkeletonToLeanManifest",
                    "Lean-owned trace skeleton",
                    solc_trace_skeleton,
                    expected_trace_skeleton,
                    "solc summary trace skeleton matches the Lean bridge manifest.",
                    "solc summary trace skeleton does not match the Lean bridge manifest.",
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
            checks.append(
                failed_check(
                    "solcTraceReplayToLeanYul",
                    "trace-replay-tested",
                    "solc summary did not produce a trace replay to compare",
                )
            )
            checks.append(
                failed_check(
                    "solcTraceSkeletonToLeanManifest",
                    "Lean-owned trace skeleton",
                    "solc summary did not produce a trace skeleton to compare",
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
            checks.append(
                failed_check(
                    "solcTraceReplayToLeanYul",
                    "trace-replay-tested",
                    "solc summary did not produce a trace replay to compare",
                )
            )
            checks.append(
                failed_check(
                    "solcTraceSkeletonToLeanManifest",
                    "Lean-owned trace skeleton",
                    "solc summary did not produce a trace skeleton to compare",
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
        checks.append(
            failed_check(
                "solcTraceReplayToLeanYul",
                "trace-replay-tested",
                "solc summary did not produce a trace replay to compare",
            )
        )
        checks.append(
            failed_check(
                "solcTraceSkeletonToLeanManifest",
                "Lean-owned trace skeleton",
                "solc summary did not produce a trace skeleton to compare",
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
        "certificate": {
            "kind": "counterBridgeCertificate",
            "version": REPORT_VERSION,
            "status": status,
            "checkGroups": check_groups(checks),
            "trustedBoundaries": [
                "Counter-only Solidity parser.",
                "Counter-specific Python solc IR recognizer.",
                "Python hex literal parsing.",
                "Python trace replay checker.",
            ],
            "nonClaims": lean_manifest["limitations"],
        },
        "bridgeManifest": {
            "expectedTrustedRules": expected_rules,
            "expectedTraceSkeleton": expected_trace_skeleton,
            "bridgeRuleProofs": lean_manifest["bridgeRuleProofs"],
            "proofReferences": lean_manifest["proofReferences"],
        },
        "checks": checks,
        "source": source_info,
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
                "traceReplay": None,
                "traceSkeleton": None,
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
                "traceReplay": None,
                "traceSkeleton": None,
            },
            "limitations": LIMITATIONS,
        }

    output = stable_json(report) if args.format == "json" else format_markdown_report(report)
    print(output, end="")
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
