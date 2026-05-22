# SoLean Roadmap

This is the living roadmap for SoLean. Update it whenever the project crosses a
meaningful boundary, especially when a manual or trusted step becomes checked by
Lean.

## Mental Model

SoLean's north star is traceable trust reduction, now aimed at a concrete
Ethereum-facing target: account-abstraction wallet validation with
post-quantum verifier-wrapper contracts.

```text
Build a boundary-aware Lean/Solidity verification pipeline for
account-abstraction contracts that authenticate user operations through
post-quantum signature verification, with cryptographic assumptions explicit
and contract-level safety properties proved.
```

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
- `PQVerifierWrapper.verifyProgram(input)` proves that successful modeled
  wrapper validation implies the configured key-length, signature-length,
  domain, and abstract verifier checks passed, with storage unchanged.
- `AAPQIntegration.validateIntegrated(...)` proves that successful integrated
  validation connects the wrapper and wallet checks over the same modeled
  verifier tuple.
- `SoLean.Examples.AAPQSource.integratedContract` defines a Solidity-shaped
  source description of the AA/PQ two-contract layout and proves that the
  wallet, wrapper, and integrated bodies instantiate to the existing proved
  programs.
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
- `scripts/check_aapq_source.py` cross-checks the three Lean-owned AA/PQ
  artifacts against the Solidity sketch and against each other (certificate's
  `expectedBehaviorSummary` vs. the standalone behavior summary), and walks
  the behavior summary's structured operands to verify each one references a
  declared parameter or a real storage slot in source-json. The report is
  committed as `tests/golden/AAPQ.source.v2.json`.
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

The previous next step ("move AA/PQ integration from pure Lean model to a
Solidity-shaped source model") has landed as a v0:

- `SoLean.Examples.AAPQSource` defines the two-contract source shape and proves
  `walletSource_instantiates_to_existing_model`,
  `wrapperSource_instantiates_to_existing_model`, and
  `integratedSource_instantiates_to_existing_model`.
- `SoLean/AAPQArtifactsMain.lean` exports `source-json` and
  `source-certificate-json` artifacts with theorem references and explicit
  out-of-scope items.
- `examples/AAPQIntegration.sol` is a hand-written Solidity fixture matching
  the source shape; it is not parsed or compared to Lean.

The next best qualitative task is:

```text
Decide whether to deepen the AA/PQ source-shape audit chain or generalize the
shared modeling vocabulary across Counter and AA/PQ.
```

Useful candidate moves, in rough priority order:

1. Extract the Solidity-shaped `Contract`/`Param`/`StorageSlot` vocabulary out
   of `AAPQSource` into a shared `SoLean.Source.Shape` module and use it from
   the Counter source artifact too, reducing per-case-study duplication.
2. Add a sibling Lean-owned trust-boundary artifact (a JSON listing of
   assumptions / unsupported / proofReferences) so the demo no longer
   re-parses the certificate to surface trust boundaries — making the
   boundary list a first-class artifact rather than a derived demo output.
3. Apply the AAPQSource pattern (structured source description + behavior
   summary + reflection theorems + cross-check + demo) to one of the
   intentionally-out-of-scope concerns: an external-call shim model
   (verified low-level call between wallet and wrapper), or replacing the
   abstract verifier oracle with a more concrete (still non-cryptographic)
   modeled scheme.
4. Keep real Solidity parsing, Yul emission, external calls, and real PQ
   cryptography out of scope until at least one of the above is done.

## Updating This Roadmap

When changing the project, update this file if any of these changes:

- A new thing becomes proved in Lean.
- A manual/trusted step becomes generated or checked.
- A supported subset grows.
- A limitation is removed.
- A future milestone becomes obsolete.

Prefer moving items from `Not Done` to `Implemented But Not Verified End-To-End`
to `Proved In Lean` rather than adding vague new goals.
