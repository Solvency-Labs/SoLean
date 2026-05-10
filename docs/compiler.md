# Tiny Verified Compiler Slice

This document describes the first compiler proof slice in SoLean.

## Scope

`SoLean/Compiler.lean` defines a tiny parameter-aware source language and a
minimal compiler to the restricted Lean Yul model.

The source language supports only what the Counter case study needs:

- one function parameter
- constants
- storage reads
- checked addition assignments of the form `slot := slot + rhs`
- `require`
- `assert`
- sequencing

The compiler is intentionally partial. Unsupported source shapes return `none`.
This is preferable to silently compiling an approximation.

## Counter Compiler Proof

`SoLean/Examples/CounterCompiler.lean` defines `counterFunction`, a generic
parameterized version of `Counter.inc`.

It proves three key facts:

- `counter_instantiates_to_existing_model`: instantiating `counterFunction`
  with an `amount` produces the existing hand-written SoLean Counter model.
- `compile_counter_eq_counter_yul`: compiling `counterFunction` produces the
  existing restricted Yul Counter program.
- `compiled_counter_refines_solean_success`: every successful execution of the
  instantiated SoLean Counter function is reproduced by the compiled restricted
  Yul program with the same final storage.

There is also `compiled_counter_success_assertion`, which states that every
successful execution of the compiled restricted Yul Counter program satisfies
the final `x >= amount` assertion.

## What This Does Not Prove

- A verified theorem that the Python Yul emitter renders exactly the Lean
  compiler output. Python tests currently check a golden output file and a
  structural mirror of the Lean-proved Counter Yul shape, but this is not a
  Lean theorem.
- A verified theorem that Solidity parsing produces `counterFunction`. Python
  tests currently check deterministic Counter source-shape JSON against a
  structural mirror of `CounterCompiler.counterFunction`, but this is not a Lean
  theorem.
- Real `solc --ir` output is equivalent to the restricted Yul program.
- The compiler supports SimpleVault or arbitrary SoLean programs.

Those are future proof obligations, not current claims.
