import SoLean.Examples.LatticePublicKey

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

end SchemeParameters
end Examples
end SoLean
