# Counter Bridge v7

`Counter Bridge v7` adds a Lean-owned restricted *behavior summary* to the
bridge certificate. v6 made the source certificate and trace skeleton
Lean-owned; v7 pins the expected restricted state-transform shape of the
Counter Yul: function parameter, ordered revert guards, and final storage
write by slot. Python's symbolic summary of the emitted Counter Yul must
match it.

This is still not verified solc parsing, verified Solidity parsing, or
semantic equivalence with real solc Yul.

## Success Condition

```text
Lean-exported Counter Yul
  -> Lean-owned restricted behavior summary
       (params, ordered revert guards, final slot writes)

Python-emitted Counter Yul
  -> trusted symbolic state-transform summary
  -> matches Lean-owned behavior summary
```

## What The Certificate Checks

`scripts/check_counter_bridge.py` now emits `reportVersion: 7` and checks:

- `soliditySourceToLeanSource`
- `soliditySourceCertificateToLeanManifest`
- `pythonYulEmitterToLeanYul`
- `behaviorSummaryToLeanManifest` *(new in v7)*
- `solcFunctionSummaryToLeanYul`
- `solcTraceReplayToLeanYul`
- `solcTraceSkeletonToLeanManifest`
- `solcTrustedRulesToLeanManifest`

The new `behaviorSummaryToLeanManifest` check moves the symbolic-summary
expectation from a Python-only smoke test into a Lean-owned manifest claim:
the report fails if Python's summary drifts away from the Lean-owned shape.

## Lean-Owned Behavior Summary

The Counter behavior summary states the expected restricted shape:

```text
object   Counter
function inc(amount)
revert   iszero(gt(amount, 0))
revert   lt(add(slot 0, amount), slot 0)
revert   lt(add(slot 0, amount), amount)
write    slot 0 <- add(slot 0, amount)
```

The summary is intentionally small: it is a state-transform skeleton over the
restricted Yul subset, not a full Yul semantics. Expressions use `param`,
`slot`, `const`, and `call(name, args)` shapes only.

## What This Reduces

Before v7, "this Yul has the right state-transform shape" was a Python
assertion against another Python summary. After v7, the same claim is checked
against a Lean-exported artifact, so Python cannot silently reorder revert
guards, drop a guard, write to a different slot, or rename the parameter
without failing against Lean.

## Remaining Trusted Boundaries

- The Solidity parser is still trusted Counter-only Python.
- The solc IR recognizer/summarizer is still trusted Counter-specific Python.
- `hexLiteralAsNat` remains parser-level trust.
- The symbolic summary itself is trusted Python audit infrastructure, not a
  Lean semantics for restricted Yul. v7 makes the *expected shape* Lean-owned;
  it does not make the summarizer verified.
- Full solc wrappers, ABI dispatch, memory, calls, gas, events, and EVM
  semantics remain unsupported.

## Checked Artifact

The bridge report is checked against:

```text
tests/golden/Counter.bridge.v7.json
```

That fixture is generated from the checked Counter Solidity file and the solc
IR fixture embedded in the Python tests, not from local `build/` artifacts.
