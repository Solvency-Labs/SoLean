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

end AAPQEvmCallGas
end Examples
end SoLean
