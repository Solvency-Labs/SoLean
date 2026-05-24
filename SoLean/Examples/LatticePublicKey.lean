import SoLean.UInt256

namespace SoLean
namespace Examples
namespace LatticePublicKey

/--
A modeled lattice-style public key: a polynomial represented as a
coefficient list together with a declared degree bound.

Real Falcon and ML-DSA public keys are polynomials over rings like
`Z_q[X] / (X^n + 1)`. This model carries the coefficient list as
`List UInt256` without ring arithmetic — the point is to introduce the
*shape* a lattice-based key has (multiple coordinates, a degree) so
downstream proofs can reference per-coordinate properties.

`coefficients.length` is not required to equal `degree + 1` here; the
shape predicates below enforce that for specific schemes.
-/
structure LatticePublicKey where
  coefficients : List UInt256
  degree : Nat
deriving Repr, DecidableEq

/--
Modeled shape constraint a real scheme would impose on its public keys:
expected polynomial degree and expected coefficient count. Concrete
schemes (Falcon-512, ML-DSA-44) pin these to specific values.
-/
structure LatticeShapeBound where
  expectedDegree : Nat
  expectedCoefficientCount : Nat
deriving Repr, DecidableEq

/--
A key satisfies a shape bound iff its declared degree and coefficient
list length match the bound.
-/
def LatticePublicKey.satisfiesShape
    (pk : LatticePublicKey) (bound : LatticeShapeBound) : Prop :=
  pk.degree = bound.expectedDegree ∧
    pk.coefficients.length = bound.expectedCoefficientCount

instance (pk : LatticePublicKey) (bound : LatticeShapeBound) :
    Decidable (pk.satisfiesShape bound) :=
  inferInstanceAs (Decidable (_ ∧ _))

/--
Compress a lattice public key down to the existing `UInt256` key slot
used by `Env.verifier`. This first-cut compression is "take the head
coefficient, or zero" — a placeholder that lets the lattice-shaped key
flow into the existing wallet/wrapper interface without changing them.

A real implementation would hash the coefficient vector; this model
uses the head coefficient so the equation is rfl-friendly and the
compression is total.
-/
def LatticePublicKey.compress (pk : LatticePublicKey) : UInt256 :=
  match pk.coefficients with
  | [] => UInt256.zero
  | head :: _ => head

/--
The compression of a key with at least one coefficient equals its head
coefficient. Useful for downstream proofs that need to peel back the
compression to reason about the underlying lattice key.
-/
theorem compress_cons (head : UInt256) (rest : List UInt256) (degree : Nat) :
    (LatticePublicKey.compress
      { coefficients := head :: rest, degree := degree }) = head := by
  rfl

/--
Two lattice public keys with identical coefficient lists compress to the
same `UInt256`. The compression depends only on the coefficient vector,
not on the declared degree — auditors reading this can rely on
"compress doesn't smuggle in degree-dependent behavior".
-/
theorem compress_degree_independent
    (coefficients : List UInt256) (d1 d2 : Nat) :
    (LatticePublicKey.compress { coefficients := coefficients, degree := d1 }) =
      (LatticePublicKey.compress
        { coefficients := coefficients, degree := d2 }) := by
  cases coefficients with
  | nil => rfl
  | cons _ _ => rfl

/--
Named compression-injectivity assumption: a compression function maps
distinct head coefficients to distinct compressed values.

The current `LatticePublicKey.compress` is a placeholder (head-or-zero)
that's trivially injective on the head coordinate when keys carry at
least one coefficient. Future Lane C work can replace `compress` with a
real hash and discharge this assumption against the hash's collision
resistance.
-/
def CompressionInjectiveOnHead
    (compress : LatticePublicKey -> UInt256) : Prop :=
  ∀ (head1 head2 : UInt256) (rest1 rest2 : List UInt256)
    (degree1 degree2 : Nat),
    compress { coefficients := head1 :: rest1, degree := degree1 } =
        compress { coefficients := head2 :: rest2, degree := degree2 } ->
      head1 = head2

/--
`LatticePublicKey.compress` (the placeholder head-or-zero compression)
satisfies `CompressionInjectiveOnHead`. This is the first concrete
discharge of a Lane C verifier-shape assumption — auditors can rely on
"under this compression, two keys with the same compressed value share
the head coefficient."
-/
theorem compress_injectiveOnHead :
    CompressionInjectiveOnHead LatticePublicKey.compress := by
  intro head1 head2 rest1 rest2 degree1 degree2 h
  rw [compress_cons head1 rest1 degree1,
      compress_cons head2 rest2 degree2] at h
  exact h

/--
Coordinate uniqueness: under `CompressionInjectiveOnHead`, two
non-empty `LatticePublicKey`s that compress to the same `UInt256`
share their head coordinate.

First Lane C statement that the lattice structure constrains the
public key beyond the opaque-word interface. A scheme that uses
this lemma can extract head-coordinate facts from any compression
equality, opening the door to per-coordinate reasoning.
-/
theorem coordinate_uniqueness_under_compressionInjective
    (compress : LatticePublicKey -> UInt256)
    (hInjective : CompressionInjectiveOnHead compress)
    (head1 head2 : UInt256)
    (rest1 rest2 : List UInt256)
    (degree1 degree2 : Nat)
    (h :
      compress { coefficients := head1 :: rest1, degree := degree1 } =
        compress { coefficients := head2 :: rest2, degree := degree2 }) :
    head1 = head2 :=
  hInjective head1 head2 rest1 rest2 degree1 degree2 h

end LatticePublicKey
end Examples
end SoLean
