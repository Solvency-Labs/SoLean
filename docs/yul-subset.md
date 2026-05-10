# Restricted Yul Subset

SoLean currently works with a tiny Yul-like subset for prototype scripting only.
This subset is not a full Yul grammar and is not a semantic equivalence system.

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

If `solc` is installed, generate local Yul output with:

```bash
mkdir -p build
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul
```

Do not commit `build/` artifacts yet. A pinned solc version and reproducible
artifact workflow should come before checked-in compiler output.

## Equivalence Checker

`scripts/check_equiv.py` compares AST equality for this restricted subset by
default. It is useful for catching deterministic emitter drift.

It is not semantic Yul equivalence. Unsupported syntax returns a distinct
nonzero result instead of pretending to compare semantics.

The old normalized-text comparison remains available:

```bash
python3 scripts/check_equiv.py --text left.yul right.yul
```
