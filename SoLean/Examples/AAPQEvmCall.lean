import SoLean.EVM.Call
import SoLean.Examples.AAPQIntegration

namespace SoLean
namespace Examples
namespace AAPQEvmCall

open EVM

/--
The modeled function selector for `PQVerifierWrapper.verify`.

Real EVM uses the first 4 bytes of `keccak256("verify(uint256,uint256,...)")`;
here we just pick a distinct `UInt256` constant. The point is that
`parseVerifierCalldata` checks the selector against this constant before
accepting any arguments — so calldata addressed to a different function
selector is rejected by shape.
-/
def verifySelector : Selector := UInt256.one

/--
Serialize the wrapper-side arguments of an `IntegratedInput` into modeled
calldata, prepended by the `verifySelector`. The argument order matches
`PQVerifierWrapper.verifyProgram`'s parameter list: publicKey,
publicKeyLength, message (= opHash), domain, signature, signatureLength.
-/
def buildVerifierCalldata (input : AAPQIntegration.IntegratedInput) :
    Calldata :=
  [verifySelector, input.publicKey, input.publicKeyLength, input.opHash,
   input.domain, input.signature, input.signatureLength]

/--
Parse a modeled calldata word list back into a `WrapperInput`. Returns
`none` for any calldata whose first word isn't `verifySelector` (wrong
function) or whose argument count is wrong (malformed payload).
-/
def parseVerifierCalldata (calldata : Calldata) :
    Option PQVerifierWrapper.WrapperInput :=
  match calldata with
  | [selector, publicKey, publicKeyLength, message, domain, signature,
     signatureLength] =>
      if selector = verifySelector then
        some
          { publicKey := publicKey,
            publicKeyLength := publicKeyLength,
            message := message,
            domain := domain,
            signature := signature,
            signatureLength := signatureLength }
      else
        none
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
Wrong-selector rejection: a 7-word calldata whose first word isn't
`verifySelector` is rejected by `parseVerifierCalldata`. The selector check
is the smallest piece of ABI dispatch discipline this layer enforces.
-/
theorem parseVerifierCalldata_rejects_wrong_selector
    (selector publicKey publicKeyLength message domain signature
      signatureLength : UInt256)
    (h : Not (selector = verifySelector)) :
    parseVerifierCalldata
        [selector, publicKey, publicKeyLength, message, domain, signature,
         signatureLength] = none := by
  simp only [parseVerifierCalldata, h, if_false]

/--
Wrong-length rejection: a calldata word list with fewer than seven words is
rejected outright, regardless of any selector word. Shows that the layer
demands the full ABI shape before any field is interpreted.
-/
theorem parseVerifierCalldata_rejects_short_calldata
    (words : Calldata) (h : words.length < 7) :
    parseVerifierCalldata words = none := by
  match words, h with
  | [], _ => rfl
  | [_], _ => rfl
  | [_, _], _ => rfl
  | [_, _, _], _ => rfl
  | [_, _, _, _], _ => rfl
  | [_, _, _, _, _], _ => rfl
  | [_, _, _, _, _, _], _ => rfl
  | _ :: _ :: _ :: _ :: _ :: _ :: _ :: _, h =>
      simp only [List.length_cons] at h
      omega

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
The canonical code hash that an honest wrapper deployment should declare.

This is a *placeholder* constant — there is no `keccak256` here yet — but
it gives `WrapperCodeBound` something concrete to compare against. Two
`EvmEnv`s declaring the same `wrapperCodeHash` are claiming to deploy the
same wrapper code at `wrapperAddress`.
-/
def canonicalWrapperCodeHash : UInt256 := UInt256.one

/--
Code-resolution assumption: the modeled code deployed at `wrapperAddress`
matches the canonical wrapper code hash. This is the named EVM-layer
companion to `WrapperOracleConsistent` — together they say "the address
hosts the right code, and the oracle's behavior at that address matches
the wrapper semantics."

Standalone, this is a single equation. Its value is enumeration in the
certificate: future Lane A milestones (address discrimination, reentrant
callbacks) extend the `EvmEnv` interface, and listing `WrapperCodeBound`
explicitly forces the certificate to acknowledge the deployed-code
assumption rather than leaving it implicit.
-/
def WrapperCodeBound (eenv : EvmEnv) : Prop :=
  eenv.wrapperCodeHash = canonicalWrapperCodeHash

/--
Trivial consequence: under `WrapperCodeBound`, the env's
`wrapperCodeHash` equals `canonicalWrapperCodeHash` by definition. The
content is the named assumption, not the math.
-/
theorem WrapperCodeBound_eq_canonical
    (eenv : EvmEnv) (h : WrapperCodeBound eenv) :
    eenv.wrapperCodeHash = canonicalWrapperCodeHash := h

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

/--
Structural no-reentrancy on the wallet side: a successful
`validateIntegratedViaEvmCall` ran the wallet program on the caller's
`walletStorage` — *not* on anything the wrapper call's oracle produced.

This is forced by the type signature of `EvmEnv.evmCall`, which takes only
the *callee's* storage (wrapperStorage). The wallet's storage flows through
the call-shaped flow without ever passing through the oracle, so even a
malicious oracle cannot reach into wallet storage during the wrapper call.
-/
theorem validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle
    (eenv : EvmEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage)
    (h :
      validateIntegratedViaEvmCall eenv input wrapperStorage walletStorage =
        EvmCallIntegratedResult.success finalWrapper finalWallet) :
    exec eenv.base (AAPQIntegration.walletProgram input) walletStorage =
      ExecResult.success finalWallet := by
  unfold validateIntegratedViaEvmCall at h
  generalize hCall :
      eenv.evmCall eenv.wrapperAddress
        (buildVerifierCalldata input) wrapperStorage = callResult at h
  cases callResult with
  | success _ =>
      generalize hWalletExec :
          exec eenv.base (AAPQIntegration.walletProgram input) walletStorage =
            walletResult at h
      cases walletResult with
      | success postWallet =>
          injection h with _ hWalletEq
          rw [hWalletEq]
      | revert _ =>
          cases h
  | revert _ =>
      cases h

/--
Wallet-configuration isolation for the call-shaped flow: a successful
`validateIntegratedViaEvmCall` leaves the wallet's `keyCommitmentSlot`,
`domainSlot`, and `entryPointSlot` unchanged. Mirrors the canonical-flow
isolation theorem and follows from
`validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle` plus
`AAWallet.ValidationPost`'s unchanged-slot clauses.

Together with the structural no-reentrancy theorem above, this shows the
call-shaped boundary doesn't open new ways for the wrapper to mutate wallet
configuration.
-/
theorem validateIntegratedViaEvmCall_preserves_wallet_configuration
    (eenv : EvmEnv) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage)
    (h :
      validateIntegratedViaEvmCall eenv input wrapperStorage walletStorage =
        EvmCallIntegratedResult.success finalWrapper finalWallet) :
    finalWallet.read AAWallet.keyCommitmentSlot =
        walletStorage.read AAWallet.keyCommitmentSlot ∧
      finalWallet.read AAWallet.domainSlot =
          walletStorage.read AAWallet.domainSlot ∧
        finalWallet.read AAWallet.entryPointSlot =
          walletStorage.read AAWallet.entryPointSlot := by
  have hWalletExec :=
    validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle
      eenv input wrapperStorage walletStorage finalWrapper finalWallet h
  have hWalletProps :=
    AAPQIntegration.wallet_program_success_properties
      eenv.base walletStorage finalWallet input hWalletExec
  rcases hWalletProps with
    ⟨_, _, _, _, _, _, hKeyUnchanged, hDomainUnchanged, hEntryUnchanged⟩
  exact ⟨hKeyUnchanged, hDomainUnchanged, hEntryUnchanged⟩

/--
Address discrimination: the call-shaped flow's outcome depends only on the
oracle's behavior at `wrapperAddress`. Two `EvmEnv`s that agree on
`base`, `wrapperAddress`, and the oracle's value at `wrapperAddress` (for
the input's calldata) produce the same `EvmCallIntegratedResult`,
regardless of what their oracles do at any other address.

Inter-contract isolation: the wallet can call the wrapper without worrying
about the oracle's behavior at unrelated addresses leaking into the
result. A different `wrapperCodeHash` or a different oracle at some
unrelated address cannot change what the integrated flow computes.
-/
theorem validateIntegratedViaEvmCall_depends_only_on_wrapper_oracle
    (eenv eenv' : EvmEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (hBase : eenv.base = eenv'.base)
    (hOracleAtWrapper :
      eenv.evmCall eenv.wrapperAddress
          (buildVerifierCalldata input) wrapperStorage =
        eenv'.evmCall eenv'.wrapperAddress
          (buildVerifierCalldata input) wrapperStorage) :
    validateIntegratedViaEvmCall eenv input wrapperStorage walletStorage =
      validateIntegratedViaEvmCall eenv' input wrapperStorage walletStorage := by
  unfold validateIntegratedViaEvmCall
  rw [hOracleAtWrapper, hBase]

/--
The named cross-contract assumption ruling out wrapper reentrancy into
the wallet: the reentrant oracle's `callerStorageAfter` equals the input
caller storage (i.e., the wrapper call doesn't write back into the
wallet) and its `result` equals the non-reentrant `evmCall` result.

Real EVM allows reentrant callbacks; this assumption is the named
contract that says "the deployed wrapper does not call back into the
wallet." Future Lane A or Lane C work could relax this and prove
safety under bounded reentrancy.
-/
def NoCallback (reenv : ReentrantEvmEnv) : Prop :=
  ∀ addr cd ws wl,
    (reenv.reentrantEvmCall addr cd ws wl).result =
        reenv.evmCall addr cd ws ∧
      (reenv.reentrantEvmCall addr cd ws wl).callerStorageAfter = wl

/--
Reentrant variant of the call-shaped integrated flow. The wrapper call
goes through `reentrantEvmCall`, so the oracle could in principle
rewrite the wallet storage; the wallet program then runs on whatever
storage the oracle returned.
-/
def validateIntegratedViaReentrantEvmCall
    (reenv : ReentrantEvmEnv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) : EvmCallIntegratedResult :=
  match (reenv.reentrantEvmCall reenv.wrapperAddress
      (buildVerifierCalldata input) wrapperStorage walletStorage).result with
  | .success _ =>
      match exec reenv.base
          (AAPQIntegration.walletProgram input)
          (reenv.reentrantEvmCall reenv.wrapperAddress
              (buildVerifierCalldata input) wrapperStorage walletStorage).callerStorageAfter with
      | .success finalWalletStorage =>
          EvmCallIntegratedResult.success wrapperStorage finalWalletStorage
      | .revert failure => EvmCallIntegratedResult.walletRevert failure
  | .revert returndata => EvmCallIntegratedResult.wrapperRevert returndata

/--
Under `NoCallback`, the reentrant flow agrees with the non-reentrant
one. The wallet runs on its original storage because
`callerStorageAfter = wl`, and the `result` matches `evmCall`.

Lifts the structural no-reentrancy from `validateIntegratedViaEvmCall`
to the richer interface: the reentrancy non-claim is now relaxed
(the oracle *could* try to call back) and ruled out by an *explicit*
named assumption surfaced in the certificate.
-/
theorem validateIntegratedViaReentrantEvmCall_eq_nonReentrant_under_noCallback
    (reenv : ReentrantEvmEnv) (hNoCallback : NoCallback reenv)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) :
    validateIntegratedViaReentrantEvmCall reenv input wrapperStorage
        walletStorage =
      validateIntegratedViaEvmCall reenv.toEvmEnv input wrapperStorage
        walletStorage := by
  unfold validateIntegratedViaReentrantEvmCall validateIntegratedViaEvmCall
  obtain ⟨hResult, hStorage⟩ :=
    hNoCallback reenv.wrapperAddress (buildVerifierCalldata input)
      wrapperStorage walletStorage
  rw [hResult, hStorage]

end AAPQEvmCall
end Examples
end SoLean
