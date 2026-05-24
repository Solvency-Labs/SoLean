import SoLean.DSL
import SoLean.Examples.AAPQIntegration
import SoLean.Examples.ToyVerifier

namespace SoLean
namespace Examples
namespace StructuredVerifier

/--
Witness produced by a structured verifier on accept.

Real PQ schemes decompose a verification into intermediate algebraic
objects (signature components, polynomial reconstructions, hash chains).
This record exposes a *shape* for those intermediate objects without
committing to a specific scheme — concrete schemes can refine the
`signatureComponents` and `publicKeyComponents` fields with their own
structure.

Carrying a witness on accept is the first step toward letting downstream
proofs say "the verifier accepted *because* of this specific decomposition,"
not just "the verifier returned true."
-/
structure VerifierWitness where
  signatureComponents : List UInt256
  publicKeyComponents : List UInt256
deriving Repr, DecidableEq

/--
Richer verifier interface. Returns `some witness` on accept and `none` on
reject. The `Option` distinguishes the two outcomes the same way `Bool`
does in `Env.verifier`, but adds shape to the accept case.

This is the substrate for Lane B's later milestones — concrete schemes
(Falcon, ML-DSA) would refine `VerifierWitness` with scheme-specific
fields, and intermediate proofs about verifier behavior can reference
those fields.
-/
structure StructuredVerifier where
  decide : UInt256 -> UInt256 -> UInt256 -> UInt256 -> Option VerifierWitness

/--
Project a `StructuredVerifier` down to the existing `Bool`-valued
`Env.verifier` interface. The wallet/wrapper code remains unchanged;
the structured shape lives alongside it.
-/
def StructuredVerifier.toBool (sv : StructuredVerifier) :
    UInt256 -> UInt256 -> UInt256 -> UInt256 -> Bool :=
  fun key message domain signature =>
    (sv.decide key message domain signature).isSome

/--
Correspondence assumption tying a structured verifier to an existing
`Bool`-valued one: they agree on every input. Under
`StructureRespectsBool`, any oracle-level assumption (DomainSeparation,
SignatureBinding, KeySeparation) on the `Bool` verifier lifts immediately
to the structured one's projection.

This is the named bridge for Lane B: existing AAPQ proofs continue to use
`Env.verifier` (which is `Bool`-valued), and a `StructuredVerifier`-based
calibration provides the projection.
-/
def StructureRespectsBool
    (sv : StructuredVerifier)
    (bv : UInt256 -> UInt256 -> UInt256 -> UInt256 -> Bool) : Prop :=
  ∀ key message domain signature,
    (sv.decide key message domain signature).isSome =
      bv key message domain signature

/--
Under `StructureRespectsBool`, the projection equals the original `Bool`
verifier. The wallet's safety theorems carry over without re-proof.
-/
theorem toBool_eq_under_respectsBool
    (sv : StructuredVerifier)
    (bv : UInt256 -> UInt256 -> UInt256 -> UInt256 -> Bool)
    (h : StructureRespectsBool sv bv) :
    sv.toBool = bv := by
  funext key message domain signature
  exact h key message domain signature

/--
Lift a `StructuredVerifier` into an `Env` with the given `msgSender`.
The resulting env's verifier is `sv.toBool`.
-/
def structuredEnv (msgSender : Address) (sv : StructuredVerifier) : Env :=
  { msgSender := msgSender, verifier := sv.toBool }

/--
Concrete structured-verifier example mirroring `ToyVerifier.allFieldsEqual
Verifier`: accept when all four inputs are equal, with a witness that
records the agreed value as a singleton public-key component.

Demonstrates that the existing toy calibration *can* be presented as a
`StructuredVerifier` without changing its acceptance set.
-/
def allFieldsEqualStructuredVerifier : StructuredVerifier :=
  { decide := fun key message domain signature =>
      if key = message ∧ message = domain ∧ domain = signature then
        some { signatureComponents := [signature],
               publicKeyComponents := [key] }
      else
        none }

/--
The structured all-fields-equal verifier projects to the same `Bool`
function as the existing toy. The correspondence is the witness that
M22'/M23' can build on.
-/
theorem allFieldsEqualStructuredVerifier_respects_bool :
    StructureRespectsBool allFieldsEqualStructuredVerifier
      ToyVerifier.allFieldsEqualVerifier := by
  intro key message domain signature
  unfold allFieldsEqualStructuredVerifier StructuredVerifier.decide
    ToyVerifier.allFieldsEqualVerifier
  by_cases h : key = message ∧ message = domain ∧ domain = signature
  · simp [h]
  · simp [h]

/--
Witness extraction from the `Bool` projection: if `sv.toBool` returned
`true`, then `sv.decide` returned `some witness` for the same input —
the structured information is recoverable from the boolean fact.
-/
theorem decide_isSome_of_toBool
    (sv : StructuredVerifier)
    (key message domain signature : UInt256)
    (h : sv.toBool key message domain signature = true) :
    ∃ witness,
      sv.decide key message domain signature = some witness := by
  unfold StructuredVerifier.toBool at h
  cases hDec : sv.decide key message domain signature with
  | some w => exact ⟨w, rfl⟩
  | none =>
      rw [hDec] at h
      simp [Option.isSome] at h

/--
Bridge theorem: under `StructureRespectsBool`, any acceptance fact about
the existing `Bool`-valued verifier lifts to witness extraction on the
structured verifier. Downstream code that holds an
`Env.verifier ... = true` fact can use this to obtain the `VerifierWitness`
without weakening any existing AAPQ-side proof.

This is the value of `StructureRespectsBool` made explicit: Bool-level
oracle assumptions discharge contract-level safety theorems, AND when
the same boolean fact holds, structural detail can be peeled out.
-/
theorem witness_extractable_under_respectsBool
    {sv : StructuredVerifier}
    {bv : UInt256 -> UInt256 -> UInt256 -> UInt256 -> Bool}
    (hRespects : StructureRespectsBool sv bv)
    {key message domain signature : UInt256}
    (h : bv key message domain signature = true) :
    ∃ witness,
      sv.decide key message domain signature = some witness := by
  apply decide_isSome_of_toBool
  rw [toBool_eq_under_respectsBool sv bv hRespects]
  exact h

end StructuredVerifier
end Examples
end SoLean
