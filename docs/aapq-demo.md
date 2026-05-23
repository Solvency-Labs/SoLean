# AA/PQ Source-Shape Research Demo

This is the current presentation-grade demo for the AA/PQ side of SoLean. It
shows the Lean-owned source artifact, source certificate, structured behavior
summary, and the Python cross-check that ties them to the Solidity sketch and
to each other — without claiming Yul or solc equivalence, and without claiming
PQ cryptographic security.

## One-Command Demo

Run:

```bash
python3 scripts/demo_aapq_source.py
```

The demo runs:

- `lake build`
- the AA/PQ-focused Python test module (`tests.test_aapq_source`)
- Lean artifact export smoke checks for `source-json`,
  `source-certificate-json`, and `behavior-summary-json`
- the AA/PQ source-shape report in Markdown mode
  (`scripts/check_aapq_source.py --format markdown`)
- a Trust Boundaries section sourced from the Lean-owned source certificate,
  listing assumptions, out-of-scope items, and the Lean theorems that back
  this boundary

Use `--skip-tests` to skip the nested unittest step during fast iteration.

No solc dependency: the AA/PQ source-shape boundary does not consume real
solc output.

## Architecture

```text
examples/AAPQIntegration.sol  -> restricted Solidity shape parser
SoLean.Examples.AAPQSource    -> Lean source/certificate/behavior artifacts
SoLean.Examples.AAPQSource
  .BehaviorReflection         -> structural reflection theorems (rfl)
scripts/check_aapq_source.py  -> deterministic cross-check report
                                 (incl. cryptoAssumptions <-> proofs audit)
scripts/demo_aapq_source.py   -> one-command runner + trust boundary summary
```

## Current Claims

The demo supports this claim:

```text
For the AA/PQ integrated validation flow, Lean proves contract-level safety of
the wallet, wrapper, and composed integration under an abstract verifier
oracle, including three integrated-flow safety theorems:

  - successful integrated validation forces abstract verifier acceptance of
    the exact (publicKey, opHash, domain, signature) tuple;
  - the same UserOp cannot validate twice on the post-validation storage
    because the nonce advanced;
  - under named, non-cryptographic crypto assumptions on Env.verifier
    (VerifierDomainSeparation, VerifierSignatureBinding,
    VerifierKeySeparation, surfaced in the certificate's cryptoAssumptions
    field), two successful validations sharing all-but-one of
    (publicKey, opHash, domain, signature) must share the remaining field.

The Solidity-shaped source description (AAPQSource) is pinned to those proved
programs by instantiation theorems, and the structured behavior summary is
pinned to the proved programs by a Lean reflection that reconstructs each
phase by rfl. The Python audit cross-checks the Lean-owned source,
certificate, and behavior summary against each other and against the Solidity
sketch, including the directed `cryptoAssumptionGraph` from each named
verifier-oracle assumption to each theorem it supports.
```

The Markdown report and demo Trust Boundaries section render that graph grouped
by assumption, with flow/layer labels, so reviewers can see which assumptions
support integrated validation theorems versus full `validateAndExecute`
theorems.

The certificate also includes `verifierModelCalibrations`. Three calibrations
are listed today: `AllFieldsEqualToyVerifier` (4-way collapse),
`KeyDomainBindingToyVerifier` (paired sig↔key, msg↔domain), and
`DerivedSignatureModel` (parametric: `signature = derive(key, message, domain)`
under explicit injectivity hypotheses on `derive`). All three are
deliberately non-cryptographic; Lean proves each satisfies the three named
verifier-oracle assumptions. The first two carry kind
`toyVerifierCalibration`; the parametric one carries kind
`parametricVerifierCalibration`.
It is included to demonstrate assumption discharge, not to claim PQ security.

Lean theorems backing the boundary (exact names also surface in the demo's
Trust Boundaries section):

- `SoLean.Examples.AAWallet.validate_success_properties`
- `SoLean.Examples.PQVerifierWrapper.verify_success_properties`
- `SoLean.Examples.AAPQIntegration.callVerifierWrapper_eq_verifyProgram`
- `SoLean.Examples.AAPQIntegration.callVerifierWrapper_success_properties`
- `SoLean.Examples.AAPQIntegration.validateIntegrated_success_properties`
- `SoLean.Examples.AAPQIntegration.validateIntegratedViaCall_eq_validateIntegrated`
- `SoLean.Examples.AAPQIntegration.validateIntegratedViaCall_success_properties`
- `SoLean.Examples.AAPQSource.walletSource_instantiates_to_existing_model`
- `SoLean.Examples.AAPQSource.wrapperSource_instantiates_to_existing_model`
- `SoLean.Examples.AAPQSource.integratedSource_instantiates_to_existing_model`
- `SoLean.Examples.AAPQSource.BehaviorReflection.wrapperPhase_reflects_verifyProgram`
- `SoLean.Examples.AAPQSource.BehaviorReflection.keyMatchPhase_reflects_keyMatchesWalletProgram`
- `SoLean.Examples.AAPQSource.BehaviorReflection.walletPhase_reflects_validateProgram`
- `SoLean.Examples.AAPQSource.BehaviorReflection.integratedBehaviorSummary_reflects_integratedProgram`
- `SoLean.Examples.AAPQSource.BehaviorReflection.reflectedValidateIntegrated_eq_validateIntegrated`
- `SoLean.Examples.AAPQIntegration.noBypass_implies_verifier_accepted`
- `SoLean.Examples.AAPQIntegration.replay_rejected_after_success`
- `SoLean.Examples.AAPQIntegration.domain_separation_under_oracle_assumption`
- `SoLean.Examples.AAPQIntegration.signature_non_malleability_under_oracle_assumption`
- `SoLean.Examples.AAPQIntegration.key_separation_under_oracle_assumption`
- `SoLean.Examples.AAPQSource.integratedCryptoAssumptions_cover_all_oracle_theorems`
- `SoLean.Examples.AAPQSource.integratedCryptoAssumptionSupportGraph_covers_assumption_references`
- `SoLean.Examples.AAWallet.fullFlow_success_implies_validate_success`
- `SoLean.Examples.AAWallet.fullFlow_success_records_opHash`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_success_implies_validateIntegrated_success`
- `SoLean.Examples.AAPQIntegration.validateAndExecuteViaCall_eq_validateAndExecute`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_success_records_opHash`
- `SoLean.Examples.AAPQSource.BehaviorReflection.executePhase_reflects_executeUserOp`
- `SoLean.Examples.AAPQSource.BehaviorReflection.integratedFullBehaviorSummary_reflects_validateAndExecuteFlow`
- `SoLean.Examples.AAPQSource.BehaviorReflection.reflectedValidateAndExecute_eq_validateAndExecute`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_implies_verifier_accepted`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_records_authorized_opHash`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_success_structure`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_replay_rejected`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_domain_separation_under_oracle_assumption`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_signature_non_malleability_under_oracle_assumption`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_key_separation_under_oracle_assumption`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_reverts_when_validateIntegrated_reverts`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_reverts_iff_validateIntegrated_reverts`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wrapper_storage`
- `SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wallet_configuration`
- `SoLean.Examples.AAPQEvmCall.parse_build_verifier_calldata`
- `SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_wrong_selector`
- `SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_short_calldata`
- `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_success_matches_validateIntegrated`
- `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success`
- `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle`
- `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_preserves_wallet_configuration`
- `SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_eq_under_enough_gas`
- `SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_outOfGas_when_insufficient`
- `SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_is_success_iff_validateIntegrated_is_success`
- `SoLean.Examples.ToyVerifier.allFieldsEqualEnv_domain_separation`
- `SoLean.Examples.ToyVerifier.allFieldsEqualEnv_signature_binding`
- `SoLean.Examples.ToyVerifier.allFieldsEqualEnv_key_separation`
- `SoLean.Examples.ToyVerifier.allFieldsEqualEnv_satisfies_oracle_assumptions`
- `SoLean.Examples.ToyVerifier.keyDomainBindingEnv_domain_separation`
- `SoLean.Examples.ToyVerifier.keyDomainBindingEnv_signature_binding`
- `SoLean.Examples.ToyVerifier.keyDomainBindingEnv_key_separation`
- `SoLean.Examples.ToyVerifier.keyDomainBindingEnv_satisfies_oracle_assumptions`
- `SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_domain_separation`
- `SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_signature_binding`
- `SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_key_separation`
- `SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_satisfies_oracle_assumptions`

## Non-Claims

The demo does not claim:

- verified Solidity parsing
- verified PQ cryptographic security
- full EVM CALL semantics (no per-opcode gas schedule, no reentrancy,
  no code resolution, no value transfer) — a first calldata/returndata
  CALL boundary exists, conditional on `WrapperOracleConsistent`, with
  a single-cost gas-aware variant conditional on `EnoughGas`
- full ABI encoding (the calldata model is one word per argument plus a
  4-byte function selector modeled as a full word; no per-byte padding,
  no dynamic types)
- memory, events, or full revert-data propagation
- semantic equivalence with any real Yul or `solc` output
- production readiness for AA wallets

The structured behavior summary is reflected to the proved programs by `rfl`
both at the *syntactic* program-equality level (each phase reconstructs the
proved program) and at the *execution* level
(`reflectedValidateIntegrated_eq_validateIntegrated` shows that composing the
reflected phases produces the same `IntegratedResult` as
`AAPQIntegration.validateIntegrated` under any environment + storage).

## Useful Commands

Run the source-shape report directly:

```bash
python3 scripts/check_aapq_source.py --format markdown
```

Export individual Lean-owned artifacts:

```bash
lake env lean --run SoLean/AAPQArtifactsMain.lean source-json
lake env lean --run SoLean/AAPQArtifactsMain.lean source-certificate-json
lake env lean --run SoLean/AAPQArtifactsMain.lean behavior-summary-json
lake env lean --run SoLean/AAPQArtifactsMain.lean full-behavior-summary-json
```

`full-behavior-summary-json` covers `validateAndExecute` (the four-phase
flow: wrapper + key-match + wallet + execute). `behavior-summary-json` covers
the three-phase `validateIntegrated` (no execute).
