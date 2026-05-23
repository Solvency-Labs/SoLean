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
- Lean proves that successful integrated validation implies wrapper checks,
  wallet checks, key agreement, and abstract verifier acceptance of the shared
  `(publicKey, opHash, domain, signature)` tuple.
- `SoLean.Examples.AAPQSource` defines the Solidity-shaped two-contract source
  description (`walletContract`, `wrapperContract`, `integratedContract`) and
  proves that wallet, wrapper, and integrated bodies instantiate to the
  existing proved programs. The sub-namespace `BehaviorReflection` reflects
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
  `source-certificate-json`, and `behavior-summary-json` artifacts naming the
  assumptions, contracts, integration flow, ordered phase guards (wrapper,
  key-match, wallet), final wallet-nonce write, theorem references, and
  explicit out-of-scope items. The source certificate embeds the behavior
  summary as `expectedBehaviorSummary`.
- `examples/AAPQIntegration.sol` is a Solidity fixture matching the source
  shape, kept as documentation only.
- `scripts/check_aapq_source.py` produces a deterministic source-shape audit
  report (`tests/golden/AAPQ.source.v2.json`) cross-checking the three
  Lean-owned artifacts against each other and against the Solidity sketch,
  and walks every operand in the behavior summary's structured
  `Condition`/`ValueExpression` shape to confirm it references a declared
  parameter or a known storage slot.
- External-call semantics, ABI/calldata, and real PQ cryptography remain out of
  scope.

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
summary with theorem references and out-of-scope items.
```
