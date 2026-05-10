import SoLean.DSL

namespace SoLean

inductive Failure where
  | requireFailed : Failure
  | assertFailed : Failure
deriving Repr, DecidableEq

inductive ExecResult where
  | success : Storage -> ExecResult
  | revert : Failure -> ExecResult

def exec (env : Env) : Stmt -> Storage -> ExecResult
  | .skip, storage => .success storage
  | .require cond, storage =>
      if evalBool env storage cond then
        .success storage
      else
        .revert .requireFailed
  | .assert cond, storage =>
      if evalBool env storage cond then
        .success storage
      else
        .revert .assertFailed
  | .assign slot expr, storage =>
      .success (Storage.write storage slot (evalValue env storage expr))
  | .seq first second, storage =>
      match exec env first storage with
      | .success storage' => exec env second storage'
      | .revert failure => .revert failure

end SoLean
