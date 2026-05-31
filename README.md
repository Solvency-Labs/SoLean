# SoLean

SoLean is a Lean 4 prototype for AI-assisted formal verification of Solidity
contract *logic* — the methodology and wallet-layer model behind the team's
post-quantum account-abstraction (PQ-AA) verification effort.

> **Where this fits.** SoLean is now the **methodology + wallet/wrapper model**
> layer. The team's active target — formally certifying the deployed
> `ForsVerifier.sol` — lives in the [`Solvency-Labs/NiceTry`
> fork](https://github.com/Solvency-Labs/NiceTry) (`verity/NiceTry/Fors/Bridge/`),
> and the plan, status, and onboarding live on the **[SoLean Field
> Guide](https://solvency-labs.github.io/solean-learn/)** (start with the
> [Roadmap](https://solvency-labs.github.io/solean-learn/project/roadmap/) and
> [Workstreams](https://solvency-labs.github.io/solean-learn/project/workstreams/)).
> SoLean's abstract **verifier oracle is the slot a finished FORS proof
> discharges** — see `docs/pq-verifier-wrapper-v0.md`.

## The idea

PQ-authenticated Ethereum transactions are deployable today by routing them
through an AA smart wallet that authenticates `UserOp`s with a PQ verifier
wrapper (Antonio Sanso, *"The road to Post-Quantum Ethereum transactions is
paved with Account Abstraction"*). SoLean verifies the **contract logic** around
that authentication — nonce/domain/key-commitment checks, wrapper validation,
and execution gating — **not** the cryptographic security of any PQ scheme. The
verifier stays an oracle / structured-verifier model.

## What's verified (the surface)

- **AA/PQ wallet + wrapper, integrated.** `validateAndExecute` proofs: success
  implies every guard passed (key-length, signature-length, domain, verifier
  acceptance), the nonce advanced through checked arithmetic, replays are
  rejected, and the execute side-effect happens exactly when validation accepts.
- **Verifier-oracle assumptions, named and discharged.** Domain separation,
  signature binding, key separation as explicit `Env.verifier` assumptions, with
  concrete non-cryptographic calibrations (`ToyVerifier`) proved to satisfy them.
- **Counter source→Yul calibration.** A restricted Lean Yul model and a focused
  verified Counter compiler slice exercising the source-to-Yul bridge in
  isolation.

Full inventory in **[`docs/status.md`](docs/status.md)**; trust base and
non-claims below.

## Boundaries & non-claims

- **No PQ crypto security.** Falcon/ML-DSA security is out of scope; the verifier
  is an oracle.
- **Bundler / ECDSA boundary.** ERC-4337 PQ-authenticates at the wallet, but the
  outer bundler tx may still rely on ECDSA until native-AA (RIP-7560 /
  EIP-7701-like) lands. Treated as an explicit non-claim.
- **EIP-7702 caveat.** Delegating an EOA adds PQ-AA behavior but leaves the
  original ECDSA key valid — a trust boundary, not solved.
- **No verified Solidity/Yul parsing or full EVM semantics yet.** The Python
  bridge tooling is auditable alignment, not proof. See `docs/assumptions.md`.

## Build

```bash
lake build        # Lean 4 via elan; if lake isn't on PATH, use ~/.elan/bin/lake
python3 -m unittest discover -s tests   # Python bridge tooling tests
```

Core proofs live in `SoLean/Examples/` (`AAWallet`, `PQVerifierWrapper`,
`AAPQIntegration`, `Counter*`, `SimpleVault`). Script usage and the full layout
are in [`docs/status.md`](docs/status.md).

## Docs

- **[`docs/README.md`](docs/README.md)** — index of current docs.
- **[`docs/status.md`](docs/status.md)** — full "what exists" inventory, trusted
  base, layout, and script commands.
- **[`docs/roadmap.md`](docs/roadmap.md)** — pointer to the canonical learn-site
  roadmap.
- `docs/archive/` — superseded roadmaps and counter-bridge dev-logs, kept for
  history.
