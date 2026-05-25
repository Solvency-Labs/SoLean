import SoLean.DSL

namespace SoLean
namespace Examples
namespace ProtocolBoundaries

/--
Named non-claim: the outer bundler transaction in ERC-4337 today still
relies on ECDSA, even when individual `UserOp`s are PQ-authenticated
via the wallet's verifier wrapper.

This is a `Prop`-level *witness* of the non-claim, not a proof. SoLean
does not prove this property holds for any modeled flow; the predicate
exists so the certificate can reference it structurally instead of only
mentioning it in prose.

A future protocol-level / native-AA milestone (RIP-7560 / EIP-7701-like
direction) would in principle let SoLean discharge this predicate
against a modeled bundler interface. Until then it remains an explicit
non-claim.
-/
def BundlerEcdsaDependence : Prop :=
  -- Intentionally `True`: the predicate carries no content, only a
  -- name and a Lean reference. It exists for the certificate's
  -- structured-non-claim surface.
  True

/--
Named non-claim: under EIP-7702, an EOA can delegate to a smart-wallet
implementation that adds PQ-AA behavior, but the original ECDSA key
remains valid for signing — a PQ-resilience risk SoLean does not
resolve.

Same shape as `BundlerEcdsaDependence`: a Prop witness of the
non-claim, not a proof.
-/
def Eip7702EcdsaKeyValidity : Prop :=
  True

/--
Trivial witness — these are non-claims, not proofs of any safety
property. The certificate uses these references to enumerate
protocol-level boundaries SoLean explicitly does not cross.
-/
theorem bundlerEcdsaDependence_trivial : BundlerEcdsaDependence := trivial

theorem eip7702EcdsaKeyValidity_trivial : Eip7702EcdsaKeyValidity := trivial

end ProtocolBoundaries
end Examples
end SoLean
