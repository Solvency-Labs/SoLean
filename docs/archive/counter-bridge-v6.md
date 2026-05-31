# Counter Bridge v6

`Counter Bridge v6` makes the bridge report more certificate-like. Bridge v5
proved that the public solc summary trace can replay to the restricted Counter
Yul artifact; v6 moves more expectations into Lean-owned artifacts:

- the accepted Counter source certificate
- the expected solc trace skeleton
- the rule/proof manifest already used by earlier bridge reports

This is still not verified Solidity parsing, verified solc parsing, or semantic
equivalence with real solc Yul.

## Success Condition

```text
examples/Counter.sol
  -> trusted Python parser
  -> source certificate
  -> matches Lean-owned source certificate

real solc Counter fun_inc_*
  -> trusted Python recognizer
  -> deterministic rule trace
  -> trace skeleton matches Lean-owned skeleton
  -> trace replay matches Lean-owned Counter Yul
```

## What The Certificate Checks

`scripts/check_counter_bridge.py` now emits `reportVersion: 6` and checks:

- `soliditySourceToLeanSource`
- `soliditySourceCertificateToLeanManifest`
- `pythonYulEmitterToLeanYul`
- `solcFunctionSummaryToLeanYul`
- `solcTraceReplayToLeanYul`
- `solcTraceSkeletonToLeanManifest`
- `solcTrustedRulesToLeanManifest`

The report also includes a `certificate` section that groups checks into tested,
Lean-owned manifest, and trusted-boundary buckets. This is a presentation and
audit aid; the trust boundary is still explicit.

## Lean-Owned Source Certificate

The source certificate states the accepted Counter shape:

```text
contract Counter
pragma 0.8.35
storage x -> slot 0
inc(uint256 amount)
require(amount > 0)
x += amount
assert(x >= amount)
```

Unsupported Solidity is still rejected loudly. The certificate does not make the
Python parser verified; it makes the parser's accepted claim precise and checked
against Lean-owned data.

## Lean-Owned Trace Skeleton

The trace skeleton removes volatile solc line numbers and source text, then
checks the stable bridge shape:

```text
index -> rule -> effect kind -> emitted restricted Yul statements -> Lean proof
```

This means Python cannot reorder bridge rules, change emitted statements, or
drop a semantic adapter effect without failing against the Lean manifest.

## Remaining Trusted Boundaries

- The Solidity parser is still trusted Counter-only Python.
- The solc IR recognizer/summarizer is still trusted Counter-specific Python.
- `hexLiteralAsNat` remains parser-level trust.
- Trace replay and skeleton checks are Python audit infrastructure, not Lean
  theorems.
- Full solc wrappers, ABI dispatch, memory, calls, gas, events, and EVM
  semantics remain unsupported.

## Checked Artifact

The bridge report is checked against:

```text
tests/golden/Counter.bridge.v6.json
```

That fixture is generated from the checked Counter Solidity file and the solc IR
fixture embedded in the Python tests, not from local `build/` artifacts.
