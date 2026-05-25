from __future__ import annotations

import io
import json
import unittest
from contextlib import redirect_stdout
from functools import lru_cache
from pathlib import Path

from scripts.check_aapq_source import (
    REPORT_VERSION,
    artifact_hash,
    check_behavior_summary_operand_scope,
    check_certificate_embeds_behavior_summary,
    check_crypto_assumption_support_graph,
    check_crypto_assumptions_link_to_proofs,
    check_full_behavior_summary_extends_short_summary,
    check_full_behavior_summary_includes_execute_phase,
    check_falcon_simple_wallet_shape,
    check_integration_variants,
    check_protocol_boundary_assumptions,
    check_phase_proof_references,
    check_source_contracts_match_certificate,
    check_under_oracle_assumption_theorems_covered,
    crypto_assumption_support_graph_view,
    check_verifier_model_calibrations,
    format_crypto_assumption_graph_markdown,
    format_verifier_model_calibrations_markdown,
    lean_artifact,
    main as check_aapq_source_main,
    parse_solidity_shape,
    render_condition,
    render_value,
    run_audit,
    stable_json,
    walk_operands_in_condition,
    walk_operands_in_value,
    verifier_model_calibrations_view,
)
from scripts.demo_aapq_source import (
    main as demo_aapq_source_main,
    print_trust_boundaries,
)


REPO_ROOT = Path(__file__).resolve().parent.parent
SOLIDITY_PATH = REPO_ROOT / "examples" / "AAPQIntegration.sol"
GOLDEN_PATH = REPO_ROOT / "tests" / "golden" / "AAPQ.source.v5.json"


@lru_cache(maxsize=None)
def cached_artifact(kind: str) -> dict:
    return lean_artifact(kind)


def copied_json(data: dict) -> dict:
    return json.loads(json.dumps(data))


class SolidityShapeParserTests(unittest.TestCase):
    def test_extracts_storage_and_external_functions(self) -> None:
        source = """
        // line comment
        /* block
           comment */
        contract Wrapper {
            uint256 public expectedDomain; // trailing
            address public owner;
            uint256 internal hidden;
            function pqVerifier(uint256 x) internal view returns (bool) {}
            function verify(uint256 a, uint256 b) external view {}
        }
        contract Empty {}
        """
        shape = parse_solidity_shape(source)
        self.assertIn("Wrapper", shape)
        self.assertIn("Empty", shape)
        self.assertEqual(
            shape["Wrapper"]["storage"],
            ["expectedDomain", "owner"],
        )
        self.assertEqual(shape["Wrapper"]["functions"], ["verify"])
        self.assertEqual(shape["Empty"], {"storage": [], "functions": []})

    def test_rejects_unbalanced_braces(self) -> None:
        with self.assertRaises(ValueError):
            parse_solidity_shape("contract Broken {\n uint256 public x;\n")


class CertificateCrossCheckTests(unittest.TestCase):
    def test_passes_when_certificate_embeds_behavior_summary(self) -> None:
        certificate = {"expectedBehaviorSummary": {"phases": [], "version": 1}}
        summary = {"phases": [], "version": 1}
        result = check_certificate_embeds_behavior_summary(certificate, summary)
        self.assertEqual(result["status"], "passed")

    def test_fails_when_certificate_disagrees(self) -> None:
        certificate = {"expectedBehaviorSummary": {"phases": [], "version": 1}}
        summary = {"phases": [{"name": "wrapper"}], "version": 1}
        result = check_certificate_embeds_behavior_summary(certificate, summary)
        self.assertEqual(result["status"], "failed")

    def test_fails_when_certificate_missing_summary(self) -> None:
        result = check_certificate_embeds_behavior_summary({}, {"phases": []})
        self.assertEqual(result["status"], "failed")

    def test_source_contracts_compare_in_a_stable_order(self) -> None:
        wallet = {"name": "AAWallet"}
        wrapper = {"name": "PQVerifierWrapper"}
        source = {"wallet": wallet, "wrapper": wrapper}
        certificate = {"contracts": [wrapper, wallet]}
        result = check_source_contracts_match_certificate(source, certificate)
        self.assertEqual(result["status"], "passed")

    def test_source_contracts_fail_on_mismatch(self) -> None:
        source = {
            "wallet": {"name": "AAWallet"},
            "wrapper": {"name": "PQVerifierWrapper"},
        }
        certificate = {"contracts": [{"name": "AAWallet"}]}
        result = check_source_contracts_match_certificate(source, certificate)
        self.assertEqual(result["status"], "failed")

    def test_phase_proof_references_required(self) -> None:
        summary = {"phases": [{"name": "wrapper", "proofReference": "X"}]}
        self.assertEqual(
            check_phase_proof_references(summary)["status"], "passed"
        )

        missing = {"phases": [{"name": "wrapper", "proofReference": ""}]}
        self.assertEqual(
            check_phase_proof_references(missing)["status"], "failed"
        )

        empty = {"phases": []}
        self.assertEqual(check_phase_proof_references(empty)["status"], "failed")


class AuditIntegrationTests(unittest.TestCase):
    def test_audit_passes_on_real_artifacts(self) -> None:
        source = cached_artifact("source-json")
        certificate = cached_artifact("source-certificate-json")
        summary = cached_artifact("behavior-summary-json")
        full_summary = cached_artifact("full-behavior-summary-json")
        solidity = SOLIDITY_PATH.read_text()

        report = run_audit(source, certificate, summary, full_summary, solidity)
        self.assertEqual(report["status"], "passed", report)
        self.assertEqual(report["reportVersion"], REPORT_VERSION)
        self.assertEqual(
            report["solidityContracts"],
            ["AAPQIntegration", "AAWallet", "PQVerifierWrapper"],
        )

    def test_audit_fails_when_behavior_summary_diverges(self) -> None:
        source = cached_artifact("source-json")
        certificate = copied_json(cached_artifact("source-certificate-json"))
        summary = copied_json(cached_artifact("behavior-summary-json"))
        full_summary = cached_artifact("full-behavior-summary-json")
        summary["phases"][0]["guards"].append(
            {
                "condition": {
                    "args": [
                        {"kind": "param", "name": "publicKey"},
                        {"kind": "param", "name": "publicKey"},
                    ],
                    "kind": "eq",
                },
                "kind": "lengthCheck",
            }
        )
        solidity = SOLIDITY_PATH.read_text()

        report = run_audit(source, certificate, summary, full_summary, solidity)
        self.assertEqual(report["status"], "failed")
        failing = [check for check in report["checks"] if check["status"] == "failed"]
        self.assertTrue(any("expectedBehaviorSummary" in c["name"] for c in failing))

    def test_audit_fails_when_solidity_drops_a_contract(self) -> None:
        source = cached_artifact("source-json")
        certificate = cached_artifact("source-certificate-json")
        summary = cached_artifact("behavior-summary-json")
        full_summary = cached_artifact("full-behavior-summary-json")
        solidity = SOLIDITY_PATH.read_text().replace(
            "contract AAWallet", "contract _RenamedAAWallet"
        )

        report = run_audit(source, certificate, summary, full_summary, solidity)
        self.assertEqual(report["status"], "failed")

    def test_main_emits_stable_json_and_zero_exit(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            exit_code = check_aapq_source_main([])
        self.assertEqual(exit_code, 0)
        report = json.loads(buffer.getvalue())
        self.assertEqual(report["status"], "passed")

    def test_main_markdown_format(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            check_aapq_source_main(["--format", "markdown"])
        text = buffer.getvalue()
        self.assertIn("# AA/PQ Source-Shape Report", text)
        self.assertIn("Status: **passed**", text)
        self.assertIn("## Crypto Assumption Support Graph", text)
        self.assertIn("VerifierSignatureBinding", text)
        self.assertIn("## Verifier Model Calibrations", text)
        self.assertIn("AllFieldsEqualToyVerifier", text)


class StructuredExpressionTests(unittest.TestCase):
    def test_walk_operands_in_condition_returns_args(self) -> None:
        condition = {
            "kind": "eq",
            "args": [
                {"kind": "param", "name": "x"},
                {"kind": "slot", "contract": "wallet", "name": "nonce"},
            ],
        }
        operands = walk_operands_in_condition(condition)
        self.assertEqual(len(operands), 2)
        self.assertEqual(operands[0]["kind"], "param")
        self.assertEqual(operands[1]["kind"], "slot")

    def test_walk_operands_in_value_flattens_checked_add(self) -> None:
        value = {
            "kind": "checkedAdd",
            "args": [
                {"kind": "slot", "contract": "wallet", "name": "nonce"},
                {"kind": "const", "value": 1},
            ],
        }
        operands = walk_operands_in_value(value)
        self.assertEqual([op["kind"] for op in operands], ["slot", "const"])

    def test_render_condition_eq_and_verifier(self) -> None:
        eq = {
            "kind": "eq",
            "args": [
                {"kind": "msgSender"},
                {"kind": "slot", "contract": "wallet", "name": "entryPoint"},
            ],
        }
        self.assertEqual(render_condition(eq), "msg.sender == wallet.entryPoint")

        verifier = {
            "kind": "verifier",
            "args": [
                {"kind": "param", "name": "publicKey"},
                {"kind": "param", "name": "opHash"},
                {"kind": "param", "name": "domain"},
                {"kind": "param", "name": "signature"},
            ],
        }
        self.assertEqual(
            render_condition(verifier),
            "verifier(publicKey, opHash, domain, signature)",
        )

    def test_render_value_checked_add(self) -> None:
        value = {
            "kind": "checkedAdd",
            "args": [
                {"kind": "slot", "contract": "wallet", "name": "nonce"},
                {"kind": "const", "value": 1},
            ],
        }
        self.assertEqual(render_value(value), "checkedAdd(wallet.nonce, 1)")


class OperandScopeCheckTests(unittest.TestCase):
    @staticmethod
    def _source_with(storage_wallet: list[str], storage_wrapper: list[str]) -> dict:
        return {
            "wallet": {"storage": [{"name": name} for name in storage_wallet]},
            "wrapper": {"storage": [{"name": name} for name in storage_wrapper]},
        }

    def test_passes_on_real_artifacts(self) -> None:
        source = cached_artifact("source-json")
        summary = cached_artifact("behavior-summary-json")
        self.assertEqual(
            check_behavior_summary_operand_scope(summary, source)["status"],
            "passed",
        )

    def test_fails_on_unknown_param(self) -> None:
        source = self._source_with(["nonce"], ["expectedDomain"])
        summary = {
            "params": ["publicKey"],
            "phases": [
                {
                    "name": "wrapper",
                    "guards": [
                        {
                            "kind": "domainCheck",
                            "condition": {
                                "kind": "eq",
                                "args": [
                                    {"kind": "param", "name": "ghost"},
                                    {"kind": "slot", "contract": "wrapper", "name": "expectedDomain"},
                                ],
                            },
                        }
                    ],
                    "finalWrites": [],
                }
            ],
        }
        result = check_behavior_summary_operand_scope(summary, source)
        self.assertEqual(result["status"], "failed")
        self.assertIn("ghost", result["message"])

    def test_fails_on_unknown_slot(self) -> None:
        source = self._source_with(["nonce"], ["expectedDomain"])
        summary = {
            "params": ["publicKey"],
            "phases": [
                {
                    "name": "wrapper",
                    "guards": [
                        {
                            "kind": "domainCheck",
                            "condition": {
                                "kind": "eq",
                                "args": [
                                    {"kind": "param", "name": "publicKey"},
                                    {"kind": "slot", "contract": "wrapper", "name": "missingSlot"},
                                ],
                            },
                        }
                    ],
                    "finalWrites": [],
                }
            ],
        }
        result = check_behavior_summary_operand_scope(summary, source)
        self.assertEqual(result["status"], "failed")
        self.assertIn("wrapper.missingSlot", result["message"])

    def test_fails_on_unknown_role(self) -> None:
        source = self._source_with(["nonce"], ["expectedDomain"])
        summary = {
            "params": [],
            "phases": [
                {
                    "name": "wrapper",
                    "guards": [
                        {
                            "kind": "domainCheck",
                            "condition": {
                                "kind": "eq",
                                "args": [
                                    {"kind": "slot", "contract": "ghost", "name": "x"},
                                    {"kind": "slot", "contract": "wrapper", "name": "expectedDomain"},
                                ],
                            },
                        }
                    ],
                    "finalWrites": [],
                }
            ],
        }
        result = check_behavior_summary_operand_scope(summary, source)
        self.assertEqual(result["status"], "failed")
        self.assertIn("ghost", result["message"])

    def test_walks_into_final_write_values(self) -> None:
        source = self._source_with(["nonce"], [])
        summary = {
            "params": [],
            "phases": [
                {
                    "name": "wallet",
                    "guards": [],
                    "finalWrites": [
                        {
                            "name": "nonce",
                            "slot": 0,
                            "contract": "AAWallet",
                            "value": {
                                "kind": "checkedAdd",
                                "args": [
                                    {"kind": "slot", "contract": "wallet", "name": "nonce"},
                                    {"kind": "slot", "contract": "wallet", "name": "missing"},
                                ],
                            },
                        }
                    ],
                }
            ],
        }
        result = check_behavior_summary_operand_scope(summary, source)
        self.assertEqual(result["status"], "failed")
        self.assertIn("wallet.missing", result["message"])


class CryptoAssumptionAuditTests(unittest.TestCase):
    def test_link_to_proofs_passes_on_real_certificate(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        result = check_crypto_assumptions_link_to_proofs(certificate)
        self.assertEqual(result["status"], "passed", result)

    def test_link_to_proofs_fails_when_assumption_dangles(self) -> None:
        certificate = {
            "cryptoAssumptions": [
                {"name": "X", "theoremReferences": ["Module.theorem_x"]},
            ],
            "proofReferences": ["Module.other_theorem"],
        }
        result = check_crypto_assumptions_link_to_proofs(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Module.theorem_x", result["message"])

    def test_link_to_proofs_fails_on_missing_theorem_reference(self) -> None:
        certificate = {
            "cryptoAssumptions": [{"name": "X", "theoremReferences": []}],
            "proofReferences": [],
        }
        result = check_crypto_assumptions_link_to_proofs(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("missing theoremReferences", result["message"])

    def test_link_to_proofs_fails_on_partial_coverage(self) -> None:
        certificate = {
            "cryptoAssumptions": [
                {
                    "name": "X",
                    "theoremReferences": [
                        "Module.theorem_a",
                        "Module.theorem_missing",
                    ],
                },
            ],
            "proofReferences": ["Module.theorem_a"],
        }
        result = check_crypto_assumptions_link_to_proofs(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Module.theorem_missing", result["message"])

    def test_link_to_proofs_fails_when_section_absent(self) -> None:
        result = check_crypto_assumptions_link_to_proofs({})
        self.assertEqual(result["status"], "failed")

    def test_under_oracle_assumption_theorems_covered_real(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        result = check_under_oracle_assumption_theorems_covered(certificate)
        self.assertEqual(result["status"], "passed", result)

    def test_under_oracle_assumption_theorems_uncovered(self) -> None:
        certificate = {
            "proofReferences": [
                "Module.foo_under_oracle_assumption",
                "Module.bar_under_oracle_assumption",
                "Module.unrelated_theorem",
            ],
            "cryptoAssumptions": [
                {"theoremReferences": ["Module.foo_under_oracle_assumption"]},
            ],
        }
        result = check_under_oracle_assumption_theorems_covered(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("bar_under_oracle_assumption", result["message"])
        self.assertNotIn("unrelated_theorem", result["message"])

    def test_under_oracle_assumption_passes_when_no_oracle_theorems(self) -> None:
        certificate = {
            "proofReferences": ["Module.plain_theorem"],
            "cryptoAssumptions": [],
        }
        result = check_under_oracle_assumption_theorems_covered(certificate)
        self.assertEqual(result["status"], "passed")

    def test_crypto_assumption_support_graph_real(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        result = check_crypto_assumption_support_graph(certificate)
        self.assertEqual(result["status"], "passed", result)

    def test_crypto_assumption_support_graph_view_real(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        graph = crypto_assumption_support_graph_view(certificate)
        self.assertEqual(
            [entry["assumption"] for entry in graph],
            [
                "VerifierDomainSeparation",
                "VerifierSignatureBinding",
                "VerifierKeySeparation",
            ],
        )
        self.assertEqual([len(entry["supports"]) for entry in graph], [2, 2, 2])
        rendered = format_crypto_assumption_graph_markdown(graph)
        self.assertIn("## Crypto Assumption Support Graph", rendered)
        self.assertIn("VerifierDomainSeparation", rendered)
        self.assertIn("validateAndExecute", rendered)

    def test_crypto_assumption_support_graph_fails_when_missing(self) -> None:
        certificate = {
            "cryptoAssumptions": [
                {"name": "X", "theoremReferences": ["Module.theorem_x"]},
            ],
            "proofReferences": ["Module.theorem_x"],
        }
        result = check_crypto_assumption_support_graph(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("no cryptoAssumptionGraph", result["message"])

    def test_crypto_assumption_support_graph_fails_on_dangling_edge(self) -> None:
        certificate = {
            "cryptoAssumptions": [
                {"name": "X", "theoremReferences": ["Module.theorem_x"]},
            ],
            "cryptoAssumptionGraph": [
                {
                    "assumption": "X",
                    "edge": "assumptionSupportsTheorem",
                    "flow": "validateIntegrated",
                    "layer": "integratedValidation",
                    "theoremReference": "Module.other",
                }
            ],
            "proofReferences": ["Module.theorem_x"],
        }
        result = check_crypto_assumption_support_graph(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Module.other", result["message"])


class FullBehaviorSummaryAuditTests(unittest.TestCase):
    def test_includes_execute_phase_real_artifact(self) -> None:
        full_summary = cached_artifact("full-behavior-summary-json")
        result = check_full_behavior_summary_includes_execute_phase(full_summary)
        self.assertEqual(result["status"], "passed", result)

    def test_includes_execute_phase_fails_when_missing(self) -> None:
        full = {"phases": [{"name": "wrapper", "guards": [], "finalWrites": []}]}
        result = check_full_behavior_summary_includes_execute_phase(full)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Expected exactly one", result["message"])

    def test_includes_execute_phase_fails_on_wrong_slot(self) -> None:
        full = {
            "phases": [
                {
                    "name": "execute",
                    "guards": [],
                    "finalWrites": [{"name": "lastOpHash", "slot": 99}],
                }
            ]
        }
        result = check_full_behavior_summary_includes_execute_phase(full)
        self.assertEqual(result["status"], "failed")
        self.assertIn("slot expected 4", result["message"])

    def test_extends_short_summary_real_artifacts(self) -> None:
        full = cached_artifact("full-behavior-summary-json")
        short = cached_artifact("behavior-summary-json")
        result = check_full_behavior_summary_extends_short_summary(full, short)
        self.assertEqual(result["status"], "passed", result)

    def test_extends_short_summary_fails_when_diverge(self) -> None:
        short = {"phases": [{"name": "wrapper", "guards": [], "finalWrites": []}]}
        full = {"phases": [{"name": "other", "guards": [], "finalWrites": []}]}
        result = check_full_behavior_summary_extends_short_summary(full, short)
        self.assertEqual(result["status"], "failed")

    def test_extends_short_summary_fails_when_full_too_short(self) -> None:
        short = {"phases": [{"name": "wrapper"}, {"name": "wallet"}]}
        full = {"phases": [{"name": "wrapper"}]}
        result = check_full_behavior_summary_extends_short_summary(full, short)
        self.assertEqual(result["status"], "failed")


class VerifierModelCalibrationTests(unittest.TestCase):
    def test_verifier_model_calibrations_real(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        result = check_verifier_model_calibrations(certificate)
        self.assertEqual(result["status"], "passed", result)

    def test_verifier_model_calibrations_view_real(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        calibrations = verifier_model_calibrations_view(certificate)
        self.assertEqual(len(calibrations), 4)
        names = [entry["name"] for entry in calibrations]
        self.assertIn("AllFieldsEqualToyVerifier", names)
        self.assertIn("KeyDomainBindingToyVerifier", names)
        self.assertIn("DerivedSignatureModel", names)
        self.assertIn("PQSchemeParameters", names)
        # Verifier-shape calibrations have varying dischargedAssumptions lists;
        # the toy/parametric ones still discharge the three oracle assumptions.
        toy_calibrations = [
            entry for entry in calibrations
            if entry["name"] != "PQSchemeParameters"
        ]
        for entry in toy_calibrations:
            self.assertEqual(
                entry["dischargedAssumptions"],
                [
                    "VerifierDomainSeparation",
                    "VerifierSignatureBinding",
                    "VerifierKeySeparation",
                ],
            )
        rendered = format_verifier_model_calibrations_markdown(calibrations)
        self.assertIn("## Verifier Model Calibrations", rendered)
        self.assertIn("AllFieldsEqualToyVerifier", rendered)
        self.assertIn("KeyDomainBindingToyVerifier", rendered)
        self.assertIn("DerivedSignatureModel", rendered)
        self.assertIn("non-cryptographic", rendered)

    def test_verifier_model_calibrations_fail_when_missing(self) -> None:
        result = check_verifier_model_calibrations({})
        self.assertEqual(result["status"], "failed")
        self.assertIn("no verifierModelCalibrations", result["message"])

    def test_verifier_model_calibrations_fail_on_dangling_proof(self) -> None:
        certificate = {
            "cryptoAssumptions": [{"name": "VerifierDomainSeparation"}],
            "proofReferences": [],
            "verifierModelCalibrations": [
                {
                    "name": "Toy",
                    "kind": "toyVerifierCalibration",
                    "nonClaim": "No crypto claim.",
                    "dischargedAssumptions": ["VerifierDomainSeparation"],
                    "proofReferences": ["Module.missing"],
                }
            ],
        }
        result = check_verifier_model_calibrations(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Module.missing", result["message"])


class IntegrationVariantsAuditTests(unittest.TestCase):
    def test_integration_variants_pass_on_real_certificate(self) -> None:
        certificate = cached_artifact("source-certificate-json")
        result = check_integration_variants(certificate)
        self.assertEqual(result["status"], "passed", result)

    def test_integration_variants_fail_without_section(self) -> None:
        result = check_integration_variants({})
        self.assertEqual(result["status"], "failed")
        self.assertIn("no integrationVariants", result["message"])

    def test_integration_variants_fail_on_dangling_equivalence(self) -> None:
        certificate = {
            "integrationVariants": [
                {
                    "name": "canon",
                    "flow": "flowA",
                    "lean": "Module.canon",
                    "equivalenceProof": "",
                    "canonical": 1,
                },
                {
                    "name": "variant",
                    "flow": "flowA",
                    "lean": "Module.variant",
                    "equivalenceProof": "Module.missing_proof",
                    "canonical": 0,
                },
            ],
            "proofReferences": ["Module.canon"],
        }
        result = check_integration_variants(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Module.missing_proof", result["message"])

    def test_integration_variants_fail_on_zero_canonical(self) -> None:
        certificate = {
            "integrationVariants": [
                {
                    "name": "v1",
                    "flow": "flow",
                    "lean": "X",
                    "equivalenceProof": "X.eq",
                    "canonical": 0,
                },
            ],
            "proofReferences": ["X.eq"],
        }
        result = check_integration_variants(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("expected exactly one canonical variant", result["message"])

    def test_integration_variants_fail_on_two_canonicals(self) -> None:
        certificate = {
            "integrationVariants": [
                {"name": "a", "flow": "f", "lean": "A", "equivalenceProof": "", "canonical": 1},
                {"name": "b", "flow": "f", "lean": "B", "equivalenceProof": "", "canonical": 1},
            ],
            "proofReferences": [],
        }
        result = check_integration_variants(certificate)
        self.assertEqual(result["status"], "failed")
        self.assertIn("expected exactly one canonical variant", result["message"])


class ProtocolBoundaryAuditTests(unittest.TestCase):
    def test_real_certificate_passes(self) -> None:
        cert = cached_artifact("source-certificate-json")
        self.assertEqual(
            check_protocol_boundary_assumptions(cert)["status"], "passed"
        )

    def test_missing_section_fails(self) -> None:
        result = check_protocol_boundary_assumptions({})
        self.assertEqual(result["status"], "failed")
        self.assertIn("no protocolBoundaryAssumptions", result["message"])

    def test_invalid_status_fails(self) -> None:
        cert = {
            "protocolBoundaryAssumptions": [
                {
                    "name": "X",
                    "leanReference": "M.X",
                    "statement": "...",
                    "status": "totally-fine",
                    "theoremReferences": ["M.X_trivial"],
                }
            ],
            "proofReferences": ["M.X_trivial"],
        }
        result = check_protocol_boundary_assumptions(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("status", result["message"])

    def test_dangling_theorem_fails(self) -> None:
        cert = {
            "protocolBoundaryAssumptions": [
                {
                    "name": "X",
                    "leanReference": "M.X",
                    "statement": "...",
                    "status": "non-claim",
                    "theoremReferences": ["M.X_missing"],
                }
            ],
            "proofReferences": ["M.Y"],
        }
        result = check_protocol_boundary_assumptions(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("M.X_missing", result["message"])


class FalconSimpleWalletShapeAuditTests(unittest.TestCase):
    def test_real_certificate_passes(self) -> None:
        cert = cached_artifact("source-certificate-json")
        self.assertEqual(
            check_falcon_simple_wallet_shape(cert)["status"], "passed"
        )

    def test_missing_section_fails(self) -> None:
        result = check_falcon_simple_wallet_shape({})
        self.assertEqual(result["status"], "failed")
        self.assertIn("no falconSimpleWalletShape", result["message"])

    def test_dangling_composite_theorem_fails(self) -> None:
        cert = {
            "falconSimpleWalletShape": {
                "walletName": "X",
                "walletFunction": "f",
                "scheme": "S",
                "storedSlots": [{"name": "s", "slot": 0, "type": "uint256"}],
                "crossStorageAssumption": {
                    "name": "X", "leanReference": "M.X", "statement": "..."
                },
                "wrapperCalibrationAssumption": {
                    "name": "Y", "leanReference": "M.Y", "statement": "..."
                },
                "compositeSafetyTheorem": "M.missing_composite",
                "schemeDiscriminationTheorem": "M.scheme_discr",
            },
            "proofReferences": ["M.scheme_discr"],
        }
        result = check_falcon_simple_wallet_shape(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("M.missing_composite", result["message"])

    def test_missing_deployment_wrapper_preservation_fails(self) -> None:
        cert = copied_json(cached_artifact("source-certificate-json"))
        del cert["falconSimpleWalletShape"]["wrapperAddressPreservation"][
            "deploymentAssumptionTheorem"
        ]
        result = check_falcon_simple_wallet_shape(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("deploymentAssumptionTheorem", result["message"])

    def test_missing_deployment_invariant_field_fails(self) -> None:
        cert = copied_json(cached_artifact("source-certificate-json"))
        cert["falconSimpleWalletShape"]["deploymentInvariant"]["fields"] = [
            "WalletStoresWrapperAddress"
        ]
        result = check_falcon_simple_wallet_shape(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("WrapperCalibratedForScheme", result["message"])

    def test_missing_integrated_v1_refinement_fails(self) -> None:
        cert = copied_json(cached_artifact("source-certificate-json"))
        del cert["falconSimpleWalletShape"]["integratedV1"][
            "refinementTheorem"
        ]
        result = check_falcon_simple_wallet_shape(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("refinementTheorem", result["message"])

    def test_missing_v1_composite_safety_fails(self) -> None:
        cert = copied_json(cached_artifact("source-certificate-json"))
        del cert["falconSimpleWalletShape"]["v1CompositeSafety"]["theorem"]
        result = check_falcon_simple_wallet_shape(cert)
        self.assertEqual(result["status"], "failed")
        self.assertIn("v1CompositeSafety", result["message"])


class DemoTests(unittest.TestCase):
    def test_print_trust_boundaries_emits_all_sections(self) -> None:
        certificate = {
            "assumptions": ["assumption A"],
            "cryptoAssumptions": [
                {
                    "name": "VerifierDomainSeparation",
                    "leanReference": "SoLean.Module.Assumption",
                    "statement": "Assumption statement.",
                }
            ],
            "cryptoAssumptionGraph": [
                {
                    "assumption": "VerifierDomainSeparation",
                    "flow": "validateIntegrated",
                    "layer": "integratedValidation",
                    "theoremReference": "SoLean.Module.theorem",
                }
            ],
            "verifierModelCalibrations": [
                {
                    "name": "AllFieldsEqualToyVerifier",
                    "lean": "SoLean.Module.toy",
                    "nonClaim": "No crypto claim.",
                    "dischargedAssumptions": ["VerifierDomainSeparation"],
                    "proofReferences": ["SoLean.Module.theorem"],
                }
            ],
            "unsupported": ["thing X"],
            "proofReferences": ["SoLean.Module.theorem"],
        }
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            print_trust_boundaries(certificate)
        text = buffer.getvalue()
        self.assertIn("Trust Boundaries", text)
        self.assertIn("assumption A", text)
        self.assertIn("Crypto assumption support graph", text)
        self.assertIn("VerifierDomainSeparation", text)
        self.assertIn("Verifier model calibrations", text)
        self.assertIn("AllFieldsEqualToyVerifier", text)
        self.assertIn("thing X", text)
        self.assertIn("SoLean.Module.theorem", text)

    def test_print_trust_boundaries_handles_missing_sections(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            print_trust_boundaries({})
        text = buffer.getvalue()
        self.assertIn("Trust Boundaries", text)
        self.assertNotIn("Assumptions", text)
        self.assertNotIn("Out of scope", text)
        self.assertNotIn("Lean theorems", text)

    def test_demo_main_runs_end_to_end(self) -> None:
        buffer = io.StringIO()
        with redirect_stdout(buffer):
            code = demo_aapq_source_main(["--skip-tests"])
        text = buffer.getvalue()
        self.assertEqual(code, 0)
        self.assertIn("# SoLean AA/PQ Source-Shape Demo", text)
        self.assertIn("Lean build: PASS", text)
        self.assertIn("AA/PQ source-shape report: PASS", text)
        self.assertIn("Trust Boundaries", text)
        self.assertIn("Crypto assumption support graph", text)
        self.assertIn("Verifier model calibrations", text)


class GoldenReportTests(unittest.TestCase):
    def test_matches_golden(self) -> None:
        source = cached_artifact("source-json")
        certificate = cached_artifact("source-certificate-json")
        summary = cached_artifact("behavior-summary-json")
        full_summary = cached_artifact("full-behavior-summary-json")
        solidity = SOLIDITY_PATH.read_text()

        report = run_audit(source, certificate, summary, full_summary, solidity)
        observed = stable_json(report)
        expected = GOLDEN_PATH.read_text()
        self.assertEqual(observed, expected)

    def test_golden_records_artifact_hashes(self) -> None:
        source = cached_artifact("source-json")
        expected = artifact_hash(source)
        golden = json.loads(GOLDEN_PATH.read_text())
        self.assertEqual(golden["artifacts"]["sourceHash"], expected)


if __name__ == "__main__":
    unittest.main()
