#!/usr/bin/env python3
"""Audit the current AA/PQ source-shape boundary against Lean-owned artifacts.

This is a Solidity-shape-only audit. It does not verify Solidity parsing
generally, does not run solc, and does not claim semantic equivalence with any
compiler output. The intended trust reduction is:

  Lean-owned source artifact  ─┐
  Lean-owned source certificate │── deterministic cross-checks
  Lean-owned behavior summary  ─┘
  Solidity sketch (examples/AAPQIntegration.sol) ── restricted shape parse

The script fails if any cross-check fails, and emits a deterministic JSON or
Markdown report otherwise.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

REPORT_VERSION = 4

LIMITATIONS = [
    "AA/PQ source-shape audit only.",
    "Solidity parsing is a narrow restricted shape extractor for the AAPQ sketch.",
    "Does not run solc or compare against Yul.",
    "Does not verify external-call, ABI, calldata, memory, gas, or reentrancy semantics.",
    "Verifier is an abstract oracle in the Lean models.",
]

# Map between the behavior-summary's contract role labels ("wallet", "wrapper")
# and the source-json keys carrying the Solidity-shaped contract for that role.
ROLE_TO_SOURCE_KEY: dict[str, str] = {
    "wallet": "wallet",
    "wrapper": "wrapper",
}

# Required Solidity-side shape. Each entry is (contract name, required storage
# slot names, required external function names).
REQUIRED_CONTRACTS: list[tuple[str, list[str], list[str]]] = [
    (
        "PQVerifierWrapper",
        ["expectedPublicKeyLength", "expectedSignatureLength", "expectedDomain"],
        ["verify"],
    ),
    (
        "AAWallet",
        ["nonce", "keyCommitment", "domain", "entryPoint"],
        ["validateUserOp"],
    ),
    (
        "AAPQIntegration",
        [],
        ["validateIntegrated"],
    ),
]


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
            "SoLean/AAPQArtifactsMain.lean",
            kind,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


_LINE_COMMENT = re.compile(r"//[^\n]*")
_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_CONTRACT_HEAD = re.compile(r"\bcontract\s+(\w+)\s*\{")
_STORAGE_DECL = re.compile(
    r"\b(?:uint256|address)\s+public\s+(\w+)\s*;",
)
_FUNCTION_DECL = re.compile(
    r"\bfunction\s+(\w+)\s*\([^)]*\)\s*(?:external|public)\b",
)


def parse_solidity_shape(text: str) -> dict[str, dict[str, list[str]]]:
    """Extract the shape of contracts from a restricted Solidity input.

    Only top-level `contract Name { ... }` blocks are walked. Inside each
    contract, only `uint256/address public <name>;` storage and
    `function <name>(...) external|public` declarations are collected. Anything
    else is intentionally ignored so the audit only enforces *presence* of the
    required shape, not absence of extras.
    """

    stripped = _BLOCK_COMMENT.sub("", text)
    stripped = _LINE_COMMENT.sub("", stripped)

    shapes: dict[str, dict[str, list[str]]] = {}
    for match in _CONTRACT_HEAD.finditer(stripped):
        name = match.group(1)
        start = match.end()
        depth = 1
        cursor = start
        while cursor < len(stripped) and depth > 0:
            char = stripped[cursor]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
            cursor += 1
        if depth != 0:
            raise ValueError(
                f"Unbalanced braces while parsing contract '{name}'"
            )
        body = stripped[start : cursor - 1]
        shapes[name] = {
            "storage": _STORAGE_DECL.findall(body),
            "functions": _FUNCTION_DECL.findall(body),
        }
    return shapes


def passed(name: str, trust: str, message: str) -> dict[str, str]:
    return {"name": name, "status": "passed", "trust": trust, "message": message}


def failed(name: str, trust: str, message: str) -> dict[str, str]:
    return {"name": name, "status": "failed", "trust": trust, "message": message}


def check_certificate_embeds_behavior_summary(
    certificate: dict[str, Any], behavior_summary: dict[str, Any]
) -> dict[str, str]:
    embedded = certificate.get("expectedBehaviorSummary")
    if embedded is None:
        return failed(
            "certificate.expectedBehaviorSummary present",
            "Lean-owned certificate",
            "Certificate does not embed expectedBehaviorSummary.",
        )
    if embedded == behavior_summary:
        return passed(
            "certificate.expectedBehaviorSummary == behavior-summary artifact",
            "Lean-owned certificate",
            "Certificate's expectedBehaviorSummary matches standalone artifact.",
        )
    return failed(
        "certificate.expectedBehaviorSummary == behavior-summary artifact",
        "Lean-owned certificate",
        "Certificate's expectedBehaviorSummary differs from standalone artifact.",
    )


def check_source_contracts_match_certificate(
    source: dict[str, Any], certificate: dict[str, Any]
) -> dict[str, str]:
    cert_contracts = certificate.get("contracts", [])
    source_pair = [source.get("wallet"), source.get("wrapper")]
    if any(value is None for value in source_pair):
        return failed(
            "source-json contracts present",
            "Lean-owned certificate",
            "source-json is missing wallet or wrapper.",
        )
    expected = sorted(source_pair, key=lambda entry: entry.get("name", ""))
    observed = sorted(cert_contracts, key=lambda entry: entry.get("name", ""))
    if expected == observed:
        return passed(
            "certificate.contracts == source-json wallet+wrapper",
            "Lean-owned certificate",
            "Certificate contracts match the source-json wallet and wrapper.",
        )
    return failed(
        "certificate.contracts == source-json wallet+wrapper",
        "Lean-owned certificate",
        "Certificate contracts disagree with source-json wallet/wrapper.",
    )


def check_solidity_contract_present(
    shape: dict[str, dict[str, list[str]]], contract: str
) -> dict[str, str]:
    if contract in shape:
        return passed(
            f"Solidity contract '{contract}' present",
            "trusted Solidity shape",
            f"Found contract '{contract}' in the Solidity sketch.",
        )
    return failed(
        f"Solidity contract '{contract}' present",
        "trusted Solidity shape",
        f"Contract '{contract}' missing from the Solidity sketch.",
    )


def check_solidity_storage(
    shape: dict[str, dict[str, list[str]]],
    contract: str,
    required_storage: list[str],
) -> dict[str, str]:
    contract_shape = shape.get(contract)
    if contract_shape is None:
        return failed(
            f"Solidity {contract} storage slots",
            "trusted Solidity shape",
            f"Contract '{contract}' missing from the Solidity sketch.",
        )
    observed = contract_shape.get("storage", [])
    missing = [name for name in required_storage if name not in observed]
    if missing:
        return failed(
            f"Solidity {contract} storage slots",
            "trusted Solidity shape",
            f"Missing storage names in '{contract}': {sorted(missing)}.",
        )
    return passed(
        f"Solidity {contract} storage slots",
        "trusted Solidity shape",
        f"All required storage names present in '{contract}'.",
    )


def check_solidity_functions(
    shape: dict[str, dict[str, list[str]]],
    contract: str,
    required_functions: list[str],
) -> dict[str, str]:
    contract_shape = shape.get(contract)
    if contract_shape is None:
        return failed(
            f"Solidity {contract} functions",
            "trusted Solidity shape",
            f"Contract '{contract}' missing from the Solidity sketch.",
        )
    observed = contract_shape.get("functions", [])
    missing = [name for name in required_functions if name not in observed]
    if missing:
        return failed(
            f"Solidity {contract} functions",
            "trusted Solidity shape",
            f"Missing external/public functions in '{contract}': {sorted(missing)}.",
        )
    return passed(
        f"Solidity {contract} functions",
        "trusted Solidity shape",
        f"All required external/public functions present in '{contract}'.",
    )


def walk_operands_in_condition(condition: dict[str, Any]) -> list[dict[str, Any]]:
    args = condition.get("args", [])
    return [arg for arg in args if isinstance(arg, dict)]


def walk_operands_in_value(value: dict[str, Any]) -> list[dict[str, Any]]:
    """Flatten a structured ValueExpression into the list of operand leaves."""
    if not isinstance(value, dict):
        return []
    kind = value.get("kind")
    if kind == "checkedAdd":
        leaves: list[dict[str, Any]] = []
        for sub in value.get("args", []):
            leaves.extend(walk_operands_in_value(sub))
        return leaves
    # Leaf operand: param / slot / msgSender / const.
    return [value]


def render_operand(operand: dict[str, Any]) -> str:
    kind = operand.get("kind")
    if kind == "param":
        return str(operand.get("name", "?"))
    if kind == "slot":
        return f"{operand.get('contract', '?')}.{operand.get('name', '?')}"
    if kind == "msgSender":
        return "msg.sender"
    if kind == "const":
        return str(operand.get("value", "?"))
    return f"<unknown:{kind}>"


def render_condition(condition: dict[str, Any]) -> str:
    kind = condition.get("kind")
    args = condition.get("args", [])
    rendered = [render_operand(arg) for arg in args]
    if kind == "eq" and len(rendered) == 2:
        return f"{rendered[0]} == {rendered[1]}"
    if kind == "verifier" and len(rendered) == 4:
        return "verifier(" + ", ".join(rendered) + ")"
    return f"<unknown-condition:{kind}>"


def render_value(value: dict[str, Any]) -> str:
    if not isinstance(value, dict):
        return "?"
    if value.get("kind") == "checkedAdd":
        parts = [render_value(arg) for arg in value.get("args", [])]
        return "checkedAdd(" + ", ".join(parts) + ")"
    return render_operand(value)


def operand_storage_lookup(source: dict[str, Any]) -> dict[str, set[str]]:
    """Build {role -> set of storage slot names declared in source-json}."""
    lookup: dict[str, set[str]] = {}
    for role, key in ROLE_TO_SOURCE_KEY.items():
        contract = source.get(key, {}) or {}
        slots = contract.get("storage", []) or []
        lookup[role] = {entry.get("name", "") for entry in slots}
    return lookup


def operand_is_in_scope(
    operand: dict[str, Any],
    params: set[str],
    storage: dict[str, set[str]],
) -> tuple[bool, str]:
    kind = operand.get("kind")
    if kind == "param":
        name = operand.get("name")
        if name in params:
            return True, ""
        return False, f"unknown param '{name}'"
    if kind == "slot":
        role = operand.get("contract")
        slot_name = operand.get("name")
        if role not in storage:
            return False, f"unknown contract role '{role}'"
        if slot_name not in storage[role]:
            return False, f"unknown slot '{role}.{slot_name}'"
        return True, ""
    if kind == "msgSender":
        return True, ""
    if kind == "const":
        return True, ""
    return False, f"unknown operand kind '{kind}'"


def check_behavior_summary_operand_scope(
    summary: dict[str, Any], source: dict[str, Any]
) -> dict[str, str]:
    params = set(summary.get("params", []))
    storage = operand_storage_lookup(source)

    violations: list[str] = []
    for phase in summary.get("phases", []):
        phase_name = phase.get("name", "?")
        for guard in phase.get("guards", []):
            condition = guard.get("condition", {})
            for operand in walk_operands_in_condition(condition):
                ok, why = operand_is_in_scope(operand, params, storage)
                if not ok:
                    violations.append(
                        f"phase '{phase_name}' guard '{guard.get('kind', '?')}': {why}"
                    )
        for write in phase.get("finalWrites", []):
            for operand in walk_operands_in_value(write.get("value", {})):
                ok, why = operand_is_in_scope(operand, params, storage)
                if not ok:
                    violations.append(
                        f"phase '{phase_name}' write '{write.get('name', '?')}': {why}"
                    )

    if violations:
        return failed(
            "behavior-summary operands in scope",
            "Lean-owned behavior summary",
            "Out-of-scope operands: " + "; ".join(violations),
        )
    return passed(
        "behavior-summary operands in scope",
        "Lean-owned behavior summary",
        "All structured operands reference a declared param or known storage slot.",
    )


def check_crypto_assumptions_link_to_proofs(
    certificate: dict[str, Any],
) -> dict[str, str]:
    """Every cryptoAssumption.theoremReferences entry must appear in
    proofReferences."""
    assumptions = certificate.get("cryptoAssumptions", [])
    if not assumptions:
        return failed(
            "cryptoAssumptions present",
            "Lean-owned certificate",
            "Certificate has no cryptoAssumptions array.",
        )
    proofs = set(certificate.get("proofReferences", []))
    missing: list[str] = []
    total_refs = 0
    for entry in assumptions:
        refs = entry.get("theoremReferences", [])
        if not refs:
            missing.append(
                f"{entry.get('name', '?')}: missing theoremReferences"
            )
            continue
        for ref in refs:
            total_refs += 1
            if ref not in proofs:
                missing.append(
                    f"{entry.get('name', '?')}: theoremReference {ref} not in proofReferences"
                )
    if missing:
        return failed(
            "cryptoAssumptions link to proofReferences",
            "Lean-owned certificate",
            "Broken links: " + "; ".join(missing),
        )
    return passed(
        "cryptoAssumptions link to proofReferences",
        "Lean-owned certificate",
        f"All {total_refs} theoremReferences across {len(assumptions)} cryptoAssumptions resolve.",
    )


def check_under_oracle_assumption_theorems_covered(
    certificate: dict[str, Any],
) -> dict[str, str]:
    """Every "_under_oracle_assumption" theorem in proofReferences must be
    pointed to by some cryptoAssumption.theoremReferences entry."""
    proofs = certificate.get("proofReferences", [])
    oracle_theorems = [name for name in proofs if name.endswith("_under_oracle_assumption")]
    if not oracle_theorems:
        return passed(
            "under_oracle_assumption theorems covered",
            "Lean-owned certificate",
            "No *_under_oracle_assumption theorems present — nothing to cover.",
        )
    declared: set[str] = set()
    for entry in certificate.get("cryptoAssumptions", []):
        for ref in entry.get("theoremReferences", []):
            declared.add(ref)
    uncovered = [name for name in oracle_theorems if name not in declared]
    if uncovered:
        return failed(
            "under_oracle_assumption theorems covered",
            "Lean-owned certificate",
            "Uncovered theorems: " + ", ".join(sorted(uncovered)),
        )
    return passed(
        "under_oracle_assumption theorems covered",
        "Lean-owned certificate",
        f"All {len(oracle_theorems)} *_under_oracle_assumption theorems have a matching cryptoAssumption.",
    )


def check_crypto_assumption_support_graph(
    certificate: dict[str, Any],
) -> dict[str, str]:
    assumptions = certificate.get("cryptoAssumptions", [])
    graph = certificate.get("cryptoAssumptionGraph", [])
    if not graph:
        return failed(
            "cryptoAssumption support graph present",
            "Lean-owned certificate",
            "Certificate has no cryptoAssumptionGraph array.",
        )

    proofs = set(certificate.get("proofReferences", []))
    refs_by_assumption: dict[str, list[str]] = {
        entry.get("name", ""): entry.get("theoremReferences", [])
        for entry in assumptions
    }
    expected_pairs = [
        (entry.get("name", ""), ref)
        for entry in assumptions
        for ref in entry.get("theoremReferences", [])
    ]

    graph_pairs: list[tuple[str, str]] = []
    problems: list[str] = []
    for edge in graph:
        assumption = edge.get("assumption", "")
        theorem = edge.get("theoremReference", "")
        graph_pairs.append((assumption, theorem))
        if edge.get("edge") != "assumptionSupportsTheorem":
            problems.append(
                f"{assumption or '?'} -> {theorem or '?'}: unsupported edge kind"
            )
        if not edge.get("flow") or not edge.get("layer"):
            problems.append(
                f"{assumption or '?'} -> {theorem or '?'}: missing flow/layer"
            )
        if assumption not in refs_by_assumption:
            problems.append(f"{assumption or '?'}: unknown assumption")
            continue
        if theorem not in refs_by_assumption[assumption]:
            problems.append(
                f"{assumption}: theoremReference {theorem or '?'} not listed on assumption"
            )
        if theorem not in proofs:
            problems.append(
                f"{assumption}: theoremReference {theorem or '?'} not in proofReferences"
            )

    if graph_pairs != expected_pairs:
        problems.append(
            "graph edges do not exactly match cryptoAssumptions theoremReferences"
        )

    if problems:
        return failed(
            "cryptoAssumption support graph resolves",
            "Lean-owned certificate",
            "Broken graph: " + "; ".join(problems),
        )

    return passed(
        "cryptoAssumption support graph resolves",
        "Lean-owned certificate",
        f"All {len(graph_pairs)} support edges resolve in stable order.",
    )


EXECUTE_PHASE_NAME = "execute"
EXECUTE_FINAL_WRITE_NAME = "lastOpHash"
EXECUTE_FINAL_WRITE_SLOT = 4


def check_full_behavior_summary_includes_execute_phase(
    full_summary: dict[str, Any],
) -> dict[str, str]:
    """The full behavior summary must include an 'execute' phase with a single
    finalWrite to AAWallet.lastOpHashSlot (slot 4)."""
    phases = full_summary.get("phases", [])
    execute_phases = [p for p in phases if p.get("name") == EXECUTE_PHASE_NAME]
    if len(execute_phases) != 1:
        return failed(
            "full-behavior-summary execute phase",
            "Lean-owned full behavior summary",
            f"Expected exactly one 'execute' phase, found {len(execute_phases)}.",
        )
    phase = execute_phases[0]
    if phase.get("guards"):
        return failed(
            "full-behavior-summary execute phase",
            "Lean-owned full behavior summary",
            "Execute phase must have zero guards.",
        )
    writes = phase.get("finalWrites", [])
    if len(writes) != 1:
        return failed(
            "full-behavior-summary execute phase",
            "Lean-owned full behavior summary",
            f"Execute phase must have exactly one finalWrite, found {len(writes)}.",
        )
    write = writes[0]
    if write.get("name") != EXECUTE_FINAL_WRITE_NAME:
        return failed(
            "full-behavior-summary execute phase",
            "Lean-owned full behavior summary",
            f"Execute finalWrite name expected {EXECUTE_FINAL_WRITE_NAME!r}, "
            f"got {write.get('name')!r}.",
        )
    if write.get("slot") != EXECUTE_FINAL_WRITE_SLOT:
        return failed(
            "full-behavior-summary execute phase",
            "Lean-owned full behavior summary",
            f"Execute finalWrite slot expected {EXECUTE_FINAL_WRITE_SLOT}, "
            f"got {write.get('slot')!r}.",
        )
    return passed(
        "full-behavior-summary execute phase",
        "Lean-owned full behavior summary",
        f"Execute phase has the expected finalWrite to slot {EXECUTE_FINAL_WRITE_SLOT}.",
    )


def check_full_behavior_summary_extends_short_summary(
    full_summary: dict[str, Any],
    short_summary: dict[str, Any],
) -> dict[str, str]:
    """The full summary's first N phases must equal the short summary's N
    phases (where N = len(short_summary.phases))."""
    short_phases = short_summary.get("phases", [])
    full_phases = full_summary.get("phases", [])
    if len(full_phases) < len(short_phases):
        return failed(
            "full-behavior-summary extends short summary",
            "Lean-owned full behavior summary",
            f"Full summary has fewer phases ({len(full_phases)}) than the short "
            f"summary ({len(short_phases)}).",
        )
    if full_phases[: len(short_phases)] != short_phases:
        return failed(
            "full-behavior-summary extends short summary",
            "Lean-owned full behavior summary",
            "Full summary's first phases diverge from the short summary.",
        )
    return passed(
        "full-behavior-summary extends short summary",
        "Lean-owned full behavior summary",
        f"Full summary extends the {len(short_phases)}-phase short summary "
        f"with {len(full_phases) - len(short_phases)} additional phase(s).",
    )


def check_phase_proof_references(behavior_summary: dict[str, Any]) -> dict[str, str]:
    phases = behavior_summary.get("phases", [])
    if not phases:
        return failed(
            "behavior-summary phases present",
            "Lean-owned behavior summary",
            "Behavior summary has no phases.",
        )
    missing = [phase.get("name") for phase in phases if not phase.get("proofReference")]
    if missing:
        return failed(
            "behavior-summary phase proof references",
            "Lean-owned behavior summary",
            f"Phases without proofReference: {sorted(missing, key=str)}.",
        )
    return passed(
        "behavior-summary phase proof references",
        "Lean-owned behavior summary",
        f"All {len(phases)} phases carry a proofReference.",
    )


def run_audit(
    source: dict[str, Any],
    certificate: dict[str, Any],
    behavior_summary: dict[str, Any],
    full_behavior_summary: dict[str, Any],
    solidity_text: str,
) -> dict[str, Any]:
    shape = parse_solidity_shape(solidity_text)

    checks: list[dict[str, str]] = []
    checks.append(
        check_certificate_embeds_behavior_summary(certificate, behavior_summary)
    )
    checks.append(check_source_contracts_match_certificate(source, certificate))
    checks.append(check_phase_proof_references(behavior_summary))
    checks.append(check_behavior_summary_operand_scope(behavior_summary, source))
    checks.append(check_crypto_assumptions_link_to_proofs(certificate))
    checks.append(check_under_oracle_assumption_theorems_covered(certificate))
    checks.append(check_crypto_assumption_support_graph(certificate))
    checks.append(
        check_full_behavior_summary_includes_execute_phase(full_behavior_summary)
    )
    checks.append(
        check_full_behavior_summary_extends_short_summary(
            full_behavior_summary, behavior_summary
        )
    )
    checks.append(
        check_behavior_summary_operand_scope(full_behavior_summary, source)
    )
    for contract, storage, functions in REQUIRED_CONTRACTS:
        checks.append(check_solidity_contract_present(shape, contract))
        if storage:
            checks.append(check_solidity_storage(shape, contract, storage))
        if functions:
            checks.append(check_solidity_functions(shape, contract, functions))

    status = "passed" if all(check["status"] == "passed" for check in checks) else "failed"
    return {
        "artifacts": {
            "behaviorSummaryHash": artifact_hash(behavior_summary),
            "fullBehaviorSummaryHash": artifact_hash(full_behavior_summary),
            "sourceCertificateHash": artifact_hash(certificate),
            "sourceHash": artifact_hash(source),
        },
        "checks": checks,
        "limitations": LIMITATIONS,
        "reportVersion": REPORT_VERSION,
        "solidityContracts": sorted(shape.keys()),
        "status": status,
    }


def format_markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# AA/PQ Source-Shape Report",
        "",
        f"Status: **{report.get('status', 'failed')}**",
        f"Report version: `{report.get('reportVersion', REPORT_VERSION)}`",
        "",
        "## Checks",
        "",
    ]
    for check in report.get("checks", []):
        icon = "x" if check.get("status") == "failed" else "v"
        lines.append(
            f"- [{icon}] **{check.get('name')}** ({check.get('trust')}): "
            f"{check.get('message')}"
        )
    lines.append("")
    lines.append("## Limitations")
    lines.append("")
    for item in report.get("limitations", []):
        lines.append(f"- {item}")
    lines.append("")
    return "\n".join(lines)


def load_json_arg(value: str | None, default_kind: str) -> dict[str, Any]:
    if value is None:
        return lean_artifact(default_kind)
    return json.loads(Path(value).read_text())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-json",
        help="Path to a precomputed aapq source-json artifact. "
        "Defaults to invoking lake.",
    )
    parser.add_argument(
        "--source-certificate-json",
        help="Path to a precomputed aapq source-certificate-json artifact. "
        "Defaults to invoking lake.",
    )
    parser.add_argument(
        "--behavior-summary-json",
        help="Path to a precomputed aapq behavior-summary-json artifact. "
        "Defaults to invoking lake.",
    )
    parser.add_argument(
        "--full-behavior-summary-json",
        help="Path to a precomputed aapq full-behavior-summary-json artifact. "
        "Defaults to invoking lake.",
    )
    parser.add_argument(
        "--solidity",
        default="examples/AAPQIntegration.sol",
        help="Path to the AA/PQ Solidity sketch.",
    )
    parser.add_argument(
        "--format",
        choices=("json", "markdown"),
        default="json",
        help="Report format.",
    )
    args = parser.parse_args(argv)

    source = load_json_arg(args.source_json, "source-json")
    certificate = load_json_arg(
        args.source_certificate_json, "source-certificate-json"
    )
    behavior_summary = load_json_arg(
        args.behavior_summary_json, "behavior-summary-json"
    )
    full_behavior_summary = load_json_arg(
        args.full_behavior_summary_json, "full-behavior-summary-json"
    )
    solidity_text = Path(args.solidity).read_text()

    report = run_audit(
        source, certificate, behavior_summary, full_behavior_summary, solidity_text
    )

    if args.format == "markdown":
        sys.stdout.write(format_markdown_report(report))
    else:
        sys.stdout.write(stable_json(report))

    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
