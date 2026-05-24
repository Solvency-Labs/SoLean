# PQ Account-Abstraction Roadmap

SoLean's strategic target is now a hybrid path that leans toward Ethereum
post-quantum account abstraction work.

Counter remains the calibration case for the bridge machinery. ERC-20-style
examples may be used as focused calibration exercises. The serious research
target is contract-level verification around account-abstraction wallets and
post-quantum signature verifier wrappers.

## North Star

```text
Build a boundary-aware Lean/Solidity verification pipeline for
account-abstraction contracts that authenticate user operations through
post-quantum signature verification, with cryptographic assumptions explicit
and contract-level safety properties proved.
```

The project should verify the contract logic around PQ authentication. It does
not currently verify the cryptographic security of a PQ signature scheme.

## Why This Direction

Ethereum post-quantum signature migration is likely to rely on account
abstraction and Solidity-level verifier contracts rather than a dedicated PQ
precompile. That makes the useful verification target a contract boundary:

```text
user operation
  -> wallet validation logic
  -> PQ verifier wrapper
  -> accept or reject execution
```

The important question is:

```text
Can an operation execute without satisfying the intended PQ authentication
condition, nonce condition, and domain-separation condition?
```

## Phase 0: Calibration

Goal: keep the bridge honest while learning modeling patterns.

Current calibration:

- Counter bridge with Lean-owned source, Yul, trace, certificate, and behavior
  artifacts.
- SimpleVault hand-written invariant proof.

Optional ERC-20 mini-calibration:

- balances update correctly for successful transfers.
- insufficient balance reverts.
- total supply is preserved by transfers.
- allowances decrease on `transferFrom`.

This is not intended to become a broad ERC-20 framework. Add it only if it
teaches reusable modeling patterns for mappings, ownership, nonces, or
allowances.

## Phase 1: Abstract AA Wallet Validation

Goal: model the first useful account validation flow with an abstract
signature verifier predicate.

Current v0:

- `SoLean.Examples.AAWallet` models entry point authorization, nonce matching,
  domain matching, abstract verifier acceptance, and checked nonce increment.
- Lean proves that successful validation implies all modeled guards passed and
  that key commitment, domain, and entry point storage slots are unchanged.
- The verifier is still an oracle; this is contract-logic verification under a
  crypto assumption, not PQ cryptographic security.

Candidate state:

- owner or verification key commitment
- nonce
- trusted entry point or caller guard

Candidate inputs:

- user operation hash
- nonce
- signature bytes, modeled abstractly at first

Candidate properties:

- invalid modeled signature rejects.
- valid modeled signature plus correct nonce accepts validation.
- replay with an old nonce rejects.
- validation binds the signature to the operation hash.
- validation binds the operation to the wallet/domain.
- execution is gated by successful validation.

At this phase, the verifier is an assumption:

```text
Verifier(pk, msg, sig) = true
```

No claim is made about the cryptographic soundness of the verifier.

## Phase 2: PQ Verifier Wrapper Contract

Goal: verify the Solidity wrapper around a PQ verifier interface or library.

Current v0:

- `SoLean.Examples.PQVerifierWrapper` models public-key length, signature
  length, domain, and abstract verifier acceptance checks.
- Lean proves that successful wrapper validation implies all modeled wrapper
  checks passed and storage is unchanged.
- The verifier is still an oracle; byte-level parsing, external calls, and PQ
  cryptographic security remain out of scope.

Candidate properties:

- public key, message, and signature inputs are passed to the verifier in the
  intended order.
- input lengths and domain tags are checked before verifier use.
- verifier return values are interpreted safely.
- malformed verifier output rejects.
- there is no bypass path that accepts without verifier success.
- wrapper behavior is explicit about unsupported schemes or parameter sets.

The wrapper proof should state its crypto assumption clearly:

```text
Assume the underlying PQ verifier returns true exactly for valid signatures
under the chosen scheme, parameter set, message, and public key.
```

## Phase 3: AA + PQ Integration

Goal: prove the wallet accepts only PQ-authenticated operations under explicit
assumptions.

Current v0:

- `SoLean.Examples.AAPQIntegration` composes the wallet and wrapper validation
  models as separate storage boundaries.
- `AAPQIntegration.callVerifierWrapper` gives the integration an explicit
  external-call shim boundary and proves the shim is behaviorally equivalent to
  the existing direct composition. It is not EVM `CALL` or `STATICCALL`.
- Lean proves that successful integrated validation implies wrapper checks,
  wallet checks, key agreement, and abstract verifier acceptance of the shared
  `(publicKey, opHash, domain, signature)` tuple.
- `SoLean.Examples.AAPQSource` defines the Solidity-shaped two-contract source
  description (`walletContract`, `wrapperContract`, `integratedContract`) and
  proves that wallet, wrapper, and integrated bodies instantiate to the
  existing proved programs. The basic contract/parameter/storage vocabulary is
  shared through `SoLean.Source.Shape`; the AA/PQ-specific behavior summary
  remains in `AAPQSource`. The sub-namespace `BehaviorReflection` reflects
  the behavior summary's structured `Operand`/`Condition`/`ValueExpression`
  DSL back into `SoLean.Stmt` and proves that each phase of
  `integratedBehaviorSummary` reconstructs the corresponding proved program
  by `rfl` — so the structured summary cannot silently drift from the
  proved validation flow. The execution-side corollary
  `reflectedValidateIntegrated_eq_validateIntegrated` lifts that to an
  execution-result equivalence: composing the reflected phases under any
  environment and storage produces the same `IntegratedResult` as
  `AAPQIntegration.validateIntegrated`.
- `SoLean/AAPQArtifactsMain.lean` emits `source-json`,
  `source-certificate-json`, `behavior-summary-json`, and
  `full-behavior-summary-json` artifacts naming the assumptions, contracts,
  integration flow, ordered phase guards (wrapper, key-match, wallet,
  execute), final wallet writes, theorem references, and explicit
  out-of-scope items. The source certificate embeds the short behavior
  summary as `expectedBehaviorSummary`, records named verifier-oracle
  assumptions in `cryptoAssumptions`, and records a directed
  `cryptoAssumptionGraph` from each assumption to each theorem it supports.
- `examples/AAPQIntegration.sol` is a Solidity fixture matching the source
  shape, kept as documentation only.
- `scripts/check_aapq_source.py` produces a deterministic source-shape audit
  report (`tests/golden/AAPQ.source.v5.json`) cross-checking the four
  Lean-owned artifacts against each other and against the Solidity sketch,
  walks every operand in the short and full behavior summaries to confirm it
  references a declared parameter or a known storage slot, audits the
  `cryptoAssumptions`/`proofReferences` loop, audits the directed
  `cryptoAssumptionGraph`, renders that graph in Markdown reports and the demo
  trust-boundary summary, checks `verifierModelCalibrations`, and checks that
  the full behavior summary extends the short summary with the execute phase.
- `SoLean.Examples.ToyVerifier` provides three assumption-discharge
  calibrations: `allFieldsEqualVerifier` (4-way collapse) and
  `keyDomainBindingVerifier` (paired sig↔key, msg↔domain) are
  concrete `toyVerifierCalibration` entries; `DerivedSignatureModel`
  is a `parametricVerifierCalibration` that bundles an abstract
  `derive : UInt256 → UInt256 → UInt256 → UInt256` with explicit
  injectivity-in-key and injectivity-in-domain hypotheses, and proves
  the three named oracle assumptions hold for any such model. The
  parametric entry shows what shape a useful verifier-wrapper
  relation has without committing to a specific cryptographic
  function.
- Real external-call semantics, ABI/calldata, and real PQ cryptography remain
  out of scope.

Candidate properties:

- the wallet calls the intended PQ verifier wrapper.
- the user operation hash is the message being verified.
- nonce and domain are included in the authenticated data.
- validation success is required before execution.
- invalid PQ auth cannot authorize execution.
- signatures cannot be replayed across nonce, wallet, chain, or domain when
  those fields are modeled.

Current v0 safety theorems (`SoLean.Examples.AAPQIntegration`):

- `noBypass_implies_verifier_accepted`: successful integrated validation
  forces abstract verifier acceptance of the exact
  `(publicKey, opHash, domain, signature)` tuple. Forward bypass-resistance.
- `replay_rejected_after_success`: a successful validation cannot be
  re-run with the same `IntegratedInput` on the resulting post-validation
  storage. The first success advances the wallet nonce through checked
  arithmetic, so the second call's modeled `nonce == wallet.nonce` require
  observes a different stored nonce. Contract-level replay-resistance for
  the modeled flow.
- `domain_separation_under_oracle_assumption`: under
  `VerifierDomainSeparation env`, two successful validations sharing
  `(publicKey, opHash, signature)` must share `domain`.
- `signature_non_malleability_under_oracle_assumption`: under
  `VerifierSignatureBinding env`, two successful validations sharing
  `(publicKey, opHash, domain)` must share `signature`.
- `key_separation_under_oracle_assumption`: under
  `VerifierKeySeparation env`, two successful validations sharing
  `(opHash, domain, signature)` must share `publicKey`.

The first two are contract-level claims that hold for the modeled flow
without any new crypto assumption. The last three are contract-level under
named, non-cryptographic assumptions on the verifier oracle and are
recorded explicitly in the source certificate's `cryptoAssumptions` field
(name, Lean reference, informal statement).

`SoLean.Examples.AAWallet` additionally models execution gating via
`executeUserOp` (writes `op.opHash` to `lastOpHashSlot`) and the
composition `fullFlow = .seq validateProgram executeUserOp`. The two
gate theorems are `fullFlow_success_implies_validate_success` (no
bypass of validation) and `fullFlow_success_records_opHash`
(observable execute side-effect requires having satisfied every
validation guard).

`SoLean.Examples.AAPQIntegration.validateAndExecute` lifts that gate
to the integrated flow: validateIntegrated then executeUserOp on the
post-validation wallet storage. The two gate theorems
(`validateAndExecute_success_implies_validateIntegrated_success` and
`validateAndExecute_success_records_opHash`) show that observing the
integrated execute write requires satisfying every wrapper, key-match,
and wallet validation guard.

Two lifted contract-level claims about the full flow:

- `validateAndExecute_implies_verifier_accepted`: successful
  validateAndExecute forces abstract verifier acceptance.
- `validateAndExecute_records_authorized_opHash`: after success,
  the wallet's lastOpHashSlot equals input.opHash AND that opHash
  was verifier-accepted under the wallet's stored keyCommitment.
  External observers reading lastOpHashSlot learn the recorded value
  was authorized.
- `validateAndExecute_replay_rejected`: re-running validateAndExecute
  on the post-state cannot succeed. The first call advanced the
  wallet nonce; the execute step writes to a different slot, so the
  replay storage retains the post-advance nonce and the validation's
  nonce check fails.
- `validateAndExecute_reverts_when_validateIntegrated_reverts` and
  the iff form `validateAndExecute_reverts_iff_validateIntegrated_
  reverts` are the contrapositive companions to the success-side
  gate theorems: validateAndExecute reverts with failure F exactly
  when the underlying validateIntegrated reverts with the same F.
  The execute step (`.assign` over `.const`) cannot itself revert,
  so the only source of revert is the integrated validation.
- `validateAndExecute_preserves_wrapper_storage` and
  `validateAndExecute_preserves_wallet_configuration` are
  storage-isolation theorems: a successful integrated flow leaves
  the wrapper's storage entirely unchanged and only touches the
  wallet's nonce slot and `lastOpHashSlot`. Auditors can rely on
  these to know the integrated flow does not silently mutate
  wrapper state or wallet configuration (`keyCommitmentSlot`,
  `domainSlot`, `entryPointSlot`).
- `SoLean.EVM.Call` and `SoLean.Examples.AAPQEvmCall` introduce a
  first call-shaped boundary for the wallet-to-wrapper interaction:
  modeled `Calldata`/`Returndata`/`CallResult`, an `EvmEnv` carrying
  an `evmCall` oracle and `wrapperAddress`, and a
  `validateIntegratedViaEvmCall` flow that builds calldata, invokes
  the oracle, and dispatches on the result. Under
  `WrapperOracleConsistent` (a named cross-contract assumption
  recorded in the certificate's `evmCallAssumptions` field) the
  call-shaped flow is proved to agree with `validateIntegrated` on
  the success path, and
  `validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success`
  lifts that to a two-sided equivalence: the call-shaped flow succeeds
  iff the canonical flow succeeds.
- `SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle`
  and `validateIntegratedViaEvmCall_preserves_wallet_configuration`
  formalize structural no-reentrancy on the wallet side: the wrapper
  call's oracle takes only `wrapperStorage` (by the `EvmEnv.evmCall`
  signature), so the wallet's storage flows through the call-shaped
  flow untouched. Even a malicious oracle cannot reach into wallet
  storage during the wrapper call; `keyCommitmentSlot`, `domainSlot`,
  and `entryPointSlot` are preserved across the entire call-shaped
  flow. Brings reentrancy into scope as a *structural* property
  rather than an ambient assumption.
- `SoLean.Examples.AAPQEvmCall` now uses a selector-prefixed calldata
  layout: `buildVerifierCalldata` prepends a modeled `verifySelector`,
  and `parseVerifierCalldata` rejects calldata with the wrong selector
  or insufficient length (`parseVerifierCalldata_rejects_wrong_selector`
  and `parseVerifierCalldata_rejects_short_calldata`). The smallest
  piece of ABI dispatch discipline — wrong-function calldata is
  rejected by shape before any field is interpreted.
- `SoLean.Examples.AAPQEvmCallGas` adds a first-cut gas dimension on
  top: `EvmGasEnv` carries a per-call `gasCost` function and a
  `gasBudget`; `validateIntegratedViaEvmCallWithGas` returns
  `outOfGas` when the budget is below cost and otherwise delegates to
  the gas-free flow. Under the named `EnoughGas` assumption the
  gas-aware flow reduces to the gas-free one (and the success-iff
  equivalence lifts), and under `Not (EnoughGas)` the flow returns
  `outOfGas` regardless of input semantics. This is not full EVM gas
  accounting — no per-opcode schedule, no calldata word/byte costs,
  no refunds, no EIP-150 63/64 rule — but it is the second non-claim
  from the original AA/PQ list to be brought into scope after EVM
  CALL itself.

The three sibling oracle-assumption theorems are also lifted to the
full validateAndExecute flow:

- `validateAndExecute_domain_separation_under_oracle_assumption`
- `validateAndExecute_signature_non_malleability_under_oracle_assumption`
- `validateAndExecute_key_separation_under_oracle_assumption`

Each derives from the integrated-level theorem via the
`validateAndExecute_success_implies_validateIntegrated_success` gate.
The certificate's `cryptoAssumptions` field now lists both the
integrated and lifted theorem for each named predicate via a
`theoremReferences : List String` field (was singular before).
`integratedCryptoAssumptionSupportGraph_covers_assumption_references`
pins the directed support graph to those theorem references by `rfl`, so a
new oracle-assumption theorem cannot be represented as an untracked floating
string without breaking the Lean build or the Python audit.

This is the first target that should feel like a serious Ethereum research demo.

## Phase 4: Bridge To Real Solidity And solc

Goal: apply the Counter bridge discipline to the AA/PQ case study.

Use the same boundary-aware style:

```text
Solidity subset
  -> source certificate
  -> Lean model
  -> proof
  -> restricted Yul
  -> pinned-solc output inspection
  -> explicit trusted boundaries
```

Do not silently support new Solidity, Yul, ABI, memory, or call features. Add
each feature only with a named assumption, test, artifact, or proof.

## Phase 5: Structured PQ Verifier Shape (v0 landed)

Goal: bring PQ cryptography into scope *structurally* without yet committing
to a specific scheme's security proof. The verifier remains an oracle in
the sense that its acceptance set is given by hypotheses, but the oracle's
*signature shape* becomes a record with named fields that the wallet and
wrapper can reason about.

Current v0 (committed):

1. **Structured verifier interface** —
   `SoLean.Examples.StructuredVerifier.StructuredVerifier` exposes
   intermediate `VerifierWitness` fields (signature/public-key components)
   on accept. `StructureRespectsBool` is the named correspondence
   assumption tying the structured verifier to the existing Bool-valued
   `Env.verifier`. `toBool_eq_under_respectsBool` and
   `allFieldsEqualStructuredVerifier_respects_bool` discharge the lift.
2. **Lattice-shaped public-key model** —
   `SoLean.Examples.LatticePublicKey.LatticePublicKey` models a public
   key as a polynomial coefficient list plus declared degree.
   `LatticeShapeBound` carries a scheme-specific
   degree/coefficient-count bound, and `LatticePublicKey.compress`
   projects the polynomial down to the existing `UInt256` slot used
   by `Env.verifier`. `compress_degree_independent` shows the
   compression doesn't smuggle in degree-dependent behavior.
3. **Scheme parameterization** — `SoLean.Examples.SchemeParameters`
   carries `falcon512` and `mlDsa44` records (public-key/signature byte
   lengths, NIST security category, polynomial degree). Surfaces in the
   certificate's `verifierModelCalibrations` as
   `schemeParameterCalibration` (the third calibration kind, alongside
   `toyVerifierCalibration` and `parametricVerifierCalibration`).
   `falcon512_ne_mlDsa44` and `falcon512_publicKey_size_ne_mlDsa44_
   publicKey_size` are sanity theorems about scheme distinctness.

The verifier-oracle assumptions still discharge the same contract-level
claims, but the wallet/wrapper code is starting to talk about real PQ
artifacts (polynomial coefficients, scheme parameters) instead of
opaque words.

## Phase 6: Concrete Verifier Properties

Goal: state and prove the first concrete cryptographic-shape property
about a `StructuredVerifier` or `LatticePublicKey`. Examples:

- **Coordinate-uniqueness** — under a specific `LatticeShapeBound`,
  two `LatticePublicKey`s with the same `compress` agree on at least
  one named coordinate (forces a structural relationship that the
  current `head-or-zero` compression can satisfy trivially; richer
  compressions would force richer agreement).
- **Witness uniqueness** — under `StructureRespectsBool` and a named
  `WitnessDeterministic` assumption, two accepting verifications of
  the same `(key, message, domain, signature)` tuple produce the same
  `VerifierWitness`.
- **Scheme-parameter discrimination** — a wrapper that checks
  `signatureByteLength` against `falcon512.signatureByteLength`
  cannot also accept inputs sized for `mlDsa44`. Formalize the
  byte-length check as a guard in `PQVerifierWrapper.verifyProgram`
  and prove the contrapositive.

Each Phase 6 slice is genuinely cryptographic work (or close to it).
Sequencing depends on which scheme parameter the wrapper enforces most
visibly — `publicKeyByteLength` is the simplest, then
`signatureByteLength`, then per-coordinate properties of the
polynomial public key.

## Non-Claims

SoLean does not currently claim:

- verified Solidity parsing.
- verified solc parsing.
- full EVM or Yul semantics.
- verified PQ cryptographic security.
- verified equivalence between real solc Yul and SoLean-generated Yul.
- production readiness for account-abstraction wallets.

The current near-term claim is:

```text
For the hand-written AAPQIntegration v0 model, Lean proves that successful
integrated validation implies the modeled wallet and wrapper guards passed over
the same authenticated tuple, under an abstract verifier-oracle assumption.
The Solidity-shaped source description in AAPQSource v0 is pinned by
instantiation theorems to those exact proved programs, and is exported as a
deterministic source artifact, source certificate, and ordered behavior
summary with theorem references, a directed crypto-assumption support graph,
and out-of-scope items.
```
