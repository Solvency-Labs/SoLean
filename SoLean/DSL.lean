import SoLean.UInt256

namespace SoLean

abbrev Slot := Nat
abbrev Address := Nat

/-- Contract storage, modeled as a total mapping from storage slots to values. -/
structure Storage where
  read : Slot -> UInt256

namespace Storage

def empty : Storage :=
  { read := fun _ => UInt256.zero }

def write (storage : Storage) (slot : Slot) (value : UInt256) : Storage :=
  { read := fun key => if key = slot then value else storage.read key }

@[simp]
theorem read_write_same (storage : Storage) (slot : Slot) (value : UInt256) :
    (write storage slot value).read slot = value := by
  simp [write]

@[simp]
theorem read_write_other (storage : Storage) {target slot : Slot}
    (value : UInt256) (h : Not (target = slot)) :
    (write storage slot value).read target = storage.read target := by
  simp [write, h]

end Storage

/-- Minimal execution environment. More EVM fields can be added as needed. -/
structure Env where
  msgSender : Address
deriving Repr, DecidableEq

namespace Env

def default : Env :=
  { msgSender := 0 }

end Env

inductive ValueExpr where
  | const : UInt256 -> ValueExpr
  | slot : Slot -> ValueExpr
  | add : ValueExpr -> ValueExpr -> ValueExpr
  | sub : ValueExpr -> ValueExpr -> ValueExpr
deriving Repr, DecidableEq

inductive BoolExpr where
  | gt : ValueExpr -> ValueExpr -> BoolExpr
  | ge : ValueExpr -> ValueExpr -> BoolExpr
  | eq : ValueExpr -> ValueExpr -> BoolExpr
deriving Repr, DecidableEq

inductive Stmt where
  | skip : Stmt
  | require : BoolExpr -> Stmt
  | assert : BoolExpr -> Stmt
  | assign : Slot -> ValueExpr -> Stmt
  | seq : Stmt -> Stmt -> Stmt
deriving Repr, DecidableEq

def evalValue (env : Env) (storage : Storage) : ValueExpr -> Option UInt256
  | .const value => some value
  | .slot slot => some (storage.read slot)
  | .add lhs rhs =>
      match evalValue env storage lhs, evalValue env storage rhs with
      | some lhsValue, some rhsValue => UInt256.checkedAdd lhsValue rhsValue
      | _, _ => none
  | .sub lhs rhs =>
      match evalValue env storage lhs, evalValue env storage rhs with
      | some lhsValue, some rhsValue => UInt256.checkedSub lhsValue rhsValue
      | _, _ => none

def evalBool (env : Env) (storage : Storage) : BoolExpr -> Option Bool
  | .gt lhs rhs =>
      match evalValue env storage lhs, evalValue env storage rhs with
      | some lhsValue, some rhsValue => some (UInt256.gt lhsValue rhsValue)
      | _, _ => none
  | .ge lhs rhs =>
      match evalValue env storage lhs, evalValue env storage rhs with
      | some lhsValue, some rhsValue => some (UInt256.ge lhsValue rhsValue)
      | _, _ => none
  | .eq lhs rhs =>
      match evalValue env storage lhs, evalValue env storage rhs with
      | some lhsValue, some rhsValue => some (decide (lhsValue = rhsValue))
      | _, _ => none

end SoLean
