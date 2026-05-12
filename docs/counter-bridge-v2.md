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

The report has kind `counterBridgeReport` and succeeds only when all four
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
- `solcTrustedRulesToLeanManifest`: the trusted-rule list observed by the
  Python solc summary matches the Lean-owned bridge manifest.

The report also includes SHA-256 hashes of the Lean-exported source, Yul, and
bridge-manifest artifacts. These hashes are for auditability and regression
detection; they are not cryptographic commitments to a verified external
artifact.

## Trusted Solc Summary Rules

Lean exports the expected solc summary rule list through:

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```

The Python solc summary emits its observed `trustedRules` in stable first-use
order, and the bridge report checks that observed list against the Lean-owned
manifest. The current expected rules are:

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

These are still trusted Python inspection rules. Lean now owns the expected
boundary list, but Lean does not yet prove that the Python recognizer implements
these rules correctly.

## Per-Rule Lean Proof References

The Lean-owned bridge manifest also exports a `bridgeRuleProofs` array, listing
each rule alongside the Lean theorem (if any) that backs its semantic
translation. The field is intentionally additive: `expectedTrustedRules` keeps
the same shape and ordering, and the report's existing rule-list check is
unchanged.

`requireHelperAsRevertGuard` is the first rule with a Lean-backed semantic
translation. The theorem
`SoLean.Bridge.RequireHelper.target_refines_source` proves that, under the
restricted Lean Yul semantics, the modeled `require_helper(cond)` step result
equals `execStmt (ifRevert (iszero cond))` for every storage and locals. This
does not prove that the trusted Python recognizer identifies the helper
correctly inside real solc output; the parser-level boundary is still trusted.
What it does establish is that, once recognized, the textual rewrite is sound
with respect to the existing Lean Yul model.

The other rules currently have an empty `leanProof` field. Each is a candidate
for future trust-reduction work in the same shape: add a tiny Lean model of the
source helper, prove the target Yul form matches it under the restricted
semantics, and link the theorem back into `bridgeRuleProofs`.

## Trust Boundary

This bridge report is useful because it makes the Counter path harder to fool:
source shape, Python emitted Yul, real solc function-body summary, and the
trusted-rule list all have to agree with Lean-owned artifacts.

The remaining trusted boundaries are still explicit:

- The Solidity parser is an exact Counter-subset parser, not a verified parser.
- The Python Yul emitter is a placeholder, not generated from Lean.
- The solc summary is Counter-specific pattern recognition.
- Real solc deployment wrappers, ABI dispatch, memory setup, helper functions,
  and full Yul/EVM semantics are outside the current verified model.
- Passing this report is not semantic equivalence with real solc Yul.
