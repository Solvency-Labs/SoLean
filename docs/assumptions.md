# SoLean Assumptions

SoLean is a research prototype for focused, proof-oriented case studies. This
document records the assumptions that matter for interpreting the current
results.

## Research Direction

- The main research target is **PQ account abstraction**: a boundary-aware
  Lean/Solidity verification pipeline for AA smart wallets that accept
  execution only after nonce/domain/key-commitment checks and successful
  post-quantum verifier-wrapper validation. This matches Antonio Sanso's
  *"The road to Post-Quantum Ethereum transactions is paved with Account
  Abstraction"* framing.
- The reference deployment shape is **FalconSimpleWallet**-style: no
  `ecrecover` in the wallet path; verification is against an explicit
  stored public key (or key commitment); signature acceptance is via the
  verifier wrapper, not the EVM's native crypto.
- Counter remains the calibration case for the Solidity/Lean/Yul bridge.
  ERC-20-style examples are optional calibration only.
- For PQ work, SoLean verifies contract-level authentication logic under
  explicit verifier assumptions. It does **not** verify the cryptographic
  security of Falcon (or any PQ scheme); the verifier stays an oracle or
  structured-verifier model.

## Arithmetic

- `UInt256` is represented as a structure carrying a `Nat` value plus a proof
  that the value is at most `2^256 - 1`.
- `UInt256.maxValue` is `2^256 - 1`.
- Checked addition returns `none` when the mathematical sum exceeds
  `UInt256.maxValue`.
- Checked subtraction returns `none` when the right-hand side is greater than
  the left-hand side.
- Existing storage values are type-enforced as bounded `UInt256` values.

## Execution

- Storage is modeled as a total mapping from slots to `UInt256` values.
- The environment contains `msg.sender` and an abstract verifier oracle of type
  `UInt256 -> UInt256 -> UInt256 -> UInt256 -> Bool`.
- `require false` reverts with `Failure.requireFailed`.
- `assert false` reverts with `Failure.assertFailed`.
- Arithmetic failure during expression evaluation reverts with
  `Failure.arithmeticFailed`.

## Account Abstraction

- `SoLean.Examples.AAWallet` is the first abstract AA/PQ-facing model.
- The model verifies wallet validation logic under an abstract verifier oracle.
- The verifier oracle is trusted as an assumption about the intended PQ
  verification result; SoLean does not currently verify PQ cryptographic
  security.
- Operation hashes, domains, signatures, addresses, and key commitments are
  represented as bounded `UInt256` placeholders.
- The model includes a configured entry point check, nonce check, domain check,
  verifier acceptance check, and checked nonce increment.
- This is not full EIP-4337 semantics and does not model calldata, memory, ABI,
  gas, bundlers, paymasters, aggregators, or external calls.

## PQ Verifier Wrapper

- `SoLean.Examples.PQVerifierWrapper` is the first standalone verifier-wrapper
  model.
- The wrapper checks modeled public-key length, signature length, domain, and
  abstract verifier acceptance.
- Successful wrapper validation proves there is no modeled bypass around those
  checks, and that wrapper storage is unchanged.
- Public keys, signatures, messages, domains, and lengths are represented as
  bounded `UInt256` placeholders.
- This does not verify PQ cryptographic security, byte-level parsing, ABI,
  calldata, memory, external calls, gas, or EVM behavior.

## FalconSimpleWallet Alignment

- `SoLean.Examples.AAWallet` + `SoLean.Examples.PQVerifierWrapper` +
  `SoLean.Examples.AAPQIntegration` are intended to model the
  **FalconSimpleWallet** deployment shape: an AA smart wallet that
  authenticates `UserOp`s against an explicit stored public key (or key
  commitment) via a PQ verifier wrapper, with no `ecrecover` in the
  validation path.
- The wallet's `keyCommitmentSlot` is the modeled "stored public key"
  anchor; the integrated flow's key-match guard enforces
  `input.publicKey == wallet.keyCommitment` before the wrapper call.
- The wrapper's `expectedPublicKeyLength`, `expectedSignatureLength`, and
  `expectedDomain` slots are the modeled deployment parameters of the
  verifier wrapper for a specific PQ scheme (e.g. Falcon-512 or
  ML-DSA-44, surfaced via `SoLean.Examples.SchemeParameters`).
- Hashing-scheme choices (Keccak-256 vs SHAKE-256 for `opHash`,
  EIP-712-style domain binding, etc.) are **not** modeled at the byte
  level. The `opHash` is a `UInt256` placeholder; downstream EVM-friendly
  vs non-EVM-friendly hashing is out of scope unless a future slice
  models it explicitly.

## Bundler / ECDSA Boundary

- ERC-4337 lets `UserOp`s be PQ-authenticated at the wallet layer.
  However, the final bundler transaction that lands the bundle on chain
  may still rely on ECDSA until protocol-level / native-AA work
  (RIP-7560, EIP-7701-like directions) lands.
- SoLean's proofs cover the **wallet-side** PQ-AA flow only. The
  residual ECDSA dependence at the bundler layer is an **explicit
  non-claim** of the certificate, not a solved problem.
- The wrapper-call shim (`AAPQIntegration.callVerifierWrapper`) and the
  EVM CALL model (`SoLean.EVM.Call`) cover the wallet-to-wrapper call
  boundary. They do **not** cover the EOA-to-EntryPoint or
  bundler-to-EntryPoint transaction layers.

## EIP-7702 Caveat

- EIP-7702 allows an EOA to delegate execution to a smart-wallet
  implementation, which can in principle add PQ-AA behavior to an
  existing account.
- However, the original ECDSA key for the EOA **remains valid for
  signing**, which is a PQ-resilience risk: anyone who can break the
  ECDSA key can authorize transactions independent of the PQ verifier
  wrapper.
- SoLean treats EIP-7702 as a **trust boundary / non-claim**, not as
  solved. A PQ-resilient deployment under EIP-7702 would require
  additional protocol-level guarantees (key disabling, key rotation,
  etc.) that are out of scope for SoLean's current proofs.

## AA + PQ Integration

- `SoLean.Examples.AAPQIntegration` composes the abstract wallet and verifier
  wrapper models.
- The integration model treats the wallet and wrapper as separate
  contract/storage boundaries.
- `AAPQIntegration.callVerifierWrapper` is a focused external-call shim that
  executes the wrapper model on wrapper storage and is proved equivalent to the
  previous direct integrated composition.
- Successful integrated validation proves wrapper checks, wallet checks, key
  agreement between wrapper input and wallet storage, and abstract verifier
  acceptance of the shared `(publicKey, opHash, domain, signature)` tuple.
- The source certificate records named verifier-oracle assumptions in
  `cryptoAssumptions` and a directed `cryptoAssumptionGraph` that links each
  assumption to each theorem it supports, including the modeled flow/layer.
  Lean proves this graph exactly covers the theorem references listed by the
  assumptions; Python audits that every edge resolves to `proofReferences`.
- `SoLean.Examples.ToyVerifier` defines `allFieldsEqualVerifier`, a
  deliberately non-cryptographic verifier calibration that accepts only when
  all modeled verifier fields are equal. Lean proves this toy model satisfies
  the three named verifier-oracle assumption predicates. This demonstrates the
  assumption-discharge pattern; it is not a PQ security claim.
- This does not model EVM `CALL`/`STATICCALL`, ABI encoding, returndata,
  calldata, memory, gas, reentrancy, or account-abstraction protocol machinery.

## Solidity And Yul

- `SoLean.Source.Shape` defines shared source-shape audit metadata used by
  Counter and AA/PQ artifacts. It is not a parser and does not add supported
  Solidity syntax.
- The AA/PQ Solidity sketch audit is a trusted restricted shape/body check. It
  requires the v1 names `lastOpHash`, `wrapperAddress`,
  `expectedWrapperAddress`, `executeUserOp`, and `validateAndExecuteV1`, and it
  recognizes the current v1 body shape exactly enough to compare a body summary
  to the Lean-owned v1 behavior summary and emit a per-statement trace. It
  still does not verify Solidity parsing generally or Solidity semantics.
- Solidity parsing and generation of SoLean models are not implemented beyond
  an explicit restricted Counter-subset parser.
- Yul parsing is limited to the restricted subset in `docs/yul-subset.md`.
- The current SoLean-to-Yul output is deterministic placeholder text for the
  Counter example only.
- `SoLean/Yul.lean` contains a hand-written Lean semantics for a restricted
  Yul subset. It is not full Yul or full EVM semantics.
- The restricted Lean Yul semantics models wrapping `add`, local variables,
  storage load/store, and revert guards for the Counter path.
- `SoLean/Examples/CounterYul.lean` proves that successful SoLean Counter
  executions are reproduced by the hand-written restricted Yul Counter model.
- `SoLean/Compiler.lean` contains a focused partial compiler from a one-parameter
  source language to restricted Lean Yul.
- `SoLean/Examples/CounterCompiler.lean` proves that the generic Counter source
  function instantiates to the existing Counter model and compiles to the
  existing restricted Yul Counter model.
- Lean exports deterministic Counter source and restricted-Yul artifacts for
  tests and audits. These artifacts are generated from Lean definitions, not
  proved to correspond to Python code.
- The Counter Solidity parser can emit deterministic source-shape JSON that is
  tested against the Lean-exported `CounterCompiler.counterFunction` artifact.
- The default Yul checker compares a restricted symbolic state-transform summary for
  Counter-shaped restricted-subset programs. This is not semantic Yul
  equivalence.
- The old bounded trace checker remains available as `--bounded-traces`.
  Strict restricted-subset AST equality is available as an explicit `--ast`
  mode, and normalized text comparison remains available as `--text`.
- `solc 0.8.35` is the intended pinned compiler version for local Counter Yul
  generation. It was chosen as the current stable Solidity compiler target when
  adopted, not because the proofs depend on that patch version.
  `scripts/solc_to_yul.py` rejects other solc versions. Generated `build/`
  artifacts are not committed yet.
- Real `solc 0.8.35 --ir` Counter output is currently outside the supported
  subset. The default classifier first observes the solc `IR:`
  preamble/wrapper. The explicit solc-inspection mode selects the deployed
  object and currently reports memory setup such as
  `mstore(64, memoryguard(128))` as the next unsupported blocker.
- The explicit solc function-inspection mode selects the generated `fun_inc_*`
  body for `inc`. Hexadecimal integer literals are parsed, and the current
  one-argument value helpers and `require_helper` are summarized for
  classification only. The current first unsupported function-body expression
  is `read_from_storage_split_offset_0_t_uint256`.
- The explicit solc function-summary mode recognizes the current Counter
  storage read, checked-add, storage update, and assert-helper patterns and
  emits a canonical restricted Counter Yul shape plus a line-by-line summary
  trace. This is trusted Python pattern recognition, not verified solc parsing
  or semantic equivalence.
- The semantic translations for the current Counter helper and adapter summary
  rules now have Lean-backed bridge theorems, except for `hexLiteralAsNat`,
  which remains parser-level trust and is covered by focused Python tests. The
  recognizer that finds those patterns inside real solc text is still trusted
  Python code.
- The Python emitter, Python parser, Solidity source, and real solc output are
  not yet connected to the Lean compiler by a verified translation. Current
  Python tests provide auditable structural alignment for Counter only.
