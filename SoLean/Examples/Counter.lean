import SoLean.Specs

namespace SoLean
namespace Examples
namespace Counter

def xSlot : Slot := 0

def xExpr : ValueExpr :=
  .slot xSlot

def incProgram (amount : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const amount) (.const UInt256.zero)))
    (.seq
      (.assign xSlot (.add xExpr (.const amount)))
      (.assert (.ge xExpr (.const amount))))

/--
The manually modeled Counter `inc(amount)` assertion is safe:
whenever execution succeeds, the final modeled value of `x` is at least
`amount`.

Assumptions: the program is the hand-written SoLean model rather than generated
Solidity semantics.
-/
theorem inc_success_assertion
    (env : Env) (storage finalStorage : Storage) (amount : UInt256)
    (h :
      exec env (incProgram amount) storage =
        ExecResult.success finalStorage) :
    amount <= finalStorage.read xSlot := by
  by_cases hAmount : amount > UInt256.zero
  · cases hAdd : UInt256.checkedAdd (storage.read xSlot) amount with
    | none =>
        have hImpossible :
            ExecResult.revert Failure.arithmeticFailed =
              ExecResult.success finalStorage := by
          simp [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
            hAmount, hAdd] at h
        cases hImpossible
    | some sum =>
      have hSum : amount <= sum :=
        UInt256.checkedAdd_ge_right hAdd
      have hPost : amount <= (Storage.write storage xSlot sum).read xSlot := by
        rw [Storage.read_write_same]
        exact hSum
      have hFinal :
          ExecResult.success (Storage.write storage xSlot sum) =
            ExecResult.success finalStorage := by
        simpa [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
          UInt256.ge, hAmount, hAdd, hSum] using h
      cases hFinal
      exact hPost
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
        hAmount] at h
    cases hImpossible

def incPost (amount : UInt256) : Post :=
  fun _ _ finalStorage => amount <= finalStorage.read xSlot

theorem inc_assertion_safe (amount : UInt256) :
    FunctionEnsures (incProgram amount) (fun _ _ => True) (incPost amount) := by
  intro env storage _
  cases h :
      exec env (incProgram amount) storage with
  | success finalStorage =>
      exact inc_success_assertion env storage finalStorage amount h
  | revert _ =>
      trivial

end Counter
end Examples
end SoLean
