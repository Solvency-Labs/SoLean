# SoLean Assumptions

SoLean is a research prototype for small, proof-oriented case studies. This
document records the assumptions that matter for interpreting the current
results.

## Arithmetic

- `UInt256` is still represented as `Nat`, not as a bounded subtype.
- `UInt256.maxValue` is `2^256 - 1`.
- Checked addition returns `none` when the mathematical sum exceeds
  `UInt256.maxValue`.
- Checked subtraction returns `none` when the right-hand side is greater than
  the left-hand side.
- Existing storage values are assumed to be valid Solidity `uint256` values
  when a case study depends on bounded stored values.

## Execution

- Storage is modeled as a total mapping from slots to `UInt256` values.
- The environment currently contains only `msg.sender`.
- `require false` reverts with `Failure.requireFailed`.
- `assert false` reverts with `Failure.assertFailed`.
- Arithmetic failure during expression evaluation reverts with
  `Failure.arithmeticFailed`.

## Solidity And Yul

- Solidity parsing and generation of SoLean models are not implemented.
- Yul parsing and semantic equivalence are not implemented.
- The current SoLean-to-Yul output is deterministic placeholder text for the
  Counter example only.
- The current equivalence checker compares normalized text only.
