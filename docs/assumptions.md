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
- The default Yul checker runs bounded trace comparison for Counter-shaped
  restricted-subset programs. This is not semantic Yul equivalence.
- Strict restricted-subset AST equality is available as an explicit `--ast`
  mode, and normalized text comparison remains available as `--text`.
- `solc 0.8.20` is the intended pinned compiler version for local Counter Yul
  generation. Generated `build/` artifacts are not committed yet.
- The Python emitter, Python parser, and Lean Yul AST are not yet connected by a
  verified translation.
