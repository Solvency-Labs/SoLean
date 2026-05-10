import SoLean.DSL

namespace SoLean

inductive Failure where
  | requireFailed : Failure
  | assertFailed : Failure
  | arithmeticFailed : Failure
deriving Repr, DecidableEq

inductive ExecResult where
  | success : Storage -> ExecResult
  | revert : Failure -> ExecResult

def exec (env : Env) : Stmt -> Storage -> ExecResult
  | .skip, storage => .success storage
  | .require cond, storage =>
      match evalBool env storage cond with
      | some true => .success storage
      | some false => .revert .requireFailed
      | none => .revert .arithmeticFailed
  | .assert cond, storage =>
      match evalBool env storage cond with
      | some true => .success storage
      | some false => .revert .assertFailed
      | none => .revert .arithmeticFailed
  | .assign slot expr, storage =>
      match evalValue env storage expr with
      | some value => .success (Storage.write storage slot value)
      | none => .revert .arithmeticFailed
  | .seq first second, storage =>
      match exec env first storage with
      | .success storage' => exec env second storage'
      | .revert failure => .revert failure

end SoLean
