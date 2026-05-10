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
  - SoLean to restricted Yul-like text for `Counter`.
  - Yul text normalization.
  - Restricted-subset bounded trace comparison, with strict AST and
    normalized-text modes as explicit fallbacks.
  - Counter-only Solidity-to-SoLean sketching through a tiny explicit parser.
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
- Verified parsing of Solidity or Yul.
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
│   ├── simple-vault.md
│   └── yul-subset.md
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
│   ├── check_equiv.py
│   ├── solidity_to_solean.py
│   └── yul_subset.py
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
mkdir -p build
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.yul
```

For reproducible local compiler setup, install `solc 0.8.20`. The recommended
version-manager path is `solc-select`:

```bash
python3 -m pip install solc-select
solc-select install 0.8.20
solc-select use 0.8.20
solc --version
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

Compare two Yul files using the current bounded restricted-subset trace checker:

```bash
python3 scripts/check_equiv.py build/Counter.yul build/Counter.solean.yul --diff
```

By default, this parses the restricted Yul subset documented in
`docs/yul-subset.md` and compares a finite set of Counter-shaped execution
traces. This is useful smoke-test tooling, not a semantic equivalence proof.
Strict AST equality is available with `--ast`, and the old normalized-text
comparison is still available with `--text`.

Sketch the exact Counter Solidity example into a Lean reference:

```bash
python3 scripts/solidity_to_solean.py examples/Counter.sol
```

This is not a general Solidity parser. It tokenizes and validates only a tiny
Counter subset and rejects unsupported input.

Run the Python tests:

```bash
python3 -m unittest discover -s tests
```

## Next Milestones

1. Continue extracting reusable proof lemmas from the Counter and SimpleVault
   examples.
2. Expand the Counter-only Solidity subset only as needed by the proof path.
3. Replace bounded trace comparison with a small semantic equivalence checker
   for the supported Yul subset.
4. Add generated artifacts only when they are deterministic and easy to audit.
