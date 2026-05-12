# Counter Bridge v5

`Counter Bridge v5` makes the solc summary trace replayable. Bridge v4 made the
trusted `fun_inc_*` recognizer line-auditable; v5 checks that the public trace
effects reconstruct the same restricted Counter Yul program that the summary
claims.

This is still not verified Solidity parsing, verified solc parsing, or semantic
equivalence with real solc Yul.

## Success Condition

```text
real solc Counter fun_inc_*
  -> trusted Python recognizer
  -> deterministic rule trace
  -> replay trace effects into restricted Yul
  -> replayed Yul matches Lean-owned Counter Yul
  -> normalized summary also matches Lean-owned Counter Yul
```

## What Changed

The solc function summary now exports:

- `trace`: the line-by-line rule/effect ledger.
- `traceReplay`: restricted Yul reconstructed only from trace effects.
- `traceReplayMatchesNormalized`: a consistency bit checked inside the
  summarizer.

`scripts/check_counter_bridge.py` adds a bridge check:

```text
solcTraceReplayToLeanYul
```

That check passes only when the replayed trace matches the Lean-exported
`CounterYul.counterProgram` artifact.

## Trust Boundary

This reduces one failure mode: the report can no longer show a nice trace while
quietly comparing a different normalized Yul object to Lean. The trace effects
themselves are still produced by trusted Python recognizer code.

Remaining trusted boundaries:

- `hexLiteralAsNat` remains parser-level trust.
- The Solidity parser is Counter-only and trusted.
- The solc IR recognizer/summarizer is trusted Python pattern recognition.
- The trace replay checker is Python test/audit infrastructure, not a Lean
  theorem.
- Full solc wrappers, ABI dispatch, memory, calls, gas, events, and EVM
  semantics remain unsupported.

## Checked Artifact

The bridge report is now `reportVersion: 5` and is checked against:

```text
tests/golden/Counter.bridge.v5.json
```

That fixture is generated from the checked Counter Solidity file and the solc IR
fixture embedded in the Python tests, not from local `build/` artifacts.
