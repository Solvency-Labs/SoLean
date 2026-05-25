import SoLean.Artifacts

def usage : String :=
  "usage: aapq_artifacts <source-json|source-certificate-json|behavior-summary-json|full-behavior-summary-json|v1-full-behavior-summary-json>"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-json"] =>
      IO.print SoLean.Artifacts.aapqSourceJson
      pure 0
  | ["source-certificate-json"] =>
      IO.print SoLean.Artifacts.aapqSourceCertificateJson
      pure 0
  | ["behavior-summary-json"] =>
      IO.print SoLean.Artifacts.aapqBehaviorSummaryJson
      pure 0
  | ["full-behavior-summary-json"] =>
      IO.print SoLean.Artifacts.aapqFullBehaviorSummaryJson
      pure 0
  | ["v1-full-behavior-summary-json"] =>
      IO.print SoLean.Artifacts.aapqV1FullBehaviorSummaryJson
      pure 0
  | _ =>
      IO.eprintln usage
      pure 2
