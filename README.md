# SoLean

SoLean is a small research/engineering prototype for AI-assisted formal
verification of Solidity and DeFi code using Lean 4.

The project is intentionally narrow. The first goal is not to verify arbitrary
Solidity. The first goal is to build a clean, inspectable skeleton around tiny
case studies, starting with `Counter` and then `SimpleVault`.

## Planned Pipeline

The sharper north star is traceable trust reduction: build a boundary-aware
verification pipeline where a tiny Solidity subset can be connected to a Lean
model, proved, compiled to restricted Yul, and compared against pinned `solc`
output, with every trusted step explicitly identified.

The intended long-term loop is:

1. Compile Solidity with `solc` to Yul1.
2. Write or generate an equivalent SoLean program.
3. Prove a specification about the SoLean representation in Lean 4.
4. Compile SoLean back to Yul2.
5. Check that Yul1 and Yul2 are equivalent for a restricted subset.

Today, the proof side has checked-arithmetic semantics for small hand-written
models, a tiny Lean model of the restricted Counter Yul path, and a tiny
verified Counter compiler slice. The broader Solidity and Yul pipeline remains
placeholder tooling.

For the current intuition and next steps, see `docs/roadmap.md`. For the exact
Counter bridge success condition, see `docs/counter-bridge-v1.md`.

## What Exists Now

- A Lake-based Lean 4 project.
- A minimal SoLean DSL:
  - `UInt256` modeled as a bounded natural-number structure.
  - Storage modeled as `Slot -> UInt256`.
  - An environment with `msg.sender`.
  - Statements for `require`, `assert`, assignment, sequencing, and skip.
  - Execution results as success with storage or revert with a failure kind,
    including arithmetic failure.
- A manual SoLean model of `Counter.inc`.
- A theorem showing that if modeled `Counter.inc(amount)` succeeds, then the
  final modeled `x` is at least `amount`.
- A tiny restricted Yul AST and execution semantics in Lean.
- A hand-written restricted Yul model of `Counter.inc`, with a theorem showing
  that successful SoLean Counter executions are reproduced by the restricted Yul
  model with the same final storage.
- A Yul-side Counter theorem showing successful restricted Yul execution implies
  the final modeled `x` is at least `amount`.
- A tiny parameter-aware source language and partial compiler to restricted
  Lean Yul for the Counter pattern.
- A theorem showing the generic Counter source function instantiates to the
  existing SoLean Counter model and compiles to the existing restricted Yul
  Counter program.
- Lean-owned Counter source and restricted-Yul audit artifacts exported from
  the proved Counter shapes.
- A `SimpleVault` model with successful-execution preservation proofs for
  `totalAssets >= totalShares`.
- Solidity examples in `examples/`.
- Python placeholder tools for:
  - Solidity to Yul via `solc`.
  - Yul subset classification for supported/unsupported compiler output.
  - SoLean to restricted Yul-like text for `Counter`.
  - Counter Yul structural checks against a Lean-exported Counter Yul artifact.
  - Counter Solidity source-shape JSON aligned with a Lean-exported
    `CounterCompiler.counterFunction` artifact.
  - Yul text normalization.
  - Restricted-subset symbolic state-transform comparison, with bounded trace,
    strict AST, and normalized-text modes as explicit fallbacks.
  - Counter-only Solidity-to-SoLean sketching through a tiny explicit parser.
- GitHub Actions CI that runs `lake build`, Python bytecode checks, and Python
  unit tests.

## Trusted Components

For the current prototype, the trusted base includes:

- Lean's kernel and the Lake/Lean toolchain.
- The hand-written SoLean model matching the intended Solidity fragment.
- The hand-written restricted Yul model matching the intended Counter emitter.
- The tiny Counter compiler implemented in Lean.
- The small-step choices encoded in `SoLean.Semantics`.
- The restricted Yul semantics encoded in `SoLean.Yul`.
- `solc`, when used to produce Yul IR.
- The placeholder Python scripts, where their behavior is used.

The project does not yet establish that the Solidity source, SoLean model,
Python emitter output, and solc Yul all have the same semantics.

## Not Supported Yet

- Full EVM wraparound arithmetic in the SoLean DSL. The restricted Lean Yul
  model currently covers only wrapping `add`.
- ABI decoding, calldata, memory, events, external calls, gas, reentrancy, or
  contract creation.
- Verified parsing of Solidity or Yul.
- Generated SoLean from Solidity.
- Generated Yul from arbitrary SoLean.
- Semantic Yul equivalence.
- Verified correspondence between the Python Yul emitter and the Lean Yul data.
  Python tests currently check alignment against Lean-exported artifacts, not a
  proof.
- Verified Solidity-to-source-language translation.
  Python tests currently check Counter source-shape alignment against a
  Lean-exported artifact, not a proof.
- Broad Solidity or DeFi verification claims.

Checked addition and subtraction are modeled for the current expression DSL.
Stored values are type-enforced as bounded `UInt256` values, but the model is
still a small Solidity subset rather than an EVM semantics.

## Repository Layout

```text
.
├── AGENTS.md
├── .gitignore
├── README.md
├── lakefile.lean
├── lean-toolchain
├── pyproject.toml
├── docs/
│   ├── assumptions.md
│   ├── compiler.md
│   ├── counter-bridge-v1.md
│   ├── counter-bridge-v2.md
│   ├── counter-bridge-v3.md
│   ├── counter-bridge-v4.md
│   ├── counter-demo.md
│   ├── counter-yul.md
│   ├── counter.md
│   ├── roadmap.md
│   ├── simple-vault.md
│   └── yul-subset.md
├── SoLean.lean
├── SoLean/
│   ├── Basic.lean
│   ├── UInt256.lean
│   ├── DSL.lean
│   ├── Semantics.lean
│   ├── Specs.lean
│   ├── Compiler.lean
│   ├── Yul.lean
│   ├── Artifacts.lean
│   ├── CounterArtifactsMain.lean
│   └── Examples/
│       ├── Counter.lean
│       ├── CounterCompiler.lean
│       ├── CounterYul.lean
│       └── SimpleVault.lean
├── examples/
│   ├── Counter.sol
│   └── SimpleVault.sol
├── scripts/
│   ├── solc_to_yul.py
│   ├── solean_to_yul.py
│   ├── normalize_yul.py
│   ├── classify_yul.py
│   ├── check_equiv.py
│   ├── check_counter_bridge.py
│   ├── demo_counter_bridge.py
│   ├── solidity_to_solean.py
│   └── yul_subset.py
└── tests/
    ├── golden/
    │   ├── Counter.bridge.v4.json
    │   └── Counter.solean.yul
    ├── README.md
    └── test_yul_tools.py
```

## Running Lean

Install Lean with `elan`, then run:

```bash
lake build
```

If `lake` is installed under `elan` but not on your shell path, either add
`$HOME/.elan/bin` to `PATH` or run:

```bash
/Users/ricardoperello/.elan/bin/lake build
```

The main proof files currently live in:

```text
SoLean/Examples/Counter.lean
SoLean/Examples/CounterCompiler.lean
SoLean/Examples/CounterYul.lean
SoLean/Examples/SimpleVault.lean
```

## Running The Scripts

Compile Solidity to Yul IR, if `solc` is installed:

```bash
mkdir -p build
PATH="$(python3 -m site --user-base)/bin:$PATH" \
  python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul
```

For reproducible local compiler setup, install `solc 0.8.35`. This is SoLean's
current stable compiler target, not a proof-relevant semantic assumption. The
recommended version-manager path is `solc-select`:

```bash
python3 -m pip install solc-select
solc-select install 0.8.35
solc-select use 0.8.35
solc --version
```

If `solc-select` is installed with `--user` and not on `PATH`, use:

```bash
PATH="$(python3 -m site --user-base)/bin:$PATH" solc --version
```

Generated `build/` artifacts are intentionally uncommitted until the compiler
version and artifact workflow are pinned in CI.

Emit placeholder SoLean-derived Yul-like text for `Counter`:

```bash
mkdir -p build
python3 scripts/solean_to_yul.py --example counter -o build/Counter.solean.yul
```

Normalize Yul-like text:

```bash
python3 scripts/normalize_yul.py build/Counter.solean.yul
```

Classify a Yul file against the current restricted subset:

```bash
python3 scripts/classify_yul.py build/Counter.solean.yul
python3 scripts/classify_yul.py build/Counter.solc.yul
```

Real `solc 0.8.35 --ir` Counter output is currently expected to classify as
unsupported; the first observed blocker is solc's `IR:` preamble/wrapper before
the object accepted by the restricted parser.

Inspect solc-style IR and select the deployed/runtime object before
classification:

```bash
python3 scripts/classify_yul.py --inspect-solc build/Counter.solc.yul
```

This still does not claim equivalence. It is an auditable extraction aid that
reports the next unsupported construct inside the selected object.

Inspect the generated Counter function body inside solc IR:

```bash
python3 scripts/classify_yul.py --inspect-function inc build/Counter.solc.yul
```

This currently selects `fun_inc_*` in the deployed object and reports the first
unsupported function-body construct.

Summarize the generated Counter function body into the current canonical
restricted Counter Yul shape:

```bash
python3 scripts/classify_yul.py --summarize-function inc build/Counter.solc.yul
```

This is a trusted, Counter-specific inspection summary. It checks structural
alignment with the Lean-owned Counter Yul shape in tests, but it is not a proof
of semantic equivalence with real solc IR.

Run the current Counter bridge audit:

```bash
python3 scripts/check_counter_bridge.py \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
```

For a presentation-friendly version:

```bash
python3 scripts/check_counter_bridge.py \
  --format markdown \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
```

This emits deterministic JSON tying the trusted Solidity source projection,
Python Counter Yul emitter, and trusted solc `fun_inc_*` summary back to
Lean-owned artifacts. It also checks the observed solc summary rules against a
Lean-owned bridge manifest. A passing report is an audit/regression signal, not
a proof of Solidity parsing or semantic equivalence with solc output. See
`docs/counter-bridge-v4.md` for the current line-auditable bridge boundary. The
JSON report is versioned as `reportVersion: 4` and checked against
`tests/golden/Counter.bridge.v4.json` in the Python test suite.

Run the full Counter research demo:

```bash
python3 scripts/demo_counter_bridge.py
```

The demo runs Lean/Python checks and, when local solc IR exists, prints the
Markdown bridge report. See `docs/counter-demo.md`.

Compare two Yul files using the current symbolic restricted-subset
state-transform checker:

```bash
python3 scripts/check_equiv.py build/Counter.yul build/Counter.solean.yul --diff
```

By default, this parses the restricted Yul subset documented in
`docs/yul-subset.md` and compares a tiny symbolic summary of parameters,
ordered revert conditions, and final storage writes. This is useful
state-transform tooling for the restricted subset, not a semantic equivalence
proof. The old bounded trace checker is available with `--bounded-traces`,
strict AST equality with `--ast`, and normalized-text comparison with `--text`.

Sketch the exact Counter Solidity example into a Lean reference:

```bash
python3 scripts/solidity_to_solean.py examples/Counter.sol
```

This is not a general Solidity parser. It tokenizes and validates only a tiny
Counter subset and rejects unsupported input.

Emit the same parsed Counter shape as deterministic JSON:

```bash
python3 scripts/solidity_to_solean.py --format source-json examples/Counter.sol
```

This JSON is an audit/test artifact that is checked against the Lean-exported
`CounterCompiler.counterFunction` shape; it is not a verified parser output.

Export the Lean-owned Counter audit artifacts:

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean source-json
lake env lean --run SoLean/CounterArtifactsMain.lean yul-json
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```

Python tests compare the Solidity source projection and Python Yul emitter
shape against these Lean-exported artifacts. The Counter bridge report also
compares the observed solc summary rule list against the Lean-exported bridge
manifest.

Render the Counter restricted Yul from the Lean-owned Yul artifact:

```bash
python3 scripts/solean_to_yul.py --example counter --source lean-artifact
```

Run the Python tests:

```bash
python3 -m unittest discover -s tests
```

## Next Milestones

The living roadmap is in `docs/roadmap.md`. Keep that file updated as proof
boundaries move from manual assumptions into checked Lean artifacts.
