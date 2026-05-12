# SoLean Roadmap

This is the living roadmap for SoLean. Update it whenever the project crosses a
meaningful boundary, especially when a manual or trusted step becomes checked by
Lean.

## Mental Model

SoLean's north star is traceable trust reduction:

```text
Build a boundary-aware verification pipeline where a tiny Solidity subset can
be connected to a Lean model, proved, compiled to restricted Yul, and compared
against pinned solc output, with every trusted step explicitly identified.
```

The project is trying to connect four worlds:

```text
Solidity source
  -> SoLean source/model
  -> Lean proofs
  -> restricted Yul output
  -> comparison with solc Yul
```

The important question at every step is:

```text
What is proved, and what is still trusted by hand?
```

Right now, the verified island is Counter inside Lean:

```text
Counter source function in Lean
  -> instantiate to existing SoLean Counter model
  -> compile with tiny Lean compiler
  -> restricted Lean Yul Counter program
  -> prove successful executions preserve the Counter assertion
```

This is real progress, but it does not yet start from Solidity text or real
`solc` output.

See `docs/counter-bridge-v1.md` for the crisp Counter success condition and
`docs/counter-bridge-v2.md` for the current auditable bridge report.

## Current State

### Proved In Lean

- `UInt256` storage values are bounded by type.
- SoLean arithmetic uses checked add/sub for the current DSL.
- `Counter.inc(amount)` is safe under the SoLean semantics when execution
  succeeds.
- `SimpleVault` preserves `totalAssets >= totalShares` for successful modeled
  `deposit` and `withdraw` executions.
- A restricted Yul semantics exists in Lean for the Counter-shaped subset.
- A hand-written restricted Yul Counter program refines successful SoLean
  Counter executions.
- A tiny Lean compiler emits that restricted Yul Counter program from a
  parameterized Counter source function.

### Implemented But Not Verified End-To-End

- Python emits deterministic Counter Yul-like text.
- Lean exports deterministic Counter source, restricted-Yul shape, and bridge
  manifest artifacts.
- Python tests check the Counter Yul emitter against the Lean-exported
  `CounterYul.counterProgram` artifact and a text golden file.
- `check_counter_bridge.py` produces one deterministic Counter bridge report
  tying the trusted Solidity source projection, Python Yul emitter, and solc
  function-body summary back to Lean-owned artifacts.
- The Counter bridge report checks observed solc summary rules against the
  Lean-owned bridge manifest.
- Python parses and normalizes a restricted Yul-like subset.
- Python performs symbolic state-transform checks for Counter-shaped restricted
  Yul programs, with bounded trace checks still available as an explicit legacy
  mode.
- Python recognizes a tiny Counter-shaped Solidity subset.
- Python emits deterministic Counter source-shape JSON that is tested against
  the Lean-exported `CounterCompiler.counterFunction` artifact.
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
- SimpleVault compilation to restricted Yul.
- ABI, calldata, memory, calls, gas, events, reentrancy, or full EVM semantics.

## Roadmap By Boundary

### 1. Keep Counter As The Calibration Case

Goal: make one tiny path genuinely understandable and hard to fool.

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
  inspection, including `cleanup_t_uint256`, `identity`, and
  `convert_t_rational_0_by_1_to_t_uint256`. After this, the first current
  `fun_inc_*` blocker is `require_helper(expr_11)`.
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
  `SoLean.Bridge.RequireHelper` defines a tiny step semantics for
  `require_helper(cond)` and proves `target_refines_source`, which shows the
  emitted `if iszero(cond) { revert(0, 0) }` shape has the same step result as
  the modeled helper under the restricted Yul semantics. This is the first
  rule whose translation is Lean-backed rather than only trusted Python pattern
  recognition.

Next tasks:

- Reduce trust further by moving one more Counter solc summary rule closer to
  Lean. The most natural next candidate is
  `assertHelperAsRevertGuard`, which has the same shape as the require helper
  (final revert guard from a boolean condition) and should reuse the bridge
  module's structure.
- Decide whether the `counterBridgeReport` JSON should remain an internal audit
  format or become a stable checked artifact.

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

### 4. Replace Bounded Trace Checks With Small Semantics

Goal: move from finite smoke tests toward real restricted equivalence.

Done:

- The default checker now compares a tiny symbolic state-transform summary for
  supported restricted Yul: parameters, ordered revert conditions, and final
  storage writes.
- The old finite Counter trace checker remains available as
  `--bounded-traces`.

Next tasks:

- Add tiny simplification/normalization for equivalent symbolic expressions
  only when needed by Counter.
- Mirror the symbolic summary in Lean or export Lean-side summaries if this
  becomes part of the trusted bridge.

Definition of done:

- The checker can explain equivalence for the supported subset in terms of
  storage behavior, not just text, AST equality, or finite traces.

### 5. Generalize Only After Counter Is Solid

Goal: avoid building a broad framework before the first bridge is trustworthy.

Next tasks:

- Extract reusable Lean lemmas from Counter compiler proofs.
- Add the minimal source/compile forms SimpleVault needs.
- Add SimpleVault restricted Yul only after Counter's emitted-text story is
  clear.

Definition of done:

- SimpleVault reuses the Counter proof architecture rather than copying a large
  one-off proof.

## Current Highest-Value Next Step

The next best qualitative task is:

```text
Lift the next Counter bridge adapter rule into Lean.
```

Why this matters:

- The expected solc summary rule list is Lean-owned and checked by the
  bridge report.
- `requireHelperAsRevertGuard` now has a Lean-backed semantic translation
  through `SoLean.Bridge.RequireHelper.target_refines_source`, exposed via the
  manifest's `bridgeRuleProofs` field.
- The remaining six rules are still trusted Python pattern recognition. The
  next trust-reduction move is to lift one more rule the same way.

Smallest useful version:

1. Pick the next simple rule. `assertHelperAsRevertGuard` mirrors the require
   case study: a final revert guard that succeeds when its boolean condition
   holds. Define `SoLean.Bridge.AssertHelper` with a step semantics and a
   `target_refines_source` theorem.
2. Wire the theorem into `Artifacts.lean`'s `counterBridgeRuleProofs` entry
   for `assertHelperAsRevertGuard` and into `proofReferences`.
3. Update the Python alignment test to assert the new rule has a non-empty
   `leanProof`.

## Updating This Roadmap

When changing the project, update this file if any of these changes:

- A new thing becomes proved in Lean.
- A manual/trusted step becomes generated or checked.
- A supported subset grows.
- A limitation is removed.
- A future milestone becomes obsolete.

Prefer moving items from `Not Done` to `Implemented But Not Verified End-To-End`
to `Proved In Lean` rather than adding vague new goals.
