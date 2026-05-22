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

end AAPQIntegration
end Examples
end SoLean
