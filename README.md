# SoLean

SoLean is a small research/engineering prototype for AI-assisted formal
verification of Solidity and DeFi code using Lean 4.

The project is intentionally narrow. The first goal is not to verify arbitrary
Solidity. The first goal is to build a clean, inspectable skeleton around tiny
case studies, starting with `Counter` and then `SimpleVault`.

## Planned Pipeline

The intended long-term loop is:

1. Compile Solidity with `solc` to Yul1.
2. Write or generate an equivalent SoLean program.
3. Prove a specification about the SoLean representation in Lean 4.
4. Compile SoLean back to Yul2.
5. Check that Yul1 and Yul2 are equivalent for a restricted subset.

Today, the proof side has checked-arithmetic semantics for small hand-written
models. The Yul pipeline remains placeholder tooling.

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
- A `SimpleVault` model with successful-execution preservation proofs for
  `totalAssets >= totalShares`.
- Solidity examples in `examples/`.
- Python placeholder tools for:
  - Solidity to Yul via `solc`.
  - SoLean to Yul-like text for `Counter`.
  - Yul text normalization.
  - Normalized-text equivalence checking.
- GitHub Actions CI that runs `lake build`, Python bytecode checks, and Python
  unit tests.

## Trusted Components

For the current prototype, the trusted base includes:

- Lean's kernel and the Lake/Lean toolchain.
- The hand-written SoLean model matching the intended Solidity fragment.
- The small-step choices encoded in `SoLean.Semantics`.
- `solc`, when used to produce Yul IR.
- The placeholder Python scripts, where their behavior is used.

The project does not yet establish that the Solidity source, solc Yul, SoLean
model, and emitted Yul all have the same semantics.

## Not Supported Yet

- EVM wraparound arithmetic.
- ABI decoding, calldata, memory, events, external calls, gas, reentrancy, or
  contract creation.
- Parsing Solidity or Yul into verified syntax trees.
- Generated SoLean from Solidity.
- Generated Yul from arbitrary SoLean.
- Semantic Yul equivalence.
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
│   ├── counter.md
│   └── simple-vault.md
├── SoLean.lean
├── SoLean/
│   ├── Basic.lean
│   ├── UInt256.lean
│   ├── DSL.lean
│   ├── Semantics.lean
│   ├── Specs.lean
│   └── Examples/
│       ├── Counter.lean
│       └── SimpleVault.lean
├── examples/
│   ├── Counter.sol
│   └── SimpleVault.sol
├── scripts/
│   ├── solc_to_yul.py
│   ├── solean_to_yul.py
│   ├── normalize_yul.py
│   └── check_equiv.py
└── tests/
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
SoLean/Examples/SimpleVault.lean
```

## Running The Scripts

Compile Solidity to Yul IR, if `solc` is installed:

```bash
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.yul
```

Emit placeholder SoLean-derived Yul-like text for `Counter`:

```bash
mkdir -p build
python3 scripts/solean_to_yul.py --example counter -o build/Counter.solean.yul
```

Normalize Yul-like text:

```bash
python3 scripts/normalize_yul.py build/Counter.solean.yul
```

Compare two Yul files using the current textual checker:

```bash
python3 scripts/check_equiv.py build/Counter.yul build/Counter.solean.yul --diff
```

This comparison is not a semantic equivalence proof. It only compares normalized
text and is expected to be replaced.

Run the Python tests:

```bash
python3 -m unittest discover -s tests
```

## Next Milestones

1. Continue extracting reusable proof lemmas from the Counter and SimpleVault
   examples.
2. Parse or ingest a small structured Solidity/Yul subset instead of relying on
   hand-written models.
3. Replace textual Yul comparison with a restricted semantic equivalence
   checker.
4. Add generated artifacts only when they are deterministic and easy to audit.
