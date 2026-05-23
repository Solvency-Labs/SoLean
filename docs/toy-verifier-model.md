# Toy Verifier Model

`SoLean.Examples.ToyVerifier` is a deliberately non-cryptographic calibration
model for the AA/PQ verifier-oracle boundary.

The model defines `allFieldsEqualVerifier`, which accepts exactly when:

```text
key = message = domain = signature
```

This is not a signature scheme. Its purpose is to show how a concrete verifier
model can discharge the named oracle assumptions currently used by the AA/PQ
integration proofs.

## What Lean Proves

For an environment using `allFieldsEqualVerifier`, Lean proves:

- `allFieldsEqualEnv_domain_separation`
- `allFieldsEqualEnv_signature_binding`
- `allFieldsEqualEnv_key_separation`
- `allFieldsEqualEnv_satisfies_oracle_assumptions`

Together these show that the toy verifier satisfies:

- `VerifierDomainSeparation`
- `VerifierSignatureBinding`
- `VerifierKeySeparation`

## Why This Helps

Before this milestone, the source certificate listed the verifier-oracle
assumptions and theorems that depend on them, but there was no concrete model
showing what assumption discharge should look like.

The toy verifier gives the project a small, checked pattern:

```text
concrete verifier model
  -> Lean proofs that it satisfies assumption predicates
  -> source certificate verifierModelCalibrations entry
  -> Python audit checks proof links and non-claims
```

## Non-Claims

- This is not PQ cryptography.
- This is not EIP-4337 semantics.
- This is not a Solidity verifier wrapper.
- This does not prove any real signature scheme secure.

The next serious version should replace this toy predicate with a more useful
abstract verifier relation or a small verified wrapper-specific property, while
keeping the same discipline: every discharged assumption must name the concrete
model and the Lean theorem that discharges it.
