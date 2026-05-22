# Instructions For Future Agents

SoLean is a serious research prototype, not a broad framework yet.

- The strategic direction is now hybrid but PQ-account-abstraction leaning:
  keep Counter as the bridge calibration case, use ERC-20 only as a small
  learning case if useful, and prioritize account-abstraction wallet
  validation plus post-quantum verifier-wrapper contract logic.
- Keep the project minimal and proof-oriented.
- Prefer small verified case studies over broad framework work.
- Do not drift into a broad DeFi framework before the AA/PQ authentication path
  is crisp.
- Do not silently approximate unsupported Solidity, EVM, or Yul features.
- Every generated or proved case study must state its assumptions and
  limitations.
- For PQ work, verify contract logic around authentication and verifier usage;
  do not claim cryptographic security of a PQ scheme unless a separate verified
  crypto model is introduced.
- Do not claim full Solidity verification.
- Do not claim Yul equivalence is solved until a real semantic checker exists.
- Run `lake build` after Lean changes. If Lean is unavailable, say so clearly.
- Keep Python scripts simple, deterministic, and dependency-light.
- Prefer readable data structures and explicit transformations over clever
  metaprogramming.
- Add TODO comments where future work is obvious, but keep TODOs specific.
- Keep README examples honest about what is implemented and what is trusted.
