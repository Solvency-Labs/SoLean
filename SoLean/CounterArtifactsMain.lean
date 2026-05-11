import SoLean.Artifacts

def usage : String :=
  "usage: counter_artifacts <source-json|yul-json>"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-json"] =>
      IO.print SoLean.Artifacts.counterSourceJson
      pure 0
  | ["yul-json"] =>
      IO.print SoLean.Artifacts.counterYulJson
      pure 0
  | _ =>
      IO.eprintln usage
      pure 2
