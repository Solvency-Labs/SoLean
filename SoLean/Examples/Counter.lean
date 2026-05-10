import SoLean.Specs

namespace SoLean
namespace Examples
namespace Counter

def xSlot : Slot := 0

def xExpr : ValueExpr :=
  .slot xSlot

def incProgram (amount : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const amount) (.const 0)))
    (.seq
      (.assign xSlot (.add xExpr (.const amount)))
      (.assert (.ge xExpr (.const amount))))

/--
The manually modeled Counter `inc(amount)` assertion is safe:
whenever execution succeeds, the final modeled value of `x` is at least
`amount`.

Assumptions: `UInt256` is `Nat` with checked addition, and the program is the
hand-written SoLean model rather than generated Solidity semantics.
-/
theorem inc_success_assertion
    (env : Env) (storage finalStorage : Storage) (amount : UInt256)
    (h :
      exec env (incProgram amount) storage =
        ExecResult.success finalStorage) :
    amount <= finalStorage.read xSlot := by
  by_cases hAmount : amount > 0
  · have hPost :
        amount <=
          (Storage.write storage xSlot (storage.read xSlot + amount)).read
            xSlot := by
      rw [Storage.read_write_same]
      exact UInt256.amount_le_add_left (storage.read xSlot) amount
    by_cases hAdd : storage.read xSlot + amount <= UInt256.maxValue
    · have hFinal :
          ExecResult.success
              (Storage.write storage xSlot (storage.read xSlot + amount)) =
            ExecResult.success finalStorage := by
        simpa [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
          UInt256.ge, UInt256.checkedAdd, hAmount, hAdd, hPost] using h
      cases hFinal
      exact hPost
    · have hImpossible :
          ExecResult.revert Failure.arithmeticFailed =
            ExecResult.success finalStorage := by
        simp [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
          UInt256.checkedAdd, hAmount, hAdd] at h
      cases hImpossible
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [incProgram, xExpr, exec, evalBool, evalValue, UInt256.gt,
        hAmount] at h
    cases hImpossible

theorem inc_assertion_safe
    (env : Env) (storage : Storage) (amount : UInt256) :
    succeedsWith (exec env (incProgram amount) storage)
      (fun finalStorage => amount <= finalStorage.read xSlot) := by
  cases h :
      exec env (incProgram amount) storage with
  | success finalStorage =>
      exact inc_success_assertion env storage finalStorage amount h
  | revert _ =>
      trivial

end Counter
end Examples
end SoLean
