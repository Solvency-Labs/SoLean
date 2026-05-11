# SoLean Assumptions

SoLean is a research prototype for small, proof-oriented case studies. This
document records the assumptions that matter for interpreting the current
results.

## Arithmetic

- `UInt256` is represented as a structure carrying a `Nat` value plus a proof
  that the value is at most `2^256 - 1`.
- `UInt256.maxValue` is `2^256 - 1`.
- Checked addition returns `none` when the mathematical sum exceeds
  `UInt256.maxValue`.
- Checked subtraction returns `none` when the right-hand side is greater than
  the left-hand side.
- Existing storage values are type-enforced as bounded `UInt256` values.

## Execution

- Storage is modeled as a total mapping from slots to `UInt256` values.
- The environment currently contains only `msg.sender`.
- `require false` reverts with `Failure.requireFailed`.
- `assert false` reverts with `Failure.assertFailed`.
- Arithmetic failure during expression evaluation reverts with
  `Failure.arithmeticFailed`.

## Solidity And Yul

- Solidity parsing and generation of SoLean models are not implemented beyond a
  tiny explicit Counter-subset parser.
- Yul parsing is limited to the restricted subset in `docs/yul-subset.md`.
- The current SoLean-to-Yul output is deterministic placeholder text for the
  Counter example only.
- `SoLean/Yul.lean` contains a hand-written Lean semantics for a tiny restricted
  Yul subset. It is not full Yul or full EVM semantics.
- The restricted Lean Yul semantics models wrapping `add`, local variables,
  storage load/store, and revert guards for the Counter path.
- `SoLean/Examples/CounterYul.lean` proves that successful SoLean Counter
  executions are reproduced by the hand-written restricted Yul Counter model.
- `SoLean/Compiler.lean` contains a tiny partial compiler from a one-parameter
  source language to restricted Lean Yul.
- `SoLean/Examples/CounterCompiler.lean` proves that the generic Counter source
  function instantiates to the existing Counter model and compiles to the
  existing restricted Yul Counter model.
- Lean exports deterministic Counter source and restricted-Yul artifacts for
  tests and audits. These artifacts are generated from Lean definitions, not
  proved to correspond to Python code.
- The Counter Solidity parser can emit deterministic source-shape JSON that is
  tested against the Lean-exported `CounterCompiler.counterFunction` artifact.
- The default Yul checker compares a tiny symbolic state-transform summary for
  Counter-shaped restricted-subset programs. This is not semantic Yul
  equivalence.
- The old bounded trace checker remains available as `--bounded-traces`.
  Strict restricted-subset AST equality is available as an explicit `--ast`
  mode, and normalized text comparison remains available as `--text`.
- `solc 0.8.35` is the intended pinned compiler version for local Counter Yul
  generation. It was chosen as the current stable Solidity compiler target when
  adopted, not because the proofs depend on that patch version.
  `scripts/solc_to_yul.py` rejects other solc versions. Generated `build/`
  artifacts are not committed yet.
- Real `solc 0.8.35 --ir` Counter output is currently outside the supported
  subset. The default classifier first observes the solc `IR:`
  preamble/wrapper. The explicit solc-inspection mode selects the deployed
  object and currently reports memory setup such as
  `mstore(64, memoryguard(128))` as the next unsupported blocker.
- The explicit solc function-inspection mode selects the generated `fun_inc_*`
  body for `inc`. Hexadecimal integer literals are parsed, and transparent
  one-argument value helpers are summarized for classification only. The
  current first unsupported function-body statement is `require_helper(expr_11)`.
- The Python emitter, Python parser, Solidity source, and real solc output are
  not yet connected to the Lean compiler by a verified translation. Current
  Python tests provide auditable structural alignment for Counter only.
