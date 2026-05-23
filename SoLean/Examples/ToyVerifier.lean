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

/--
A second non-cryptographic verifier model that's structurally distinct from
`allFieldsEqualVerifier`.

It accepts exactly when the signature equals the key and the message equals
the domain — a two-pair binding (`signature ↔ key`, `message ↔ domain`)
rather than a 4-way collapse. The point is to show that
`verifierModelCalibrations` is genuinely a list with multiple, structurally
different entries. This is still not a PQ signature scheme.
-/
def keyDomainBindingVerifier
    (key message domain signature : UInt256) : Bool :=
  decide (signature = key ∧ message = domain)

theorem keyDomainBindingVerifier_eq_true
    {key message domain signature : UInt256}
    (h :
      keyDomainBindingVerifier key message domain signature = true) :
    signature = key ∧ message = domain := by
  exact of_decide_eq_true h

def keyDomainBindingEnv (msgSender : Address) : Env :=
  { msgSender := msgSender, verifier := keyDomainBindingVerifier }

theorem keyDomainBindingEnv_domain_separation
    (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
      (keyDomainBindingEnv msgSender) := by
  intro key message domain1 domain2 signature h1 h2
  have hAccepted1 := keyDomainBindingVerifier_eq_true h1
  have hAccepted2 := keyDomainBindingVerifier_eq_true h2
  exact hAccepted1.right.symm.trans hAccepted2.right

theorem keyDomainBindingEnv_signature_binding
    (msgSender : Address) :
    AAPQIntegration.VerifierSignatureBinding
      (keyDomainBindingEnv msgSender) := by
  intro key message domain signature1 signature2 h1 h2
  have hAccepted1 := keyDomainBindingVerifier_eq_true h1
  have hAccepted2 := keyDomainBindingVerifier_eq_true h2
  exact hAccepted1.left.trans hAccepted2.left.symm

theorem keyDomainBindingEnv_key_separation
    (msgSender : Address) :
    AAPQIntegration.VerifierKeySeparation
      (keyDomainBindingEnv msgSender) := by
  intro key1 key2 message domain signature h1 h2
  have hAccepted1 := keyDomainBindingVerifier_eq_true h1
  have hAccepted2 := keyDomainBindingVerifier_eq_true h2
  exact hAccepted1.left.symm.trans hAccepted2.left

theorem keyDomainBindingEnv_satisfies_oracle_assumptions
    (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
        (keyDomainBindingEnv msgSender) ∧
      AAPQIntegration.VerifierSignatureBinding
        (keyDomainBindingEnv msgSender) ∧
      AAPQIntegration.VerifierKeySeparation
        (keyDomainBindingEnv msgSender) := by
  exact
    ⟨keyDomainBindingEnv_domain_separation msgSender,
      keyDomainBindingEnv_signature_binding msgSender,
      keyDomainBindingEnv_key_separation msgSender⟩

end ToyVerifier
end Examples
end SoLean
