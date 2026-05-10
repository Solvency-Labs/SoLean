# Counter Restricted Yul Proof

This page documents the first restricted Yul proof slice in SoLean.

## What Was Added

`SoLean/Yul.lean` defines a tiny restricted Yul model in Lean:

- local variables as a partial map from names to `UInt256`
- expressions for constants, locals, `sload`, and `add`
- conditions for `gt`, `lt`, and `iszero`
- statements for `let`, `sstore`, and `if ... revert`
- block execution that returns either success with storage or revert

The Yul `add` operation uses UInt256 wraparound. This is intentionally narrower
than full Yul or EVM semantics, but it lets the Counter proof reason about the
overflow guard emitted by the placeholder Yul path.

## Counter Program

`SoLean/Examples/CounterYul.lean` defines the restricted Yul version of
`Counter.inc` as Lean data:

1. Revert when `amount` is zero.
2. Load `old_x` from storage slot `0`.
3. Compute `new_x` with wrapping Yul addition.
4. Revert if `new_x < old_x`, which detects overflow for this Counter path.
5. Store `new_x` back to slot `0`.
6. Revert if `new_x < amount`, which models the final assertion.

## Proven Theorems

`counter_refines_solean_success` proves:

```text
if the SoLean Counter model succeeds,
then the restricted Yul Counter program succeeds with the same final storage.
```

`counter_yul_success_assertion` proves:

```text
if the restricted Yul Counter program succeeds,
then final x >= amount.
```

This is a qualitative step beyond Python trace testing: part of the Yul path is
now represented and checked inside Lean.

The next layer is documented in `docs/compiler.md`: a tiny Lean compiler emits
this Counter Yul program from a parameterized Counter source function.

## Limitations

- The Yul program is still hand-written Lean data, though
  `SoLean/Examples/CounterCompiler.lean` now proves the tiny Lean compiler emits
  this exact program for Counter.
- The Python emitter is not verified against this Lean Yul data.
- The Solidity parser is not verified.
- Real `solc --ir` output is not parsed into this Lean Yul model.
- The model covers only the current Counter subset, not full Yul or EVM.
