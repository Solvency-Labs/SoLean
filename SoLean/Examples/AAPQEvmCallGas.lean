import SoLean.Examples.AAPQEvmCall

namespace SoLean
namespace Examples
namespace AAPQEvmCallGas

open EVM

/--
The named gas assumption: the caller has forwarded enough gas to cover the
modeled cost of the wrapper call.

This is the analog of `WrapperOracleConsistent` for the gas dimension. The
existing call-shaped equivalence theorems hold only when the call is
actually made (i.e., not aborted with out-of-gas); `EnoughGas` makes that
condition explicit and auditable.
-/
def EnoughGas
    (geenv : EvmGasEnv)
    (input : AAPQIntegration.IntegratedInput) : Prop :=
  geenv.gasCost geenv.wrapperAddress
      (AAPQEvmCall.buildVerifierCalldata input) <=
    geenv.gasBudget

/--
Result of the gas-aware integrated flow. `outOfGas` distinguishes
"insufficient gas budget" from any business-logic revert — the latter is
encoded by lifting `EvmCallIntegratedResult` into a wrapper variant.
-/
inductive GasAwareIntegratedResult where
  | run : AAPQEvmCall.EvmCallIntegratedResult -> GasAwareIntegratedResult
  | outOfGas : GasAwareIntegratedResult

/--
Gas-aware integrated validation: check the gas budget against the modeled
cost of the wrapper call; if insufficient, return `outOfGas` and skip the
wallet entirely. Otherwise delegate to `validateIntegratedViaEvmCall` over
the underlying `EvmEnv`.
-/
def validateIntegratedViaEvmCallWithGas
    (geenv : EvmGasEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) : GasAwareIntegratedResult :=
  match geenv.callWithGas geenv.wrapperAddress
      (AAPQEvmCall.buildVerifierCalldata input) wrapperStorage with
  | some _ =>
      .run
        (AAPQEvmCall.validateIntegratedViaEvmCall geenv.toEvmEnv input
          wrapperStorage walletStorage)
  | none => .outOfGas

/--
Under `EnoughGas`, the gas-aware flow does not abort with `outOfGas` and
its `run` payload is exactly the result of the gas-free
`validateIntegratedViaEvmCall`.
-/
theorem validateIntegratedViaEvmCallWithGas_eq_under_enough_gas
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (h : EnoughGas geenv input) :
    validateIntegratedViaEvmCallWithGas geenv input wrapperStorage walletStorage =
      GasAwareIntegratedResult.run
        (AAPQEvmCall.validateIntegratedViaEvmCall geenv.toEvmEnv input
          wrapperStorage walletStorage) := by
  unfold validateIntegratedViaEvmCallWithGas EvmGasEnv.callWithGas
  unfold EnoughGas at h
  rw [if_pos h]

/--
Out-of-gas characterization: if the gas budget is below the modeled cost,
the gas-aware flow returns `outOfGas` regardless of input semantics.
-/
theorem validateIntegratedViaEvmCallWithGas_outOfGas_when_insufficient
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (h : Not (EnoughGas geenv input)) :
    validateIntegratedViaEvmCallWithGas geenv input wrapperStorage walletStorage =
      GasAwareIntegratedResult.outOfGas := by
  unfold validateIntegratedViaEvmCallWithGas EvmGasEnv.callWithGas
  unfold EnoughGas at h
  rw [if_neg h]

/--
Gas-aware success-iff equivalence: under `EnoughGas` and
`WrapperOracleConsistent`, the gas-aware flow succeeds iff the canonical
direct integrated flow succeeds. Combines the gas-free iff theorem with
the `EnoughGas` reduction above.
-/
theorem validateIntegratedViaEvmCallWithGas_is_success_iff_validateIntegrated_is_success
    (geenv : EvmGasEnv)
    (hConsistent : AAPQEvmCall.WrapperOracleConsistent geenv.toEvmEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (hGas : EnoughGas geenv input) :
    (∃ fw fwa,
      validateIntegratedViaEvmCallWithGas geenv input wrapperStorage walletStorage =
        GasAwareIntegratedResult.run
          (AAPQEvmCall.EvmCallIntegratedResult.success fw fwa)) ↔
    (∃ fw fwa,
      AAPQIntegration.validateIntegrated geenv.toEvmEnv.base input
          wrapperStorage walletStorage =
        AAPQIntegration.IntegratedResult.success fw fwa) := by
  rw [validateIntegratedViaEvmCallWithGas_eq_under_enough_gas geenv input
        wrapperStorage walletStorage hGas]
  constructor
  · rintro ⟨fw, fwa, h⟩
    have hInner :
        AAPQEvmCall.validateIntegratedViaEvmCall geenv.toEvmEnv input
            wrapperStorage walletStorage =
          AAPQEvmCall.EvmCallIntegratedResult.success fw fwa := by
      injection h
    exact
      (AAPQEvmCall.validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success
          geenv.toEvmEnv hConsistent input wrapperStorage walletStorage).mp
        ⟨fw, fwa, hInner⟩
  · intro hDirect
    obtain ⟨fw, fwa, hInner⟩ :=
      (AAPQEvmCall.validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success
          geenv.toEvmEnv hConsistent input wrapperStorage walletStorage).mpr
        hDirect
    exact ⟨fw, fwa, by rw [hInner]⟩

/--
EIP-150-aware variant of the gas budget check: the caller forwards only
`forward6364 gasBudget` to the wrapper, holding back `1/64` for its own
post-call cleanup. The wrapper must fit within the forwarded amount.

A real-EVM-faithful gas-cost comparison: not against the caller's full
budget but against what the call frame actually sees after the 63/64
trim.
-/
def EnoughGasAfter6364Forwarding
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput) : Prop :=
  geenv.gasCost geenv.wrapperAddress
      (AAPQEvmCall.buildVerifierCalldata input) <=
    EVM.forward6364 geenv.gasBudget

/--
`EnoughGasAfter6364Forwarding` is stricter than `EnoughGas`: surviving the
63/64 trim implies surviving the unrestricted budget check. Useful as a
"refinement" lemma when reasoning about EIP-150 in terms of the existing
gas-aware flow.
-/
theorem enoughGasAfter6364Forwarding_implies_enoughGas
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput)
    (h : EnoughGasAfter6364Forwarding geenv input) :
    EnoughGas geenv input :=
  Nat.le_trans h (EVM.forward6364_le_self geenv.gasBudget)

/--
EIP-150-aware gas-aware flow: same shape as
`validateIntegratedViaEvmCallWithGas`, but the forwarded gas is
`forward6364 gasBudget`. Returns `outOfGas` when the cost exceeds the
forwarded amount.
-/
def validateIntegratedViaEvmCallWith6364Gas
    (geenv : EvmGasEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) : GasAwareIntegratedResult :=
  if geenv.gasCost geenv.wrapperAddress
      (AAPQEvmCall.buildVerifierCalldata input) <=
      EVM.forward6364 geenv.gasBudget then
    .run
      (AAPQEvmCall.validateIntegratedViaEvmCall geenv.toEvmEnv input
        wrapperStorage walletStorage)
  else
    .outOfGas

/--
Under EIP-150's 63/64 rule, when the caller has enough gas after
forwarding, the EIP-150-aware flow is exactly the gas-free EVM-call flow.
-/
theorem validateIntegratedViaEvmCallWith6364Gas_eq_under_enoughGas
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (h : EnoughGasAfter6364Forwarding geenv input) :
    validateIntegratedViaEvmCallWith6364Gas geenv input wrapperStorage
        walletStorage =
      GasAwareIntegratedResult.run
        (AAPQEvmCall.validateIntegratedViaEvmCall geenv.toEvmEnv input
          wrapperStorage walletStorage) := by
  unfold validateIntegratedViaEvmCallWith6364Gas
  unfold EnoughGasAfter6364Forwarding at h
  rw [if_pos h]

/--
Conservative-collapse theorem: when EIP-150 forwarding is satisfied, the
EIP-150-aware flow agrees with the existing non-63/64 gas-aware flow.
The EIP-150 refinement does not change the outcome whenever the caller
has enough gas-after-forwarding.
-/
theorem validateIntegratedViaEvmCallWith6364Gas_eq_unrestricted_under_enoughGas
    (geenv : EvmGasEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (h : EnoughGasAfter6364Forwarding geenv input) :
    validateIntegratedViaEvmCallWith6364Gas geenv input wrapperStorage
        walletStorage =
      validateIntegratedViaEvmCallWithGas geenv input wrapperStorage
        walletStorage := by
  rw [validateIntegratedViaEvmCallWith6364Gas_eq_under_enoughGas geenv input
        wrapperStorage walletStorage h]
  rw [validateIntegratedViaEvmCallWithGas_eq_under_enough_gas geenv input
        wrapperStorage walletStorage
        (enoughGasAfter6364Forwarding_implies_enoughGas geenv input h)]

end AAPQEvmCallGas
end Examples
end SoLean
