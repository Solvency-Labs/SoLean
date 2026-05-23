import SoLean.Examples.AAPQIntegration

namespace SoLean
namespace Examples
namespace ToyVerifier

/--
A deliberately non-cryptographic verifier model for assumption-discharge
calibration.

It accepts exactly when all modeled fields are equal. This is useful because
the accepted tuple uniquely determines key, message, domain, and signature,
which lets Lean prove the existing verifier-oracle assumptions for this toy
environment. It is not a PQ signature scheme and should not be used as one.
-/
def allFieldsEqualVerifier
    (key message domain signature : UInt256) : Bool :=
  decide (key = message ∧ message = domain ∧ domain = signature)

theorem allFieldsEqualVerifier_eq_true
    {key message domain signature : UInt256}
    (h :
      allFieldsEqualVerifier key message domain signature = true) :
    key = message ∧ message = domain ∧ domain = signature := by
  exact of_decide_eq_true h

def allFieldsEqualEnv (msgSender : Address) : Env :=
  { msgSender := msgSender, verifier := allFieldsEqualVerifier }

theorem allFieldsEqualEnv_domain_separation
    (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
      (allFieldsEqualEnv msgSender) := by
  intro key message domain1 domain2 signature h1 h2
  have hAccepted1 := allFieldsEqualVerifier_eq_true h1
  have hAccepted2 := allFieldsEqualVerifier_eq_true h2
  exact hAccepted1.right.left.symm.trans hAccepted2.right.left

theorem allFieldsEqualEnv_signature_binding
    (msgSender : Address) :
    AAPQIntegration.VerifierSignatureBinding
      (allFieldsEqualEnv msgSender) := by
  intro key message domain signature1 signature2 h1 h2
  have hAccepted1 := allFieldsEqualVerifier_eq_true h1
  have hAccepted2 := allFieldsEqualVerifier_eq_true h2
  exact hAccepted1.right.right.symm.trans hAccepted2.right.right

theorem allFieldsEqualEnv_key_separation
    (msgSender : Address) :
    AAPQIntegration.VerifierKeySeparation
      (allFieldsEqualEnv msgSender) := by
  intro key1 key2 message domain signature h1 h2
  have hAccepted1 := allFieldsEqualVerifier_eq_true h1
  have hAccepted2 := allFieldsEqualVerifier_eq_true h2
  exact hAccepted1.left.trans hAccepted2.left.symm

theorem allFieldsEqualEnv_satisfies_oracle_assumptions
    (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
        (allFieldsEqualEnv msgSender) ∧
      AAPQIntegration.VerifierSignatureBinding
        (allFieldsEqualEnv msgSender) ∧
      AAPQIntegration.VerifierKeySeparation
        (allFieldsEqualEnv msgSender) := by
  exact
    ⟨allFieldsEqualEnv_domain_separation msgSender,
      allFieldsEqualEnv_signature_binding msgSender,
      allFieldsEqualEnv_key_separation msgSender⟩

end ToyVerifier
end Examples
end SoLean
