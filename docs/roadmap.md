# SoLean Roadmap

This is the living roadmap for SoLean. Update it whenever the project crosses a
meaningful boundary, especially when a manual or trusted step becomes checked by
Lean.

## Mental Model

SoLean is trying to connect four worlds:

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
- Python tests check the Counter Yul emitter against a golden file and a
  JSON-like structural mirror of the Lean-proved `CounterYul.counterProgram`.
- Python parses and normalizes a restricted Yul-like subset.
- Python performs bounded trace checks for Counter-shaped Yul programs.
- Python recognizes a tiny Counter-shaped Solidity subset.
- `solc_to_yul.py` can call `solc` when it is installed.

These are useful engineering tools, but they are not part of the trusted Lean
proof chain yet.

### Not Done

- Verified Solidity parsing.
- Verified translation from Solidity text to the Lean source function.
- Verified connection between the Python Yul emitter and the Lean compiler. The
  current connection is an auditable structural/golden test, not a proof.
- Parsing emitted Yul text back into Lean Yul data.
- Real `solc 0.8.20 --ir` Counter output comparison.
- Semantic equivalence against real Yul.
- SimpleVault compilation to restricted Yul.
- ABI, calldata, memory, calls, gas, events, reentrancy, or full EVM semantics.

## Roadmap By Boundary

### 1. Keep Counter As The Calibration Case

Goal: make one tiny path genuinely understandable and hard to fool.

Done:

- Python emitter output is checked against `tests/golden/Counter.solean.yul`.
- Python `counter_object()` is checked against a canonical JSON-like shape that
  mirrors the Lean-proved `CounterYul.counterProgram`.

Next tasks:

- Reduce duplicate Counter Yul definitions between Lean and Python further.
- Decide whether Python should generate from a shared JSON/golden AST, whether
  Lean should export expected Yul data, or whether both should come from one
  small source of truth.
- Keep documenting every trusted/manual step.

Definition of done:

- The repository can explain exactly why the Counter Yul emitted by tooling is
  the same program as the one proved in Lean, with less hand-maintained
  duplication than the current structural mirror.

### 2. Connect Solidity To The Lean Source Shape

Goal: stop treating the Solidity input as only a human reference.

Next tasks:

- Make the Counter Solidity parser produce a tiny structured JSON-like summary.
- Add a golden check that the parsed Counter summary matches the Lean
  `counterFunction` shape.
- Keep unsupported Solidity rejection loud and precise.

Definition of done:

- For Counter, the path from `examples/Counter.sol` to the Lean source function
  is explicit enough to audit, even if the parser itself is not verified.

### 3. Bring In Real `solc 0.8.20` Output

Goal: compare against the real compiler without pretending the whole solc IR is
supported.

Next tasks:

- Install/select `solc 0.8.20` locally with `solc-select`.
- Generate `build/Counter.solc.yul` locally, but do not commit it yet.
- Inspect the real IR and decide the smallest additional subset needed.
- Reject unsupported solc output by default.

Definition of done:

- There is a documented, reproducible local command for generating Counter solc
  Yul, and a clear list of unsupported constructs still blocking comparison.

### 4. Replace Bounded Trace Checks With Small Semantics

Goal: move from finite smoke tests toward real restricted equivalence.

Next tasks:

- Define a small semantic comparison for the Python restricted Yul AST.
- Keep it intentionally smaller than full Yul.
- Mirror the semantics already used in Lean where possible.

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
Connect the Counter Solidity parser to the Lean source function shape.
```

Why this matters:

- We now have a Lean source function, compiler proof, and Yul structural/golden
  checks.
- But `examples/Counter.sol` is still only recognized by a Python parser that
  emits a Lean reference.
- The bridge from Solidity text to `CounterCompiler.counterFunction` is still
  informal.

Smallest useful version:

1. Make the Counter Solidity parser emit a deterministic JSON-like source
   summary.
2. Add a golden test that this summary matches the shape of
   `CounterCompiler.counterFunction`.
3. Keep the claim modest: auditable structural alignment, not verified Solidity
   parsing.

## Updating This Roadmap

When changing the project, update this file if any of these changes:

- A new thing becomes proved in Lean.
- A manual/trusted step becomes generated or checked.
- A supported subset grows.
- A limitation is removed.
- A future milestone becomes obsolete.

Prefer moving items from `Not Done` to `Implemented But Not Verified End-To-End`
to `Proved In Lean` rather than adding vague new goals.
