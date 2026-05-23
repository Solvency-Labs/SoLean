import SoLean.DSL

namespace SoLean
namespace EVM

/--
Modeled EVM address. Wraps a `UInt256` to keep the type distinct from raw
values flowing through the DSL.
-/
structure Address where
  value : UInt256
deriving Repr, DecidableEq

/--
Modeled calldata as a sequence of `UInt256` words.

This is a deliberate simplification: real EVM calldata is a byte string with
a 4-byte selector followed by ABI-encoded arguments. The current model uses
one word per argument, no selector, no padding. The point is to introduce
the *shape* of a call boundary (data in, data out, distinguishable
success/revert) without committing to full ABI semantics yet.
-/
abbrev Calldata := List UInt256

/--
Modeled returndata, same word-list shape as `Calldata`.
-/
abbrev Returndata := List UInt256

/--
The result of a modeled EVM `CALL`.

`success` carries the returndata produced by the callee on a successful
return. `revert` carries the returndata produced by the callee on a revert
(in real EVM, this is the bytes after `REVERT`). The caller is expected to
dispatch on the constructor.

Gas, value transfer, code resolution, and reentrancy are intentionally not
modeled here. This is the *first* call-shaped boundary, not full EVM CALL
semantics.
-/
inductive CallResult where
  | success : Returndata -> CallResult
  | revert : Returndata -> CallResult
deriving Repr

/--
An `Env` extended with an EVM-call oracle and the address of the verifier
wrapper.

The `evmCall` field is the oracle that, given a callee address, calldata,
and the callee's storage, returns a `CallResult`. The `wrapperAddress` field
names the address of the PQ verifier wrapper as seen from the wallet.

Concrete instantiations and oracle-consistency assumptions live in the
modules that consume this type; this file only defines the data layer.
-/
structure EvmEnv where
  base : Env
  evmCall : Address -> Calldata -> Storage -> CallResult
  wrapperAddress : Address

/--
Modeled EVM gas counter. A natural number; one "unit" per modeled
operation. This is not the real EVM gas schedule (no per-opcode costs,
no calldata word/byte costs, no refunds) — it is the smallest counter
needed to make "did the caller forward enough gas?" a meaningful
question.
-/
abbrev Gas := Nat

/--
An `EvmEnv` extended with a per-call gas-cost function and a gas budget
held by the caller.

`gasCost addr calldata` is the modeled gas consumed by a call to `addr`
with the given calldata. `gasBudget` is the gas the caller has available
to forward. A call with `gasBudget < gasCost ...` is considered out-of-gas
and produces no `CallResult`.

This is the data layer for "did the caller forward enough gas?" — the
consistency assumptions and the gas-aware call function live in modules
that consume this type.
-/
structure EvmGasEnv extends EvmEnv where
  gasCost : Address -> Calldata -> Gas
  gasBudget : Gas

/--
Gas-aware call. Returns `none` when the caller's `gasBudget` is below the
modeled `gasCost` for the call; otherwise returns `some` of the underlying
`evmCall` result. The `Option` distinguishes "out of gas" from
"called, then reverted" — two structurally different failure modes that
real auditors care about.
-/
def EvmGasEnv.callWithGas
    (geenv : EvmGasEnv) (addr : Address) (calldata : Calldata)
    (storage : Storage) : Option CallResult :=
  if geenv.gasCost addr calldata <= geenv.gasBudget then
    some (geenv.evmCall addr calldata storage)
  else
    none

end EVM
end SoLean
