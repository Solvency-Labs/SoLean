# PQ Verifier Wrapper v0

PQ Verifier Wrapper v0 is the first standalone verifier-wrapper case study for
SoLean's account-abstraction direction.

It models wrapper logic around an abstract verifier oracle. It does not verify
any PQ signature scheme.

## Model

The model lives in `SoLean.Examples.PQVerifierWrapper`.

Storage slots:

- slot `0`: expected public-key length
- slot `1`: expected signature length
- slot `2`: expected domain

The modeled wrapper input contains:

- public key
- public-key length
- message
- domain
- signature
- signature length

All values are represented as bounded `UInt256` placeholders. This keeps the
model aligned with the current SoLean DSL while avoiding premature byte-array,
ABI, calldata, hashing, and external-call semantics.

## Validation Flow

`verifyProgram input` succeeds only if:

1. the provided public-key length matches the configured length;
2. the provided signature length matches the configured length;
3. the provided domain matches the configured domain;
4. the abstract verifier oracle accepts exactly
   `(publicKey, message, domain, signature)`.

The program has no storage writes. Successful execution leaves storage
unchanged.

## Proved Claim

The main theorem is `PQVerifierWrapper.verify_success_properties`.

It proves that if:

```text
exec env (verifyProgram input) storage = success finalStorage
```

then:

- the public-key length check passed;
- the signature length check passed;
- the domain check passed;
- the verifier oracle accepted the exact modeled tuple;
- final storage equals initial storage.

`PQVerifierWrapper.verify_ensures` wraps the same property in the existing
`FunctionEnsures` spec helper.

## Assumptions And Non-Claims

Trusted or assumed:

- The verifier oracle represents the intended PQ verifier result.
- Public keys, signatures, messages, domains, and lengths are modeled as
  `UInt256` values.
- The model is hand-written in Lean.

Not claimed:

- PQ cryptographic security;
- byte-level parsing of keys, messages, or signatures;
- ABI/calldata/memory semantics;
- external calls into a real verifier contract or library;
- gas, reentrancy, or EVM behavior;
- Solidity/Yul generation or equivalence.

The value of this milestone is that the wrapper boundary now has a Lean-proved
no-bypass shape: a successful wrapper result implies all modeled preconditions
and verifier acceptance.
