import SoLean.Examples.Counter
import SoLean.Yul

namespace SoLean
namespace Examples
namespace CounterYul

def counterProgram : Yul.Program :=
  [
    .ifRevert (.iszero (.gt (.local "amount") (.const UInt256.zero))),
    .let_ "old_x" (.sload Counter.xSlot),
    .let_ "new_x" (.add (.local "old_x") (.local "amount")),
    .ifRevert (.lt (.local "new_x") (.local "old_x")),
    .sstore Counter.xSlot (.local "new_x"),
    .ifRevert (.lt (.local "new_x") (.local "amount"))
  ]

def execCounter (amount : UInt256) (storage : Storage) : Yul.ExecResult :=
  Yul.execFunction counterProgram amount storage

/--
The restricted Yul Counter program succeeds with the same final storage as the
SoLean Counter model whenever the SoLean model succeeds.

This is the first tiny compiler-correctness-style theorem in the repository.
It is still about hand-written Lean syntax on both sides, not parsed Solidity or
real solc output.
-/
theorem counter_refines_solean_success
    (env : Env) (storage finalStorage : Storage) (amount : UInt256)
    (h :
      exec env (Counter.incProgram amount) storage =
        ExecResult.success finalStorage) :
    execCounter amount storage = Yul.ExecResult.success finalStorage := by
  by_cases hAmount : amount > UInt256.zero
  · cases hAdd : UInt256.checkedAdd (storage.read Counter.xSlot) amount with
    | none =>
        have hImpossible :
            ExecResult.revert Failure.arithmeticFailed =
              ExecResult.success finalStorage := by
          simp [Counter.incProgram, Counter.xExpr, exec, evalBool, evalValue, UInt256.gt,
            hAmount, hAdd] at h
        cases hImpossible
    | some sum =>
      have hFinal :
          ExecResult.success (Storage.write storage Counter.xSlot sum) =
            ExecResult.success finalStorage := by
        have hAmountLe : amount <= sum :=
          UInt256.checkedAdd_ge_right hAdd
        simpa [Counter.incProgram, Counter.xExpr, exec, evalBool, evalValue, UInt256.gt,
          UInt256.ge, hAmount, hAdd, hAmountLe] using h
      have hWrap :
          Yul.UInt256.wrapAdd (storage.read Counter.xSlot) amount = sum :=
        Yul.UInt256.wrapAdd_eq_of_checkedAdd hAdd
      have hOldLe : storage.read Counter.xSlot <= sum :=
        UInt256.checkedAdd_ge_left hAdd
      have hNotOverflow : Not (sum < storage.read Counter.xSlot) :=
        Nat.not_lt_of_ge hOldLe
      have hAmountLe : amount <= sum :=
        UInt256.checkedAdd_ge_right hAdd
      have hAssert : Not (sum < amount) :=
        Nat.not_lt_of_ge hAmountLe
      cases hFinal
      simp [execCounter, counterProgram, Yul.execFunction, Yul.execBlock,
        Yul.execStmt, Yul.evalCond, Yul.evalExpr, UInt256.gt, hAmount,
        hNotOverflow, hAssert, hWrap]
  · have hImpossible :
        ExecResult.revert Failure.requireFailed =
          ExecResult.success finalStorage := by
      simp [Counter.incProgram, Counter.xExpr, exec, evalBool, evalValue, UInt256.gt,
        hAmount] at h
    cases hImpossible

/--
The final assertion is safe for successful executions of the restricted Yul
Counter program.
-/
theorem counter_yul_success_assertion
    (storage finalStorage : Storage) (amount : UInt256)
    (h : execCounter amount storage = Yul.ExecResult.success finalStorage) :
    amount <= finalStorage.read Counter.xSlot := by
  by_cases hAmount : amount > UInt256.zero
  · let oldX := storage.read Counter.xSlot
    let newX := Yul.UInt256.wrapAdd oldX amount
    by_cases hOverflow : newX < oldX
    · simp [execCounter, counterProgram, Yul.execFunction, Yul.execBlock,
          Yul.execStmt, Yul.evalCond, Yul.evalExpr, UInt256.gt, oldX, newX,
          hAmount, hOverflow] at h
    · by_cases hAssert : newX < amount
      · simp [execCounter, counterProgram, Yul.execFunction, Yul.execBlock,
            Yul.execStmt, Yul.evalCond, Yul.evalExpr, UInt256.gt, oldX, newX,
            hAmount, hOverflow, hAssert] at h
      · simp [execCounter, counterProgram, Yul.execFunction, Yul.execBlock,
            Yul.execStmt, Yul.evalCond, Yul.evalExpr, UInt256.gt, oldX, newX,
            hAmount, hOverflow, hAssert] at h
        cases h
        rw [Storage.read_write_same]
        exact Nat.not_lt.mp hAssert
  · simp [execCounter, counterProgram, Yul.execFunction, Yul.execBlock,
        Yul.execStmt, Yul.evalCond, Yul.evalExpr, UInt256.gt, hAmount] at h

end CounterYul
end Examples
end SoLean
