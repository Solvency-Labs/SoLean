import SoLean.Bridge
import SoLean.Examples.CounterCompiler

namespace SoLean
namespace Artifacts

/--
Small JSON renderer for checked artifacts exported from Lean.

This is intentionally tiny and dependency-free. It is only used for the current
Counter bridge audit artifacts; it is not a general JSON library.
-/
inductive Json where
  | obj : List (String × Json) -> Json
  | arr : List Json -> Json
  | str : String -> Json
  | num : Nat -> Json
deriving Inhabited

def intercalate (sep : String) : List String -> String
  | [] => ""
  | [x] => x
  | x :: xs => x ++ sep ++ intercalate sep xs

def indent (level : Nat) : String :=
  String.mk (List.replicate (2 * level) ' ')

def quote (value : String) : String :=
  "\"" ++ value ++ "\""

partial def renderJsonAux (level : Nat) : Json -> String
  | .str value => quote value
  | .num value => toString value
  | .arr values =>
      match values with
      | [] => "[]"
      | _ =>
          let rendered :=
            values.map (fun value =>
              indent (level + 1) ++ renderJsonAux (level + 1) value)
          "[\n" ++ intercalate ",\n" rendered ++ "\n" ++ indent level ++ "]"
  | .obj fields =>
      match fields with
      | [] => "{}"
      | _ =>
          let rendered :=
            fields.map (fun (key, value) =>
              indent (level + 1) ++ quote key ++ ": " ++
                renderJsonAux (level + 1) value)
          "{\n" ++ intercalate ",\n" rendered ++ "\n" ++ indent level ++ "}"

def renderJson (json : Json) : String :=
  renderJsonAux 0 json ++ "\n"

def stringsJson (values : List String) : Json :=
  .arr (values.map Json.str)

namespace Source

def valueJson (paramName : String) : SoLean.Source.ValueExpr -> Json
  | .const value => .obj [("const", .num value.toNat)]
  | .param => .obj [("param", .str paramName)]
  | .slot slot => .obj [("slot", .num slot)]
  | .add lhs rhs =>
      .obj [("add", .arr [valueJson paramName lhs, valueJson paramName rhs])]

def boolJson (paramName : String) : SoLean.Source.BoolExpr -> Json
  | .gt lhs rhs =>
      .obj [("gt", .arr [valueJson paramName lhs, valueJson paramName rhs])]
  | .ge lhs rhs =>
      .obj [("ge", .arr [valueJson paramName lhs, valueJson paramName rhs])]

def flattenSeq : SoLean.Source.Stmt -> List SoLean.Source.Stmt
  | .seq first second => flattenSeq first ++ flattenSeq second
  | stmt => [stmt]

partial def stmtJson (paramName : String) : SoLean.Source.Stmt -> Json
  | .require cond => .obj [("require", boolJson paramName cond)]
  | .assert cond => .obj [("assert", boolJson paramName cond)]
  | .assign slot expr =>
      .obj [
        ("assign", .obj [
          ("expr", valueJson paramName expr),
          ("slot", .num slot)
        ])
      ]
  | .seq first second =>
      .obj [("seq", .arr ((flattenSeq (.seq first second)).map (stmtJson paramName)))]

def functionJson (function : SoLean.Source.Function) : Json :=
  .obj [
    ("contract", .obj [
      ("name", .str "Counter"),
      ("pragma", .str "0.8.35")
    ]),
    ("function", .obj [
      ("body", .obj [
        ("seq", .arr ((flattenSeq function.body).map (stmtJson function.paramName)))
      ]),
      ("name", .str "inc"),
      ("param", .obj [
        ("name", .str function.paramName),
        ("type", .str "uint256")
      ])
    ]),
    ("kind", .str "sourceFunction"),
    ("lean", .str "SoLean.Examples.CounterCompiler.counterFunction"),
    ("storage", .obj [
      ("x", .obj [
        ("slot", .num Examples.Counter.xSlot),
        ("type", .str "uint256"),
        ("visibility", .str "public")
      ])
    ])
  ]

end Source

namespace Yul

def exprJson : SoLean.Yul.Expr -> Json
  | .const value => .obj [("const", .num value.toNat)]
  | .local name => .obj [("ident", .str name)]
  | .sload slot => .obj [("call", .str "sload"), ("args", .arr [.obj [("const", .num slot)]])]
  | .add lhs rhs => .obj [("call", .str "add"), ("args", .arr [exprJson lhs, exprJson rhs])]

def condJson : SoLean.Yul.Cond -> Json
  | .gt lhs rhs => .obj [("call", .str "gt"), ("args", .arr [exprJson lhs, exprJson rhs])]
  | .lt lhs rhs => .obj [("call", .str "lt"), ("args", .arr [exprJson lhs, exprJson rhs])]
  | .iszero cond => .obj [("call", .str "iszero"), ("args", .arr [condJson cond])]

def stmtJson : SoLean.Yul.Stmt -> Json
  | .let_ name expr => .obj [("stmt", .str "let"), ("name", .str name), ("expr", exprJson expr)]
  | .sstore slot expr =>
      .obj [
        ("stmt", .str "sstore"),
        ("slot", .obj [("const", .num slot)]),
        ("value", exprJson expr)
      ]
  | .ifRevert cond => .obj [("stmt", .str "ifRevert"), ("cond", condJson cond)]

def programJson (program : SoLean.Yul.Program) : Json :=
  .obj [
    ("object", .str "Counter"),
    ("function", .obj [
      ("name", .str "inc"),
      ("params", .arr [.str "amount"]),
      ("body", .arr (program.map stmtJson))
    ])
  ]

end Yul

def counterSourceJson : String :=
  renderJson (Source.functionJson Examples.CounterCompiler.counterFunction)

def counterYulJson : String :=
  renderJson (Yul.programJson Examples.CounterYul.counterProgram)

/--
Per-rule status entry for the Counter bridge manifest.

`leanProof` names the Lean theorem that backs this rule's semantic translation.
When `leanProof` is the empty string, the rule is still trusted Python pattern
recognition only.
-/
structure BridgeRuleProof where
  rule : String
  leanProof : String
deriving Repr

def counterBridgeRuleProofs : List BridgeRuleProof :=
  [
    { rule := "hexLiteralAsNat",                          leanProof := "" },
    { rule := "transparentValueHelper",                   leanProof := "" },
    { rule := "requireHelperAsRevertGuard",
      leanProof := "SoLean.Bridge.RequireHelper.target_refines_source" },
    { rule := "storageReadSlot0AsSload",
      leanProof := "SoLean.Bridge.StorageRead.target_refines_source" },
    { rule := "checkedAddUInt256AsAddWithOverflowGuard",
      leanProof := "SoLean.Bridge.CheckedAdd.counterTarget_refines_source" },
    { rule := "storageUpdateSlot0AsSstore",
      leanProof := "SoLean.Bridge.StorageWrite.target_refines_source" },
    { rule := "assertHelperAsRevertGuard",
      leanProof := "SoLean.Bridge.AssertHelper.targetForIszero_refines_source" }
  ]

def counterBridgeTrustedRules : List String :=
  counterBridgeRuleProofs.map BridgeRuleProof.rule

def bridgeRuleProofJson (entry : BridgeRuleProof) : Json :=
  .obj [
    ("leanProof", .str entry.leanProof),
    ("rule", .str entry.rule)
  ]

def counterBridgeManifest : Json :=
  .obj [
    ("kind", .str "counterBridgeManifest"),
    ("version", .num 1),
    ("sourceArtifact", .obj [
      ("name", .str "SoLean.Examples.CounterCompiler.counterFunction"),
      ("export", .str "source-json")
    ]),
    ("yulArtifact", .obj [
      ("name", .str "SoLean.Examples.CounterYul.counterProgram"),
      ("export", .str "yul-json")
    ]),
    ("expectedTrustedRules", stringsJson counterBridgeTrustedRules),
    ("bridgeRuleProofs", .arr (counterBridgeRuleProofs.map bridgeRuleProofJson)),
    ("proofReferences", stringsJson [
      "SoLean.Bridge.AssertHelper.targetForIszero_refines_source",
      "SoLean.Bridge.CheckedAdd.counterTarget_refines_source",
      "SoLean.Bridge.RequireHelper.target_refines_source",
      "SoLean.Bridge.StorageRead.target_refines_source",
      "SoLean.Bridge.StorageWrite.target_refines_source",
      "SoLean.Examples.Counter.inc_assertion_safe",
      "SoLean.Examples.CounterCompiler.compile_counter_eq_counter_yul",
      "SoLean.Examples.CounterCompiler.compiled_counter_refines_solean_success",
      "SoLean.Examples.CounterCompiler.compiled_counter_success_assertion"
    ]),
    ("limitations", stringsJson [
      "Counter-only bridge audit.",
      "Solidity parsing is trusted deterministic Python parsing for one tiny subset.",
      "Python Yul rendering is tested against Lean-owned artifacts, not verified.",
      "solc IR summarization is trusted Counter-specific pattern recognition.",
      "This report is not semantic equivalence against real solc Yul."
    ])
  ]

def counterBridgeManifestJson : String :=
  renderJson counterBridgeManifest

end Artifacts
end SoLean
