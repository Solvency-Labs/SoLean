# AA Wallet Validation v0

AA Wallet Validation v0 is the first account-abstraction-facing SoLean case
study. It extends the existing DSL with just enough structure to model wallet
validation around an abstract verifier oracle.

This is a contract-logic model. It is not EIP-4337 semantics, not a Solidity
translation, and not a PQ cryptography proof.

## Model

The model lives in `SoLean.Examples.AAWallet`.

Storage slots:

- slot `0`: nonce
- slot `1`: verification key commitment
- slot `2`: domain
- slot `3`: entry point

The environment contains:

- `msgSender`
- `verifier key message domain signature`, an abstract Boolean oracle

The modeled `UserOp` contains:

- operation hash
- nonce
- domain
- signature

All of these values are represented as bounded `UInt256` placeholders. This
keeps the first model aligned with the current SoLean storage and expression
semantics while avoiding premature calldata, hashing, byte-array, or PQ-scheme
modeling.

## Validation Flow

`validateProgram op` succeeds only if:

1. `msg.sender` equals the configured entry point.
2. `op.nonce` equals the stored nonce.
3. `op.domain` equals the stored domain.
4. The verifier oracle accepts the stored key commitment, operation hash,
   domain, and signature.
5. The stored nonce can be incremented with checked `UInt256` addition.

If any `require` fails, execution reverts with `Failure.requireFailed`. If the
nonce increment overflows, execution reverts with `Failure.arithmeticFailed`.

## Proved Claim

The main theorem is `AAWallet.validate_success_properties`.

It proves that if:

```text
exec env (validateProgram op) storage = success finalStorage
```

then:

- the caller was the configured entry point;
- the operation nonce matched the stored nonce;
- the operation domain matched the stored domain;
- the abstract verifier accepted exactly the modeled key, operation hash,
  domain, and signature tuple;
- the final nonce is the checked increment of the initial nonce;
- key commitment, domain, and entry point storage slots are unchanged.

`AAWallet.validate_ensures` wraps the same property in the existing
`FunctionEnsures` spec helper.

## Assumptions And Non-Claims

Trusted or assumed:

- The verifier oracle is assumed to represent the intended PQ verification
  result.
- `opHash`, `domain`, `signature`, addresses, and key commitments are modeled
  as `UInt256` values.
- The model is hand-written in Lean.

Not claimed:

- full EIP-4337 semantics;
- verified Solidity parsing or generation for an AA wallet;
- calldata, memory, ABI, gas, bundler, paymaster, or aggregator behavior;
- PQ signature scheme security;
- equivalence with real `solc` output.

The value of this milestone is that SoLean now has a first Lean-proved
authentication-gating shape for the PQ/account-abstraction direction.
