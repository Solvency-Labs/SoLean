import SoLean.Specs

namespace SoLean
namespace Examples
namespace SimpleVault

def totalAssetsSlot : Slot := 0
def totalSharesSlot : Slot := 1

def totalAssetsExpr : ValueExpr :=
  .slot totalAssetsSlot

def totalSharesExpr : ValueExpr :=
  .slot totalSharesSlot

def invariant : Invariant := fun storage =>
  storage.read totalSharesSlot <= storage.read totalAssetsSlot

/--
SoLean model of `deposit`.

Arithmetic is checked by expression evaluation. Overflow reverts with
`Failure.arithmeticFailed`.
-/
def depositProgram (assets : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const assets) (.const UInt256.zero)))
    (.seq
      (.assign totalAssetsSlot (.add totalAssetsExpr (.const assets)))
      (.seq
        (.assign totalSharesSlot (.add totalSharesExpr (.const assets)))
        (.assert (.ge totalAssetsExpr totalSharesExpr))))

/--
SoLean model of `withdraw`.

Arithmetic is checked by expression evaluation. The subtraction guards mirror
the Solidity `require` checks and underflow reverts with
`Failure.arithmeticFailed`.
-/
def withdrawProgram (shares : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const shares) (.const UInt256.zero)))
    (.seq
      (.require (.ge totalSharesExpr (.const shares)))
      (.seq
        (.require (.ge totalAssetsExpr (.const shares)))
        (.seq
          (.assign totalAssetsSlot (.sub totalAssetsExpr (.const shares)))
          (.seq
            (.assign totalSharesSlot (.sub totalSharesExpr (.const shares)))
            (.assert (.ge totalAssetsExpr totalSharesExpr))))))

/--
Successful `deposit` executions preserve `totalAssets >= totalShares`.

This theorem is about the hand-written SoLean model, not generated Solidity
semantics or Yul equivalence.
-/
theorem deposit_preserves_invariant
    (env : Env) (storage finalStorage : Storage) (assets : UInt256)
    (hInv : invariant storage)
    (h :
      exec env (depositProgram assets) storage =
        ExecResult.success finalStorage) :
    invariant finalStorage := by
  by_cases hAssets : assets > UInt256.zero
  · cases hAddAssets :
        UInt256.checkedAdd (storage.read totalAssetsSlot) assets with
    | none =>
        have hImpossible :
            ExecResult.revert Failure.arithmeticFailed =
              ExecResult.success finalStorage := by
          simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, hAssets, hAddAssets] at h
        cases hImpossible
    | some newAssets =>
      cases hAddShares :
          UInt256.checkedAdd
            ((Storage.write storage totalAssetsSlot newAssets).read
              totalSharesSlot)
            assets with
      | none =>
          have hImpossible :
              ExecResult.revert Failure.arithmeticFailed =
                ExecResult.success finalStorage := by
            simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec,
              evalBool, evalValue, UInt256.gt, hAssets, hAddAssets,
              hAddShares] at h
          cases hImpossible
      | some newShares =>
        have hNewSharesLe : newShares <= newAssets := by
          show newShares.toNat <= newAssets.toNat
          rw [UInt256.checkedAdd_toNat hAddShares,
            UInt256.checkedAdd_toNat hAddAssets]
          simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
            Nat.add_le_add_right hInv assets.toNat
        have hPost :
            invariant
              (Storage.write
                (Storage.write storage totalAssetsSlot newAssets)
                totalSharesSlot newShares) := by
          simpa [invariant, totalAssetsSlot, totalSharesSlot, Storage.write]
            using hNewSharesLe
        have hAssert :
            newShares <=
              (Storage.write
                (Storage.write storage totalAssetsSlot newAssets)
                totalSharesSlot newShares).read totalAssetsSlot := by
          simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
            hNewSharesLe
        have hFinal :
            ExecResult.success
                (Storage.write
                  (Storage.write storage totalAssetsSlot newAssets)
                  totalSharesSlot newShares) =
              ExecResult.success finalStorage := by
          simpa [depositProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.ge, hAssets, hAddAssets,
            hAddShares, hAssert] using h
        cases hFinal
        exact hPost
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec, evalBool,
        evalValue, UInt256.gt, hAssets] at h
    cases hImpossible

theorem deposit_invariant_safe (assets : UInt256) :
    PreservesInvariant (depositProgram assets) invariant := by
  unfold PreservesInvariant FunctionEnsures
  intro env storage hInv
  cases h :
      exec env (depositProgram assets) storage with
  | success finalStorage =>
      exact deposit_preserves_invariant env storage finalStorage assets hInv h
  | revert _ =>
      trivial

/--
Successful `withdraw` executions preserve `totalAssets >= totalShares`.

This relies on the modeled `require` guards and the pre-state invariant.
-/
theorem withdraw_preserves_invariant
    (env : Env) (storage finalStorage : Storage) (shares : UInt256)
    (hInv : invariant storage)
    (h :
      exec env (withdrawProgram shares) storage =
        ExecResult.success finalStorage) :
    invariant finalStorage := by
  by_cases hShares : shares > UInt256.zero
  · by_cases hEnoughShares : shares <= storage.read totalSharesSlot
    · by_cases hEnoughAssets : shares <= storage.read totalAssetsSlot
      · cases hSubAssets :
            UInt256.checkedSub (storage.read totalAssetsSlot) shares with
        | none =>
            have hImpossible :
                ExecResult.revert Failure.arithmeticFailed =
                  ExecResult.success finalStorage := by
              simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
                evalBool, evalValue, UInt256.gt, UInt256.ge, hShares,
                hEnoughShares, hEnoughAssets, hSubAssets] at h
            cases hImpossible
        | some newAssets =>
          cases hSubShares :
              UInt256.checkedSub
                ((Storage.write storage totalAssetsSlot newAssets).read
                  totalSharesSlot)
                shares with
          | none =>
              have hImpossible :
                  ExecResult.revert Failure.arithmeticFailed =
                    ExecResult.success finalStorage := by
                simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
                  evalBool, evalValue, UInt256.gt, UInt256.ge, hShares,
                  hEnoughShares, hEnoughAssets, hSubAssets, hSubShares] at h
              cases hImpossible
          | some newShares =>
            have hNewSharesLe : newShares <= newAssets := by
              show newShares.toNat <= newAssets.toNat
              rw [UInt256.checkedSub_toNat hSubShares,
                UInt256.checkedSub_toNat hSubAssets]
              simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
                UInt256.sub_le_sub_right hInv (c := shares)
            have hPost :
                invariant
                  (Storage.write
                    (Storage.write storage totalAssetsSlot newAssets)
                    totalSharesSlot newShares) := by
              simpa [invariant, totalAssetsSlot, totalSharesSlot, Storage.write]
                using hNewSharesLe
            have hAssert :
                newShares <=
                  (Storage.write
                    (Storage.write storage totalAssetsSlot newAssets)
                    totalSharesSlot newShares).read totalAssetsSlot := by
              simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
                hNewSharesLe
            have hFinal :
                ExecResult.success
                    (Storage.write
                      (Storage.write storage totalAssetsSlot newAssets)
                      totalSharesSlot newShares) =
                  ExecResult.success finalStorage := by
              simpa [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
                evalBool, evalValue, UInt256.gt, UInt256.ge, hShares,
                hEnoughShares, hEnoughAssets, hSubAssets, hSubShares,
                hAssert] using h
            cases hFinal
            exact hPost
      · have hImpossible :
            ExecResult.revert Failure.requireFailed =
              ExecResult.success finalStorage := by
          simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.ge, hShares,
            hEnoughShares, hEnoughAssets] at h
        cases hImpossible
    · have hImpossible :
          ExecResult.revert Failure.requireFailed =
            ExecResult.success finalStorage := by
        simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
          evalBool, evalValue, UInt256.gt, UInt256.ge, hShares,
          hEnoughShares] at h
      cases hImpossible
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec, evalBool,
        evalValue, UInt256.gt, hShares] at h
    cases hImpossible

theorem withdraw_invariant_safe (shares : UInt256) :
    PreservesInvariant (withdrawProgram shares) invariant := by
  unfold PreservesInvariant FunctionEnsures
  intro env storage hInv
  cases h :
      exec env (withdrawProgram shares) storage with
  | success finalStorage =>
      exact withdraw_preserves_invariant env storage finalStorage shares hInv h
  | revert _ =>
      trivial

end SimpleVault
end Examples
end SoLean
