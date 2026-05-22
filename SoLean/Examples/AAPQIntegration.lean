import SoLean.Examples.AAWallet
import SoLean.Examples.PQVerifierWrapper

namespace SoLean
namespace Examples
namespace AAPQIntegration

/--
Shared input for the first AA wallet + PQ verifier-wrapper integration model.

The wallet and wrapper are modeled as separate contract/storage boundaries. The
`publicKey`, `opHash`, `domain`, and `signature` fields are intentionally
shared so the theorem can state that the same tuple is authenticated by the
wrapper and consumed by the wallet validation path.
-/
structure IntegratedInput where
  publicKey : UInt256
  publicKeyLength : UInt256
  opHash : UInt256
  nonce : UInt256
  domain : UInt256
  signature : UInt256
  signatureLength : UInt256
deriving Repr, DecidableEq

def toUserOp (input : IntegratedInput) : AAWallet.UserOp :=
  { opHash := input.opHash,
    nonce := input.nonce,
    domain := input.domain,
    signature := input.signature }

def toWrapperInput (input : IntegratedInput) : PQVerifierWrapper.WrapperInput :=
  { publicKey := input.publicKey,
    publicKeyLength := input.publicKeyLength,
    message := input.opHash,
    domain := input.domain,
    signature := input.signature,
    signatureLength := input.signatureLength }

def keyMatchesWalletProgram (input : IntegratedInput) : Stmt :=
  .require (.eq (.const input.publicKey) AAWallet.keyCommitmentExpr)

def walletProgram (input : IntegratedInput) : Stmt :=
  .seq (keyMatchesWalletProgram input)
    (AAWallet.validateProgram (toUserOp input))

inductive IntegratedResult where
  | success : Storage -> Storage -> IntegratedResult
  | revert : Failure -> IntegratedResult

/--
Run the verifier-wrapper boundary first, then the wallet-validation boundary.
The two storages model two contracts rather than one shared layout.
-/
def validateIntegrated
    (env : Env)
    (input : IntegratedInput)
    (wrapperStorage walletStorage : Storage) : IntegratedResult :=
  match exec env (PQVerifierWrapper.verifyProgram (toWrapperInput input)) wrapperStorage with
  | .success finalWrapperStorage =>
      match exec env (walletProgram input) walletStorage with
      | .success finalWalletStorage =>
          .success finalWrapperStorage finalWalletStorage
      | .revert failure => .revert failure
  | .revert failure => .revert failure

def IntegratedPost
    (input : IntegratedInput)
    (env : Env)
    (wrapperStorage walletStorage finalWrapperStorage finalWalletStorage :
      Storage) : Prop :=
  PQVerifierWrapper.VerificationPost
    (toWrapperInput input)
    env
    wrapperStorage
    finalWrapperStorage ∧
  AAWallet.ValidationPost
    (toUserOp input)
    env
    walletStorage
    finalWalletStorage ∧
  input.publicKey = walletStorage.read AAWallet.keyCommitmentSlot ∧
  env.verifier input.publicKey input.opHash input.domain input.signature = true ∧
  env.verifier
      (walletStorage.read AAWallet.keyCommitmentSlot)
      input.opHash
      input.domain
      input.signature = true

theorem wallet_program_success_properties
    (env : Env) (walletStorage finalWalletStorage : Storage)
    (input : IntegratedInput)
    (h :
      exec env (walletProgram input) walletStorage =
        ExecResult.success finalWalletStorage) :
    input.publicKey = walletStorage.read AAWallet.keyCommitmentSlot ∧
      AAWallet.ValidationPost
        (toUserOp input)
        env
        walletStorage
        finalWalletStorage := by
  by_cases hKey :
      input.publicKey = walletStorage.read AAWallet.keyCommitmentSlot
  · have hValidate :
        exec env (AAWallet.validateProgram (toUserOp input)) walletStorage =
          ExecResult.success finalWalletStorage := by
      simpa [walletProgram, keyMatchesWalletProgram, exec, evalBool, evalValue,
        hKey] using h
    exact
      ⟨hKey,
        AAWallet.validate_success_properties
          env
          walletStorage
          finalWalletStorage
          (toUserOp input)
          hValidate⟩
  · simp [walletProgram, keyMatchesWalletProgram, exec, evalBool, evalValue,
      hKey] at h

/--
Integrated AA/PQ validation has no modeled authentication bypass.

Successful integrated execution implies:

* the wrapper length/domain checks passed;
* the wallet entry point, nonce, and domain checks passed;
* the wallet key commitment matches the wrapper public key; and
* the abstract verifier accepted the same
  `(publicKey, opHash, domain, signature)` tuple.
-/
theorem validateIntegrated_success_properties
    (env : Env)
    (wrapperStorage walletStorage finalWrapperStorage finalWalletStorage :
      Storage)
    (input : IntegratedInput)
    (h :
      validateIntegrated env input wrapperStorage walletStorage =
        IntegratedResult.success finalWrapperStorage finalWalletStorage) :
    IntegratedPost
      input
      env
      wrapperStorage
      walletStorage
      finalWrapperStorage
      finalWalletStorage := by
  generalize hWrapper :
      exec env (PQVerifierWrapper.verifyProgram (toWrapperInput input))
        wrapperStorage = wrapperResult
  cases wrapperResult with
  | success observedWrapperStorage =>
      generalize hWallet :
          exec env (walletProgram input) walletStorage = walletResult
      cases walletResult with
      | success observedWalletStorage =>
          have hFinal :
              IntegratedResult.success
                  observedWrapperStorage
                  observedWalletStorage =
                IntegratedResult.success
                  finalWrapperStorage
                  finalWalletStorage := by
            simpa [validateIntegrated, hWrapper, hWallet] using h
          cases hFinal
          have hWrapperPost :
              PQVerifierWrapper.VerificationPost
                (toWrapperInput input)
                env
                wrapperStorage
                finalWrapperStorage :=
            PQVerifierWrapper.verify_success_properties
              env
              wrapperStorage
              finalWrapperStorage
              (toWrapperInput input)
              hWrapper
          have hWalletProps :
              input.publicKey = walletStorage.read AAWallet.keyCommitmentSlot ∧
                AAWallet.ValidationPost
                  (toUserOp input)
                  env
                  walletStorage
                  finalWalletStorage :=
            wallet_program_success_properties
              env
              walletStorage
              finalWalletStorage
              input
              hWallet
          rcases hWrapperPost with
            ⟨hPublicKeyLength, hSignatureLength, hWrapperDomain,
              hWrapperVerify, hWrapperStorage⟩
          rcases hWalletProps with ⟨hKeyMatch, hWalletPost⟩
          rcases hWalletPost with
            ⟨hCaller, hNonce, hWalletDomain, hWalletVerify, hNonceAdd,
              hKeyUnchanged, hDomainUnchanged, hEntryPointUnchanged⟩
          exact
            ⟨⟨hPublicKeyLength, hSignatureLength, hWrapperDomain,
                hWrapperVerify, hWrapperStorage⟩,
              ⟨hCaller, hNonce, hWalletDomain, hWalletVerify, hNonceAdd,
                hKeyUnchanged, hDomainUnchanged, hEntryPointUnchanged⟩,
              hKeyMatch,
              hWrapperVerify,
              hWalletVerify⟩
      | revert failure =>
          simp [validateIntegrated, hWrapper, hWallet] at h
  | revert failure =>
      simp [validateIntegrated, hWrapper] at h

/--
Successful integrated validation implies the abstract verifier accepted the
exact modeled `(publicKey, opHash, domain, signature)` tuple — there is no
bypass path through the integrated flow that succeeds without verifier
acceptance.
-/
theorem noBypass_implies_verifier_accepted
    (env : Env)
    (input : IntegratedInput)
    (wrapperStorage walletStorage finalWrapperStorage finalWalletStorage :
      Storage)
    (h :
      validateIntegrated env input wrapperStorage walletStorage =
        IntegratedResult.success finalWrapperStorage finalWalletStorage) :
    env.verifier input.publicKey input.opHash input.domain input.signature =
      true :=
  (validateIntegrated_success_properties
      env
      wrapperStorage
      walletStorage
      finalWrapperStorage
      finalWalletStorage
      input
      h).2.2.2.1

/--
Replay rejection: after a successful integrated validation, re-running the
same `UserOp`-derived `IntegratedInput` against the post-validation storage
cannot succeed.

The argument is contract-level: the first call advanced the wallet nonce
through checked arithmetic, so the second call's modeled `nonce == wallet.nonce`
require would observe a different stored nonce and revert. The proof derives a
contradiction from two `validateIntegrated_success_properties` instances.
-/
theorem replay_rejected_after_success
    (env : Env)
    (input : IntegratedInput)
    (wrapperStorage walletStorage finalWrapperStorage finalWalletStorage :
      Storage)
    (replayWrapperStorage replayWalletStorage : Storage)
    (h :
      validateIntegrated env input wrapperStorage walletStorage =
        IntegratedResult.success finalWrapperStorage finalWalletStorage) :
    validateIntegrated env input finalWrapperStorage finalWalletStorage ≠
      IntegratedResult.success replayWrapperStorage replayWalletStorage := by
  intro hReplay
  have hFirst :=
    validateIntegrated_success_properties
      env wrapperStorage walletStorage
      finalWrapperStorage finalWalletStorage input h
  have hSecond :=
    validateIntegrated_success_properties
      env finalWrapperStorage finalWalletStorage
      replayWrapperStorage replayWalletStorage input hReplay
  rcases hFirst with ⟨_, hFirstWallet, _, _, _⟩
  rcases hSecond with ⟨_, hSecondWallet, _, _, _⟩
  rcases hFirstWallet with
    ⟨_, hFirstNonce, _, _, hFirstNonceAdd, _, _, _⟩
  rcases hSecondWallet with
    ⟨_, hSecondNonce, _, _, _, _, _, _⟩
  have hAdvanced :
      (finalWalletStorage.read AAWallet.nonceSlot).toNat =
        (walletStorage.read AAWallet.nonceSlot).toNat + 1 := by
    have hAddNat :
        (finalWalletStorage.read AAWallet.nonceSlot).toNat =
          (walletStorage.read AAWallet.nonceSlot).toNat + UInt256.one.toNat :=
      UInt256.checkedAdd_toNat hFirstNonceAdd
    simpa using hAddNat
  have hReplayEq :
      (toUserOp input).nonce =
        finalWalletStorage.read AAWallet.nonceSlot := hSecondNonce
  have hFirstEq :
      (toUserOp input).nonce =
        walletStorage.read AAWallet.nonceSlot := hFirstNonce
  have hSame :
      walletStorage.read AAWallet.nonceSlot =
        finalWalletStorage.read AAWallet.nonceSlot := by
    rw [← hFirstEq, hReplayEq]
  have hSameNat :
      (walletStorage.read AAWallet.nonceSlot).toNat =
        (finalWalletStorage.read AAWallet.nonceSlot).toNat := by
    rw [hSame]
  rw [hAdvanced] at hSameNat
  exact absurd hSameNat (Nat.ne_of_lt (Nat.lt_succ_self _))

/--
Crypto assumption: the abstract verifier oracle is domain-separated.

If the same `(publicKey, message, signature)` triple is accepted under two
domains, those domains must be equal. This is a *named, non-cryptographic*
assumption on `Env.verifier`: it captures the property that real PQ
signatures should have when bound to a domain tag, without committing to any
particular scheme.
-/
def VerifierDomainSeparation (env : Env) : Prop :=
  ∀ key message domain1 domain2 signature,
    env.verifier key message domain1 signature = true ->
    env.verifier key message domain2 signature = true ->
    domain1 = domain2

/--
Crypto assumption: the abstract verifier oracle binds the signature.

If two signatures are accepted for the same `(publicKey, message, domain)`
triple, they must be equal. Real PQ schemes typically have this kind of
binding/non-malleability property; this is the named assumption that lets
SoLean model the consequence at the contract layer.
-/
def VerifierSignatureBinding (env : Env) : Prop :=
  ∀ key message domain signature1 signature2,
    env.verifier key message domain signature1 = true ->
    env.verifier key message domain signature2 = true ->
    signature1 = signature2

/--
Crypto assumption: the abstract verifier oracle is key-separated.

If two public keys both accept the same `(message, domain, signature)`
triple, they must be equal. This is the named assumption behind
`key_separation_under_oracle_assumption`.
-/
def VerifierKeySeparation (env : Env) : Prop :=
  ∀ key1 key2 message domain signature,
    env.verifier key1 message domain signature = true ->
    env.verifier key2 message domain signature = true ->
    key1 = key2

/--
Under `VerifierDomainSeparation env`, two successful integrated validations of
operations sharing the same `publicKey`, `opHash`, and `signature` must also
share the same `domain` — there is no domain-confusion bypass through the
integrated flow.
-/
theorem domain_separation_under_oracle_assumption
    (env : Env)
    (hSep : VerifierDomainSeparation env)
    (input1 input2 : IntegratedInput)
    (wrapperStorage1 walletStorage1 finalWrapper1 finalWallet1 : Storage)
    (wrapperStorage2 walletStorage2 finalWrapper2 finalWallet2 : Storage)
    (hKey : input1.publicKey = input2.publicKey)
    (hOpHash : input1.opHash = input2.opHash)
    (hSignature : input1.signature = input2.signature)
    (h1 :
      validateIntegrated env input1 wrapperStorage1 walletStorage1 =
        IntegratedResult.success finalWrapper1 finalWallet1)
    (h2 :
      validateIntegrated env input2 wrapperStorage2 walletStorage2 =
        IntegratedResult.success finalWrapper2 finalWallet2) :
    input1.domain = input2.domain := by
  have hVerify1 :
      env.verifier input1.publicKey input1.opHash input1.domain
          input1.signature = true :=
    noBypass_implies_verifier_accepted
      env input1 wrapperStorage1 walletStorage1
      finalWrapper1 finalWallet1 h1
  have hVerify2 :
      env.verifier input2.publicKey input2.opHash input2.domain
          input2.signature = true :=
    noBypass_implies_verifier_accepted
      env input2 wrapperStorage2 walletStorage2
      finalWrapper2 finalWallet2 h2
  have hVerify2' :
      env.verifier input1.publicKey input1.opHash input2.domain
          input1.signature = true := by
    rw [hKey, hOpHash, hSignature]; exact hVerify2
  exact
    hSep input1.publicKey input1.opHash input1.domain input2.domain
      input1.signature hVerify1 hVerify2'

/--
Under `VerifierSignatureBinding env`, two successful integrated validations of
operations sharing `publicKey`, `opHash`, and `domain` must also share
`signature`. The integrated flow forwards modeled non-malleability of the
underlying verifier into the contract layer.
-/
theorem signature_non_malleability_under_oracle_assumption
    (env : Env)
    (hBind : VerifierSignatureBinding env)
    (input1 input2 : IntegratedInput)
    (wrapperStorage1 walletStorage1 finalWrapper1 finalWallet1 : Storage)
    (wrapperStorage2 walletStorage2 finalWrapper2 finalWallet2 : Storage)
    (hKey : input1.publicKey = input2.publicKey)
    (hOpHash : input1.opHash = input2.opHash)
    (hDomain : input1.domain = input2.domain)
    (h1 :
      validateIntegrated env input1 wrapperStorage1 walletStorage1 =
        IntegratedResult.success finalWrapper1 finalWallet1)
    (h2 :
      validateIntegrated env input2 wrapperStorage2 walletStorage2 =
        IntegratedResult.success finalWrapper2 finalWallet2) :
    input1.signature = input2.signature := by
  have hVerify1 :
      env.verifier input1.publicKey input1.opHash input1.domain
          input1.signature = true :=
    noBypass_implies_verifier_accepted
      env input1 wrapperStorage1 walletStorage1
      finalWrapper1 finalWallet1 h1
  have hVerify2 :
      env.verifier input2.publicKey input2.opHash input2.domain
          input2.signature = true :=
    noBypass_implies_verifier_accepted
      env input2 wrapperStorage2 walletStorage2
      finalWrapper2 finalWallet2 h2
  have hVerify2' :
      env.verifier input1.publicKey input1.opHash input1.domain
          input2.signature = true := by
    rw [hKey, hOpHash, hDomain]; exact hVerify2
  exact
    hBind input1.publicKey input1.opHash input1.domain
      input1.signature input2.signature hVerify1 hVerify2'

/--
Under `VerifierKeySeparation env`, two successful integrated validations of
operations sharing `opHash`, `domain`, and `signature` must also share
`publicKey`. The integrated flow forwards modeled key-separation of the
underlying verifier into the contract layer.
-/
theorem key_separation_under_oracle_assumption
    (env : Env)
    (hKeySep : VerifierKeySeparation env)
    (input1 input2 : IntegratedInput)
    (wrapperStorage1 walletStorage1 finalWrapper1 finalWallet1 : Storage)
    (wrapperStorage2 walletStorage2 finalWrapper2 finalWallet2 : Storage)
    (hOpHash : input1.opHash = input2.opHash)
    (hDomain : input1.domain = input2.domain)
    (hSignature : input1.signature = input2.signature)
    (h1 :
      validateIntegrated env input1 wrapperStorage1 walletStorage1 =
        IntegratedResult.success finalWrapper1 finalWallet1)
    (h2 :
      validateIntegrated env input2 wrapperStorage2 walletStorage2 =
        IntegratedResult.success finalWrapper2 finalWallet2) :
    input1.publicKey = input2.publicKey := by
  have hVerify1 :
      env.verifier input1.publicKey input1.opHash input1.domain
          input1.signature = true :=
    noBypass_implies_verifier_accepted
      env input1 wrapperStorage1 walletStorage1
      finalWrapper1 finalWallet1 h1
  have hVerify2 :
      env.verifier input2.publicKey input2.opHash input2.domain
          input2.signature = true :=
    noBypass_implies_verifier_accepted
      env input2 wrapperStorage2 walletStorage2
      finalWrapper2 finalWallet2 h2
  have hVerify2' :
      env.verifier input2.publicKey input1.opHash input1.domain
          input1.signature = true := by
    rw [hOpHash, hDomain, hSignature]; exact hVerify2
  exact
    hKeySep input1.publicKey input2.publicKey input1.opHash
      input1.domain input1.signature hVerify1 hVerify2'

end AAPQIntegration
end Examples
end SoLean
