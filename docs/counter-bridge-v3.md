# Counter Bridge v3

`Counter Bridge v3` removes the old bundled `transparentValueHelper` rule from
the Counter bridge. The real-solc function summary now names each observed
transparent helper rewrite, and every current Counter semantic adapter rewrite
except hex-literal parsing has a Lean proof reference.

This is still not verified Solidity parsing, verified solc parsing, or semantic
equivalence with real solc Yul.

This page records the v3 milestone. The current line-auditable bridge boundary
is `Counter Bridge v4`; see `docs/counter-bridge-v4.md`.

## Success Condition

```text
real solc Counter fun_inc_*
  -> trusted Python recognizer
  -> named helper/adaptor rules
  -> Lean proof references for current semantic rewrites
  -> normalized restricted Yul matches Lean-owned Counter Yul
```

## Current Rule Boundary

The bridge manifest exports the expected Counter summary rules in stable
first-use order:

- `hexLiteralAsNat`: parse hexadecimal integer literals as natural-number
  literals. This remains parser-level trust.
- `cleanupUint256AsIdentity`: treat `cleanup_t_uint256(x)` as `x`.
- `convertRationalZeroByOneToUint256AsIdentity`: treat
  `convert_t_rational_0_by_1_to_t_uint256(x)` as `x`.
- `requireHelperAsRevertGuard`: treat `require_helper(cond)` as a revert
  guard.
- `storageReadSlot0AsSload`: treat the current slot-0 read helper as
  `sload(0)`.
- `checkedAddUInt256AsAddWithOverflowGuard`: treat the checked-add helper as
  wrapping `add` plus the overflow guard.
- `storageUpdateSlot0AsSstore`: treat the current slot-0 update helper as
  `sstore(0, value)`.
- `assertHelperAsRevertGuard`: treat the current assertion helper as a revert
  guard.

The identity-like helper names `identityHelperAsIdentity` and
`cleanupRationalZeroByOneAsIdentity` are known to the Python summarizer and have
small Lean identity proofs available, but they are not listed in the Counter
bridge manifest unless they appear in the summarized `fun_inc_*` body.

## Trust Boundary

The bridge report is now stronger because the main current Counter semantic
rewrites are Lean-backed. The remaining trusted boundaries are still explicit:

- `hexLiteralAsNat` is parser-level trust.
- The Solidity parser is a trusted Counter-only parser.
- The solc IR recognizer/summarizer is trusted Python pattern recognition.
- Real solc deployment wrappers, ABI dispatch, memory setup, helper bodies, and
  full Yul/EVM semantics are outside the current verified model.
- Passing the bridge report is not semantic equivalence between real solc Yul
  and SoLean-generated Yul.

## Commands

```bash
lake env lean --run SoLean/CounterArtifactsMain.lean bridge-json
python3 scripts/check_counter_bridge.py \
  --format markdown \
  --solidity examples/Counter.sol \
  --solc-yul build/Counter.solc.yul
python3 scripts/demo_counter_bridge.py
```
