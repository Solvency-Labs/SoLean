import SoLean.Specs

namespace SoLean
namespace Examples
namespace PQVerifierWrapper

def expectedPublicKeyLengthSlot : Slot := 0
def expectedSignatureLengthSlot : Slot := 1
def expectedDomainSlot : Slot := 2

def expectedPublicKeyLengthExpr : ValueExpr :=
  .slot expectedPublicKeyLengthSlot

def expectedSignatureLengthExpr : ValueExpr :=
  .slot expectedSignatureLengthSlot

def expectedDomainExpr : ValueExpr :=
  .slot expectedDomainSlot

/--
Modeled inputs to a PQ verifier wrapper.

Lengths and byte-like values are `UInt256` placeholders in this first model.
The underlying PQ verifier remains the abstract oracle in `Env`.
-/
structure WrapperInput where
  publicKey : UInt256
  publicKeyLength : UInt256
  message : UInt256
  domain : UInt256
  signature : UInt256
  signatureLength : UInt256
deriving Repr, DecidableEq

/--
Focused verifier-wrapper model.

The wrapper checks public-key length, signature length, and domain before
accepting exactly the verifier oracle result for
`(publicKey, message, domain, signature)`.
-/
def verifyProgram (input : WrapperInput) : Stmt :=
  .seq
    (.require
      (.eq (.const input.publicKeyLength) expectedPublicKeyLengthExpr))
    (.seq
      (.require
        (.eq (.const input.signatureLength) expectedSignatureLengthExpr))
      (.seq
        (.require (.eq (.const input.domain) expectedDomainExpr))
        (.require
          (.verify
            (.const input.publicKey)
            (.const input.message)
            (.const input.domain)
            (.const input.signature)))))

def VerificationPost
    (input : WrapperInput) (env : Env) (storage finalStorage : Storage) : Prop :=
  input.publicKeyLength = storage.read expectedPublicKeyLengthSlot ∧
  input.signatureLength = storage.read expectedSignatureLengthSlot ∧
  input.domain = storage.read expectedDomainSlot ∧
  env.verifier
      input.publicKey
      input.message
      input.domain
      input.signature = true ∧
  finalStorage = storage

/--
Successful wrapper validation implies all wrapper guards passed and the
underlying verifier oracle accepted the exact modeled tuple.

Assumptions: this is a hand-written SoLean model of wrapper logic. It does not
verify a PQ scheme, byte parsing, ABI decoding, or external-call behavior.
-/
theorem verify_success_properties
    (env : Env) (storage finalStorage : Storage) (input : WrapperInput)
    (h :
      exec env (verifyProgram input) storage =
        ExecResult.success finalStorage) :
    VerificationPost input env storage finalStorage := by
  by_cases hPublicKeyLength :
      input.publicKeyLength = storage.read expectedPublicKeyLengthSlot
  · by_cases hSignatureLength :
      input.signatureLength = storage.read expectedSignatureLengthSlot
    · by_cases hDomain : input.domain = storage.read expectedDomainSlot
      · by_cases hVerify :
          env.verifier
              input.publicKey
              input.message
              (storage.read expectedDomainSlot)
              input.signature = true
        · have hFinal :
            ExecResult.success storage = ExecResult.success finalStorage := by
            simpa [verifyProgram, expectedPublicKeyLengthExpr,
              expectedSignatureLengthExpr, expectedDomainExpr, exec, evalBool,
              evalValue, hPublicKeyLength, hSignatureLength, hDomain, hVerify]
              using h
          cases hFinal
          have hVerifyPost :
              env.verifier
                  input.publicKey
                  input.message
                  input.domain
                  input.signature = true := by
            simpa [hDomain] using hVerify
          exact
            ⟨hPublicKeyLength, hSignatureLength, hDomain, hVerifyPost, rfl⟩
        · simp [verifyProgram, expectedPublicKeyLengthExpr,
            expectedSignatureLengthExpr, expectedDomainExpr, exec, evalBool,
            evalValue, hPublicKeyLength, hSignatureLength, hDomain, hVerify]
            at h
      · simp [verifyProgram, expectedPublicKeyLengthExpr,
          expectedSignatureLengthExpr, expectedDomainExpr, exec, evalBool,
          evalValue, hPublicKeyLength, hSignatureLength, hDomain] at h
    · simp [verifyProgram, expectedPublicKeyLengthExpr,
        expectedSignatureLengthExpr, exec, evalBool, evalValue,
        hPublicKeyLength, hSignatureLength] at h
  · simp [verifyProgram, expectedPublicKeyLengthExpr, exec, evalBool,
      evalValue, hPublicKeyLength] at h

def verifyPost (input : WrapperInput) : Post :=
  fun env storage finalStorage => VerificationPost input env storage finalStorage

theorem verify_ensures (input : WrapperInput) :
    FunctionEnsures
      (verifyProgram input)
      (fun _ _ => True)
      (verifyPost input) := by
  intro env storage _
  cases h :
      exec env (verifyProgram input) storage with
  | success finalStorage =>
      exact verify_success_properties env storage finalStorage input h
  | revert _ =>
      trivial

end PQVerifierWrapper
end Examples
end SoLean
