import SoLean.Examples.AAPQIntegration
import SoLean.Examples.LatticePublicKey
import SoLean.Examples.PQVerifierWrapper

namespace SoLean
namespace Examples
namespace SchemeParameters

/--
Modeled parameter record for a PQ signature scheme.

This carries the shape information a wrapper or wallet might want to
check before accepting a signature: declared public-key byte length,
signature byte length, NIST PQC security category, and the matching
`LatticeShapeBound` for the public-key polynomial. None of these
correspond to any actual cryptographic invariant — they are
calibration data bridging to the NIST standards documents.
-/
structure SchemeParameters where
  name : String
  publicKeyByteLength : Nat
  signatureByteLength : Nat
  /-- NIST PQC security category. 1, 2, 3, or 5. -/
  securityCategory : Nat
  publicKeyShape : LatticePublicKey.LatticeShapeBound
deriving Repr, DecidableEq

/--
Falcon-512 parameters (NIST PQC Round 3 selected).

Public-key size 897 bytes, signature size ~666 bytes (variable),
security category 1, polynomial degree 512.

Source: https://falcon-sign.info/. Values are documented constants;
no cryptographic claim attached.
-/
def falcon512 : SchemeParameters :=
  { name := "Falcon-512",
    publicKeyByteLength := 897,
    signatureByteLength := 666,
    securityCategory := 1,
    publicKeyShape :=
      { expectedDegree := 512,
        expectedCoefficientCount := 512 } }

/--
ML-DSA-44 parameters (NIST FIPS 204).

Public-key size 1312 bytes, signature size 2420 bytes, security
category 2, modeled as a 256-degree polynomial bundle.

Source: NIST FIPS 204. Values are documented constants; no
cryptographic claim attached.
-/
def mlDsa44 : SchemeParameters :=
  { name := "ML-DSA-44",
    publicKeyByteLength := 1312,
    signatureByteLength := 2420,
    securityCategory := 2,
    publicKeyShape :=
      { expectedDegree := 256,
        expectedCoefficientCount := 256 } }

/--
Declared schemes are distinct in name and parameter shape. A wrapper
that accepts one cannot silently accept the other under the same
parameter check.
-/
theorem falcon512_ne_mlDsa44 : falcon512.name ≠ mlDsa44.name := by
  decide

/--
Falcon-512 and ML-DSA-44 declare different public-key sizes — a
wrapper using `publicKeyByteLength` as a length check would reject
calldata sized for the other scheme.
-/
theorem falcon512_publicKey_size_ne_mlDsa44_publicKey_size :
    falcon512.publicKeyByteLength ≠ mlDsa44.publicKeyByteLength := by
  decide

/--
Lift a scheme's `signatureByteLength` (a `Nat`) into the `UInt256` slot
used by `PQVerifierWrapper.WrapperInput.signatureLength`. For values
within range (all NIST PQ signature sizes fit easily) this produces the
matching `UInt256`; out-of-range values fall back to `UInt256.zero`.
-/
def SchemeParameters.signatureByteLengthUInt256
    (sp : SchemeParameters) : UInt256 :=
  (UInt256.ofNat? sp.signatureByteLength).getD UInt256.zero

/--
Lift a scheme's `publicKeyByteLength` to `UInt256`, parallel to the
signature variant.
-/
def SchemeParameters.publicKeyByteLengthUInt256
    (sp : SchemeParameters) : UInt256 :=
  (UInt256.ofNat? sp.publicKeyByteLength).getD UInt256.zero

private theorem falcon512_sig_le_max : 666 <= UInt256.maxValue := by decide
private theorem mlDsa44_sig_le_max : 2420 <= UInt256.maxValue := by decide
private theorem falcon512_pk_le_max : 897 <= UInt256.maxValue := by decide
private theorem mlDsa44_pk_le_max : 1312 <= UInt256.maxValue := by decide

private theorem falcon512_sigUInt256_toNat :
    falcon512.signatureByteLengthUInt256.toNat = 666 := by
  unfold SchemeParameters.signatureByteLengthUInt256
  rw [show falcon512.signatureByteLength = 666 from rfl,
      UInt256.ofNat?, dif_pos falcon512_sig_le_max]
  rfl

private theorem mlDsa44_sigUInt256_toNat :
    mlDsa44.signatureByteLengthUInt256.toNat = 2420 := by
  unfold SchemeParameters.signatureByteLengthUInt256
  rw [show mlDsa44.signatureByteLength = 2420 from rfl,
      UInt256.ofNat?, dif_pos mlDsa44_sig_le_max]
  rfl

private theorem falcon512_pkUInt256_toNat :
    falcon512.publicKeyByteLengthUInt256.toNat = 897 := by
  unfold SchemeParameters.publicKeyByteLengthUInt256
  rw [show falcon512.publicKeyByteLength = 897 from rfl,
      UInt256.ofNat?, dif_pos falcon512_pk_le_max]
  rfl

private theorem mlDsa44_pkUInt256_toNat :
    mlDsa44.publicKeyByteLengthUInt256.toNat = 1312 := by
  unfold SchemeParameters.publicKeyByteLengthUInt256
  rw [show mlDsa44.publicKeyByteLength = 1312 from rfl,
      UInt256.ofNat?, dif_pos mlDsa44_pk_le_max]
  rfl

/--
Falcon-512 and ML-DSA-44 carry distinct signature-byte-length `UInt256`s
(666 vs 2420). A wrapper calibrated for one cannot silently accept the
other under a `signatureLength` length check.
-/
theorem falcon512_sigUInt256_ne_mlDsa44_sigUInt256 :
    falcon512.signatureByteLengthUInt256 ≠
      mlDsa44.signatureByteLengthUInt256 := by
  intro h
  have hNat := congrArg UInt256.toNat h
  rw [falcon512_sigUInt256_toNat, mlDsa44_sigUInt256_toNat] at hNat
  omega

/--
Same distinctness, for public-key byte length (897 vs 1312).
-/
theorem falcon512_pkUInt256_ne_mlDsa44_pkUInt256 :
    falcon512.publicKeyByteLengthUInt256 ≠
      mlDsa44.publicKeyByteLengthUInt256 := by
  intro h
  have hNat := congrArg UInt256.toNat h
  rw [falcon512_pkUInt256_toNat, mlDsa44_pkUInt256_toNat] at hNat
  omega

/--
A wrapper whose `expectedSignatureLengthSlot` is calibrated to one scheme
cannot succeed on an input whose `signatureLength` matches a different
scheme — provided the two schemes' `signatureByteLengthUInt256` values
differ.

The proof is the contrapositive of `PQVerifierWrapper.verify_success_
properties`: a successful verification forces `input.signatureLength`
to equal the stored expected length; if the input claims a different
scheme's length, equality fails and verification cannot succeed.

This is the first Lane C theorem — concrete cryptographic-shape
discrimination at the wrapper layer.
-/
theorem wrapper_calibrated_for_one_scheme_rejects_other_signature_length
    (env : Env)
    (wrapperStorage : Storage)
    (input : PQVerifierWrapper.WrapperInput)
    (calibrated rejected : SchemeParameters)
    (hCalibratedSig :
      wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot =
        calibrated.signatureByteLengthUInt256)
    (hRejectedSig :
      input.signatureLength = rejected.signatureByteLengthUInt256)
    (hSchemesDiffer :
      calibrated.signatureByteLengthUInt256 ≠
        rejected.signatureByteLengthUInt256) :
    ∀ finalStorage,
      exec env (PQVerifierWrapper.verifyProgram input) wrapperStorage ≠
        ExecResult.success finalStorage := by
  intro finalStorage hSuccess
  have hPost := PQVerifierWrapper.verify_success_properties env wrapperStorage
    finalStorage input hSuccess
  have hSigEq : input.signatureLength =
      wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot :=
    hPost.2.1
  rw [hCalibratedSig] at hSigEq
  rw [hRejectedSig] at hSigEq
  exact hSchemesDiffer hSigEq.symm

/--
Concrete corollary: a Falcon-512-calibrated wrapper rejects calldata sized
for ML-DSA-44 signatures (2420 bytes vs Falcon's 666). Auditors can read
this as: a wrapper deployed for one scheme cannot accept the other under
the simple length check, even if every other field aligns.
-/
theorem falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length
    (env : Env)
    (wrapperStorage : Storage)
    (input : PQVerifierWrapper.WrapperInput)
    (hFalconCalibrated :
      wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot =
        falcon512.signatureByteLengthUInt256)
    (hMlDsaSig :
      input.signatureLength = mlDsa44.signatureByteLengthUInt256) :
    ∀ finalStorage,
      exec env (PQVerifierWrapper.verifyProgram input) wrapperStorage ≠
        ExecResult.success finalStorage :=
  wrapper_calibrated_for_one_scheme_rejects_other_signature_length
    env wrapperStorage input falcon512 mlDsa44
    hFalconCalibrated hMlDsaSig
    falcon512_sigUInt256_ne_mlDsa44_sigUInt256

/--
Cross-scheme replay impossibility at the integrated level: a Falcon-512-
calibrated wrapper inside `validateAndExecute` cannot succeed on an
`IntegratedInput` whose `signatureLength` matches ML-DSA-44. The wrapper
revert from `falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length`
propagates through `validateIntegrated` and then through
`validateAndExecute`.

Concrete content: an attacker who holds a valid Falcon-512 signed
operation cannot re-submit its calldata (same opHash, same domain) sized
for ML-DSA-44 against an ML-DSA-44-calibrated wrapper and expect the
length check to pass — the wrapper's stored expected length forces a
revert before any verifier oracle is consulted.
-/
theorem validateAndExecute_falcon512_calibrated_rejects_mlDsa44_signature_length
    (env : Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (hFalconCalibrated :
      wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot =
        falcon512.signatureByteLengthUInt256)
    (hMlDsaSig :
      input.signatureLength = mlDsa44.signatureByteLengthUInt256) :
    ∀ finalWrapper finalWallet,
      AAPQIntegration.validateAndExecute env input
          wrapperStorage walletStorage ≠
        AAPQIntegration.IntegratedFullResult.success finalWrapper
          finalWallet := by
  intro finalWrapper finalWallet hSuccess
  -- Pull validateIntegrated success out of the validateAndExecute success.
  obtain ⟨postWallet, hValidate⟩ :=
    AAPQIntegration.validateAndExecute_success_implies_validateIntegrated_success
      env input wrapperStorage walletStorage finalWrapper finalWallet hSuccess
  -- Translate the integrated input's signatureLength into the wrapper
  -- input's signatureLength (toWrapperInput preserves it).
  have hMlDsaSig' :
      (AAPQIntegration.toWrapperInput input).signatureLength =
        mlDsa44.signatureByteLengthUInt256 :=
    hMlDsaSig
  -- validateIntegrated unfolds to a match on `exec wrapper ws`. In the
  -- success branch we get the wrapper exec result; in the revert branch
  -- the unfolded hValidate becomes `revert _ = success _`, contradiction.
  cases hExec :
      exec env
        (PQVerifierWrapper.verifyProgram
          (AAPQIntegration.toWrapperInput input))
        wrapperStorage with
  | success postWrapper =>
      -- The wrapper exec succeeded with `postWrapper`, but
      -- falcon512_calibrated_wrapper_rejects... says it cannot return
      -- success on this calibration + input.
      exact
        falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length env
          wrapperStorage (AAPQIntegration.toWrapperInput input)
          hFalconCalibrated hMlDsaSig' postWrapper hExec
  | revert failure =>
      simp [AAPQIntegration.validateIntegrated, hExec] at hValidate

end SchemeParameters
end Examples
end SoLean
