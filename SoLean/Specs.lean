import SoLean.Semantics

namespace SoLean

abbrev Pre := Env -> Storage -> Prop
abbrev Post := Env -> Storage -> Storage -> Prop
abbrev Invariant := Storage -> Prop

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

def FunctionEnsures (program : Stmt) (pre : Pre) (post : Post) : Prop :=
  forall env storage,
    pre env storage ->
      match exec env program storage with
      | .success finalStorage => post env storage finalStorage
      | .revert _ => True

def PreservesInvariant (program : Stmt) (invariant : Invariant) : Prop :=
  FunctionEnsures program
    (fun _ storage => invariant storage)
    (fun _ _ finalStorage => invariant finalStorage)

end SoLean
