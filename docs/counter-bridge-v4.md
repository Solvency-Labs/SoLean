# Counter Bridge v4

`Counter Bridge v4` makes the trusted solc function summary auditable line by
line. The summary is still trusted Python recognizer code, but it now emits a
structured trace that explains which solc line triggered which bridge rule, what
restricted-Yul effect was produced, and which Lean proof backs that rule when
one exists.

This is still not verified Solidity parsing, verified solc parsing, or semantic
equivalence with real solc Yul.

Bridge v4.1 stabilizes this report as a checked audit artifact. The JSON report
now carries `reportVersion: 4`, and tests compare the fixture-backed report with
`tests/golden/Counter.bridge.v4.json`. That golden file is a regression target
for the audit boundary; it is not a proof about real solc semantics.

## Success Condition

```text
real solc Counter fun_inc_*
  -> trusted Python recognizer
  -> deterministic rule trace
  -> Lean proof links for non-hex rule effects
  -> normalized restricted Yul matches Lean-owned Counter Yul
```

## Trace Shape

`scripts/classify_yul.py --summarize-function inc build/Counter.solc.yul`
emits the existing summary fields plus a `trace` array. Each trace entry has:

- `sourceLine`: normalized line number in the selected solc runtime object.
- `source`: normalized solc source line.
- `rule`: bridge rule name.
- `effect`: deterministic JSON describing the restricted-Yul effect.
- `leanProof`: Lean theorem name, or the empty string for parser-level trust.

`hexLiteralAsNat` is intentionally the only current rule with an empty
`leanProof`. It is parser-level trust: Lean receives the already-parsed literal
value and does not verify Python string parsing.

## Checked Report Artifact

`scripts/check_counter_bridge.py` emits a deterministic JSON shape with:

- `reportVersion: 4`
- Lean artifact names and hashes
- bridge checks and statuses
- the Lean-owned expected rule list and proof references
- the solc summary trace
- explicit limitations

The committed golden report is generated from the checked Counter Solidity file
and the solc IR fixture embedded in the Python tests, not from local
`build/` artifacts. If the report shape, Lean artifact hashes, bridge manifest,
or solc summary trace changes, the golden test fails and forces a reviewer to
look at the boundary change.

## Trust Boundary

The bridge report is now easier to audit because a reviewer can inspect:

```text
solc line -> named bridge rule -> restricted-Yul effect -> Lean proof reference
```

The remaining trusted boundaries are still explicit:

- `hexLiteralAsNat` remains parser-level trust.
- The Solidity parser is Counter-only and trusted.
- The solc IR recognizer/summarizer is trusted Python pattern recognition.
- Real solc deployment wrappers, ABI dispatch, memory setup, helper bodies, and
  full Yul/EVM semantics are outside the current verified model.
- Passing the bridge report is not semantic equivalence between real solc Yul
  and SoLean-generated Yul.

## Commands

```bash
python3 scripts/classify_yul.py --summarize-function inc build/Counter.solc.yul
python3 scripts/check_counter_bridge.py \
  --format markdown \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
python3 scripts/demo_counter_bridge.py
```
