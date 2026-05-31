# SoLean — status & inventory

The detailed "what exists" record, moved off the README. For the plan and
current direction see the [learn-site
roadmap](https://solvency-labs.github.io/solean-learn/project/roadmap/); for the
short summary see the top-level `README.md`.

## What exists now

- A Lake-based Lean 4 project with a focused **SoLean DSL**: `UInt256` as a
  bounded natural-number structure, storage as `Slot -> UInt256`, an environment
  with `msg.sender` and an abstract verifier oracle, statements for
  `require`/`assert`/assignment/sequencing/skip, and execution results as success
  (with storage) or revert (with a failure kind, including arithmetic failure).

### Counter calibration (source → Yul bridge, in isolation)

- A manual SoLean model of `Counter.inc` and a theorem: successful
  `Counter.inc(amount)` implies final `x >= amount`.
- A restricted Yul AST + execution semantics in Lean, a hand-written restricted
  Yul model of `Counter.inc`, and theorems linking SoLean execution to the Yul
  model (same final storage; Yul-side `x >= amount`).
- A parameter-aware source language and partial compiler to restricted Lean Yul
  for the Counter pattern, with an instantiation theorem tying the generic source
  function to the SoLean model and the emitted Yul program.
- Lean-owned Counter source and restricted-Yul audit artifacts exported from the
  proved shapes. Current bridge certificate boundary: `docs/counter-bridge-v7.md`.
- A `SimpleVault` model with `totalAssets >= totalShares` preservation proofs.

### AA/PQ verified surface (the current core)

- **`AAWallet`** validation model: successful validation implies the entry-point,
  nonce, domain, and abstract verifier checks passed and the nonce advanced
  through checked arithmetic; plus `executeUserOp` and a `fullFlow` composition
  with no-bypass and observable-side-effect gate theorems.
- **`PQVerifierWrapper`**: successful wrapper validation implies key-length,
  signature-length, domain, and verifier checks passed. *This is the oracle a
  finished FORS proof discharges* (`docs/pq-verifier-wrapper-v0.md`).
- **`AAPQIntegration`**: integrated validation connects wrapper + wallet checks
  over the same verifier tuple, with safety theorems — `noBypass_implies_
  verifier_accepted`, `replay_rejected_after_success`, and three under named
  non-cryptographic oracle assumptions (`VerifierDomainSeparation`,
  `VerifierSignatureBinding`, `VerifierKeySeparation`). Integrated execution
  gating via `validateAndExecute` with matching gate/contrapositive theorems.
- **Coverage/audit theorems** pinning that every `*_under_oracle_assumption`
  theorem is registered (`integratedCryptoAssumptions_cover_all_oracle_theorems`)
  and a directed support graph from assumptions to theorems.
- **`ToyVerifier`** calibrations (`allFieldsEqualVerifier`,
  `keyDomainBindingVerifier`, `DerivedSignatureModel`) proved to satisfy the
  three oracle assumptions.
- **`AAPQSource`** Solidity-shaped two-contract description with instantiation
  theorems back to the proved programs, behavior-summary / source-certificate /
  trace-manifest artifacts (structured `Condition`/`ValueExpression` DSL), and
  `BehaviorReflection` proving each summary phase reconstructs the proved program
  (down to full execution-result equivalence).
- **EVM-call boundary** (`SoLean.EVM.Call`): a first-cut `CALL` boundary
  (calldata/returndata/CallResult/selector/gas) with `validateIntegratedViaEvmCall`
  proved equivalent to the direct composition under `WrapperOracleConsistent`,
  selector/length-rejection proofs, and a gas-aware variant. Partially retires the
  external-call / gas / ABI-shape / wallet-no-reentrancy non-claims — *not* full
  EVM CALL.

### Tooling

- An AA/PQ source-shape audit (`scripts/check_aapq_source.py`) cross-checking the
  Lean-owned artifacts against a restricted Solidity sketch, with a Lean-owned v1
  trace manifest and a golden fixture (`tests/golden/AAPQ.source.v8.json`).
- Python placeholder tools: Solidity→Yul via `solc`, Yul-subset classification,
  SoLean→restricted-Yul text for Counter, structural checks vs Lean-exported
  artifacts, normalization, and a restricted symbolic state-transform comparator.
- GitHub Actions CI: `lake build`, Python bytecode checks, Python unit tests.

## Trusted components

Lean's kernel + Lake/Lean toolchain; the hand-written SoLean and restricted-Yul
models matching their intended fragments; the Lean Counter compiler; the
small-step choices in `SoLean.Semantics` and `SoLean.Yul`; `solc` when used; and
the placeholder Python scripts where their behavior is used. **The project does
not yet establish that Solidity source, SoLean model, Python emitter output, and
solc Yul all share semantics.**

## Not supported yet

Full EVM wraparound arithmetic (only wrapping `add` in the Yul model); ABI
decoding / calldata / memory / events / general external calls / gas / reentrancy
/ contract creation; verified Solidity or Yul parsing; generated SoLean from
Solidity; generated Yul from arbitrary SoLean; semantic Yul equivalence; verified
emitter↔Lean correspondence; full ERC-4337 or PQ-wrapper contract semantics
beyond the abstract models; PQ cryptographic security; broad Solidity/DeFi claims.

## Repository layout

```text
SoLean/            Lean sources (DSL, Semantics, Yul, Compiler, Artifacts, Examples/)
examples/          Solidity sketches (documentation fixtures, not parser targets)
scripts/           Python bridge tooling (solc→yul, classify, check_*, demos)
tests/             Python tests + golden fixtures
docs/              Current docs (this file, assumptions, model docs); archive/ for history
```

Core proofs: `SoLean/Examples/{AAWallet,PQVerifierWrapper,AAPQIntegration,Counter,CounterCompiler,CounterYul,SimpleVault}.lean`.

## Running the scripts

```bash
# Solidity → Yul IR (needs solc 0.8.35, e.g. via solc-select)
python3 scripts/solc_to_yul.py examples/Counter.sol -o build/Counter.solc.yul

# Counter bridge audit (JSON / markdown)
python3 scripts/check_counter_bridge.py --solidity examples/Counter.sol --solc-yul build/Counter.solc.yul

# AA/PQ source-shape audit + demo
python3 scripts/check_aapq_source.py          # add --format markdown
python3 scripts/demo_aapq_source.py

# Export Lean-owned audit artifacts
lake env lean --run SoLean/AAPQArtifactsMain.lean source-certificate-json
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```

These emit deterministic JSON tying the trusted Solidity projection + Python
emitter + solc summary back to Lean-owned artifacts. A passing report is an
audit/regression signal, **not** a proof of Solidity parsing or semantic
equivalence. Full command set: see `git log` / the archived counter-bridge docs.
