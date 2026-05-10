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

def invariant (storage : Storage) : Prop :=
  storage.read totalSharesSlot <= storage.read totalAssetsSlot

/--
SoLean model of `deposit`.

Arithmetic is checked by expression evaluation. Overflow reverts with
`Failure.arithmeticFailed`.
-/
def depositProgram (assets : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const assets) (.const 0)))
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
    (.require (.gt (.const shares) (.const 0)))
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
  by_cases hAssets : assets > 0
  · by_cases hAddAssets :
        storage.read totalAssetsSlot + assets <= UInt256.maxValue
    · by_cases hAddShares :
          (Storage.write storage totalAssetsSlot
                (storage.read totalAssetsSlot + assets)).read totalSharesSlot +
              assets <= UInt256.maxValue
      · have hPost :
            invariant
              (Storage.write
                (Storage.write storage totalAssetsSlot
                  (storage.read totalAssetsSlot + assets))
                totalSharesSlot
                ((Storage.write storage totalAssetsSlot
                    (storage.read totalAssetsSlot + assets)).read
                  totalSharesSlot + assets)) := by
          simpa [invariant, totalAssetsSlot, totalSharesSlot, Storage.write]
            using hInv
        have hAddInv : storage.read 1 + assets <= storage.read 0 + assets :=
          Nat.add_le_add_right hInv assets
        have hAddAssets0 : storage.read 0 + assets <= UInt256.maxValue := by
          simpa [totalAssetsSlot] using hAddAssets
        have hAddShares0 : storage.read 1 + assets <= UInt256.maxValue := by
          simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
            hAddShares
        have hFinal :
            ExecResult.success
                (Storage.write
                  (Storage.write storage totalAssetsSlot
                    (storage.read totalAssetsSlot + assets))
                  totalSharesSlot
                  ((Storage.write storage totalAssetsSlot
                      (storage.read totalAssetsSlot + assets)).read
                    totalSharesSlot + assets)) =
              ExecResult.success finalStorage := by
          simpa [depositProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.ge, UInt256.checkedAdd,
            invariant, totalAssetsSlot, totalSharesSlot, Storage.write,
            hAssets, hAddAssets0, hAddShares0, hInv, hAddInv, hPost] using h
        cases hFinal
        exact hPost
      · have hImpossible :
            ExecResult.revert Failure.arithmeticFailed =
              ExecResult.success finalStorage := by
          have hAddAssets0 : storage.read 0 + assets <= UInt256.maxValue := by
            simpa [totalAssetsSlot] using hAddAssets
          have hAddShares0 :
              Not (storage.read 1 + assets <= UInt256.maxValue) := by
            simpa [totalAssetsSlot, totalSharesSlot, Storage.write] using
              hAddShares
          simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.checkedAdd,
            totalAssetsSlot, totalSharesSlot, Storage.write, hAssets,
            hAddAssets0, hAddShares0] at h
        cases hImpossible
    · have hImpossible :
          ExecResult.revert Failure.arithmeticFailed =
            ExecResult.success finalStorage := by
        have hAddAssets0 :
            Not (storage.read 0 + assets <= UInt256.maxValue) := by
          simpa [totalAssetsSlot] using hAddAssets
        simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec, evalBool,
          evalValue, UInt256.gt, UInt256.checkedAdd, totalAssetsSlot,
          totalSharesSlot, Storage.write, hAssets, hAddAssets0] at h
      cases hImpossible
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [depositProgram, totalAssetsExpr, totalSharesExpr, exec, evalBool,
        evalValue, UInt256.gt, hAssets] at h
    cases hImpossible

theorem deposit_invariant_safe
    (env : Env) (storage : Storage) (assets : UInt256)
    (hInv : invariant storage) :
    succeedsWith (exec env (depositProgram assets) storage) invariant := by
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
  by_cases hShares : shares > 0
  · by_cases hEnoughShares : shares <= storage.read totalSharesSlot
    · by_cases hEnoughAssets : shares <= storage.read totalAssetsSlot
      · have hPost :
            invariant
              (Storage.write
                (Storage.write storage totalAssetsSlot
                  (storage.read totalAssetsSlot - shares))
                totalSharesSlot
                ((Storage.write storage totalAssetsSlot
                    (storage.read totalAssetsSlot - shares)).read
                  totalSharesSlot - shares)) := by
          simp [invariant, totalAssetsSlot, totalSharesSlot, Storage.write]
          exact UInt256.sub_le_sub_right hInv
        have hSubInv : storage.read 1 - shares <= storage.read 0 - shares :=
          UInt256.sub_le_sub_right hInv
        have hEnoughShares0 : shares <= storage.read 1 := by
          simpa [totalSharesSlot] using hEnoughShares
        have hEnoughAssets0 : shares <= storage.read 0 := by
          simpa [totalAssetsSlot] using hEnoughAssets
        have hFinal :
            ExecResult.success
                (Storage.write
                  (Storage.write storage totalAssetsSlot
                    (storage.read totalAssetsSlot - shares))
                  totalSharesSlot
                  ((Storage.write storage totalAssetsSlot
                      (storage.read totalAssetsSlot - shares)).read
                    totalSharesSlot - shares)) =
              ExecResult.success finalStorage := by
          simpa [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.ge, UInt256.checkedSub,
            invariant, totalAssetsSlot, totalSharesSlot, Storage.write,
            hShares, hEnoughShares0, hEnoughAssets0, hSubInv, hPost] using h
        cases hFinal
        exact hPost
      · have hImpossible :
            ExecResult.revert Failure.requireFailed =
              ExecResult.success finalStorage := by
          have hEnoughShares0 : shares <= storage.read 1 := by
            simpa [totalSharesSlot] using hEnoughShares
          have hEnoughAssets0 : Not (shares <= storage.read 0) := by
            simpa [totalAssetsSlot] using hEnoughAssets
          simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
            evalBool, evalValue, UInt256.gt, UInt256.ge, totalAssetsSlot,
            totalSharesSlot, Storage.write, hShares, hEnoughShares,
            hEnoughShares0, hEnoughAssets0] at h
        cases hImpossible
    · have hImpossible :
          ExecResult.revert Failure.requireFailed =
            ExecResult.success finalStorage := by
        have hEnoughShares0 : Not (shares <= storage.read 1) := by
          simpa [totalSharesSlot] using hEnoughShares
        simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec,
          evalBool, evalValue, UInt256.gt, UInt256.ge, totalAssetsSlot,
          totalSharesSlot, Storage.write, hShares, hEnoughShares0] at h
      cases hImpossible
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [withdrawProgram, totalAssetsExpr, totalSharesExpr, exec, evalBool,
        evalValue, UInt256.gt, hShares] at h
    cases hImpossible

theorem withdraw_invariant_safe
    (env : Env) (storage : Storage) (shares : UInt256)
    (hInv : invariant storage) :
    succeedsWith (exec env (withdrawProgram shares) storage) invariant := by
  cases h :
      exec env (withdrawProgram shares) storage with
  | success finalStorage =>
      exact withdraw_preserves_invariant env storage finalStorage shares hInv h
  | revert _ =>
      trivial

end SimpleVault
end Examples
end SoLean
