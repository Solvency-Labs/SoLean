# AA + PQ Integration v0

AA + PQ Integration v0 connects the two first AA/PQ-facing Lean models:

- `SoLean.Examples.AAWallet`
- `SoLean.Examples.PQVerifierWrapper`

The goal is to prove one integrated no-bypass property while keeping the
cryptographic verifier abstract.

## Model

The model lives in `SoLean.Examples.AAPQIntegration`.

It treats the wallet and verifier wrapper as separate contract/storage
boundaries:

- wrapper storage contains wrapper configuration such as expected key length,
  signature length, and domain;
- wallet storage contains wallet state such as nonce, key commitment, domain,
  and entry point.

The integrated input shares:

- public key;
- operation hash;
- nonce;
- domain;
- signature;
- public-key length;
- signature length.

The integration model first runs the wrapper validation, then runs wallet
validation. Before wallet validation, it requires the wrapper public key to
match the wallet's stored key commitment.

## Proved Claim

The main theorem is `AAPQIntegration.validateIntegrated_success_properties`.

It proves that if integrated validation succeeds, then:

- the wrapper public-key length check passed;
- the wrapper signature-length check passed;
- the wrapper domain check passed;
- the wallet entry point check passed;
- the wallet nonce check passed;
- the wallet domain check passed;
- the wrapper public key matched the wallet key commitment;
- the abstract verifier accepted the shared
  `(publicKey, opHash, domain, signature)` tuple;
- the wallet nonce advanced through checked arithmetic;
- wrapper storage remained unchanged.

This is the first proof that connects the wallet authentication gate to the
verifier-wrapper boundary.

## Assumptions And Non-Claims

Trusted or assumed:

- The verifier oracle represents the intended PQ verifier result.
- Wallet and wrapper are modeled as separate storage boundaries.
- Public keys, signatures, messages, domains, and lengths are modeled as
  bounded `UInt256` placeholders.
- The model is hand-written in Lean.

Not claimed:

- full EIP-4337 semantics;
- external calls between wallet and wrapper contracts;
- ABI/calldata/memory semantics;
- byte-level parsing of PQ keys or signatures;
- PQ cryptographic security;
- Solidity/Yul generation or equivalence.

The value of this milestone is that the AA/PQ direction now has one connected
Lean proof: successful modeled validation requires both wrapper-level checks
and wallet-level checks over the same authenticated tuple.
