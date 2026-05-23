# SoLean

SoLean is a focused research/engineering prototype for AI-assisted formal
verification of Solidity contract logic using Lean 4.

The project is intentionally scope-controlled. The first goal is not to verify
arbitrary Solidity. The first goal is to build a clean, inspectable skeleton
around calibrated case studies. `Counter` is the calibration case for the
Solidity/Lean/Yul bridge. The strategic research target is now
account-abstraction wallet
validation and post-quantum signature verifier-wrapper contracts, with ERC-20
used only as an optional calibration case.

## Planned Pipeline

The sharper north star is traceable trust reduction: build a boundary-aware
verification pipeline where a restricted Solidity subset can be connected to a
Lean model, proved, compiled to restricted Yul, and compared against pinned `solc`
output, with every trusted step explicitly identified.

The near-term application target is PQ account abstraction:

```text
AA wallet validation logic
  -> PQ verifier-wrapper contract
  -> integration proof that execution requires modeled PQ authentication,
     nonce validity, and domain binding
```

SoLean should verify the contract logic around PQ authentication. It does not
currently verify the cryptographic security of a PQ signature scheme.

The intended long-term loop is:

1. Compile Solidity with `solc` to Yul1.
2. Write or generate an equivalent SoLean program.
3. Prove a specification about the SoLean representation in Lean 4.
4. Compile SoLean back to Yul2.
5. Check that Yul1 and Yul2 are equivalent for a restricted subset.

Today, the proof side has checked-arithmetic semantics for focused hand-written
models, a restricted Lean model of the Counter Yul path, and a focused verified
Counter compiler slice. The broader Solidity and Yul pipeline remains
placeholder tooling.

For the current intuition and next steps, see `docs/roadmap.md` and
`docs/pq-aa-roadmap.md`. For the exact Counter bridge success condition, see
`docs/counter-bridge-v1.md`.

## What Exists Now

- A Lake-based Lean 4 project.
- A focused SoLean DSL:
  - `UInt256` modeled as a bounded natural-number structure.
  - Storage modeled as `Slot -> UInt256`.
  - An environment with `msg.sender` and an abstract verifier oracle.
  - Statements for `require`, `assert`, assignment, sequencing, and skip.
  - Execution results as success with storage or revert with a failure kind,
    including arithmetic failure.
- A manual SoLean model of `Counter.inc`.
- A theorem showing that if modeled `Counter.inc(amount)` succeeds, then the
  final modeled `x` is at least `amount`.
- A restricted Yul AST and execution semantics in Lean.
- A hand-written restricted Yul model of `Counter.inc`, with a theorem showing
  that successful SoLean Counter executions are reproduced by the restricted Yul
  model with the same final storage.
- A Yul-side Counter theorem showing successful restricted Yul execution implies
  the final modeled `x` is at least `amount`.
- A focused parameter-aware source language and partial compiler to restricted
  Lean Yul for the Counter pattern.
- A theorem showing the generic Counter source function instantiates to the
  existing SoLean Counter model and compiles to the existing restricted Yul
  Counter program.
- Lean-owned Counter source and restricted-Yul audit artifacts exported from
  the proved Counter shapes.
- A `SimpleVault` model with successful-execution preservation proofs for
  `totalAssets >= totalShares`.
- An `AAWallet` validation model proving that successful validation implies the
  modeled entry point, nonce, domain, and abstract verifier checks passed, and
  that the nonce advanced through checked arithmetic. Plus a modeled
  `executeUserOp` step (writes `op.opHash` to a dedicated slot) and a
  `fullFlow = .seq validateProgram executeUserOp` composition with two gate
  theorems: `fullFlow_success_implies_validate_success` (no bypass of
  validation) and `fullFlow_success_records_opHash` (observable execute
  side-effect requires having satisfied every validation guard).
- A `PQVerifierWrapper` model proving that successful wrapper validation
  implies the modeled key-length, signature-length, domain, and abstract
  verifier checks passed.
- An `AAPQIntegration` model proving that successful integrated validation
  connects wrapper checks and wallet checks over the same modeled verifier
  tuple, plus five safety theorems for the integrated flow:
  `noBypass_implies_verifier_accepted` (success implies abstract verifier
  acceptance), `replay_rejected_after_success` (the same `UserOp` cannot
  validate again on the post-validation storage, because the nonce
  advanced), and three under named non-cryptographic crypto assumptions on
  `Env.verifier`: `domain_separation_under_oracle_assumption`
  (`VerifierDomainSeparation`), `signature_non_malleability_under_oracle_
  assumption` (`VerifierSignatureBinding`), and
  `key_separation_under_oracle_assumption` (`VerifierKeySeparation`).
  Also models integrated execution gating via `validateAndExecute`
  (validateIntegrated then `AAWallet.executeUserOp` on the post-validation
  wallet storage) with two gate theorems:
  `validateAndExecute_success_implies_validateIntegrated_success` and
  `validateAndExecute_success_records_opHash`.
- An `AAPQSource` Solidity-shaped source description of the two-contract
  layout with instantiation theorems back to the proved wallet, wrapper, and
  integrated programs, plus Lean-owned `source-json`,
  `source-certificate-json`, and `behavior-summary-json` artifacts emitted
  from `AAPQArtifactsMain.lean`. The behavior summary names the ordered
  guards per phase (wrapper, key-match, wallet), the final write to the
  wallet nonce slot, and the Lean theorem backing each phase; its guards and
  final-write values are structured `Condition` / `ValueExpression` nodes
  over a small `Operand` DSL (param / slot / msgSender / const) instead of
  English condition strings.
- A shared `SoLean.Source.Shape` vocabulary for source-shape audit metadata
  (`Param`, `StorageSlot`, `Contract`, and `IntegratedContract`) used by both
  Counter and AA/PQ artifacts.
- `integratedCryptoAssumptions_cover_all_oracle_theorems` is a Lean-side
  coverage theorem: the `theoremReference`s in `integratedCryptoAssumptions`
  match the enumerated `OracleAssumptionId.theoremReference` for every
  oracle-assumption safety theorem, by `rfl`. Adding a new
  `*_under_oracle_assumption` without registering it in both lists breaks
  the build.
- `AAPQSource.BehaviorReflection` reflects that structured DSL into
  `SoLean.Stmt` semantics and proves that each phase of
  `integratedBehaviorSummary` reconstructs the corresponding proved program:
  `wrapperPhase_reflects_verifyProgram`,
  `keyMatchPhase_reflects_keyMatchesWalletProgram`,
  `walletPhase_reflects_validateProgram`, and
  `integratedBehaviorSummary_reflects_integratedProgram`. The
  execution-side corollary `reflectedValidateIntegrated_eq_validateIntegrated`
  lifts this from syntactic program equality to a full execution-result
  equivalence: composing the three reflected phases under any environment
  and storage produces the exact same `IntegratedResult` as
  `AAPQIntegration.validateIntegrated`.
- A strategic PQ/account-abstraction roadmap for the next serious case study.
- Solidity examples in `examples/`, including a hand-written
  `AAPQIntegration.sol` sketch matching the Lean AA/PQ source shape as a
  documentation fixture (not a parser target).
- An AA/PQ source-shape audit script (`scripts/check_aapq_source.py`) that
  loads the four Lean-owned AA/PQ artifacts, parses the restricted Solidity
  sketch, and emits a deterministic JSON or Markdown report cross-checking
  contract/storage/function names, the certificate's embedded behavior
  summary, structural scope of every operand in both the short and full
  behavior summaries, the bidirectional link between `cryptoAssumptions`
  entries and their `*_under_oracle_assumption` theorems in
  `proofReferences`, and that the full summary includes the expected
  `execute` phase and extends the short summary's first three phases. The
  report has a committed golden fixture at `tests/golden/AAPQ.source.v4.json`.
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
  - Counter-only Solidity-to-SoLean sketching through an explicit restricted
    parser.
- GitHub Actions CI that runs `lake build`, Python bytecode checks, and Python
  unit tests.

## Trusted Components

For the current prototype, the trusted base includes:

- Lean's kernel and the Lake/Lean toolchain.
- The hand-written SoLean model matching the intended Solidity fragment.
- The hand-written restricted Yul model matching the intended Counter emitter.
- The Counter compiler implemented in Lean.
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
- Full EIP-4337/account-abstraction wallet semantics beyond the abstract
  `AAWallet` validation model.
- Full PQ verifier-wrapper contract semantics beyond the abstract
  `PQVerifierWrapper` model.
- External-call semantics between the wallet and verifier wrapper beyond the
  abstract `AAPQIntegration` composition model.
- PQ cryptographic security proofs.
- Broad Solidity or DeFi verification claims.

Checked addition and subtraction are modeled for the current expression DSL.
Stored values are type-enforced as bounded `UInt256` values, but the model is
still a restricted Solidity subset rather than an EVM semantics.

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
│   ├── aapq-demo.md
│   ├── assumptions.md
│   ├── compiler.md
│   ├── counter-bridge-v1.md
│   ├── counter-bridge-v2.md
│   ├── counter-bridge-v3.md
│   ├── counter-bridge-v4.md
│   ├── counter-bridge-v5.md
│   ├── counter-bridge-v6.md
│   ├── counter-bridge-v7.md
│   ├── counter-demo.md
│   ├── counter-yul.md
│   ├── counter.md
│   ├── pq-aa-roadmap.md
│   ├── roadmap.md
│   ├── simple-vault.md
│   ├── source-shape.md
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
│   ├── AAPQArtifactsMain.lean
│   ├── Source/
│   │   └── Shape.lean
│   └── Examples/
│       ├── AAPQIntegration.lean
│       ├── AAPQSource.lean
│       ├── AAWallet.lean
│       ├── Counter.lean
│       ├── CounterCompiler.lean
│       ├── CounterYul.lean
│       ├── PQVerifierWrapper.lean
│       └── SimpleVault.lean
├── examples/
│   ├── AAPQIntegration.sol
│   ├── Counter.sol
│   └── SimpleVault.sol
├── scripts/
│   ├── solc_to_yul.py
│   ├── solean_to_yul.py
│   ├── normalize_yul.py
│   ├── classify_yul.py
│   ├── check_equiv.py
│   ├── check_counter_bridge.py
│   ├── check_aapq_source.py
│   ├── demo_counter_bridge.py
│   ├── demo_aapq_source.py
│   ├── solidity_to_solean.py
│   └── yul_subset.py
└── tests/
    ├── golden/
    │   ├── AAPQ.source.v4.json
    │   ├── Counter.bridge.v7.json
    │   └── Counter.solean.yul
    ├── README.md
    ├── test_aapq_source.py
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
Lean-owned artifacts. It also checks the observed solc summary rules, source
certificate, trace skeleton, and restricted behavior summary against a
Lean-owned bridge manifest. A passing report is an audit/regression signal,
not a proof of Solidity parsing or semantic equivalence with solc output. See
`docs/counter-bridge-v7.md` for the current Lean-owned bridge certificate
boundary. The JSON report is versioned as `reportVersion: 7` and checked
against `tests/golden/Counter.bridge.v7.json` in the Python test suite.

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
`docs/yul-subset.md` and compares a restricted symbolic summary of parameters,
ordered revert conditions, and final storage writes. This is useful
state-transform tooling for the restricted subset, not a semantic equivalence
proof. The old bounded trace checker is available with `--bounded-traces`,
strict AST equality with `--ast`, and normalized-text comparison with `--text`.

Sketch the exact Counter Solidity example into a Lean reference:

```bash
python3 scripts/solidity_to_solean.py examples/Counter.sol
```

This is not a general Solidity parser. It tokenizes and validates only a
restricted Counter subset and rejects unsupported input.

Emit the same parsed Counter shape as deterministic JSON:

```bash
python3 scripts/solidity_to_solean.py --format source-json examples/Counter.sol
```

This JSON is an audit/test artifact that is checked against the Lean-exported
`CounterCompiler.counterFunction` shape; it is not a verified parser output.

Emit the accepted source certificate:

```bash
python3 scripts/solidity_to_solean.py --format source-certificate-json examples/Counter.sol
```

This certificate is checked against the Lean-owned bridge manifest. It states
the accepted Counter-only source shape and assumptions.

Export the Lean-owned Counter audit artifacts:

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean source-json
lake env lean --run SoLean/CounterArtifactsMain.lean source-certificate-json
lake env lean --run SoLean/CounterArtifactsMain.lean yul-json
lake env lean --run SoLean/CounterArtifactsMain.lean trace-skeleton-json
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
```

Export the Lean-owned AA/PQ source-shape audit artifacts:

```bash
lake env lean --run SoLean/AAPQArtifactsMain.lean source-json
lake env lean --run SoLean/AAPQArtifactsMain.lean source-certificate-json
lake env lean --run SoLean/AAPQArtifactsMain.lean behavior-summary-json
lake env lean --run SoLean/AAPQArtifactsMain.lean full-behavior-summary-json
```

Run the AA/PQ source-shape audit (deterministic JSON report by default):

```bash
python3 scripts/check_aapq_source.py
python3 scripts/check_aapq_source.py --format markdown
```

The script invokes `lake` to fetch the three Lean-owned artifacts, parses
`examples/AAPQIntegration.sol` with a narrow restricted shape extractor, and
cross-checks contract/storage/function names plus the certificate's embedded
behavior summary. It is a Solidity-shape-only audit; it does not run solc and
does not claim Yul or semantic equivalence.

Run the full AA/PQ source-shape research demo (build + tests + artifacts +
markdown report + trust-boundary summary):

```bash
python3 scripts/demo_aapq_source.py
```

See `docs/aapq-demo.md` for the architecture, current claims, non-claims, and
the full list of Lean theorems backing the boundary.

These artifacts pin the Solidity-shaped two-contract description in
`SoLean.Examples.AAPQSource.integratedContract` and name the theorems backing
the integrated AA/PQ proof. They are not a verified Solidity parser output and
do not claim Yul or solc equivalence.

Python tests compare the Solidity source projection and Python Yul emitter
shape against these Lean-exported artifacts. The Counter bridge report also
compares the observed solc summary rule list, source certificate, and trace
skeleton against the Lean-exported bridge manifest.

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
