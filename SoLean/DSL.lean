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

def evalValue (env : Env) (storage : Storage) : ValueExpr -> UInt256
  | .const value => value
  | .slot slot => storage.read slot
  | .add lhs rhs =>
      UInt256.add (evalValue env storage lhs) (evalValue env storage rhs)
  | .sub lhs rhs =>
      UInt256.sub (evalValue env storage lhs) (evalValue env storage rhs)

def evalBool (env : Env) (storage : Storage) : BoolExpr -> Bool
  | .gt lhs rhs =>
      UInt256.gt (evalValue env storage lhs) (evalValue env storage rhs)
  | .ge lhs rhs =>
      UInt256.ge (evalValue env storage lhs) (evalValue env storage rhs)
  | .eq lhs rhs =>
      decide (evalValue env storage lhs = evalValue env storage rhs)

end SoLean
