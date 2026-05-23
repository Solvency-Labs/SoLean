import SoLean.EVM.Call
import SoLean.Examples.AAPQIntegration

namespace SoLean
namespace Examples
namespace AAPQEvmCall

open EVM

/--
Serialize the wrapper-side arguments of an `IntegratedInput` into modeled
calldata. The argument order matches `PQVerifierWrapper.verifyProgram`'s
parameter list: publicKey, publicKeyLength, message (= opHash), domain,
signature, signatureLength.
-/
def buildVerifierCalldata (input : AAPQIntegration.IntegratedInput) :
    Calldata :=
  [input.publicKey, input.publicKeyLength, input.opHash, input.domain,
   input.signature, input.signatureLength]

/--
Parse a modeled calldata word list back into a `WrapperInput`. Returns
`none` for any calldata that doesn't have exactly six words in the expected
order — this is the smallest "well-formed calldata" check the caller can
make.
-/
def parseVerifierCalldata (calldata : Calldata) :
    Option PQVerifierWrapper.WrapperInput :=
  match calldata with
  | [publicKey, publicKeyLength, message, domain, signature, signatureLength] =>
      some
        { publicKey := publicKey,
          publicKeyLength := publicKeyLength,
          message := message,
          domain := domain,
          signature := signature,
          signatureLength := signatureLength }
  | _ => none

/--
Calldata round-trip: serializing an `IntegratedInput` and parsing it back
yields exactly `AAPQIntegration.toWrapperInput input`.
-/
theorem parse_build_verifier_calldata
    (input : AAPQIntegration.IntegratedInput) :
    parseVerifierCalldata (buildVerifierCalldata input) =
      some (AAPQIntegration.toWrapperInput input) := by
  rfl

/--
Lift a wrapper `ExecResult` into the modeled `CallResult`.

A successful wrapper execution returns no payload in this first model
(the wrapper's `verifyProgram` just asserts conditions; it does not produce
output beyond the success/revert distinction). A reverted execution also
returns no payload here. Future revisions could attach structured returndata
once the wrapper exposes a richer interface.
-/
def liftWrapperResult : ExecResult -> CallResult
  | .success _ => CallResult.success []
  | .revert _ => CallResult.revert []

/--
The named cross-contract assumption that ties the modeled `evmCall` oracle
to the existing wrapper semantics: when the wallet calls the wrapper
address with well-formed verifier calldata, the oracle's result equals
`liftWrapperResult` applied to running the wrapper program directly.

This is the analog of the verifier-oracle assumptions for cross-contract
calls. It is not a claim about real EVM `CALL`; it is the explicit
contract that lets the via-EVM-call flow be proved equivalent to the
direct composition.
-/
def WrapperOracleConsistent (eenv : EvmEnv) : Prop :=
  ∀ input wrapperStorage,
    eenv.evmCall eenv.wrapperAddress
        (buildVerifierCalldata input)
        wrapperStorage =
      liftWrapperResult
        (exec eenv.base
          (PQVerifierWrapper.verifyProgram (AAPQIntegration.toWrapperInput input))
          wrapperStorage)

/--
Result of `validateIntegratedViaEvmCall`. Mirrors `IntegratedResult` but
carries an explicit `oracleFailure` failure kind for the case where the
EVM call returns malformed returndata — the wallet has to dispatch on the
shape of the result, not just succeed/revert.

For the current minimal model returndata is always `[]`, so this extra
failure kind is structurally reachable only through future extensions. The
constructor exists so the type can grow without breaking callers.
-/
inductive EvmCallIntegratedResult where
  | success : Storage -> Storage -> EvmCallIntegratedResult
  | wrapperRevert : Returndata -> EvmCallIntegratedResult
  | walletRevert : Failure -> EvmCallIntegratedResult

/--
Integrated validation routed through the EVM-call oracle for the wrapper.

The wallet builds calldata, makes an EVM call to the wrapper address, and
dispatches on the `CallResult`. On `success`, it runs `walletProgram` on
its own storage; the wrapper storage update is the oracle's responsibility
(modeled as unchanged here, mirroring the wrapper's existing
"storage unchanged" post-condition).
-/
def validateIntegratedViaEvmCall
    (eenv : EvmEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) : EvmCallIntegratedResult :=
  match eenv.evmCall eenv.wrapperAddress
      (buildVerifierCalldata input) wrapperStorage with
  | .success _ =>
      match exec eenv.base (AAPQIntegration.walletProgram input)
          walletStorage with
      | .success finalWalletStorage =>
          .success wrapperStorage finalWalletStorage
      | .revert failure => .walletRevert failure
  | .revert returndata => .wrapperRevert returndata

/--
Equivalence theorem: under `WrapperOracleConsistent`, the EVM-call routed
flow agrees with the direct composition wherever the latter terminates in
`success`. The successful path of `validateIntegrated` lifts to the
`EvmCallIntegratedResult.success` constructor, preserving `finalWrapper`
(which equals `wrapperStorage` by the wrapper's storage-unchanged
post-condition) and `finalWallet`.
-/
theorem validateIntegratedViaEvmCall_success_matches_validateIntegrated
    (eenv : EvmEnv) (hConsistent : WrapperOracleConsistent eenv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage)
    (h :
      AAPQIntegration.validateIntegrated eenv.base input
          wrapperStorage walletStorage =
        AAPQIntegration.IntegratedResult.success finalWrapper finalWallet) :
    validateIntegratedViaEvmCall eenv input wrapperStorage walletStorage =
      EvmCallIntegratedResult.success wrapperStorage finalWallet := by
  have hPost :=
    AAPQIntegration.validateIntegrated_success_properties
      eenv.base wrapperStorage walletStorage finalWrapper finalWallet input h
  have hWrapperStorageEq : finalWrapper = wrapperStorage := hPost.1.2.2.2.2
  simp only [AAPQIntegration.validateIntegrated] at h
  generalize hWrapperExec :
      exec eenv.base
          (PQVerifierWrapper.verifyProgram
            (AAPQIntegration.toWrapperInput input))
          wrapperStorage = wrapperResult at h
  cases wrapperResult with
  | success postWrapper =>
      generalize hWalletExec :
          exec eenv.base (AAPQIntegration.walletProgram input) walletStorage =
            walletResult at h
      cases walletResult with
      | success postWallet =>
          injection h with hWrapEq hWallEq
          have hPostWrapperEq : postWrapper = wrapperStorage :=
            hWrapEq.trans hWrapperStorageEq
          subst hPostWrapperEq
          subst hWallEq
          unfold validateIntegratedViaEvmCall
          rw [hConsistent input postWrapper, hWrapperExec]
          simp only [liftWrapperResult, hWalletExec]
      | revert _ =>
          cases h
  | revert _ =>
      cases h

/--
The call-shaped flow's success is mapped one-to-one with the canonical
flow's success under `WrapperOracleConsistent`. The backward direction
re-uses the existing success-matches theorem; the forward direction unfolds
the call-shaped flow, uses the oracle assumption to relate `evmCall`'s
result to direct wrapper execution, observes that `liftWrapperResult`
returns `CallResult.success` only on `ExecResult.success`, and then
recovers the canonical `IntegratedResult.success` from the wallet exec.
-/
theorem validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success
    (eenv : EvmEnv) (hConsistent : WrapperOracleConsistent eenv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) :
    (∃ fw fwa,
      validateIntegratedViaEvmCall eenv input wrapperStorage walletStorage =
        EvmCallIntegratedResult.success fw fwa) ↔
    (∃ fw fwa,
      AAPQIntegration.validateIntegrated eenv.base input wrapperStorage walletStorage =
        AAPQIntegration.IntegratedResult.success fw fwa) := by
  refine ⟨?_, ?_⟩
  · rintro ⟨fw, fwa, hCall⟩
    unfold validateIntegratedViaEvmCall at hCall
    rw [hConsistent input wrapperStorage] at hCall
    generalize hWrapperExec :
        exec eenv.base
            (PQVerifierWrapper.verifyProgram
              (AAPQIntegration.toWrapperInput input))
            wrapperStorage = wrapperResult at hCall
    cases wrapperResult with
    | success postWrapper =>
        simp only [liftWrapperResult] at hCall
        generalize hWalletExec :
            exec eenv.base (AAPQIntegration.walletProgram input)
                walletStorage = walletResult at hCall
        cases walletResult with
        | success postWallet =>
            refine ⟨postWrapper, postWallet, ?_⟩
            simp only [AAPQIntegration.validateIntegrated, hWrapperExec,
              hWalletExec]
        | revert _ =>
            cases hCall
    | revert _ =>
        simp only [liftWrapperResult] at hCall
        cases hCall
  · rintro ⟨fw, fwa, hDirect⟩
    refine ⟨wrapperStorage, fwa, ?_⟩
    exact
      validateIntegratedViaEvmCall_success_matches_validateIntegrated
        eenv hConsistent input wrapperStorage walletStorage fw fwa hDirect

end AAPQEvmCall
end Examples
end SoLean
