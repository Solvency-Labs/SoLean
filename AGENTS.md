# Instructions For Future Agents

SoLean is a focused research prototype, not a broad framework yet.

- The strategic direction is **PQ account abstraction**: a boundary-aware
  Lean/Solidity verification pipeline for AA smart wallets that accept
  execution only after nonce/domain/key-commitment checks and successful
  post-quantum verifier-wrapper validation. Match Antonio Sanso's
  *"The road to Post-Quantum Ethereum transactions is paved with Account
  Abstraction"* framing: focus on contract-level safety of the PQ-AA path,
  not broad DeFi and not cryptographic security of Falcon itself.
- The reference deployment shape is **FalconSimpleWallet**-style: no
  `ecrecover` in the wallet path, verification is against an explicit
  stored public key (or key commitment), and signature acceptance is via
  the verifier wrapper, not the EVM's native crypto.
- Keep Counter as the bridge calibration case. Use ERC-20 only as an
  optional calibration case if it teaches a reusable pattern. Do not
  broaden into a generic DeFi framework.
- Keep the project proof-oriented and scope-controlled.
- Prefer focused verified case studies over broad framework work.
- Do not drift into a broad DeFi framework before the AA/PQ authentication path
  is crisp.
- Do not silently approximate unsupported Solidity, EVM, or Yul features.
- Every generated or proved case study must state its assumptions and
  limitations.
- For PQ work, verify contract logic around authentication and verifier usage;
  do not claim cryptographic security of a PQ scheme unless a separate verified
  crypto model is introduced. Falcon/ML-DSA verification stays an oracle or
  structured-verifier model in SoLean.
- EVM-friendly hashing choices like Keccak-vs-SHAKE are out of scope unless
  modeled explicitly; the source certificate must mark them as such.
- **Bundler/ECDSA boundary:** ERC-4337 lets `UserOp`s be PQ-authenticated at
  the wallet layer, but the final bundler transaction may still rely on
  ECDSA until protocol-level/native-AA work (RIP-7560 / EIP-7701-like
  directions) lands. Treat that residual ECDSA dependence as an explicit
  non-claim, not as solved.
- **EIP-7702 caveat:** delegating an EOA to a smart-wallet implementation
  *can* add PQ-AA behavior, but the original ECDSA key remains valid for
  signing — a PQ-resilience risk. SoLean treats this as a non-claim /
  trust boundary, not as solved.
- Do not claim full Solidity verification.
- Do not claim Yul equivalence is solved until a real semantic checker exists.
- Run `lake build` after Lean changes. If Lean is unavailable, say so clearly.
- Keep Python scripts simple, deterministic, and dependency-light.
- Prefer readable data structures and explicit transformations over clever
  metaprogramming.
- Add TODO comments where future work is obvious, but keep TODOs specific.
- Keep README examples honest about what is implemented and what is trusted.
