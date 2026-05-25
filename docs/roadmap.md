# SoLean Roadmap

This is the living roadmap for SoLean. Update it whenever the project crosses a
meaningful boundary, especially when a manual or trusted step becomes checked by
Lean.

## Mental Model

SoLean's north star is traceable trust reduction, now aimed at a concrete
Ethereum-facing target: **PQ account abstraction**. The framing follows
Antonio Sanso's *"The road to Post-Quantum Ethereum transactions is paved
with Account Abstraction"*: the deployable route to PQ-authenticated
Ethereum transactions today is an AA smart wallet that authenticates
`UserOp`s with a PQ verifier wrapper, not native EVM cryptography.

```text
Build a boundary-aware Lean/Solidity verification pipeline for
account-abstraction smart wallets that accept execution only after
nonce/domain/key-commitment checks and successful post-quantum
verifier-wrapper validation, with cryptographic assumptions, EVM-call
assumptions, and remaining protocol-level ECDSA boundaries explicitly
identified.
```

The reference deployment shape is **FalconSimpleWallet**-style: no
`ecrecover` in the wallet path, verification against an explicit stored
public key (or key commitment), signature acceptance through the verifier
wrapper. Falcon/ML-DSA cryptographic security stays an oracle assumption;
SoLean does not prove it.

The project is trying to connect four worlds:

```text
Solidity source
  -> SoLean source/model
  -> Lean proofs
  -> restricted Yul output
  -> comparison with solc Yul
```

The intended first serious application is:

```text
AA wallet validation logic
  -> PQ verifier-wrapper contract
  -> integration proof that execution requires modeled PQ authentication,
     nonce validity, and domain binding
```

The important question at every step is:

```text
What is proved, and what is still trusted by hand?
```

Right now, the verified island is Counter inside Lean:

```text
Counter source function in Lean
  -> instantiate to existing SoLean Counter model
  -> compile with focused Lean compiler
  -> restricted Lean Yul Counter program
  -> prove successful executions preserve the Counter assertion
```

This is real progress, but it does not yet start from Solidity text or real
`solc` output.

See `docs/counter-bridge-v1.md` for the crisp Counter success condition,
`docs/counter-bridge-v2.md` for the first auditable bridge report,
`docs/counter-bridge-v4.md` for the line-auditable bridge boundary,
`docs/counter-bridge-v6.md` for the Lean-owned source certificate and trace
skeleton, and `docs/counter-bridge-v7.md` for the current Lean-owned
behavior-summary boundary.

See `docs/pq-aa-roadmap.md` for the strategic AA/PQ case-study roadmap.

## Current State

### Proved In Lean

- `UInt256` storage values are bounded by type.
- SoLean arithmetic uses checked add/sub for the current DSL.
- `Counter.inc(amount)` is safe under the SoLean semantics when execution
  succeeds.
- `SimpleVault` preserves `totalAssets >= totalShares` for successful modeled
  `deposit` and `withdraw` executions.
- `AAWallet.validateProgram(op)` proves that successful modeled validation
  implies the configured entry point, nonce, domain, and abstract verifier
  checks passed, and that the nonce advanced with checked arithmetic.
- `AAWallet.fullFlow = .seq validateProgram executeUserOp` plus
  `fullFlow_success_implies_validate_success` and
  `fullFlow_success_records_opHash`: modeled execution gating. The
  `executeUserOp` step writes `op.opHash` to a dedicated `lastOpHashSlot`,
  giving the gate theorems something observable. Any path that produces
  the execute write must have first satisfied every validation guard.
- `AAPQIntegration.validateAndExecute` lifts the gate to the integrated
  flow: validateIntegrated then executeUserOp on the post-validation
  wallet storage. The two gate theorems
  (`validateAndExecute_success_implies_validateIntegrated_success` and
  `validateAndExecute_success_records_opHash`) show that observing the
  integrated execute write requires satisfying every wrapper +
  key-match + wallet validation guard.
- `PQVerifierWrapper.verifyProgram(input)` proves that successful modeled
  wrapper validation implies the configured key-length, signature-length,
  domain, and abstract verifier checks passed, with storage unchanged.
- `AAPQIntegration.validateIntegrated(...)` proves that successful integrated
  validation connects the wrapper and wallet checks over the same modeled
  verifier tuple.
- `SoLean.Examples.AAPQSource.integratedCryptoAssumptions_cover_all_oracle_theorems`
  is a Lean-side coverage theorem: the `theoremReference`s in
  `integratedCryptoAssumptions` are exactly the references named by the
  enumerated `OracleAssumptionId`. Build-time drift detection that mirrors
  the Python audit at the proof layer.
- `SoLean.Examples.AAPQSource.integratedCryptoAssumptionSupportGraph_covers_assumption_references`
  is a Lean-side support-graph theorem: every named verifier-oracle assumption
  edge in the exported `cryptoAssumptionGraph` is exactly one
  assumption-to-theorem reference from `integratedCryptoAssumptions`, with
  explicit flow/layer labels for the audit boundary.
- `AAPQIntegration` carries five integrated-flow safety theorems:
  `noBypass_implies_verifier_accepted`, `replay_rejected_after_success`,
  `domain_separation_under_oracle_assumption`,
  `signature_non_malleability_under_oracle_assumption`, and
  `key_separation_under_oracle_assumption`. The last three are under
  named non-cryptographic crypto assumptions on `Env.verifier`
  (`VerifierDomainSeparation`, `VerifierSignatureBinding`,
  `VerifierKeySeparation`) and are surfaced in
  `aapqSourceCertificate.cryptoAssumptions` as structured entries
  carrying name, Lean reference, and informal statement.
- `SoLean.Examples.AAPQSource.integratedContract` defines a Solidity-shaped
  source description of the AA/PQ two-contract layout and proves that the
  wallet, wrapper, and integrated bodies instantiate to the existing proved
  programs.
- `SoLean.Source.Shape` provides shared `Param`, `StorageSlot`, `Contract`,
  and `IntegratedContract` vocabulary used by both Counter and AA/PQ source
  artifacts.
- `SoLean.Examples.AAPQSource.integratedBehaviorSummary` is the Lean-owned
  ordered behavior summary of the integrated AA/PQ flow: structured
  `Condition`/`ValueExpression` nodes over a small `Operand` DSL (param,
  slot, msgSender, const) for each guard per phase (wrapper, key-match,
  wallet), final writes per contract, and the Lean theorem reference that
  backs each phase.
- `SoLean.Examples.AAPQSource.BehaviorReflection` defines semantics
  (`operandToValueExpr`, `conditionToBoolExpr`, `valueToValueExpr`,
  `phaseToStmt`) for the structured DSL and proves that each phase of
  `integratedBehaviorSummary` reconstructs the corresponding proved program:
  the four `*_reflects_*` theorems. The structured summary is therefore a
  Lean-checked property of the proved programs.
- `reflectedValidateIntegrated_eq_validateIntegrated` extends that to
  execution-result equality: composing the reflected phases under any
  `Env` and `Storage` produces the same `IntegratedResult` as
  `AAPQIntegration.validateIntegrated`.
- `AAPQIntegration.callVerifierWrapper` makes the wallet-to-wrapper boundary
  explicit as a focused external-call shim. The shim is proved equivalent to
  the direct wrapper execution used by the integrated flow; this is not EVM
  `CALL` or `STATICCALL` semantics.
- A restricted Yul semantics exists in Lean for the Counter-shaped subset.
- A hand-written restricted Yul Counter program refines successful SoLean
  Counter executions.
- A focused Lean compiler emits that restricted Yul Counter program from a
  parameterized Counter source function.

### Implemented But Not Verified End-To-End

- Python emits deterministic Counter Yul-like text.
- Lean exports deterministic Counter source, source certificate,
  restricted-Yul shape, trace skeleton, and bridge manifest artifacts.
- Lean exports a deterministic AA/PQ integrated source artifact, source
  certificate, and behavior summary via `SoLean/AAPQArtifactsMain.lean`,
  naming the two-contract layout, integration flow, ordered phase guards,
  final wallet-nonce write, theorem references, and out-of-scope items. The
  source certificate carries the behavior summary as its
  `expectedBehaviorSummary` field.
- A hand-written Solidity sketch lives at `examples/AAPQIntegration.sol` as
  documentation/audit fixture only; it is not parsed or compared to Lean.
- `scripts/check_aapq_source.py` cross-checks the four Lean-owned AA/PQ
  artifacts against the Solidity sketch and against each other (certificate's
  `expectedBehaviorSummary` vs. the standalone behavior summary), walks
  the behavior summary's structured operands (both short and full) to
  verify each one references a declared parameter or a real storage slot
  in source-json, audits the bidirectional link between `cryptoAssumptions`
  and the `*_under_oracle_assumption` theorems in `proofReferences`, audits
  the directed `cryptoAssumptionGraph`, renders that graph in Markdown reports
  and demo output, checks `verifierModelCalibrations`, and verifies the
  full-behavior-summary contains an `execute` phase with the
  expected `lastOpHash` finalWrite and extends the standalone three-phase
  summary. The report is committed as `tests/golden/AAPQ.source.v5.json`
  (reportVersion 4).
- `scripts/demo_aapq_source.py` is a one-command research demo that runs
  `lake build`, the AA/PQ-focused Python tests, the three artifact smokes,
  the markdown source-shape report, and a Trust Boundaries summary sourced
  from the Lean-owned source certificate. See `docs/aapq-demo.md` for the
  current claims and non-claims.
- Python tests check the Counter Yul emitter against the Lean-exported
  `CounterYul.counterProgram` artifact and a text golden file.
- `check_counter_bridge.py` produces one deterministic Counter bridge report
  tying the trusted Solidity source projection, Python Yul emitter, and solc
  function-body summary back to Lean-owned artifacts.
- The Counter bridge report checks observed solc summary rules, source
  certificate, and solc trace skeleton against the Lean-owned bridge manifest.
- Python parses and normalizes a restricted Yul-like subset.
- Python performs symbolic state-transform checks for Counter-shaped restricted
  Yul programs, with bounded trace checks still available as an explicit legacy
  mode.
- Python recognizes a restricted Counter-shaped Solidity subset.
- Python emits deterministic Counter source-shape JSON that is tested against
  the Lean-exported `CounterCompiler.counterFunction` artifact.
- Python emits a deterministic Counter source certificate that is tested against
  the Lean-owned bridge manifest.
- `solc_to_yul.py` enforces the pinned `solc 0.8.35` target when `solc` is
  installed.
- Local `solc 0.8.35 --ir` Counter output has been generated and classified as
  unsupported by the current restricted subset.
- `classify_yul.py` reports whether Yul text is in the supported subset or
  names the first unsupported wrapper/statement/expression/shape blocker.
- `classify_yul.py --inspect-solc` identifies candidate solc object blocks,
  selects the deployed/runtime object, and reports the first unsupported
  construct inside that trusted extraction boundary.

These are useful engineering tools, but they are not part of the trusted Lean
proof chain yet.

### Not Done

- Verified Solidity parsing.
- Verified translation from Solidity text to the Lean source function. The
  current bridge is an auditable test against a Lean-exported artifact, not a
  proof.
- Verified connection between the Python Yul emitter and the Lean compiler. The
  current connection is an auditable test against Lean-exported artifacts, not a
  proof.
- Parsing emitted Yul text back into Lean Yul data.
- Real `solc 0.8.35 --ir` Counter semantic comparison.
- Semantic equivalence against real Yul.
- Full EIP-4337/account-abstraction wallet semantics beyond the abstract
  `AAWallet` validation model.
- Full PQ verifier-wrapper contract semantics beyond the abstract
  `PQVerifierWrapper` model.
- External-call semantics between the wallet and verifier wrapper beyond the
  abstract `AAPQIntegration` composition model.
- PQ cryptographic security proofs. Future PQ work should verify contract
  logic under explicit verifier assumptions unless a separate verified crypto
  model is introduced.
- SimpleVault or ERC-20 compilation to restricted Yul.
- ABI, calldata, memory, calls, gas, events, reentrancy, or full EVM semantics.

## Strategic Case-Study Roadmap

This roadmap is hybrid, but it leans toward PQ account abstraction rather than
broad DeFi verification.

### Phase 0: Calibration

Counter remains the bridge calibration case. Optional ERC-20 work should be
focused and tactical: balances, total supply, allowance decrease, and
insufficient balance rejection. Do not turn this into a broad token framework.

### Phase 1: Abstract AA Wallet Validation

Model a scope-controlled account-abstraction wallet validation flow with an abstract
verifier predicate. Prove properties such as:

- invalid modeled signatures reject.
- valid modeled signatures with the correct nonce accept validation.
- replay with an old nonce rejects.
- the signature is bound to the operation hash and wallet/domain.
- execution is gated by successful validation.

Status: started with `SoLean.Examples.AAWallet`, a hand-written Lean model that
checks entry point, nonce, domain, abstract verifier acceptance, and checked
nonce increment.

### Phase 2: PQ Verifier Wrapper

Model the Solidity wrapper around a PQ verifier under explicit crypto
assumptions. Prove that inputs are bound correctly, length/domain checks happen
before verifier use, verifier return values are interpreted safely, and there
is no bypass path that accepts without verifier success.

Status: started with `SoLean.Examples.PQVerifierWrapper`, a hand-written Lean
model that checks public-key length, signature length, domain, and abstract
verifier acceptance.

### Phase 3: AA + PQ Integration

Prove that the wallet accepts only operations authenticated by the intended PQ
verifier wrapper, with nonce and domain separation modeled explicitly.

Status: started with `SoLean.Examples.AAPQIntegration`, a hand-written Lean
composition of the wallet and wrapper models over a shared verifier tuple.

### Phase 4: Real Solidity And solc Boundary

Apply the Counter bridge discipline to the first useful AA/PQ contract:
source certificate, Lean model, proof, restricted Yul, pinned-solc inspection,
and explicit trusted boundaries.

## Roadmap By Boundary

### 1. Keep Counter As The Calibration Case

Goal: make one calibrated path genuinely understandable and hard to fool.

Done:

- Python emitter output is checked against `tests/golden/Counter.solean.yul`.
- Python `counter_object()` and emitted Yul are checked against a Lean-exported
  artifact derived from `CounterYul.counterProgram`.
- `Counter Bridge v1` is defined as an auditable milestone with explicit
  proof/test/classification/trust boundaries.

Next tasks:

- Reduce duplicate Counter Yul definitions between Lean and Python further by
  generating Python output from the Lean-owned artifact or a shared source.
- Keep documenting every trusted/manual step.

Definition of done:

- The repository can explain exactly why the Counter Yul emitted by tooling is
  the same program as the one proved in Lean, with less hand-maintained
  duplication than the current Python-side Counter AST copy.

### 2. Connect Solidity To The Lean Source Shape

Goal: stop treating the Solidity input as only a human reference.

Done:

- The Counter Solidity parser can emit deterministic source-shape JSON.
- Tests check that this JSON matches the Lean-exported
  `CounterCompiler.counterFunction` artifact.
- Unsupported Solidity still fails loudly.

Next tasks:

- Reduce duplication by deriving more of the Python parser projection from a
  shared schema, while keeping unsupported Solidity rejection explicit.

Definition of done:

- For Counter, the path from `examples/Counter.sol` to the Lean source function
  has less hand-maintained duplication than the current Python source-shape
  projection.

### 3. Bring In Real `solc 0.8.35` Output

Goal: compare against the real compiler without pretending the whole solc IR is
supported.

Done:

- Install/select `solc 0.8.35` locally with `solc-select`.
- Generate `build/Counter.solc.yul` locally without committing it.
- Reject unsupported solc output by default.
- Record the first blocker: solc's `IR:` preamble/wrapper is outside the
  current restricted parser.
- Inspect solc-style wrapper text, select the deployed object, and report the
  first unsupported construct inside it. For current Counter IR this is memory
  setup such as `mstore(64, memoryguard(128))`.
- Inspect the generated `fun_inc_*` function body inside the deployed object
  and report the first unsupported function-body construct. For current Counter
  IR this initially exposed the hexadecimal literal `0x00`.
- Parse hexadecimal integer literals in the restricted Python Yul subset. After
  this, the first current `fun_inc_*` blocker is the helper call
  `cleanup_t_uint256`.
- Summarize explicitly trusted transparent value helpers in solc function-body
  inspection, initially bundled under `transparentValueHelper`. After this, the
  first current `fun_inc_*` blocker is `require_helper(expr_11)`.
- Summarize `require_helper(condition)` as a revert guard for classification.
  After this, the first current `fun_inc_*` blocker is
  `read_from_storage_split_offset_0_t_uint256`.
- Add a Counter-specific solc function summary mode that normalizes the real
  `fun_inc_*` body into the canonical restricted Counter Yul shape. It handles
  the current storage read helper, checked-add helper, storage update helper,
  and assert helper as trusted inspection patterns.
- Test that the normalized solc Counter function summary matches the
  Lean-exported `CounterYul.counterProgram` artifact.
- Emit a stable `trustedRules` list for the Counter-specific solc summary and
  surface it in the Counter bridge report.
- Export a Lean-owned bridge manifest with the expected trusted-rule list,
  proof references, and limitations.
- Check the Python-observed `trustedRules` list against that Lean-owned
  manifest in the Counter bridge report.
- Add a Lean-owned `bridgeRuleProofs` array to the manifest that pairs each
  trusted rule with the Lean theorem (if any) that backs its semantic
  translation.
- Model the first Counter bridge adapter rule semantically in Lean:
  `SoLean.Bridge.RequireHelper` defines a focused step semantics for
  `require_helper(cond)` and proves `target_refines_source`, which shows the
  emitted `if iszero(cond) { revert(0, 0) }` shape has the same step result as
  the modeled helper under the restricted Yul semantics. This is the first
  rule whose translation is Lean-backed rather than only trusted Python pattern
  recognition.
- Model the second Counter bridge adapter rule semantically in Lean:
  `SoLean.Bridge.AssertHelper` defines a focused step semantics for
  `assert_helper(cond)` and proves the current Counter-specific rewrite
  `assert_helper(iszero(bad)) ~> if bad { revert(0, 0) }`.
- Model the checked-add Counter bridge adapter rule semantically in Lean:
  `SoLean.Bridge.CheckedAdd` defines a focused model of
  `checked_add_t_uint256(old_x, amount)` and proves the current
  Counter-specific rewrite
  `let new_x := add(old_x, amount); if lt(new_x, old_x) { revert(0, 0) }`.
- Model the slot-0 storage bridge adapter rules semantically in Lean:
  `SoLean.Bridge.StorageRead` and `SoLean.Bridge.StorageWrite` prove the
  current Counter storage-helper rewrites to `sload(0)` and `sstore(0, value)`.
- Split the bundled `transparentValueHelper` rule into concrete observed helper
  rules and add Lean identity proofs for the current Counter helper rewrites.
- Add a deterministic solc summary trace that maps normalized `fun_inc_*` lines
  to bridge rules, restricted-Yul effects, and Lean proof references when
  available.
- Stabilize the Counter bridge JSON report as a checked golden artifact,
  initially at `reportVersion: 4`.
- Replay the solc summary trace effects into restricted Yul, compare that
  replayed program with the Lean-exported Counter Yul artifact, and stabilize
  the resulting `reportVersion: 5` report against
  `tests/golden/Counter.bridge.v5.json`.
- Export a Lean-owned Counter source certificate and expected solc trace
  skeleton, then check both in the `reportVersion: 6` bridge certificate
  against `tests/golden/Counter.bridge.v6.json`.
- Export a Lean-owned restricted behavior summary for Counter Yul (parameter,
  ordered revert guards, final slot-0 write), check Python's symbolic
  state-transform summary against it, and stabilize the resulting
  `reportVersion: 7` report against `tests/golden/Counter.bridge.v7.json`.
- Keep `hexLiteralAsNat` as explicit parser-level trust and cover the specific
  hex-literal parser behavior with focused tests.
- Add Markdown bridge-report output and a one-command Counter demo runner.
- Add a rendering path from the Lean-exported Counter Yul artifact, so the demo
  can display restricted Yul from Lean-owned data rather than only from the
  Python placeholder AST.

Next tasks:

- If continuing the Counter bridge, summarize the solc trace replay output
  against the existing Lean-owned behavior summary.
- Decide how much of the remaining Counter-only solc recognizer should become
  checked by independent table-driven fixtures before adding broader contract
  examples.

Definition of done:

- The repo can classify the actual Counter `fun_inc_*` body through the first
  helper-call/storage operation blocker, without claiming full equivalence.
- The repo can summarize the actual Counter `fun_inc_*` body into the same
  canonical restricted Counter Yul shape exported from Lean, without claiming
  full equivalence.
- The repo can produce one deterministic Counter bridge report that names the
  trusted solc summary rules and fails if source, emitted Yul, or solc summary
  artifacts drift away from Lean-owned artifacts.
- The expected trusted-rule list is owned by a Lean-exported bridge manifest
  rather than only by Python tests/docs.
- All current Counter semantic adapter rules except `hexLiteralAsNat` have
  Lean-backed semantic translation theorems. `hexLiteralAsNat` remains
  parser-level trust.
- The repo can run a single Counter demo command that reports proved, tested,
  trusted, and skipped-real-solc boundaries.
- The solc function summary is line-auditable: each trace entry names the solc
  source line, bridge rule, restricted-Yul effect, and Lean proof reference when
  one exists.
- The bridge report is a checked audit artifact, with a committed golden
  fixture generated from test fixtures rather than local `build/` outputs.
- The solc summary trace is replayable: the restricted-Yul effects shown in the
  trace reconstruct the same Counter Yul artifact that the bridge compares
  against Lean.
- The accepted Solidity source certificate and solc trace skeleton are
  Lean-owned artifacts checked by the bridge report.

### 4. Replace Bounded Trace Checks With Restricted Semantics

Goal: move from finite smoke tests toward real restricted equivalence.

Done:

- The default checker now compares a restricted symbolic state-transform summary for
  supported restricted Yul: parameters, ordered revert conditions, and final
  storage writes.
- The old finite Counter trace checker remains available as
  `--bounded-traces`.

Next tasks:

- Add targeted simplification/normalization for equivalent symbolic expressions
  only when needed by Counter.
- Mirror the symbolic summary in Lean or export Lean-side summaries if this
  becomes part of the trusted bridge.

Definition of done:

- The checker can explain equivalence for the supported subset in terms of
  storage behavior, not just text, AST equality, or finite traces.

### 5. Generalize Toward AA/PQ Only After Counter Is Solid

Goal: avoid building a broad framework before the first bridge and first AA/PQ
model are trustworthy.

Next tasks:

- Extract reusable Lean lemmas from Counter compiler proofs.
- Add a focused ERC-20-style calibration only if it directly helps model mappings,
  balances, allowances, or nonces for the AA/PQ path.
- Define the focused source/model forms needed for AA wallet validation:
  operation hash, nonce, domain, abstract verifier result, and execution gate.
- Defer SimpleVault restricted Yul until the AA/PQ direction has a crisp first
  model.

Definition of done:

- The first AA wallet validation model reuses the Counter proof architecture
  rather than copying a large one-off proof.

## Current Highest-Value Next Step

The previous next steps ("move AA/PQ integration from pure Lean model to a
Solidity-shaped source model", "generalize the shared modeling vocabulary
across Counter and AA/PQ", "add a modeled external-call shim", and "promote
crypto assumptions into a directed support graph") have landed as v0s, and the
graph is now visible in the Markdown/demo trust-boundary surface:

- `SoLean.Examples.AAPQSource` defines the two-contract source shape and proves
  `walletSource_instantiates_to_existing_model`,
  `wrapperSource_instantiates_to_existing_model`, and
  `integratedSource_instantiates_to_existing_model`.
- `SoLean/AAPQArtifactsMain.lean` exports `source-json` and
  `source-certificate-json` artifacts with theorem references and explicit
  out-of-scope items.
- `examples/AAPQIntegration.sol` is a hand-written Solidity fixture matching
  the source shape; it is not parsed or compared to Lean.
- `SoLean.Source.Shape` now owns the shared Solidity-shaped source metadata
  vocabulary, and both Counter and AA/PQ artifacts use it.
- `AAPQIntegration.callVerifierWrapper` and the `ViaCall` variants make the
  wallet-wrapper boundary explicit while staying below real EVM call semantics.
- `integratedCryptoAssumptionSupportGraph_covers_assumption_references` and
  the Python audit make the oracle-assumption support boundary graph-shaped
  instead of a flat list of strings.
- The source-shape Markdown report and `scripts/demo_aapq_source.py` render the
  graph grouped by assumption and flow/layer.
- `SoLean.Examples.ToyVerifier.allFieldsEqualVerifier` and
  `SoLean.Examples.ToyVerifier.keyDomainBindingVerifier` are two concrete
  verifier-model calibrations with structurally different binding shapes
  (4-way collapse vs. paired sig↔key / msg↔domain). Both are intentionally
  non-cryptographic, but Lean proves each satisfies the three named
  verifier-oracle assumptions.
- `SoLean.Examples.ToyVerifier.DerivedSignatureModel` is a parametric
  calibration bundling an abstract `derive : UInt256 → UInt256 → UInt256
  → UInt256` with explicit injectivity-in-key and injectivity-in-domain
  hypotheses. The same three named oracle assumptions are proved for any
  such model. The certificate distinguishes concrete vs. parametric
  calibrations via the typed `kind` field (`toyVerifierCalibration` vs.
  `parametricVerifierCalibration`), and the Python audit's
  `CALIBRATION_KINDS` set is the single source of truth for accepted
  kinds.
- `validateAndExecute_reverts_iff_validateIntegrated_reverts` (and the
  forward `..._when_...` form) are the contrapositive companions to the
  existing success-side gate theorems. They state that the modeled execute
  side-effect happens exactly when the integrated validation accepts; revert
  failures propagate unchanged through the execute composition.
- `validateAndExecute_preserves_wrapper_storage` and
  `validateAndExecute_preserves_wallet_configuration` formalize
  storage-isolation: successful integrated flow leaves wrapper storage
  unchanged and only touches the wallet's nonce slot and `lastOpHashSlot`.
  Auditors can rely on this to know the integrated flow does not silently
  mutate `keyCommitmentSlot`, `domainSlot`, or `entryPointSlot`.
- `SoLean.EVM.Call` brings real EVM CALL semantics into scope for the first
  time. `Calldata`/`Returndata`/`CallResult` and an `EvmEnv` carrying a
  pluggable `evmCall` oracle let the wallet-to-wrapper boundary be modeled
  as an actual call (calldata in, distinguishable success/revert
  returndata out) rather than direct composition.
  `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_success_matches_validateIntegrated`
  proves the call-shaped flow agrees with the canonical direct flow on the
  success path, and
  `validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success`
  lifts that to a two-sided equivalence, under the named
  `WrapperOracleConsistent` assumption
  (surfaced in the certificate's `evmCallAssumptions` field). This is not
  full EVM CALL — no gas, no reentrancy, no code resolution, no value
  transfer — but it is the first non-claim from the original AA/PQ list
  that has been brought into scope.
- `validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle` and
  `validateIntegratedViaEvmCall_preserves_wallet_configuration` formalize
  structural no-reentrancy: the wrapper call's oracle takes only
  `wrapperStorage` (by `EvmEnv.evmCall`'s signature), so wallet storage
  cannot be observed or modified during the wrapper call, and
  `keyCommitmentSlot`/`domainSlot`/`entryPointSlot` are preserved end-to-end
  in the call-shaped flow. Fourth real-EVM non-claim partially in scope.
- `SoLean.Examples.AAPQEvmCall` now uses a selector-prefixed calldata
  layout. `verifySelector` is the modeled function ID;
  `parseVerifierCalldata` rejects wrong-selector and wrong-length
  inputs (`parseVerifierCalldata_rejects_wrong_selector`,
  `parseVerifierCalldata_rejects_short_calldata`). Third non-claim
  from the original AA/PQ list (ABI shape) partially brought into
  scope — wrong-function calldata is rejected by shape before any
  field is interpreted.
- `SoLean.Examples.AAPQEvmCallGas` adds a gas dimension on top of the
  EVM-call boundary. `EvmGasEnv` extends `EvmEnv` with `gasCost` and
  `gasBudget`, and `validateIntegratedViaEvmCallWithGas` returns
  `outOfGas` when the budget is below cost. Three theorems
  characterize the gas-aware variant: it reduces to the gas-free flow
  under `EnoughGas`, it returns `outOfGas` under `Not EnoughGas`, and
  its success-iff equivalence with the canonical flow lifts through
  the gas reduction. Not full EVM gas accounting — single per-call
  cost vs. budget — but it makes "did the caller forward enough gas?"
  a Lean-checkable question.

Explicit non-claim — *no concrete `DerivedSignatureModel` instance is
provided in `UInt256`*. By pigeon-hole, no total function `UInt256³ →
UInt256` can be injective in all three arguments (cardinality `2^768` vs
`2^256`), so the parametric model documents the shape a useful verifier
relation must have but cannot be inhabited by a concrete `UInt256`
derivation. A concrete witness would require either restricting to a
finite sub-domain or moving to a richer codomain (e.g., tuples).

The v2.1 safety theorem is now landed:

```text
FalconSimpleWallet v2.1 safety theorem — successful validateAndExecuteV1
yields the reviewer-facing composite safety bundle plus the expected wrapper
address check as a first-class successful-execution fact.
```

The next best qualitative task is FalconSimpleWallet v2.2 manifest hygiene:
factor the repeated certificate theorem-reference checks while keeping the
model and JSON shape stable.

### FalconSimpleWallet shape v0 (landed)

Reframed and consolidated the AA/PQ proofs around the Antonio-Sanso-style
PQ-AA reference deployment:

1. **AA-facing source-shape view** *(landed)* —
   `SoLean.Examples.FalconSimpleWallet.falconSimpleWalletDeployment`
   bundles the wallet contract (re-named "FalconSimpleWallet" /
   "validateUserOp"), wrapper contract, scheme parameters, and the
   wrapper's EVM address. Surfaced as the new
   `falconSimpleWalletShape` field in the source certificate.
2. **Wallet storage layout** *(landed)* — `AAWallet.wrapperAddressSlot`
   (slot 5) declared on the wallet side. The deployment view's
   wallet contract carries the new `wrapperAddress` storage entry, and
   `validateProgramV1` requires the operation's expected wrapper address to
   match that stored slot before running the v0 wallet validation.
3. **Verifier-wrapper call shape with calibration** *(landed)* —
   `WrapperCalibratedForScheme` is the named assumption tying the
   wrapper's `expectedPublicKeyLengthSlot` and
   `expectedSignatureLengthSlot` to a `SchemeParameters` instance
   (Falcon-512 by default).
4. **Composite safety theorem** *(landed)* —
   `falconSimpleWallet_composite_safety` produces a single
   `FalconSimpleWalletSafety` record from a successful
   `validateAndExecute`, bundling: (a) key match, (b) verifier
   accepted the exact tuple, (c) nonce advanced through checked
   arithmetic, (d) opHash recorded at `lastOpHashSlot`, (e) replay
   cannot succeed on the post-state.
5. **Deployment invariant bundle** *(landed)* —
   `FalconSimpleWalletDeploymentInvariant` bundles
   `WalletStoresWrapperAddress` and `WrapperCalibratedForScheme`, and
   `validateAndExecute_preserves_deploymentInvariant` proves successful
   `validateAndExecute` preserves that bundle.
6. **Loud non-claims** *(landed)* — new `falconSimpleWalletNonClaims`
   field in the certificate enumerates: real Falcon / PQ
   cryptographic security; Keccak-vs-SHAKE hashing choice; byte-level
   ABI parsing; full ERC-4337 EntryPoint / paymaster / aggregator;
   bundler ECDSA dependence; EIP-7702 ECDSA-key-still-valid risk;
   signature aggregation; full gas schedule.

Counter stays as a calibration case. ERC-20 stays optional. Do not
broaden into generic DeFi.

### Already-completed lanes (kept for reference)

Work is organized into named lanes. Lanes A, B, C below are
feature-complete; FalconSimpleWallet shape v2.0 is now landed through the
wallet-side wrapper-address check, preservation theorem, deployment invariant
bundle, and `validateAndExecuteV1` refinement path. v2.1 lifts the composite
safety theorem onto that v1 path, adding the stored-wrapper-address agreement
to the reviewer-facing safety bundle. The next useful step is manifest hygiene:
factor repeated certificate theorem-reference checks without widening the
model.

### Lane A — Deepen the EVM CALL boundary (in flight)

1. **M21 — Code resolution.** Add `wrapperCodeHash : UInt256` to `EvmEnv`
   and a `WrapperCodeBound` assumption: the oracle's behavior on
   `wrapperAddress` is consistent with the declared code hash. Surfaces as
   a new structured entry in `evmCallAssumptions`.
2. **M22 — Address-discrimination theorem.** Prove the call-shaped flow's
   outcome depends only on the oracle's behavior at `wrapperAddress`, not
   at any other address. Captures inter-contract isolation.
3. **M23 — Cross-contract reentrant callbacks.** Make the oracle
   interface richer (so a malicious oracle could *try* to call back) and
   add a named `NoCallback` assumption ruling it out. Lifts no-reentrancy
   from a structural fact to an explicit assumption that can be relaxed.
4. **M24 — EIP-150 63/64 gas forwarding.** Refine the gas model so the
   wallet only forwards `(63/64) * gasBudget` to the wrapper.
5. **M25 — Richer ABI calldata.** Lift `[selector, args]` into a
   structured `CalldataABI` type with head/tail and multi-selector
   dispatch.

### Lane B — Structured PQ verifier shape (complete)

All three planned slices landed:

1. **M21' — Structured PQ verifier interface** —
   `SoLean.Examples.StructuredVerifier`: `VerifierWitness` exposing
   signature/key components, `StructuredVerifier.toBool` projection,
   `StructureRespectsBool` correspondence assumption,
   `toBool_eq_under_respectsBool` discharge.
2. **M22' — Lattice-shaped public-key model** —
   `SoLean.Examples.LatticePublicKey`: polynomial coefficient list +
   degree, `LatticeShapeBound`, `LatticePublicKey.compress`,
   degree-independence theorem.
3. **M23' — Scheme parameterization** —
   `SoLean.Examples.SchemeParameters`: `falcon512`, `mlDsa44`
   records with documented NIST constants; surfaced as
   `schemeParameterCalibration` (third calibration kind) in the
   certificate.

### Lane C — Concrete verifier properties (Phase 6, in flight)

1. **M21'' — Byte-length scheme discrimination** *(landed)* —
   `SchemeParameters.signatureByteLengthUInt256` and
   `publicKeyByteLengthUInt256` lift the documented constants into
   the `UInt256` slot used by the wrapper. Generic theorem
   `wrapper_calibrated_for_one_scheme_rejects_other_signature_length`
   shows that under different `signatureByteLengthUInt256` values a
   wrapper calibrated for one scheme cannot succeed on an input sized
   for another. Concrete corollary
   `falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length`
   pins this for the Falcon-512 / ML-DSA-44 case. Surfaced as
   `wrapperGuardTheorems` in the schemeParameterCalibration.
2. **M22'' — Witness extraction** *(landed)* — reframed from the
   originally-planned "witness determinism" (trivially true for
   `Option`-valued functions). The deliverable:
   `decide_isSome_of_toBool` extracts a `VerifierWitness` from any
   Bool-level acceptance, and
   `witness_extractable_under_respectsBool` lifts that to the
   `StructureRespectsBool` bridge — downstream code holding an
   `Env.verifier ... = true` fact can pull out the structured
   witness without weakening any existing AAPQ proof.
3. **M23'' — Coordinate uniqueness** *(landed)* — under a named
   `CompressionInjectiveOnHead` assumption, two non-empty
   `LatticePublicKey`s that compress to the same `UInt256` share
   their head coordinate. The placeholder `compress` function
   discharges the assumption via `compress_injectiveOnHead`.
   First Lean statement that the lattice structure constrains the
   public key beyond the opaque-word interface; a future replacement
   of the placeholder compression with a real hash can keep the
   coordinate-uniqueness lemma and discharge the named assumption
   against the hash's collision resistance.

### Out of scope until at least one lane completes

- real PQ cryptographic security (M21'–M23' approach the shape, not the
  security proof)
- production-readiness for AA wallets

## Updating This Roadmap

When changing the project, update this file if any of these changes:

- A new thing becomes proved in Lean.
- A manual/trusted step becomes generated or checked.
- A supported subset grows.
- A limitation is removed.
- A future milestone becomes obsolete.

Prefer moving items from `Not Done` to `Implemented But Not Verified End-To-End`
to `Proved In Lean` rather than adding vague new goals.
