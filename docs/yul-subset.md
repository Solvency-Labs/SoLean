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
  - hexadecimal integer literals such as `0x00`
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

For reproducible local compiler setup, use `solc 0.8.35`. This is SoLean's
current stable compiler target, not a proof-relevant semantic assumption. We
recommend `solc-select` as a version manager, similar in spirit to `elan` for
Lean:

```bash
python3 -m pip install solc-select
solc-select install 0.8.35
solc-select use 0.8.35
solc --version
```

If `solc` is installed, generate local Counter Yul output with:

```bash
mkdir -p build
PATH="$(python3 -m site --user-base)/bin:$PATH" \
  python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul
```

Do not commit `build/` artifacts yet. The repository should keep generated
compiler output local until a pinned solc workflow exists in CI.

## Counter solc IR Findings

With `solc 0.8.35 --ir`, the local Counter output is not in SoLean's current
restricted subset.

The first blocker reported by `scripts/classify_yul.py` is:

```text
unsupported-wrapper: solc output preamble is not supported: IR:
```

The explicit solc-inspection mode gets one trusted extraction boundary further:

```bash
python3 scripts/classify_yul.py --inspect-solc build/Counter.solc.yul
```

It identifies candidate object blocks, selects the deployed/runtime object, and
reports the first unsupported construct inside that object. For current Counter
IR, the next blocker is memory setup like:

```text
unsupported-statement: unsupported statement form: mstore(64, memoryguard(128))
```

The function-body inspection mode gets one boundary further:

```bash
python3 scripts/classify_yul.py --inspect-function inc build/Counter.solc.yul
```

It selects `fun_inc_*` inside the deployed object. For current Counter IR, the
first function-body blocker is:

```text
unsupported-expression: ... line ...: unsupported expression function: read_from_storage_split_offset_0_t_uint256
```

Hexadecimal literals are now parsed into the same `Literal` AST node as decimal
literals and render back canonically as decimal. The solc function inspector
also summarizes explicitly trusted one-argument value helpers such as
`cleanup_t_uint256`, `identity`, and
`convert_t_rational_0_by_1_to_t_uint256`. These summaries are classification
helpers only; they are not part of the general restricted Yul equivalence
subset. The inspector also summarizes `require_helper(condition)` as a revert
guard for classification.

The Counter-specific summary mode gets through the storage read helper,
checked-add helper, storage update helper, and assert helper:

```bash
python3 scripts/classify_yul.py --summarize-function inc build/Counter.solc.yul
```

It emits deterministic JSON containing a normalized restricted Counter Yul
shape. This summary is checked against the Lean-exported Counter Yul artifact in
tests. It is still a trusted inspection summary, not semantic equivalence
against real solc IR.

Current trusted Counter summary rules:

- `hexLiteralAsNat`: hexadecimal literals become natural-number literals.
- `transparentValueHelper`: current one-argument value helpers are treated as
  transparent wrappers.
- `requireHelperAsRevertGuard`: `require_helper(condition)` becomes a revert
  guard.
- `storageReadSlot0AsSload`: `read_from_storage_split_offset_0_t_uint256(0)`
  becomes `sload(0)`.
- `checkedAddUInt256AsAddWithOverflowGuard`: `checked_add_t_uint256(old,
  amount)` becomes `add(old, amount)` plus the
  checked-add overflow guard.
- `storageUpdateSlot0AsSstore`:
  `update_storage_value_offset_0_t_uint256_to_t_uint256(0, value)` becomes
  `sstore(0, value)`.
- `assertHelperAsRevertGuard`: `assert_helper(iszero(lt(lhs, rhs)))` becomes
  the final `lt(lhs, rhs)` revert guard.

The expected rule list is exported by Lean as part of the Counter bridge
manifest:

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```

The manifest also records which rule translations have Lean-backed semantics.
At the moment, `requireHelperAsRevertGuard`, `storageReadSlot0AsSload`,
`checkedAddUInt256AsAddWithOverflowGuard`, `storageUpdateSlot0AsSstore`, and
`assertHelperAsRevertGuard` have non-empty Lean proof references. The
recognizer that finds those patterns inside real solc text is still trusted
Python code.

The Python bridge report checks the observed rule list against that manifest.
This makes the boundary easier to audit, but the recognizers are still trusted
Python code rather than Lean-proved solc helper semantics.

After that, the real IR also contains constructs outside the subset:

- a top-level creation object plus a nested deployed object
- memory setup such as `mstore(64, memoryguard(128))`
- constructor/deployment code and helper functions
- ABI dispatch using calldata, selector extraction, `switch`, and `case`
- expression helpers such as `mload`, `shr`, `mul`, `sub`, and `slt`

These are future subset-expansion targets. The current checker must reject this
output rather than claiming semantic equivalence.

## Equivalence Checker

`scripts/check_equiv.py` parses this subset into typed AST nodes. By default, it
runs a tiny symbolic state-transform comparison for supported restricted Yul.
The summary records:

- function parameters
- ordered revert conditions
- final storage writes

This is more informative than finite traces, but it still does not simplify
expressions or prove semantic equivalence.

The legacy bounded trace checker remains available:

```bash
python3 scripts/check_equiv.py --bounded-traces left.yul right.yul
```

It runs over Counter-shaped inputs:

- `amount = 0`
- small successful additions
- edge cases near `2^256 - 1`

The trace interpreter models `add` with EVM-style 256-bit wraparound, then
observes whether the emitted overflow guard reverts. This is useful for catching
obvious Counter emitter regressions.

Neither checker is semantic Yul equivalence. Unsupported syntax returns a
distinct nonzero result instead of pretending to compare semantics.

Strict AST equality is available with:

```bash
python3 scripts/check_equiv.py --ast left.yul right.yul
```

The old normalized-text comparison remains available:

```bash
python3 scripts/check_equiv.py --text left.yul right.yul
```

Classify support without comparing two files:

```bash
python3 scripts/classify_yul.py build/Counter.solean.yul
python3 scripts/classify_yul.py build/Counter.solc.yul
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

Python tests check that `scripts/yul_subset.py`'s Counter structure matches a
Lean-exported artifact derived from the Lean-proved Counter Yul shape and that
`scripts/solean_to_yul.py --example counter` matches
`tests/golden/Counter.solean.yul`. This is structural/golden alignment, not a
verified translation theorem.
