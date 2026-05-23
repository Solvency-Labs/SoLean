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

end EVM
end SoLean
