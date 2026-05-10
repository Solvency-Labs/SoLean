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
- Python emits deterministic Counter source-shape JSON that is tested against a
  JSON-like mirror of `CounterCompiler.counterFunction`.
- `solc_to_yul.py` enforces the pinned `solc 0.8.35` target when `solc` is
  installed.
- Local `solc 0.8.35 --ir` Counter output has been generated and classified as
  unsupported by the current restricted subset.
- `classify_yul.py` reports whether Yul text is in the supported subset or
  names the first unsupported wrapper/statement/expression/shape blocker.

These are useful engineering tools, but they are not part of the trusted Lean
proof chain yet.

### Not Done

- Verified Solidity parsing.
- Verified translation from Solidity text to the Lean source function. The
  current bridge is an auditable structural/golden test, not a proof.
- Verified connection between the Python Yul emitter and the Lean compiler. The
  current connection is an auditable structural/golden test, not a proof.
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

Done:

- The Counter Solidity parser can emit deterministic source-shape JSON.
- Tests check that this JSON matches a canonical mirror of
  `CounterCompiler.counterFunction`.
- Unsupported Solidity still fails loudly.

Next tasks:

- Reduce duplication between the Python source-shape mirror and Lean
  `counterFunction`.
- Decide whether Lean should export a source-shape artifact, or whether a shared
  checked representation should drive both sides.

Definition of done:

- For Counter, the path from `examples/Counter.sol` to the Lean source function
  has less hand-maintained duplication than the current source-shape mirror.

### 3. Bring In Real `solc 0.8.35` Output

Goal: compare against the real compiler without pretending the whole solc IR is
supported.

Done:

- Install/select `solc 0.8.35` locally with `solc-select`.
- Generate `build/Counter.solc.yul` locally without committing it.
- Reject unsupported solc output by default.
- Record the first blocker: solc's `IR:` preamble/wrapper is outside the
  current restricted parser.

Next tasks:

- Add a solc-output preprocessor that can intentionally select the deployed
  object, or decide that this selection should happen in a separate trusted
  extraction step.
- Decide the next minimal subset target after wrapper handling: likely nested
  objects, multiple functions, memory setup, or ABI dispatch.

Definition of done:

- The repo can classify real Counter solc IR with a blocker more semantic than
  the outer solc wrapper, without claiming full equivalence.

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
Handle the solc IR wrapper boundary.
```

Why this matters:

- We can now generate and classify real `solc 0.8.35 --ir` Counter output.
- The first blocker is not yet arithmetic or storage semantics; it is the solc
  output wrapper and deployed-object selection problem.
- Handling that boundary will expose the next real semantic subset gap.

Smallest useful version:

1. Add an explicit, documented extraction/classification mode for solc IR
   wrapper text.
2. Identify the deployed object and report the first unsupported construct
   inside it.
3. Keep extraction trusted and auditable; do not claim semantic equivalence.

## Updating This Roadmap

When changing the project, update this file if any of these changes:

- A new thing becomes proved in Lean.
- A manual/trusted step becomes generated or checked.
- A supported subset grows.
- A limitation is removed.
- A future milestone becomes obsolete.

Prefer moving items from `Not Done` to `Implemented But Not Verified End-To-End`
to `Proved In Lean` rather than adding vague new goals.
