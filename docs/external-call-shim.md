# External-Call Shim v0

`AAPQIntegration.callVerifierWrapper` is SoLean's first modeled wallet-to-wrapper
call boundary.

It is intentionally not EVM `CALL` or `STATICCALL`. It models only the current
contract-logic boundary:

```text
wallet/integration boundary
  -> callVerifierWrapper
  -> execute PQVerifierWrapper.verifyProgram on wrapper storage
  -> success with wrapper storage or revert
```

## Proved Shape

The shim is backed by Lean theorems:

- `callVerifierWrapper_eq_verifyProgram`
- `callVerifierWrapper_success_properties`
- `validateIntegratedViaCall_eq_validateIntegrated`
- `validateIntegratedViaCall_success_properties`
- `validateAndExecuteViaCall_eq_validateAndExecute`

Together, these say that the call-shim flow has the same modeled behavior as
the existing direct integrated flow, and that a successful shimmed wrapper call
still implies the wrapper's length/domain/verifier checks.

## Non-Claims

This does not model:

- EVM call frames;
- `CALL`, `STATICCALL`, or returndata;
- ABI encoding/decoding;
- gas or call failure modes;
- reentrancy;
- real Solidity external-call semantics.

The value of this milestone is audit precision. The AA/PQ model now has an
explicit name and proof boundary for "wallet invokes verifier wrapper" instead
of hiding that step inside direct composition prose.
