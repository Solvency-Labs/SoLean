import SoLean.Artifacts

def usage : String :=
  "usage: counter_artifacts <source-json|source-certificate-json|yul-json|trace-skeleton-json|bridge-json>"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-json"] =>
      IO.print SoLean.Artifacts.counterSourceJson
      pure 0
  | ["source-certificate-json"] =>
      IO.print SoLean.Artifacts.counterSourceCertificateJson
      pure 0
  | ["yul-json"] =>
      IO.print SoLean.Artifacts.counterYulJson
      pure 0
  | ["trace-skeleton-json"] =>
      IO.print SoLean.Artifacts.counterTraceSkeletonJson
      pure 0
  | ["bridge-json"] =>
      IO.print SoLean.Artifacts.counterBridgeManifestJson
      pure 0
  | _ =>
      IO.eprintln usage
      pure 2
