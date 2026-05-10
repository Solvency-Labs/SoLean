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

Today, only the skeleton exists. The proof side is real Lean code for the
manual `Counter` model; the Yul pipeline is placeholder tooling.

## What Exists Now

- A Lake-based Lean 4 project.
- A minimal SoLean DSL:
  - `UInt256` modeled as `Nat`.
  - Storage modeled as `Slot -> UInt256`.
  - An environment with `msg.sender`.
  - Statements for `require`, `assert`, assignment, sequencing, and skip.
  - Execution results as success with storage or revert with a failure kind.
- A manual SoLean model of `Counter.inc`.
- A theorem showing that if modeled `Counter.inc(amount)` succeeds, then the
  final modeled `x` is at least `amount`.
- A first-pass `SimpleVault` model with TODOs for invariant proofs.
- Solidity examples in `examples/`.
- Python placeholder tools for:
  - Solidity to Yul via `solc`.
  - SoLean to Yul-like text for `Counter`.
  - Yul text normalization.
  - Normalized-text equivalence checking.
- GitHub Actions CI that runs `lake build` and Python bytecode checks.

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

- Real `uint256` overflow and wraparound.
- Solidity 0.8.x checked arithmetic semantics beyond manual guards.
- ABI decoding, calldata, memory, events, external calls, gas, reentrancy, or
  contract creation.
- Parsing Solidity or Yul into verified syntax trees.
- Generated SoLean from Solidity.
- Generated Yul from arbitrary SoLean.
- Semantic Yul equivalence.
- Broad Solidity or DeFi verification claims.

`UInt256` is currently `Nat`, and Lean's `Nat` subtraction saturates at zero.
Every case study that relies on this approximation must say so.

## Repository Layout

```text
.
├── AGENTS.md
├── .gitignore
├── README.md
├── lakefile.lean
├── lean-toolchain
├── pyproject.toml
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
    └── README.md
```

## Running Lean

Install Lean with `elan`, then run:

```bash
lake build
```

The central proof currently lives in:

```text
SoLean/Examples/Counter.lean
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

## Next Milestones

1. Add a precise checked-arithmetic model for the subset of Solidity `uint256`
   used in the examples.
2. Strengthen the Counter model with explicit pre/post specifications.
3. Prove the SimpleVault invariant for deposit and withdraw under stated
   assumptions.
4. Parse or ingest a small structured Solidity/Yul subset instead of relying on
   hand-written models.
5. Replace textual Yul comparison with a restricted semantic equivalence
   checker.
6. Add generated artifacts only when they are deterministic and easy to audit.
