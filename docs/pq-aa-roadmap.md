# PQ Account-Abstraction Roadmap

SoLean's strategic target is now a hybrid path that leans toward Ethereum
post-quantum account abstraction work.

Counter remains the calibration case for the bridge machinery. ERC-20-style
examples may be used as small learning exercises. The serious research target
is contract-level verification around account-abstraction wallets and
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

Goal: model the smallest useful account validation flow with an abstract
signature verifier predicate.

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

Candidate properties:

- the wallet calls the intended PQ verifier wrapper.
- the user operation hash is the message being verified.
- nonce and domain are included in the authenticated data.
- validation success is required before execution.
- invalid PQ auth cannot authorize execution.
- signatures cannot be replayed across nonce, wallet, chain, or domain when
  those fields are modeled.

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

The near-term claim should be narrower:

```text
For a tiny modeled AA/PQ authentication flow, Lean proves that successful
validation/execution implies the operation satisfied the modeled authentication,
nonce, and domain checks.
```
