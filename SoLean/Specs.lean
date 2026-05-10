import SoLean.Semantics

namespace SoLean

/--
`succeedsWith result post` means every successful execution result satisfies
`post`. Reverts are treated as vacuously safe for this predicate.
-/
def succeedsWith (result : ExecResult) (post : Storage -> Prop) : Prop :=
  match result with
  | .success storage => post storage
  | .revert _ => True

def ProgramEnsures (program : Stmt) (post : Storage -> Prop) : Prop :=
  forall env storage, succeedsWith (exec env program storage) post

end SoLean
