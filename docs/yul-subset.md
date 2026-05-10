# Restricted Yul Subset

SoLean currently works with a tiny Yul-like subset for prototype scripting and
for the first Lean-side restricted Yul proof. This subset is not a full Yul
grammar and is not a semantic equivalence system.

## Supported Shape

The subset accepts exactly:

- One `object`.
- One `code` block.
- One `function`.
- Function parameters as plain identifiers.
- Statements:
  - `let name := expr`
  - `sstore(expr, expr)`
  - `if expr { revert(0, 0) }`
- Expressions:
  - decimal literals
  - identifiers
  - `sload(expr)`
  - `add(expr, expr)`
  - `gt(expr, expr)`
  - `lt(expr, expr)`
  - `iszero(expr)`

Anything outside this subset must be rejected with an unsupported-subset error.

## Current Counter Output

The SoLean-to-Yul placeholder emits the Counter model as a deterministic subset
AST. The output mirrors the intended checked-arithmetic path:

1. Revert if `amount` is zero.
2. Load `x` from slot `0`.
3. Compute `new_x := add(old_x, amount)`.
4. Revert if checked addition would overflow, approximated by
   `lt(new_x, old_x)` in this Yul-like text.
5. Store `new_x` to slot `0`.
6. Revert if the final assertion `new_x >= amount` fails.

## solc Output

For reproducible local compiler setup, use `solc 0.8.20`. We recommend
`solc-select` as a version manager, similar in spirit to `elan` for Lean:

```bash
python3 -m pip install solc-select
solc-select install 0.8.20
solc-select use 0.8.20
solc --version
```

If `solc` is installed, generate local Counter Yul output with:

```bash
mkdir -p build
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul
```

Do not commit `build/` artifacts yet. The repository should keep generated
compiler output local until a pinned solc workflow exists in CI.

## Equivalence Checker

`scripts/check_equiv.py` parses this subset into typed AST nodes. By default, it
runs a tiny bounded trace comparison over Counter-shaped inputs:

- `amount = 0`
- small successful additions
- edge cases near `2^256 - 1`

The interpreter models `add` with EVM-style 256-bit wraparound, then observes
whether the emitted overflow guard reverts. This is useful for catching obvious
Counter emitter regressions.

It is not semantic Yul equivalence. It is a finite smoke-test over a deliberately
small subset. Unsupported syntax returns a distinct nonzero result instead of
pretending to compare semantics.

Strict AST equality is available with:

```bash
python3 scripts/check_equiv.py --ast left.yul right.yul
```

The old normalized-text comparison remains available:

```bash
python3 scripts/check_equiv.py --text left.yul right.yul
```

## Lean Restricted Yul Model

`SoLean/Yul.lean` defines a separate Lean model for a similarly tiny restricted
Yul subset. It is intentionally hand-written and proof-oriented rather than a
parser for arbitrary Yul text.

The Lean model currently supports the Counter path: locals, storage load/store,
wrapping `add`, `gt`, `lt`, `iszero`, and revert guards. See
`docs/counter-yul.md` for the current Counter theorem.

`SoLean/Compiler.lean` now contains a tiny partial compiler that can emit this
restricted Lean Yul shape for the Counter source function. See
`docs/compiler.md` for the current compiler proof.
