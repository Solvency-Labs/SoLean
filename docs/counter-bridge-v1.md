# Counter Bridge v1

`Counter Bridge v1` is the first named trust-reduction milestone for SoLean.
It defines what "connected" means for the Counter example without pretending
that Solidity parsing or real Yul equivalence has been solved.

## Success Condition

The intended checked path is:

```text
examples/Counter.sol
  -> Python Counter parser
  -> canonical source-shape JSON
  -> matches Lean-owned Counter source artifact
  -> Lean proves Counter source compiles/refines restricted Yul
  -> Python emitted Yul matches Lean-owned Yul artifact
  -> real solc IR is classified with explicit unsupported blockers
```

Each arrow has a different trust level:

- `Counter.sol -> Python Counter parser` is trusted deterministic parsing for a
  tiny exact Solidity subset. Unsupported Solidity must be rejected loudly.
- `source-shape JSON -> Lean-owned Counter source artifact` is tested by Python
  against JSON exported from Lean.
- `Lean source -> restricted Lean Yul` is proved in Lean for the current Counter
  compiler slice.
- `Python emitted Yul -> Lean-owned Yul artifact` is tested structurally against
  JSON exported from Lean, plus a text golden for deterministic rendering.
- `real solc IR -> unsupported blocker report` is classification only. It does
  not prove equivalence.

## Current Status

Implemented:

- Lean exports `counterFunction` and `counterProgram` audit artifacts via:

  ```bash
  lake env lean --run SoLean/CounterArtifactsMain.lean source-json
  lake env lean --run SoLean/CounterArtifactsMain.lean yul-json
  ```

- Python tests compare the Counter Solidity source-shape projection to the
  Lean-exported source artifact.
- Python tests compare the structured Counter Yul emitter shape to the
  Lean-exported Yul artifact.
- The default Yul checker now compares symbolic state-transform summaries for
  supported restricted Yul programs.
- `scripts/classify_yul.py --inspect-solc` selects the deployed object in
  solc-style IR and reports the first unsupported construct inside it.

Not implemented:

- Verified Solidity parsing.
- Verified translation from Solidity text to the Lean source language.
- Verified rendering from Lean Yul data to Python text.
- Parsing real solc IR into the restricted Lean Yul model.
- Semantic equivalence against real solc Yul.

## Current Solc Boundary

For `solc 0.8.35 --ir` on `examples/Counter.sol`, the default classifier still
rejects the outer solc wrapper. The solc inspection mode gets one boundary
further: it identifies the deployed object and reports memory setup such as
`mstore(64, memoryguard(128))` as the first unsupported construct.

That is progress, but it is still classification rather than verification. The
next useful boundary is to inspect the actual `fun_inc_*` body and name the
first unsupported function-body construct.
