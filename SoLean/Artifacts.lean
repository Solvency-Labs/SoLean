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
Lean-owned source certificate for the tiny Counter Solidity subset accepted by
the current trusted Python parser.

This is an audit artifact, not a verified Solidity parser. It states the source
shape and assumptions that Python must report before the bridge accepts the
Counter input.
-/
def counterSourceCertificate : Json :=
  .obj [
    ("assumptions", stringsJson [
      "Counter-only Solidity subset.",
      "Storage slot assignment is explicit: x maps to slot 0.",
      "The parser rejects unsupported Solidity instead of approximating it."
    ]),
    ("contract", .obj [
      ("name", .str "Counter"),
      ("pragma", .str "0.8.35")
    ]),
    ("function", .obj [
      ("bodyShape", stringsJson [
        "require(amount > 0)",
        "x += amount",
        "assert(x >= amount)"
      ]),
      ("name", .str "inc"),
      ("parameter", .obj [
        ("name", .str "amount"),
        ("type", .str "uint256")
      ]),
      ("visibility", .str "public")
    ]),
    ("kind", .str "counterSourceCertificate"),
    ("lean", .str "SoLean.Examples.CounterCompiler.counterFunction"),
    ("storageSlots", .arr [
      .obj [
        ("name", .str "x"),
        ("slot", .num Examples.Counter.xSlot),
        ("type", .str "uint256"),
        ("visibility", .str "public")
      ]
    ]),
    ("unsupported", stringsJson [
      "ABI decoding",
      "memory",
      "external calls",
      "events",
      "gas",
      "reentrancy",
      "full Solidity parsing"
    ]),
    ("version", .num 1)
  ]

def counterSourceCertificateJson : String :=
  renderJson counterSourceCertificate

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
    { rule := "cleanupUint256AsIdentity",
      leanProof := "SoLean.Bridge.TransparentHelper.cleanupUint256_refines_source" },
    { rule := "convertRationalZeroByOneToUint256AsIdentity",
      leanProof :=
        "SoLean.Bridge.TransparentHelper.convertRationalZeroByOneToUint256_refines_source" },
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

def proofForRule (rule : String) : String :=
  match counterBridgeRuleProofs.find? (fun entry => entry.rule == rule) with
  | some entry => entry.leanProof
  | none => ""

def bridgeRuleProofJson (entry : BridgeRuleProof) : Json :=
  .obj [
    ("leanProof", .str entry.leanProof),
    ("rule", .str entry.rule)
  ]

namespace TraceSkeleton

def zero : SoLean.Yul.Expr :=
  .const UInt256.zero

def amount : SoLean.Yul.Expr :=
  .local "amount"

def oldX : SoLean.Yul.Expr :=
  .local "old_x"

def newX : SoLean.Yul.Expr :=
  .local "new_x"

def requireGuard : SoLean.Yul.Stmt :=
  .ifRevert (.iszero (.gt amount zero))

def loadOldX : SoLean.Yul.Stmt :=
  .let_ "old_x" (.sload Examples.Counter.xSlot)

def checkedAddBind : SoLean.Yul.Stmt :=
  .let_ "new_x" (.add oldX amount)

def checkedAddGuard : SoLean.Yul.Stmt :=
  .ifRevert (.lt newX oldX)

def storeNewX : SoLean.Yul.Stmt :=
  .sstore Examples.Counter.xSlot newX

def assertGuard : SoLean.Yul.Stmt :=
  .ifRevert (.lt newX amount)

def entryJson (index : Nat) (rule effectKind : String)
    (emits : List SoLean.Yul.Stmt) : Json :=
  .obj [
    ("effectKind", .str effectKind),
    ("emits", .arr (emits.map Yul.stmtJson)),
    ("index", .num index),
    ("leanProof", .str (proofForRule rule)),
    ("rule", .str rule)
  ]

end TraceSkeleton

/--
Lean-owned expected skeleton for the current Counter solc summary trace.

It intentionally excludes volatile solc source line numbers and source text.
Python must match the rule/effect order and emitted restricted-Yul statements
against this artifact.
-/
def counterTraceSkeleton : Json :=
  .arr [
    TraceSkeleton.entryJson 1 "hexLiteralAsNat" "hexLiteral" [],
    TraceSkeleton.entryJson 2 "cleanupUint256AsIdentity" "transparentHelper" [],
    TraceSkeleton.entryJson 3 "convertRationalZeroByOneToUint256AsIdentity"
      "transparentHelper" [],
    TraceSkeleton.entryJson 4 "requireHelperAsRevertGuard" "emitStmt"
      [TraceSkeleton.requireGuard],
    TraceSkeleton.entryJson 5 "hexLiteralAsNat" "hexLiteral" [],
    TraceSkeleton.entryJson 6 "storageReadSlot0AsSload" "emitStmt"
      [TraceSkeleton.loadOldX],
    TraceSkeleton.entryJson 7 "checkedAddUInt256AsAddWithOverflowGuard" "emitStmts"
      [TraceSkeleton.checkedAddBind, TraceSkeleton.checkedAddGuard],
    TraceSkeleton.entryJson 8 "hexLiteralAsNat" "hexLiteral" [],
    TraceSkeleton.entryJson 9 "storageUpdateSlot0AsSstore" "emitStmt"
      [TraceSkeleton.storeNewX],
    TraceSkeleton.entryJson 10 "hexLiteralAsNat" "hexLiteral" [],
    TraceSkeleton.entryJson 11 "storageReadSlot0AsSload" "readCachedSlot" [],
    TraceSkeleton.entryJson 12 "cleanupUint256AsIdentity" "transparentHelper" [],
    TraceSkeleton.entryJson 13 "assertHelperAsRevertGuard" "emitStmt"
      [TraceSkeleton.assertGuard]
  ]

def counterTraceSkeletonJson : String :=
  renderJson counterTraceSkeleton

def counterBridgeManifest : Json :=
  .obj [
    ("kind", .str "counterBridgeManifest"),
    ("version", .num 2),
    ("sourceArtifact", .obj [
      ("name", .str "SoLean.Examples.CounterCompiler.counterFunction"),
      ("export", .str "source-json")
    ]),
    ("yulArtifact", .obj [
      ("name", .str "SoLean.Examples.CounterYul.counterProgram"),
      ("export", .str "yul-json")
    ]),
    ("sourceCertificate", counterSourceCertificate),
    ("expectedTrustedRules", stringsJson counterBridgeTrustedRules),
    ("expectedTraceSkeleton", counterTraceSkeleton),
    ("bridgeRuleProofs", .arr (counterBridgeRuleProofs.map bridgeRuleProofJson)),
    ("proofReferences", stringsJson [
      "SoLean.Bridge.AssertHelper.targetForIszero_refines_source",
      "SoLean.Bridge.CheckedAdd.counterTarget_refines_source",
      "SoLean.Bridge.RequireHelper.target_refines_source",
      "SoLean.Bridge.StorageRead.target_refines_source",
      "SoLean.Bridge.StorageWrite.target_refines_source",
      "SoLean.Bridge.TransparentHelper.cleanupUint256_refines_source",
      "SoLean.Bridge.TransparentHelper.convertRationalZeroByOneToUint256_refines_source",
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
