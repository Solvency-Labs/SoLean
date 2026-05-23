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
Modeled function selector. Real EVM selectors are the first 4 bytes of
`keccak256(signature)`; this model uses a full `UInt256` to stay inside
the existing word size without modeling hashing.
-/
abbrev Selector := UInt256

/--
Structured ABI calldata: a selector, a fixed-shape `head` for
statically-sized arguments, and a `tail` for dynamically-sized data
(currently just a word list).

Real Solidity ABI distinguishes static heads (encoded inline) from
dynamic tails (encoded at offsets named in the head). This model keeps
both as `List UInt256` — there's no per-byte layout — but the
separation lets the encoder/decoder distinguish "what the function
signature requires" from "extra data."
-/
structure CalldataABI where
  selector : Selector
  head : List UInt256
  tail : List UInt256
deriving Repr, DecidableEq

/--
Encode a `CalldataABI` into the flat `Calldata` word list. Selector
goes first, then head, then tail. This is the inverse of
`decodeCalldataABI` for the fixed-head case below.
-/
def CalldataABI.encode (c : CalldataABI) : List UInt256 :=
  c.selector :: (c.head ++ c.tail)

/--
Decode a flat calldata into a `CalldataABI` with a head of the given
length and the remainder as tail. Returns `none` if the calldata is
shorter than `selector + head`.
-/
def decodeCalldataABI (headLen : Nat) (calldata : List UInt256) :
    Option CalldataABI :=
  match calldata with
  | [] => none
  | selector :: rest =>
      if h : headLen <= rest.length then
        some
          { selector := selector,
            head := rest.take headLen,
            tail := rest.drop headLen }
      else
        none

/--
Encoded calldata length: selector + head + tail.
-/
theorem encode_length (c : CalldataABI) :
    (CalldataABI.encode c).length = 1 + c.head.length + c.tail.length := by
  unfold CalldataABI.encode
  simp [List.length_cons, List.length_append]
  omega

/--
Encoded calldata starts with the selector.
-/
theorem encode_head_is_selector (c : CalldataABI) :
    ∃ rest, CalldataABI.encode c = c.selector :: rest := by
  refine ⟨c.head ++ c.tail, ?_⟩
  unfold CalldataABI.encode
  rfl

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
  /-- Modeled code hash deployed at `wrapperAddress`. Real EVM
      `EXTCODEHASH` returns `keccak256(code)`; this is a placeholder
      identifier that downstream assumptions can reference. -/
  wrapperCodeHash : UInt256

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
EIP-150 63/64 rule: when a contract makes an external call, the EVM caps
the gas forwarded to the callee at `63/64` of the *available* gas at the
call site. The remaining `1/64` stays with the caller so it can recover
from a callee revert.

Computed as `g - g/64` using Nat division. For all `g`, this is at most
`g` (so the caller has at least `g/64` left after the call) and at most
`(63/64) * g` (the real EIP-150 forwarding cap).
-/
def forward6364 (g : Gas) : Gas := g - g / 64

theorem forward6364_le_self (g : Gas) : forward6364 g <= g := by
  unfold forward6364
  exact Nat.sub_le g (g / 64)

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

/--
Result of a reentrant call: a `CallResult` plus the (possibly modified)
*caller* storage after any reentrant write-back.

Real EVM allows a callee to make further calls (including back into the
caller). This type makes that possibility explicit by letting the
oracle's result carry a new caller-side storage. Concrete oracles
constrained by `NoCallback` leave the caller storage unchanged.
-/
structure ReentrantCallResult where
  result : CallResult
  callerStorageAfter : Storage

/--
A richer `EvmEnv` whose oracle can in principle write back into the
caller's storage. The non-reentrant `EvmEnv.evmCall` is recovered by
projecting `reentrantEvmCall ... wl |>.result` and discarding the
returned caller storage.

This type is the substrate for stating reentrancy assumptions explicitly:
a model that uses `reentrantEvmCall` and then adds `NoCallback` is
provably no-reentrant by assumption rather than by accident of the
non-reentrant interface.
-/
structure ReentrantEvmEnv extends EvmEnv where
  reentrantEvmCall :
    Address -> Calldata -> Storage -> Storage -> ReentrantCallResult

end EVM
end SoLean
