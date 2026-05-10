import SoLean.Yul

namespace SoLean
namespace Source

/--
Tiny parameter-aware source language for compiler experiments.

This is deliberately smaller than the main SoLean DSL. It supports one function
parameter and only the expression/statement forms needed by the Counter case
study.
-/
inductive ValueExpr where
  | const : UInt256 -> ValueExpr
  | param : ValueExpr
  | slot : Slot -> ValueExpr
  | add : ValueExpr -> ValueExpr -> ValueExpr
deriving Repr, DecidableEq

inductive BoolExpr where
  | gt : ValueExpr -> ValueExpr -> BoolExpr
  | ge : ValueExpr -> ValueExpr -> BoolExpr
deriving Repr, DecidableEq

inductive Stmt where
  | require : BoolExpr -> Stmt
  | assert : BoolExpr -> Stmt
  | assign : Slot -> ValueExpr -> Stmt
  | seq : Stmt -> Stmt -> Stmt
deriving Repr, DecidableEq

structure Function where
  paramName : String
  body : Stmt
deriving Repr, DecidableEq

def instantiateValue (arg : UInt256) : ValueExpr -> SoLean.ValueExpr
  | .const value => .const value
  | .param => .const arg
  | .slot slot => .slot slot
  | .add lhs rhs => .add (instantiateValue arg lhs) (instantiateValue arg rhs)

def instantiateBool (arg : UInt256) : BoolExpr -> SoLean.BoolExpr
  | .gt lhs rhs => .gt (instantiateValue arg lhs) (instantiateValue arg rhs)
  | .ge lhs rhs => .ge (instantiateValue arg lhs) (instantiateValue arg rhs)

def instantiateStmt (arg : UInt256) : Stmt -> SoLean.Stmt
  | .require cond => .require (instantiateBool arg cond)
  | .assert cond => .assert (instantiateBool arg cond)
  | .assign slot expr => .assign slot (instantiateValue arg expr)
  | .seq first second => .seq (instantiateStmt arg first) (instantiateStmt arg second)

def instantiateFunction (function : Function) (arg : UInt256) : SoLean.Stmt :=
  instantiateStmt arg function.body

end Source

namespace Compiler

abbrev SlotAliases := Slot -> Option String

namespace SlotAliases

def empty : SlotAliases :=
  fun _ => none

def write (aliases : SlotAliases) (slot : Slot) (name : String) :
    SlotAliases :=
  fun key => if key = slot then some name else aliases key

end SlotAliases

structure CompileState where
  slotAlias : SlotAliases

namespace CompileState

def empty : CompileState :=
  { slotAlias := SlotAliases.empty }

def rememberSlot (state : CompileState) (slot : Slot) (name : String) :
    CompileState :=
  { slotAlias := SlotAliases.write state.slotAlias slot name }

end CompileState

def compileValue (paramName : String) (state : CompileState) :
    Source.ValueExpr -> Option Yul.Expr
  | .const value => some (.const value)
  | .param => some (.local paramName)
  | .slot slot =>
      match state.slotAlias slot with
      | some name => some (.local name)
      | none => some (.sload slot)
  | .add lhs rhs =>
      match compileValue paramName state lhs, compileValue paramName state rhs with
      | some lhsExpr, some rhsExpr => some (.add lhsExpr rhsExpr)
      | _, _ => none

def compileTruthCond (paramName : String) (state : CompileState) :
    Source.BoolExpr -> Option Yul.Cond
  | .gt lhs rhs =>
      match compileValue paramName state lhs, compileValue paramName state rhs with
      | some lhsExpr, some rhsExpr => some (.gt lhsExpr rhsExpr)
      | _, _ => none
  | .ge lhs rhs =>
      match compileValue paramName state lhs, compileValue paramName state rhs with
      | some lhsExpr, some rhsExpr => some (.iszero (.lt lhsExpr rhsExpr))
      | _, _ => none

def compileAssertRevertCond (paramName : String) (state : CompileState) :
    Source.BoolExpr -> Option Yul.Cond
  | .ge lhs rhs =>
      match compileValue paramName state lhs, compileValue paramName state rhs with
      | some lhsExpr, some rhsExpr => some (.lt lhsExpr rhsExpr)
      | _, _ => none
  | cond =>
      match compileTruthCond paramName state cond with
      | some truth => some (.iszero truth)
      | none => none

/--
Compile only the checked-add assignment pattern needed by Counter:

`slot := slot + rhs`

The fixed temporary names are part of the current tiny compiler contract and
match the restricted Yul Counter model.
-/
def compileCheckedAddAssign
    (paramName : String) (state : CompileState)
    (slot oldSlot : Slot) (rhs : Source.ValueExpr) :
    Option (List Yul.Stmt × CompileState) :=
  if oldSlot = slot then
    match compileValue paramName state rhs with
    | some rhsExpr =>
        let oldName := "old_x"
        let newName := "new_x"
        some
          ( [ .let_ oldName (.sload slot),
              .let_ newName (.add (.local oldName) rhsExpr),
              .ifRevert (.lt (.local newName) (.local oldName)),
              .sstore slot (.local newName)
            ],
            state.rememberSlot slot newName)
    | none => none
  else
    none

def compileStmt (paramName : String) :
    Source.Stmt -> CompileState -> Option (List Yul.Stmt × CompileState)
  | .require cond, state =>
      match compileTruthCond paramName state cond with
      | some truth => some ([.ifRevert (.iszero truth)], state)
      | none => none
  | .assert cond, state =>
      match compileAssertRevertCond paramName state cond with
      | some revertCond => some ([.ifRevert revertCond], state)
      | none => none
  | .assign slot (.add (.slot oldSlot) rhs), state =>
      compileCheckedAddAssign paramName state slot oldSlot rhs
  | .assign _ _, _ => none
  | .seq first second, state =>
      match compileStmt paramName first state with
      | some (firstCode, state') =>
          match compileStmt paramName second state' with
          | some (secondCode, state'') => some (firstCode ++ secondCode, state'')
          | none => none
      | none => none

def compileFunction (function : Source.Function) : Option Yul.Program :=
  match compileStmt function.paramName function.body CompileState.empty with
  | some (program, _) => some program
  | none => none

end Compiler
end SoLean
