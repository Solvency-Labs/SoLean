import SoLean.Semantics

namespace SoLean
namespace Yul

/--
Local variables for the tiny restricted Yul model.

This is intentionally partial: reading an unknown local fails and execution
reverts in the prototype semantics.
-/
abbrev Locals := String -> Option UInt256

namespace Locals

def empty : Locals :=
  fun _ => none

def write (locals : Locals) (name : String) (value : UInt256) : Locals :=
  fun key => if key = name then some value else locals key

@[simp]
theorem write_same (locals : Locals) (name : String) (value : UInt256) :
    (write locals name value) name = some value := by
  simp [write]

@[simp]
theorem write_other (locals : Locals) {target name : String}
    (value : UInt256) (h : Not (target = name)) :
    (write locals name value) target = locals target := by
  simp [write, h]

end Locals

inductive Expr where
  | const : UInt256 -> Expr
  | local : String -> Expr
  | sload : Slot -> Expr
  | add : Expr -> Expr -> Expr
deriving Repr, DecidableEq

inductive Cond where
  | gt : Expr -> Expr -> Cond
  | lt : Expr -> Expr -> Cond
  | iszero : Cond -> Cond
deriving Repr, DecidableEq

inductive Stmt where
  | let_ : String -> Expr -> Stmt
  | sstore : Slot -> Expr -> Stmt
  | ifRevert : Cond -> Stmt
deriving Repr, DecidableEq

abbrev Program := List Stmt

/-- Wrap a natural number into the UInt256 range, as EVM arithmetic does. -/
def UInt256.wrap (value : Nat) : UInt256 :=
  { toNat := value % (UInt256.maxValue + 1),
    isValid := by
      have hPositive : 0 < UInt256.maxValue + 1 := by
        exact Nat.succ_pos UInt256.maxValue
      have hLt : value % (UInt256.maxValue + 1) < UInt256.maxValue + 1 :=
        Nat.mod_lt value hPositive
      exact Nat.lt_succ_iff.mp hLt }

def UInt256.wrapAdd (a b : UInt256) : UInt256 :=
  UInt256.wrap (a.toNat + b.toNat)

theorem UInt256.wrap_toNat_of_le {value : Nat}
    (h : value <= UInt256.maxValue) :
    (UInt256.wrap value).toNat = value := by
  unfold UInt256.wrap
  have hLt : value < UInt256.maxValue + 1 :=
    Nat.lt_succ_iff.mpr h
  exact Nat.mod_eq_of_lt hLt

theorem UInt256.wrapAdd_eq_of_checkedAdd {a b result : UInt256}
    (h : UInt256.checkedAdd a b = some result) :
    UInt256.wrapAdd a b = result := by
  apply UInt256.ext
  have hToNat := UInt256.checkedAdd_toNat h
  have hBound : a.toNat + b.toNat <= UInt256.maxValue := by
    rw [← hToNat]
    exact result.isValid
  unfold UInt256.wrapAdd
  rw [UInt256.wrap_toNat_of_le hBound]
  exact hToNat.symm

def evalExpr (storage : Storage) (locals : Locals) : Expr -> Option UInt256
  | .const value => some value
  | .local name => locals name
  | .sload slot => some (storage.read slot)
  | .add lhs rhs =>
      match evalExpr storage locals lhs, evalExpr storage locals rhs with
      | some lhsValue, some rhsValue => some (UInt256.wrapAdd lhsValue rhsValue)
      | _, _ => none

def evalCond (storage : Storage) (locals : Locals) : Cond -> Option Bool
  | .gt lhs rhs =>
      match evalExpr storage locals lhs, evalExpr storage locals rhs with
      | some lhsValue, some rhsValue => some (UInt256.gt lhsValue rhsValue)
      | _, _ => none
  | .lt lhs rhs =>
      match evalExpr storage locals lhs, evalExpr storage locals rhs with
      | some lhsValue, some rhsValue => some (decide (lhsValue < rhsValue))
      | _, _ => none
  | .iszero cond =>
      match evalCond storage locals cond with
      | some value => some (!value)
      | none => none

inductive StepResult where
  | ok : Storage -> Locals -> StepResult
  | revert : StepResult

inductive ExecResult where
  | success : Storage -> ExecResult
  | revert : ExecResult

def execStmt (stmt : Stmt) (storage : Storage) (locals : Locals) : StepResult :=
  match stmt with
  | .let_ name expr =>
      match evalExpr storage locals expr with
      | some value => .ok storage (Locals.write locals name value)
      | none => .revert
  | .sstore slot expr =>
      match evalExpr storage locals expr with
      | some value => .ok (Storage.write storage slot value) locals
      | none => .revert
  | .ifRevert cond =>
      match evalCond storage locals cond with
      | some true => .revert
      | some false => .ok storage locals
      | none => .revert

def execBlock (program : Program) (storage : Storage) (locals : Locals) :
    ExecResult :=
  match program with
  | [] => .success storage
  | stmt :: rest =>
      match execStmt stmt storage locals with
      | .ok storage' locals' => execBlock rest storage' locals'
      | .revert => .revert

def execFunction (program : Program) (amount : UInt256) (storage : Storage) :
    ExecResult :=
  execBlock program storage (Locals.write Locals.empty "amount" amount)

end Yul
end SoLean
