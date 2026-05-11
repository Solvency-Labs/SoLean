# Counter Bridge v2

`Counter Bridge v2` turns the current Counter path into one auditable report.
It is still not verified Solidity parsing, verified solc parsing, or semantic
equivalence with real solc Yul.

The bridge command is:

```bash
python3 scripts/check_counter_bridge.py \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
```

It expects local `solc 0.8.35 --ir` output in `build/Counter.solc.yul`. The
`build/` directory remains uncommitted.

## What The Report Checks

The report has kind `counterBridgeReport` and succeeds only when all three
checks pass:

- `soliditySourceToLeanSource`: the trusted Counter-only Solidity parser emits
  the same source-shape JSON as the Lean-owned
  `SoLean.Examples.CounterCompiler.counterFunction` artifact.
- `pythonYulEmitterToLeanYul`: the Python placeholder Counter Yul emitter
  renders restricted Yul that parses to the same shape as the Lean-owned
  `SoLean.Examples.CounterYul.counterProgram` artifact.
- `solcFunctionSummaryToLeanYul`: the trusted Counter-specific solc function
  summary normalizes the generated `fun_inc_*` body to the same Lean-owned Yul
  artifact.

The report also includes SHA-256 hashes of the Lean-exported source and Yul
artifacts. These hashes are for auditability and regression detection; they are
not cryptographic commitments to a verified external artifact.

## Trusted Solc Summary Rules

The solc summary rule list is emitted as `trustedRules` in stable first-use
order. The current rules are:

- `hexLiteralAsNat`: parse solc hexadecimal integer literals as natural-number
  literals in the restricted subset.
- `transparentValueHelper`: treat current one-argument value helpers such as
  `cleanup_t_uint256`, `identity`, and
  `convert_t_rational_0_by_1_to_t_uint256` as transparent wrappers.
- `requireHelperAsRevertGuard`: summarize `require_helper(condition)` as a
  revert guard.
- `storageReadSlot0AsSload`: summarize the current slot-0 storage read helper
  as `sload(0)`.
- `checkedAddUInt256AsAddWithOverflowGuard`: summarize the current checked-add
  helper as `add(old, amount)` plus the overflow guard.
- `storageUpdateSlot0AsSstore`: summarize the current slot-0 storage update
  helper as `sstore(0, value)`.
- `assertHelperAsRevertGuard`: summarize the current assertion helper as a
  final revert guard.

These are trusted Python inspection rules. They are tested against Lean-owned
artifacts, but they are not proved in Lean.

## Trust Boundary

This bridge report is useful because it makes the Counter path harder to fool:
source shape, Python emitted Yul, and real solc function-body summary all have
to agree with Lean-owned artifacts.

The remaining trusted boundaries are still explicit:

- The Solidity parser is an exact Counter-subset parser, not a verified parser.
- The Python Yul emitter is a placeholder, not generated from Lean.
- The solc summary is Counter-specific pattern recognition.
- Real solc deployment wrappers, ABI dispatch, memory setup, helper functions,
  and full Yul/EVM semantics are outside the current verified model.
- Passing this report is not semantic equivalence with real solc Yul.
