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

/--
Parametric verifier model: the verifier accepts iff
`signature = derive key message domain` for some abstract
signature-derivation function `derive`.

This is the parametric counterpart to the concrete toy models above. It
captures the *shape* a useful verifier-wrapper relation should have — the
signature is uniquely determined by `(key, message, domain)` — without
committing to a specific cryptographic function. The two injectivity
hypotheses are exactly what's needed to discharge `VerifierKeySeparation`
and `VerifierDomainSeparation`; `VerifierSignatureBinding` follows directly
from the verifier's predicate shape and needs no hypothesis.

Concrete instances are intentionally not provided here (the model says what
shape a `derive` must have for the proofs to go through, not that any
particular `derive` exists in `UInt256`).
-/
structure DerivedSignatureModel where
  derive : UInt256 -> UInt256 -> UInt256 -> UInt256
  injectiveKey :
    ∀ key1 key2 message domain,
      derive key1 message domain = derive key2 message domain ->
      key1 = key2
  injectiveDomain :
    ∀ key message domain1 domain2,
      derive key message domain1 = derive key message domain2 ->
      domain1 = domain2

def DerivedSignatureModel.verifier
    (model : DerivedSignatureModel)
    (key message domain signature : UInt256) : Bool :=
  decide (signature = model.derive key message domain)

def DerivedSignatureModel.toEnv
    (model : DerivedSignatureModel) (msgSender : Address) : Env :=
  { msgSender := msgSender, verifier := model.verifier }

theorem DerivedSignatureModel.verifier_eq_true
    {model : DerivedSignatureModel}
    {key message domain signature : UInt256}
    (h : model.verifier key message domain signature = true) :
    signature = model.derive key message domain :=
  of_decide_eq_true h

theorem DerivedSignatureModel.toEnv_domain_separation
    (model : DerivedSignatureModel) (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
      (model.toEnv msgSender) := by
  intro key message domain1 domain2 signature h1 h2
  have hSig1 := DerivedSignatureModel.verifier_eq_true h1
  have hSig2 := DerivedSignatureModel.verifier_eq_true h2
  have hDerivesEq :
      model.derive key message domain1 = model.derive key message domain2 :=
    hSig1.symm.trans hSig2
  exact model.injectiveDomain key message domain1 domain2 hDerivesEq

theorem DerivedSignatureModel.toEnv_signature_binding
    (model : DerivedSignatureModel) (msgSender : Address) :
    AAPQIntegration.VerifierSignatureBinding
      (model.toEnv msgSender) := by
  intro key message domain signature1 signature2 h1 h2
  have hSig1 := DerivedSignatureModel.verifier_eq_true h1
  have hSig2 := DerivedSignatureModel.verifier_eq_true h2
  exact hSig1.trans hSig2.symm

theorem DerivedSignatureModel.toEnv_key_separation
    (model : DerivedSignatureModel) (msgSender : Address) :
    AAPQIntegration.VerifierKeySeparation
      (model.toEnv msgSender) := by
  intro key1 key2 message domain signature h1 h2
  have hSig1 := DerivedSignatureModel.verifier_eq_true h1
  have hSig2 := DerivedSignatureModel.verifier_eq_true h2
  have hDerivesEq :
      model.derive key1 message domain = model.derive key2 message domain :=
    hSig1.symm.trans hSig2
  exact model.injectiveKey key1 key2 message domain hDerivesEq

theorem DerivedSignatureModel.toEnv_satisfies_oracle_assumptions
    (model : DerivedSignatureModel) (msgSender : Address) :
    AAPQIntegration.VerifierDomainSeparation
        (model.toEnv msgSender) ∧
      AAPQIntegration.VerifierSignatureBinding
        (model.toEnv msgSender) ∧
      AAPQIntegration.VerifierKeySeparation
        (model.toEnv msgSender) := by
  exact
    ⟨model.toEnv_domain_separation msgSender,
      model.toEnv_signature_binding msgSender,
      model.toEnv_key_separation msgSender⟩

end ToyVerifier
end Examples
end SoLean
