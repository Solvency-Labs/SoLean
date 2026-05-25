import SoLean.EVM.Call
import SoLean.Examples.AAPQIntegration
import SoLean.Examples.AAPQSource
import SoLean.Examples.SchemeParameters

namespace SoLean
namespace Examples
namespace FalconSimpleWallet

/--
AA-reviewer-facing deployment view for a FalconSimpleWallet-style PQ-AA
wallet.

The wallet has no `ecrecover`; authentication is against a stored public
key (or key commitment) via a PQ verifier wrapper deployed at a known
address. This record bundles the wallet contract, the wrapper contract,
the scheme parameters the wrapper is calibrated for, and the wrapper's
deployment address.

The fields mirror the modeled state: `walletStorage` carries
key-commitment, nonce, domain, entry-point, lastOpHash, and wrapper
address; `wrapperStorage` carries the expected public-key / signature /
domain values matching the scheme parameters.
-/
structure FalconSimpleWalletDeployment where
  wallet : AAPQSource.Contract
  wrapper : AAPQSource.Contract
  scheme : SchemeParameters.SchemeParameters
  wrapperAddress : EVM.Address

/--
The default Falcon-512 FalconSimpleWallet deployment. The wallet is the
existing `AAPQSource.walletContract` extended (in the source-shape view)
with a `wrapperAddress` slot; the wrapper is `AAPQSource.wrapperContract`
calibrated for Falcon-512 lengths.
-/
def falconSimpleWalletDeployment : FalconSimpleWalletDeployment :=
  { wallet :=
      { name := "FalconSimpleWallet",
        pragma := "0.8.35",
        storage := AAPQSource.walletContract.storage ++ [
          { name := "wrapperAddress",
            slot := AAWallet.wrapperAddressSlot,
            typeName := "address" }
        ],
        functionName := "validateUserOp",
        params := AAPQSource.walletContract.params },
    wrapper := AAPQSource.wrapperContract,
    scheme := SchemeParameters.falcon512,
    wrapperAddress := ({ value := UInt256.one } : EVM.Address) }

/--
Named cross-storage assumption: the wallet's `wrapperAddressSlot` stores
the same address the integration actually calls. Bridges the runtime
`Address` value to the modeled wallet storage.

This is the analog of `WrapperOracleConsistent` for the wallet-side
address declaration: it ties the wallet's stored deployment data to the
EvmEnv's runtime configuration.
-/
def WalletStoresWrapperAddress
    (deployment : FalconSimpleWalletDeployment)
    (walletStorage : Storage) : Prop :=
  walletStorage.read AAWallet.wrapperAddressSlot =
    deployment.wrapperAddress.value

/--
Named calibration: the wrapper's stored expected lengths match the
deployment's scheme parameters. A FalconSimpleWallet deployment with
Falcon-512 has the wrapper storing `falcon512.publicKeyByteLengthUInt256`
and `falcon512.signatureByteLengthUInt256`.
-/
def WrapperCalibratedForScheme
    (deployment : FalconSimpleWalletDeployment)
    (wrapperStorage : Storage) : Prop :=
  wrapperStorage.read PQVerifierWrapper.expectedPublicKeyLengthSlot =
      deployment.scheme.publicKeyByteLengthUInt256 ∧
    wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot =
      deployment.scheme.signatureByteLengthUInt256

/--
Composite safety result for a successful `validateAndExecute` against a
FalconSimpleWallet-style deployment.

Bundles the five claims an AA reviewer wants in one place:
(a) the input public key matches the wallet's stored commitment;
(b) the abstract verifier accepted the exact
    `(publicKey, opHash, domain, signature)` tuple;
(c) the wallet's nonce advanced through checked arithmetic;
(d) the operation hash is recorded at `lastOpHashSlot`;
(e) the same `UserOp` cannot replay against the post-validation state.
-/
structure FalconSimpleWalletSafety
    (env : Env) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage) :
    Prop where
  keyMatchesCommitment :
    input.publicKey = walletStorage.read AAWallet.keyCommitmentSlot
  verifierAcceptedTuple :
    env.verifier input.publicKey input.opHash input.domain input.signature
      = true
  nonceAdvanced :
    UInt256.checkedAdd (walletStorage.read AAWallet.nonceSlot)
        UInt256.one =
      some (finalWallet.read AAWallet.nonceSlot)
  opHashRecorded :
    finalWallet.read AAWallet.lastOpHashSlot = input.opHash
  replayCannotSucceed :
    ∀ rw rw',
      AAPQIntegration.validateAndExecute env input finalWrapper finalWallet ≠
        AAPQIntegration.IntegratedFullResult.success rw rw'

/--
The FalconSimpleWallet composite safety theorem. A single statement an
AA reviewer can cite to know what a successful integrated
`validateAndExecute` means against this deployment shape.

Each conjunct projects an existing AA/PQ safety theorem:
- (a) from `AAPQIntegration.IntegratedPost` via
  `validateIntegrated_success_properties`;
- (b) from `validateAndExecute_implies_verifier_accepted`;
- (c) from the wallet `ValidationPost`'s nonce-add clause, lifted through
  `validateAndExecute_success_structure` and `Storage.read_write_other`
  on `lastOpHashSlot` vs `nonceSlot`;
- (d) from `validateAndExecute_success_records_opHash`;
- (e) from `validateAndExecute_replay_rejected`.
-/
theorem falconSimpleWallet_composite_safety
    (env : Env) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage)
    (h :
      AAPQIntegration.validateAndExecute env input
          wrapperStorage walletStorage =
        AAPQIntegration.IntegratedFullResult.success finalWrapper
          finalWallet) :
    FalconSimpleWalletSafety env input wrapperStorage walletStorage
      finalWrapper finalWallet := by
  -- Extract the structural decomposition: ∃ postWallet,
  --   validateIntegrated ... = success finalWrapper postWallet ∧
  --   finalWallet = Storage.write postWallet lastOpHashSlot input.opHash
  obtain ⟨postWallet, hValidate, hFinalWalletEq⟩ :=
    AAPQIntegration.validateAndExecute_success_structure env input
      wrapperStorage walletStorage finalWrapper finalWallet h
  -- Extract the IntegratedPost from validateIntegrated success.
  have hPost :=
    AAPQIntegration.validateIntegrated_success_properties env wrapperStorage
      walletStorage finalWrapper postWallet input hValidate
  -- Wallet-side ValidationPost gives nonce-add etc.
  rcases hPost.2.1 with
    ⟨_, _, _, _, hNonceAdd, _, _, _⟩
  -- finalWallet.nonce = postWallet.nonce because lastOpHashSlot ≠ nonceSlot.
  have hLastOpNeNonce :
      Not (AAWallet.nonceSlot = AAWallet.lastOpHashSlot) := by decide
  have hFinalNonceEqPost :
      finalWallet.read AAWallet.nonceSlot =
        postWallet.read AAWallet.nonceSlot := by
    rw [hFinalWalletEq,
        Storage.read_write_other postWallet input.opHash hLastOpNeNonce]
  refine
    { keyMatchesCommitment := hPost.2.2.1,
      verifierAcceptedTuple := ?_,
      nonceAdvanced := ?_,
      opHashRecorded := ?_,
      replayCannotSucceed := ?_ }
  · exact
      AAPQIntegration.validateAndExecute_implies_verifier_accepted env input
        wrapperStorage walletStorage finalWrapper finalWallet h
  · rw [hFinalNonceEqPost]; exact hNonceAdd
  · exact
      AAPQIntegration.validateAndExecute_success_records_opHash env input
        wrapperStorage walletStorage finalWrapper finalWallet h
  · intro rw rw' hReplay
    exact
      AAPQIntegration.validateAndExecute_replay_rejected env input
        wrapperStorage walletStorage finalWrapper finalWallet rw rw' h hReplay

/--
Deployment-level scheme discrimination: a Falcon-512 FalconSimpleWallet
deployment, under `WrapperCalibratedForScheme`, cannot succeed
`validateAndExecute` on an `IntegratedInput` whose `signatureLength`
matches ML-DSA-44.

Lifts `SchemeParameters.validateAndExecute_falcon512_calibrated_rejects_
mlDsa44_signature_length` from the wrapper-level to the deployment-level
through the named scheme equality in `falconSimpleWalletDeployment`.

Concrete content: an attacker holding an ML-DSA-44-sized signature
cannot replay calldata against a wallet deployment that was provisioned
for Falcon-512 — the wrapper's stored expected signature length forces
a revert before any verifier oracle runs, and the integration boundary
propagates that revert.
-/
theorem falconSimpleWalletDeployment_rejects_mlDsa44_signature_length
    (env : Env) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage)
    (hCalibrated :
      WrapperCalibratedForScheme falconSimpleWalletDeployment wrapperStorage)
    (hMlDsaSig :
      input.signatureLength =
        SchemeParameters.mlDsa44.signatureByteLengthUInt256) :
    ∀ finalWrapper finalWallet,
      AAPQIntegration.validateAndExecute env input wrapperStorage
          walletStorage ≠
        AAPQIntegration.IntegratedFullResult.success finalWrapper
          finalWallet := by
  -- WrapperCalibratedForScheme unpacks to the two stored-length equalities;
  -- the relevant one is the signature length matching falcon512.
  have hSigCalibrated :
      wrapperStorage.read PQVerifierWrapper.expectedSignatureLengthSlot =
        SchemeParameters.falcon512.signatureByteLengthUInt256 := by
    -- falconSimpleWalletDeployment.scheme is falcon512 by definition.
    exact hCalibrated.2
  exact
    SchemeParameters.validateAndExecute_falcon512_calibrated_rejects_mlDsa44_signature_length
      env input wrapperStorage walletStorage hSigCalibrated hMlDsaSig

/--
Deployment-level wrapper-address preservation: if the wallet storage initially
satisfies the named `WalletStoresWrapperAddress` assumption, then a successful
integrated `validateAndExecute` preserves that assumption on the final wallet
storage.

This is the v1.6 lift from raw slot preservation
(`AAPQIntegration.validateAndExecute_preserves_wallet_wrapperAddress`) to the
deployment-facing cross-storage assumption auditors actually read.
-/
theorem validateAndExecute_preserves_walletStoresWrapperAddress
    (deployment : FalconSimpleWalletDeployment)
    (env : Env) (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage finalWrapper finalWallet : Storage)
    (hStored : WalletStoresWrapperAddress deployment walletStorage)
    (h :
      AAPQIntegration.validateAndExecute env input wrapperStorage
          walletStorage =
        AAPQIntegration.IntegratedFullResult.success finalWrapper
          finalWallet) :
    WalletStoresWrapperAddress deployment finalWallet := by
  unfold WalletStoresWrapperAddress at *
  rw [AAPQIntegration.validateAndExecute_preserves_wallet_wrapperAddress
    env input wrapperStorage walletStorage finalWrapper finalWallet h]
  exact hStored

end FalconSimpleWallet
end Examples
end SoLean
