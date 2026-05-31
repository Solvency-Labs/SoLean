# Counter Research Demo

This is the current presentation-grade Counter demo for SoLean. It is designed
to show a real Lean-proved core and an auditable bridge to pinned `solc`
output, without claiming full Solidity verification or real Yul equivalence.

## One-Command Demo

Run:

```bash
python3 scripts/demo_counter_bridge.py
```

The demo runs:

- `lake build`
- bridge-focused Python tests
- Lean artifact export smoke checks for `source-json`,
  `source-certificate-json`, `yul-json`, `trace-skeleton-json`, and
  `bridge-json`, and `behavior-summary-json`
- the Counter bridge report in Markdown mode if `build/Counter.solc.yul`
  exists

If local solc IR is missing, the demo skips only the real-solc boundary and
prints the exact generation command:

```bash
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul
```

## Architecture

```mermaid
flowchart TD
  Sol["examples/Counter.sol"] --> PySol["trusted Python Counter parser"]
  PySol --> SrcJson["canonical source JSON"]
  LeanSrc["Lean Counter source artifact"] --> Proof["Lean Counter proofs"]
  SrcJson --> SrcCheck["source artifact check"]
  LeanSrc --> SrcCheck
  LeanSrc --> Compiler["tiny Lean compiler"]
  Compiler --> LeanYul["Lean-owned restricted Counter Yul"]
  LeanYul --> Proof
  PyEmit["Python / Lean-artifact Yul rendering"] --> EmitCheck["Yul artifact check"]
  LeanYul --> EmitCheck
  Solc["solc 0.8.35 --ir"] --> Summary["trusted Counter fun_inc_* summary"]
  Summary --> SolcCheck["summary equals Lean Yul artifact"]
  LeanYul --> SolcCheck
  Manifest["Lean bridge manifest"] --> RuleCheck["trusted-rule check"]
  Summary --> RuleCheck
```

## Current Claims

The demo supports this claim:

```text
For Counter, the Lean-owned source and restricted Yul artifacts are proved
inside Lean, and the Solidity parser, Python/Lean-artifact Yul rendering, and
trusted solc function summary all align with those Lean-owned artifacts.
```

The current Counter bridge rules now have Lean-backed semantic models for every
semantic helper rewrite except hex-literal parsing:

- `cleanupUint256AsIdentity`
- `convertRationalZeroByOneToUint256AsIdentity`
- `requireHelperAsRevertGuard`
- `storageReadSlot0AsSload`
- `checkedAddUInt256AsAddWithOverflowGuard`
- `storageUpdateSlot0AsSstore`
- `assertHelperAsRevertGuard`

The exact proof names are exported in the Lean-owned `bridge-json` manifest.
The solc function summary also emits a line-by-line trace that maps normalized
solc lines to bridge rules, restricted-Yul effects, and Lean proof references
when available.

Bridge v6 replays those trace effects back into restricted Yul, checks the
replayed program against the Lean-owned Counter Yul artifact, checks the trace
skeleton against a Lean-owned skeleton, and checks the accepted Solidity source
certificate against a Lean-owned certificate. Bridge v7 adds a Lean-owned
restricted behavior summary (function parameter, ordered revert guards, and
final slot-0 write) and checks Python's symbolic state-transform summary of
the emitted Counter Yul against that Lean-owned summary. The bridge report
JSON is versioned as `reportVersion: 7` and checked against
`tests/golden/Counter.bridge.v7.json`. That fixture is a presentation/audit
regression artifact: it makes the current Counter boundary stable enough to
review, but it does not turn the trusted Python recognizers into verified code.

## Non-Claims

The demo does not claim:

- verified Solidity parsing
- verified Python solc-IR parsing
- full Yul or EVM semantics
- semantic equivalence between real `solc` Yul and SoLean-generated Yul
- SimpleVault compilation to Yul
- support for ABI decoding, memory, calls, gas, events, reentrancy, or contract
  creation

The most important non-claim is:

```text
Yul_1 = real solc output
Yul_2 = SoLean output
Lean proves Yul_1 ≈ Yul_2
```

That is not implemented yet.

## Remaining Trusted Rules

These Counter solc summary rules are still trusted Python pattern recognition:

- `hexLiteralAsNat`

The transparent helper bundle from Bridge v2 has been split into concrete rule
names. Bridge v4 keeps `hexLiteralAsNat` as explicit parser-level trust and
hard-tests the narrow hex literal parser behavior.

## Useful Commands

Render the Counter Yul from the Lean-owned artifact:

```bash
python3 scripts/solean_to_yul.py --example counter --source lean-artifact
```

Run the bridge report as Markdown:

```bash
python3 scripts/check_counter_bridge.py \
  --format markdown \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
```

Export the Lean bridge manifest:

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```
