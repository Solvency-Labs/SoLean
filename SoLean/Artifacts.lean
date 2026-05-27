import SoLean.Bridge
import SoLean.Examples.AAPQSource
import SoLean.Examples.CounterCompiler
import SoLean.Examples.FalconSimpleWallet
import SoLean.Examples.ProtocolBoundaries
import SoLean.Examples.SchemeParameters
import SoLean.Examples.StructuredVerifier
import SoLean.Examples.ToyVerifier
import SoLean.Source.Shape

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

def counterParam : SoLean.Source.Shape.Param :=
  { name := "amount", typeName := "uint256" }

def counterStorageSlot : SoLean.Source.Shape.StorageSlot :=
  { name := "x", slot := Examples.Counter.xSlot, typeName := "uint256" }

def counterContract : SoLean.Source.Shape.Contract :=
  { name := "Counter",
    pragma := "0.8.35",
    storage := [counterStorageSlot],
    functionName := "inc",
    params := [counterParam] }

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
      ("name", .str counterContract.name),
      ("pragma", .str counterContract.pragma)
    ]),
    ("function", .obj [
      ("body", .obj [
        ("seq", .arr ((flattenSeq function.body).map (stmtJson function.paramName)))
      ]),
      ("name", .str counterContract.functionName),
      ("param", .obj [
        ("name", .str counterParam.name),
        ("type", .str counterParam.typeName)
      ])
    ]),
    ("kind", .str "sourceFunction"),
    ("lean", .str "SoLean.Examples.CounterCompiler.counterFunction"),
    ("storage", .obj [
      ("x", .obj [
        ("slot", .num counterStorageSlot.slot),
        ("type", .str counterStorageSlot.typeName),
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

namespace Behavior

def constJson (n : Nat) : Json :=
  .obj [("const", .num n)]

def paramJson (name : String) : Json :=
  .obj [("param", .str name)]

def slotJson (n : Nat) : Json :=
  .obj [("slot", .num n)]

def callJson (name : String) (args : List Json) : Json :=
  .obj [("args", .arr args), ("call", .str name)]

def amount : Json := paramJson "amount"

def slot0Init : Json := slotJson Examples.Counter.xSlot

def zero : Json := constJson 0

def amountGtZero : Json := callJson "gt" [amount, zero]

def revertRequire : Json := callJson "iszero" [amountGtZero]

def newX : Json := callJson "add" [slot0Init, amount]

def revertOverflow : Json := callJson "lt" [newX, slot0Init]

def revertAssert : Json := callJson "lt" [newX, amount]

end Behavior

/--
Lean-owned restricted behavior summary for the Counter Yul artifact.

This is a symbolic state-transform shape: function parameter, ordered revert
guard conditions in source order, and final storage writes by slot. It is the
Lean-owned counterpart to Python's `summarize_symbolic` output for the
restricted Counter Yul subset.

This is not a verified semantics for real solc Yul. It pins the expected
Counter behavior shape so the bridge report can fail if Python's symbolic
summary drifts away from Lean.
-/
def counterBehaviorSummary : Json :=
  .obj [
    ("finalWrites", .arr [
      .obj [
        ("slot", .num Examples.Counter.xSlot),
        ("value", Behavior.newX)
      ]
    ]),
    ("function", .str "inc"),
    ("kind", .str "counterBehaviorSummary"),
    ("lean", .str "SoLean.Examples.CounterYul.counterProgram"),
    ("object", .str "Counter"),
    ("params", .arr [.str "amount"]),
    ("revertConditions", .arr [
      Behavior.revertRequire,
      Behavior.revertOverflow,
      Behavior.revertAssert
    ]),
    ("version", .num 1)
  ]

def counterBehaviorSummaryJson : String :=
  renderJson counterBehaviorSummary

def counterBridgeManifest : Json :=
  .obj [
    ("kind", .str "counterBridgeManifest"),
    ("version", .num 3),
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
    ("expectedBehaviorSummary", counterBehaviorSummary),
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

namespace AAPQ

def paramJson (param : SoLean.Source.Shape.Param) : Json :=
  .obj [
    ("name", .str param.name),
    ("type", .str param.typeName)
  ]

def storageSlotJson (entry : SoLean.Source.Shape.StorageSlot) : Json :=
  .obj [
    ("name", .str entry.name),
    ("slot", .num entry.slot),
    ("type", .str entry.typeName)
  ]

def contractJson (contract : SoLean.Source.Shape.Contract) : Json :=
  .obj [
    ("function", .obj [
      ("name", .str contract.functionName),
      ("params", .arr (contract.params.map paramJson))
    ]),
    ("name", .str contract.name),
    ("pragma", .str contract.pragma),
    ("storage", .arr (contract.storage.map storageSlotJson))
  ]

def integratedFlow : Json :=
  stringsJson [
    "verify(publicKey, publicKeyLength, opHash, domain, signature, signatureLength)",
    "require(wallet.keyCommitment == publicKey)",
    "validateUserOp(opHash, nonce, domain, signature)"
  ]

def integratedV1Flow : Json :=
  stringsJson [
    "verify(publicKey, publicKeyLength, opHash, domain, signature, signatureLength)",
    "require(wallet.keyCommitment == publicKey)",
    "validateUserOp(opHash, nonce, domain, signature, expectedWrapperAddress)",
    "executeUserOp(opHash)"
  ]

def integratedContractJsonWithLean
    (leanName : String)
    (contract : SoLean.Source.Shape.IntegratedContract)
    (flow : Json := integratedFlow) : Json :=
  .obj [
    ("integration", .obj [
      ("flow", flow),
      ("name", .str contract.integrationName),
      ("params", .arr (contract.params.map paramJson))
    ]),
    ("kind", .str "aapqIntegratedSource"),
    ("lean", .str leanName),
    ("name", .str contract.name),
    ("pragma", .str contract.pragma),
    ("wallet", contractJson contract.wallet),
    ("wrapper", contractJson contract.wrapper)
  ]

def integratedContractJson
    (contract : SoLean.Source.Shape.IntegratedContract) : Json :=
  integratedContractJsonWithLean
    "SoLean.Examples.AAPQSource.integratedContract"
    contract

end AAPQ

namespace AAPQBehavior

def operandJson : SoLean.Examples.AAPQSource.Operand -> Json
  | .param name =>
      .obj [("kind", .str "param"), ("name", .str name)]
  | .slot contract slotName =>
      .obj [
        ("contract", .str contract),
        ("kind", .str "slot"),
        ("name", .str slotName)
      ]
  | .msgSender =>
      .obj [("kind", .str "msgSender")]
  | .const value =>
      .obj [("kind", .str "const"), ("value", .num value)]

def conditionJson : SoLean.Examples.AAPQSource.Condition -> Json
  | .eq lhs rhs =>
      .obj [
        ("args", .arr [operandJson lhs, operandJson rhs]),
        ("kind", .str "eq")
      ]
  | .verifier key message domain signature =>
      .obj [
        ("args", .arr [
          operandJson key, operandJson message, operandJson domain,
          operandJson signature
        ]),
        ("kind", .str "verifier")
      ]

partial def valueJson : SoLean.Examples.AAPQSource.ValueExpression -> Json
  | .operand op => operandJson op
  | .checkedAdd lhs rhs =>
      .obj [
        ("args", .arr [valueJson lhs, valueJson rhs]),
        ("kind", .str "checkedAdd")
      ]

def guardJson (guard : SoLean.Examples.AAPQSource.Guard) : Json :=
  .obj [
    ("condition", conditionJson guard.condition),
    ("kind", .str (SoLean.Examples.AAPQSource.GuardKind.toString guard.kind))
  ]

def finalWriteJson (write : SoLean.Examples.AAPQSource.FinalWrite) : Json :=
  .obj [
    ("contract", .str write.contract),
    ("name", .str write.slotName),
    ("slot", .num write.slot),
    ("value", valueJson write.value)
  ]

def phaseJson (phase : SoLean.Examples.AAPQSource.Phase) : Json :=
  .obj [
    ("contract", .str phase.contract),
    ("finalWrites", .arr (phase.finalWrites.map finalWriteJson)),
    ("guards", .arr (phase.guards.map guardJson)),
    ("name", .str phase.name),
    ("proofReference", .str phase.proofReference)
  ]

def summaryJsonWithLean
    (leanName : String)
    (summary : SoLean.Examples.AAPQSource.BehaviorSummary) : Json :=
  .obj [
    ("function", .str summary.function),
    ("kind", .str "aapqBehaviorSummary"),
    ("lean", .str leanName),
    ("object", .str summary.object),
    ("params", stringsJson summary.params),
    ("phases", .arr (summary.phases.map phaseJson)),
    ("version", .num 2)
  ]

def summaryJson (summary : SoLean.Examples.AAPQSource.BehaviorSummary) : Json :=
  summaryJsonWithLean "SoLean.Examples.AAPQSource.integratedBehaviorSummary"
    summary

def cryptoAssumptionJson
    (entry : SoLean.Examples.AAPQSource.CryptoAssumption) : Json :=
  .obj [
    ("leanReference", .str entry.leanReference),
    ("name", .str entry.name),
    ("statement", .str entry.statement),
    ("theoremReferences", stringsJson entry.theoremReferences)
  ]

def cryptoAssumptionSupportEdgeJson
    (entry : SoLean.Examples.AAPQSource.CryptoAssumptionSupportEdge) : Json :=
  .obj [
    ("assumption", .str entry.assumptionName),
    ("edge", .str "assumptionSupportsTheorem"),
    ("flow", .str entry.flow),
    ("layer", .str entry.layer),
    ("theoremReference", .str entry.theoremReference)
  ]

def toyVerifierCalibrationJson : Json :=
  .obj [
    ("dischargedAssumptions", stringsJson [
      "VerifierDomainSeparation",
      "VerifierSignatureBinding",
      "VerifierKeySeparation"
    ]),
    ("kind", .str "toyVerifierCalibration"),
    ("lean", .str "SoLean.Examples.ToyVerifier.allFieldsEqualVerifier"),
    ("name", .str "AllFieldsEqualToyVerifier"),
    ("nonClaim", .str
      "Deliberately non-cryptographic verifier model for assumption-discharge calibration only."),
    ("proofReferences", stringsJson [
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_key_separation",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_satisfies_oracle_assumptions"
    ])
  ]

def schemeParametersToJson (sp : SoLean.Examples.SchemeParameters.SchemeParameters) : Json :=
  .obj [
    ("name", .str sp.name),
    ("publicKeyByteLength", .num sp.publicKeyByteLength),
    ("signatureByteLength", .num sp.signatureByteLength),
    ("securityCategory", .num sp.securityCategory),
    ("publicKeyShape", .obj [
      ("expectedDegree", .num sp.publicKeyShape.expectedDegree),
      ("expectedCoefficientCount",
        .num sp.publicKeyShape.expectedCoefficientCount)
    ])
  ]

def schemeParameterCalibrationJson : Json :=
  .obj [
    ("dischargedAssumptions", stringsJson [
      "LatticeShapeBound"
    ]),
    ("kind", .str "schemeParameterCalibration"),
    ("lean", .str "SoLean.Examples.SchemeParameters"),
    ("name", .str "PQSchemeParameters"),
    ("nonClaim", .str
      "Parameter records for NIST-standardized PQ schemes (Falcon-512, ML-DSA-44). Carries documented constants (key/signature byte lengths, security category, polynomial degree) sourced from the standards docs. No cryptographic claim attached; these are calibration data for the LatticeShapeBound verifier-shape assumption."),
    ("schemes", .arr [
      schemeParametersToJson SoLean.Examples.SchemeParameters.falcon512,
      schemeParametersToJson SoLean.Examples.SchemeParameters.mlDsa44
    ]),
    ("wrapperGuardTheorems", stringsJson [
      "SoLean.Examples.SchemeParameters.wrapper_calibrated_for_one_scheme_rejects_other_signature_length",
      "SoLean.Examples.SchemeParameters.falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length",
      "SoLean.Examples.SchemeParameters.validateAndExecute_falcon512_calibrated_rejects_mlDsa44_signature_length"
    ]),
    ("proofReferences", stringsJson [
      "SoLean.Examples.SchemeParameters.falcon512_ne_mlDsa44",
      "SoLean.Examples.SchemeParameters.falcon512_publicKey_size_ne_mlDsa44_publicKey_size",
      "SoLean.Examples.SchemeParameters.falcon512_sigUInt256_ne_mlDsa44_sigUInt256",
      "SoLean.Examples.SchemeParameters.falcon512_pkUInt256_ne_mlDsa44_pkUInt256",
      "SoLean.Examples.SchemeParameters.wrapper_calibrated_for_one_scheme_rejects_other_signature_length",
      "SoLean.Examples.SchemeParameters.falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length"
    ])
  ]

def derivedSignatureCalibrationJson : Json :=
  .obj [
    ("dischargedAssumptions", stringsJson [
      "VerifierDomainSeparation",
      "VerifierSignatureBinding",
      "VerifierKeySeparation"
    ]),
    ("kind", .str "parametricVerifierCalibration"),
    ("lean", .str "SoLean.Examples.ToyVerifier.DerivedSignatureModel"),
    ("name", .str "DerivedSignatureModel"),
    ("nonClaim", .str
      "Parametric model: signature = derive(key, message, domain) for any derive function with explicit injectivity-in-key and injectivity-in-domain hypotheses. No concrete derive instance is committed; this is a shape, not a scheme."),
    ("parameters", stringsJson [
      "derive : UInt256 -> UInt256 -> UInt256 -> UInt256",
      "injectiveKey : forall key1 key2 message domain, derive key1 message domain = derive key2 message domain -> key1 = key2",
      "injectiveDomain : forall key message domain1 domain2, derive key message domain1 = derive key message domain2 -> domain1 = domain2"
    ]),
    ("proofReferences", stringsJson [
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_key_separation",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_satisfies_oracle_assumptions"
    ])
  ]

def keyDomainBindingCalibrationJson : Json :=
  .obj [
    ("dischargedAssumptions", stringsJson [
      "VerifierDomainSeparation",
      "VerifierSignatureBinding",
      "VerifierKeySeparation"
    ]),
    ("kind", .str "toyVerifierCalibration"),
    ("lean", .str "SoLean.Examples.ToyVerifier.keyDomainBindingVerifier"),
    ("name", .str "KeyDomainBindingToyVerifier"),
    ("nonClaim", .str
      "Deliberately non-cryptographic two-pair binding model (signature ↔ key, message ↔ domain) for assumption-discharge calibration only."),
    ("proofReferences", stringsJson [
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_key_separation",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_satisfies_oracle_assumptions"
    ])
  ]

end AAPQBehavior

def aapqSourceJson : String :=
  renderJson (AAPQ.integratedContractJson Examples.AAPQSource.integratedContract)

def aapqV1Source : Json :=
  AAPQ.integratedContractJsonWithLean
    "SoLean.Examples.AAPQSource.integratedV1Contract"
    Examples.AAPQSource.integratedV1Contract
    AAPQ.integratedV1Flow

def aapqV1SourceJson : String :=
  renderJson aapqV1Source

/--
Lean-owned source certificate for the integrated AA/PQ validation flow.

This is an audit artifact, not a verified Solidity parser. It states the
two-contract source shape, theorem references that back the integrated proof,
and the explicit out-of-scope items for this first source boundary.
-/
def aapqSourceCertificate : Json :=
  .obj [
    ("assumptions", stringsJson [
      "Two-contract boundary: AAWallet and PQVerifierWrapper have separate storage.",
      "Verifier is an abstract oracle in Env; no PQ cryptographic semantics modeled.",
      "Wallet-wrapper integration includes a focused external-call shim, a calldata/returndata EVM-call boundary parameterized by an EvmEnv oracle, and a gas-aware variant over EvmGasEnv. None of these are real EVM CALL/STATICCALL with full gas accounting, reentrancy, or code resolution. The gas model is a single per-call cost vs. budget check; real EVM has per-opcode costs, calldata word/byte costs, refunds, and the EIP-150 63/64 forwarding rule.",
      "Wallet key commitment must equal the wrapper public key for the integrated path to be authorized.",
      "ABI decoding, calldata, memory, gas, events, and reentrancy are not modeled.",
      "Named, non-cryptographic crypto assumptions on Env.verifier are listed under cryptoAssumptions.",
      "Listed verifierModelCalibrations entries are deliberately non-cryptographic verifier models used only to calibrate assumption discharge."
    ]),
    ("contracts", .arr [
      AAPQ.contractJson Examples.AAPQSource.walletContract,
      AAPQ.contractJson Examples.AAPQSource.wrapperContract
    ]),
    ("cryptoAssumptions", .arr
      (Examples.AAPQSource.integratedCryptoAssumptions.map
        AAPQBehavior.cryptoAssumptionJson)),
    ("cryptoAssumptionGraph", .arr
      (Examples.AAPQSource.integratedCryptoAssumptionSupportGraph.map
        AAPQBehavior.cryptoAssumptionSupportEdgeJson)),
    ("verifierShapeAssumptions", .arr [
      .obj [
        ("leanReference", .str
          "SoLean.Examples.StructuredVerifier.StructureRespectsBool"),
        ("name", .str "StructureRespectsBool"),
        ("statement", .str
          "A StructuredVerifier sv and a Bool-valued Env.verifier bv agree on every input: sv.decide.isSome equals bv. Under this correspondence, oracle-level assumptions on bv (DomainSeparation, SignatureBinding, KeySeparation) lift to sv.toBool without re-proof. First step toward letting downstream proofs reference scheme-specific signature/key shape."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.StructuredVerifier.toBool_eq_under_respectsBool",
          "SoLean.Examples.StructuredVerifier.allFieldsEqualStructuredVerifier_respects_bool",
          "SoLean.Examples.StructuredVerifier.decide_isSome_of_toBool",
          "SoLean.Examples.StructuredVerifier.witness_extractable_under_respectsBool",
          "SoLean.Examples.StructuredVerifier.validateIntegrated_success_extracts_witness",
          "SoLean.Examples.StructuredVerifier.validateAndExecute_success_extracts_witness",
          "SoLean.Examples.StructuredVerifier.validateAndExecute_success_extracts_witness_with_authorized_opHash"
        ])
      ],
      .obj [
        ("leanReference", .str
          "SoLean.Examples.LatticePublicKey.LatticePublicKey.satisfiesShape"),
        ("name", .str "LatticeShapeBound"),
        ("statement", .str
          "A lattice-style public key (polynomial coefficient list + declared degree) satisfies a scheme-specific LatticeShapeBound when its degree and coefficient-count match the bound. Lifts the verifier's publicKey input from an opaque UInt256 to a structured polynomial without ring arithmetic. Concrete schemes (Falcon-512, ML-DSA-44) refine the bound."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.LatticePublicKey.compress_cons",
          "SoLean.Examples.LatticePublicKey.compress_degree_independent",
          "SoLean.Examples.LatticePublicKey.compress_injectiveOnHead",
          "SoLean.Examples.LatticePublicKey.coordinate_uniqueness_under_compressionInjective"
        ])
      ]
    ]),
    ("verifierModelCalibrations", .arr [
      AAPQBehavior.toyVerifierCalibrationJson,
      AAPQBehavior.keyDomainBindingCalibrationJson,
      AAPQBehavior.derivedSignatureCalibrationJson,
      AAPQBehavior.schemeParameterCalibrationJson
    ]),
    ("expectedBehaviorSummary",
      AAPQBehavior.summaryJson Examples.AAPQSource.integratedBehaviorSummary),
    ("expectedV1Source", aapqV1Source),
    ("expectedV1FullBehaviorSummary",
      AAPQBehavior.summaryJsonWithLean
        "SoLean.Examples.AAPQSource.integratedV1FullBehaviorSummary"
        Examples.AAPQSource.integratedV1FullBehaviorSummary),
    ("integration", .obj [
      ("flow", AAPQ.integratedFlow),
      ("lean", .str "SoLean.Examples.AAPQIntegration.validateIntegrated"),
      ("name", .str "validateIntegrated"),
      ("params", .arr (Examples.AAPQSource.integratedContract.params.map AAPQ.paramJson))
    ]),
    ("integrationVariants", .arr [
      .obj [
        ("canonical", .num 1),
        ("equivalenceProof", .str ""),
        ("flow", .str "validateIntegrated"),
        ("lean", .str "SoLean.Examples.AAPQIntegration.validateIntegrated"),
        ("name", .str "validateIntegrated")
      ],
      .obj [
        ("canonical", .num 0),
        ("equivalenceProof", .str
          "SoLean.Examples.AAPQIntegration.validateIntegratedViaCall_eq_validateIntegrated"),
        ("flow", .str "validateIntegrated"),
        ("lean", .str "SoLean.Examples.AAPQIntegration.validateIntegratedViaCall"),
        ("name", .str "validateIntegratedViaCall")
      ],
      .obj [
        ("canonical", .num 1),
        ("equivalenceProof", .str ""),
        ("flow", .str "validateAndExecute"),
        ("lean", .str "SoLean.Examples.AAPQIntegration.validateAndExecute"),
        ("name", .str "validateAndExecute")
      ],
      .obj [
        ("canonical", .num 0),
        ("equivalenceProof", .str
          "SoLean.Examples.AAPQIntegration.validateAndExecuteViaCall_eq_validateAndExecute"),
        ("flow", .str "validateAndExecute"),
        ("lean", .str "SoLean.Examples.AAPQIntegration.validateAndExecuteViaCall"),
        ("name", .str "validateAndExecuteViaCall")
      ],
      .obj [
        ("canonical", .num 0),
        ("equivalenceProof", .str
          "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_success_matches_validateIntegrated"),
        ("flow", .str "validateIntegrated"),
        ("lean", .str "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall"),
        ("name", .str "validateIntegratedViaEvmCall")
      ]
    ]),
    ("evmCallAssumptions", .arr [
      .obj [
        ("leanReference", .str
          "SoLean.Examples.AAPQEvmCall.WrapperOracleConsistent"),
        ("name", .str "WrapperOracleConsistent"),
        ("statement", .str
          "When the wallet calls the wrapper address with the well-formed verifier calldata layout, the modeled EvmEnv.evmCall oracle returns the same CallResult as directly executing PQVerifierWrapper.verifyProgram on wrapper storage."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.AAPQEvmCall.parse_build_verifier_calldata",
          "SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_wrong_selector",
          "SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_short_calldata",
          "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_success_matches_validateIntegrated",
          "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success"
        ])
      ],
      .obj [
        ("leanReference", .str
          "SoLean.Examples.AAPQEvmCall.WrapperCodeBound"),
        ("name", .str "WrapperCodeBound"),
        ("statement", .str
          "The modeled code deployed at wrapperAddress matches canonicalWrapperCodeHash. Real EVM uses EXTCODEHASH/keccak256; here the hash is a placeholder identifier. Pairs with WrapperOracleConsistent: code identity at the address + oracle behavior consistent with the wrapper semantics."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.AAPQEvmCall.WrapperCodeBound_eq_canonical",
          "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_depends_only_on_wrapper_oracle"
        ])
      ],
      .obj [
        ("leanReference", .str
          "SoLean.Examples.AAPQEvmCall.NoCallback"),
        ("name", .str "NoCallback"),
        ("statement", .str
          "The reentrant oracle does not call back into the wallet: callerStorageAfter equals the input wallet storage and result agrees with the non-reentrant evmCall. Lifts the structural no-reentrancy of EvmEnv.evmCall to an explicit named assumption over the richer ReentrantEvmEnv interface."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.AAPQEvmCall.validateIntegratedViaReentrantEvmCall_eq_nonReentrant_under_noCallback"
        ])
      ],
      .obj [
        ("leanReference", .str
          "SoLean.Examples.AAPQEvmCallGas.EnoughGas"),
        ("name", .str "EnoughGas"),
        ("statement", .str
          "The caller's gasBudget is at least the modeled gasCost of the wrapper call. Below this budget the gas-aware flow returns OutOfGas; above it, the gas-aware flow agrees with the gas-free call-shaped flow."),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_eq_under_enough_gas",
          "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_outOfGas_when_insufficient",
          "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_is_success_iff_validateIntegrated_is_success",
          "SoLean.Examples.AAPQEvmCallGas.enoughGasAfter6364Forwarding_implies_enoughGas",
          "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWith6364Gas_eq_under_enoughGas",
          "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWith6364Gas_eq_unrestricted_under_enoughGas"
        ])
      ]
    ]),
    ("falconSimpleWalletShape", .obj [
      ("deploymentRecord", .str
        "SoLean.Examples.FalconSimpleWallet.falconSimpleWalletDeployment"),
      ("kind", .str "falconSimpleWalletShape"),
      ("walletName", .str
        Examples.FalconSimpleWallet.falconSimpleWalletDeployment.wallet.name),
      ("walletFunction", .str
        Examples.FalconSimpleWallet.falconSimpleWalletDeployment.wallet.functionName),
      ("scheme", .str
        Examples.FalconSimpleWallet.falconSimpleWalletDeployment.scheme.name),
      ("storedSlots", .arr
        (Examples.FalconSimpleWallet.falconSimpleWalletDeployment.wallet.storage.map
          AAPQ.storageSlotJson)),
      ("crossStorageAssumption", .obj [
        ("leanReference", .str
          "SoLean.Examples.FalconSimpleWallet.WalletStoresWrapperAddress"),
        ("name", .str "WalletStoresWrapperAddress"),
        ("statement", .str
          "The wallet's wrapperAddressSlot stores the same EVM address the integration's EvmEnv configures as wrapperAddress. Bridges the modeled wallet-storage view to the runtime EVM call boundary.")
      ]),
      ("wrapperCalibrationAssumption", .obj [
        ("leanReference", .str
          "SoLean.Examples.FalconSimpleWallet.WrapperCalibratedForScheme"),
        ("name", .str "WrapperCalibratedForScheme"),
        ("statement", .str
          "The wrapper's expectedPublicKeyLengthSlot and expectedSignatureLengthSlot store the modeled byte-length UInt256s for the deployment's SchemeParameters (publicKeyByteLengthUInt256 / signatureByteLengthUInt256). Ties the wrapper storage to the named scheme parameters.")
      ]),
      ("compositeSafetyTheorem", .str
        "SoLean.Examples.FalconSimpleWallet.falconSimpleWallet_composite_safety"),
      ("schemeDiscriminationTheorem", .str
        "SoLean.Examples.FalconSimpleWallet.falconSimpleWalletDeployment_rejects_mlDsa44_signature_length"),
      ("walletV1", .obj [
        ("program", .str "SoLean.Examples.AAWallet.validateProgramV1"),
        ("userOpType", .str "SoLean.Examples.AAWallet.UserOpV1"),
        ("addressCheckTheorem", .str
          "SoLean.Examples.AAWallet.validateV1_success_properties"),
        ("rationale", .str
          "v1 wallet validation asserts the wallet's stored wrapperAddress matches the user op's declared expectedWrapperAddress before running the v0 ValidationPost checks. Strictly stronger than validateProgram; success implies both the v0 post and op.expectedWrapperAddress = wallet.wrapperAddress.")
      ]),
      ("integratedV1", .obj [
        ("program", .str
          "SoLean.Examples.AAPQIntegration.validateAndExecuteV1"),
        ("inputType", .str
          "SoLean.Examples.AAPQIntegration.IntegratedInputV1"),
        ("refinementTheorem", .str
          "SoLean.Examples.AAPQIntegration.validateAndExecuteV1_success_implies_validateAndExecute_success"),
        ("rationale", .str
          "Integrated v1 carries expectedWrapperAddress through the AA/PQ input and runs validateProgramV1 in the wallet phase. Successful v1 execution refines the existing validateAndExecute result.")
      ]),
      ("v1CompositeSafety", .obj [
        ("record", .str
          "SoLean.Examples.FalconSimpleWallet.FalconSimpleWalletV1Safety"),
        ("theorem", .str
          "SoLean.Examples.FalconSimpleWallet.falconSimpleWallet_v1_composite_safety"),
        ("extends", .str
          "SoLean.Examples.FalconSimpleWallet.FalconSimpleWalletSafety"),
        ("extraClaim", .str
          "input.expectedWrapperAddress = walletStorage.read AAWallet.wrapperAddressSlot"),
        ("rationale", .str
          "Successful validateAndExecuteV1 now gives the existing composite FalconSimpleWallet safety bundle and the v1-specific stored-wrapper-address agreement.")
      ]),
      ("wrapperAddressPreservation", .obj [
        ("walletProgramTheorem", .str
          "SoLean.Examples.AAWallet.validateProgram_preserves_wrapperAddressSlot"),
        ("integratedTheorem", .str
          "SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wallet_wrapperAddress"),
        ("deploymentAssumptionTheorem", .str
          "SoLean.Examples.FalconSimpleWallet.validateAndExecute_preserves_walletStoresWrapperAddress"),
        ("rationale", .str
          "validateProgram only writes to nonceSlot and the execute step only writes to lastOpHashSlot; the new FalconSimpleWallet wrapperAddressSlot is preserved end-to-end. Auditors can rely on the wallet's stored wrapper address surviving every successful validateAndExecute, and on WalletStoresWrapperAddress remaining true for the deployment.")
      ]),
      ("deploymentInvariant", .obj [
        ("record", .str
          "SoLean.Examples.FalconSimpleWallet.FalconSimpleWalletDeploymentInvariant"),
        ("preservationTheorem", .str
          "SoLean.Examples.FalconSimpleWallet.validateAndExecute_preserves_deploymentInvariant"),
        ("fields", stringsJson [
          "WalletStoresWrapperAddress",
          "WrapperCalibratedForScheme"
        ]),
        ("rationale", .str
          "Bundles the current deployment-facing facts that should survive successful validateAndExecute: the wallet keeps pointing at the deployment wrapper address, and the wrapper remains calibrated to the deployment scheme.")
      ])
    ]),
    ("protocolBoundaryAssumptions", .arr [
      .obj [
        ("leanReference", .str
          "SoLean.Examples.ProtocolBoundaries.BundlerEcdsaDependence"),
        ("name", .str "BundlerEcdsaDependence"),
        ("statement", .str
          "ERC-4337 today relies on ECDSA for the outer bundler transaction that lands a UserOp bundle on chain, even when individual UserOps are PQ-authenticated via the wallet's verifier wrapper. SoLean does not prove any property of this boundary. A future protocol-level / native-AA milestone (RIP-7560 / EIP-7701-like direction) would let SoLean model the bundler interface and discharge the dependence; until then it remains an explicit non-claim."),
        ("status", .str "non-claim"),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.ProtocolBoundaries.bundlerEcdsaDependence_trivial"
        ])
      ],
      .obj [
        ("leanReference", .str
          "SoLean.Examples.ProtocolBoundaries.Eip7702EcdsaKeyValidity"),
        ("name", .str "Eip7702EcdsaKeyValidity"),
        ("statement", .str
          "Under EIP-7702, an EOA can delegate to a smart-wallet implementation that adds PQ-AA behavior, but the original ECDSA key remains valid for signing — a PQ-resilience risk SoLean does not resolve. A PQ-resilient EIP-7702 deployment would require additional protocol-level guarantees (key disabling, key rotation, on-delegation revocation, etc.) that are out of scope for SoLean's current proofs."),
        ("status", .str "non-claim"),
        ("theoremReferences", stringsJson [
          "SoLean.Examples.ProtocolBoundaries.eip7702EcdsaKeyValidity_trivial"
        ])
      ]
    ]),
    ("falconSimpleWalletNonClaims", stringsJson [
      "Real Falcon (or any PQ scheme) cryptographic security — the verifier stays an oracle / structured-verifier model.",
      "EVM-friendly hashing choices (Keccak-256 vs SHAKE-256) for opHash and EIP-712-style domain binding are not modeled at the byte level; opHash is a UInt256 placeholder.",
      "Byte-level ABI parsing of calldata: the modeled calldata layout is one word per argument + a selector word, not real ABI bytes/padding.",
      "Full ERC-4337 EntryPoint / paymaster / aggregator / bundler machinery: the integration covers the wallet ↔ wrapper boundary only.",
      "Bundler ECDSA dependence: the outer bundler transaction in ERC-4337 today still relies on ECDSA. Protocol-level / native-AA work (RIP-7560, EIP-7701-like) would close this; SoLean leaves it as an explicit non-claim.",
      "EIP-7702 caveat: delegating an EOA to a smart-wallet implementation can add PQ-AA behavior, but the original ECDSA key remains valid for signing — a PQ-resilience risk SoLean does not resolve.",
      "Signature aggregation (BLS-style or PQ-aggregate) is out of scope.",
      "Full per-opcode EVM gas schedule (calldata bytes, refunds, memory expansion) beyond the single-cost gas-aware variant."
    ]),
    ("kind", .str "aapqSourceCertificate"),
    ("lean", .str "SoLean.Examples.AAPQSource.integratedContract"),
    ("proofReferences", stringsJson [
      "SoLean.Examples.AAWallet.validate_success_properties",
      "SoLean.Examples.PQVerifierWrapper.verify_success_properties",
      "SoLean.Examples.AAPQIntegration.callVerifierWrapper_eq_verifyProgram",
      "SoLean.Examples.AAPQIntegration.callVerifierWrapper_success_properties",
      "SoLean.Examples.AAPQIntegration.validateIntegrated_success_properties",
      "SoLean.Examples.AAPQIntegration.validateIntegratedViaCall_eq_validateIntegrated",
      "SoLean.Examples.AAPQIntegration.validateIntegratedViaCall_success_properties",
      "SoLean.Examples.AAPQSource.walletSource_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.walletV1Source_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.wrapperSource_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.integratedSource_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.integratedV1Source_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.BehaviorReflection.wrapperPhase_reflects_verifyProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.keyMatchPhase_reflects_keyMatchesWalletProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.walletPhase_reflects_validateProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.walletV1Phase_reflects_validateProgramV1",
      "SoLean.Examples.AAPQSource.BehaviorReflection.integratedBehaviorSummary_reflects_integratedProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.reflectedValidateIntegrated_eq_validateIntegrated",
      "SoLean.Examples.AAPQIntegration.noBypass_implies_verifier_accepted",
      "SoLean.Examples.AAPQIntegration.replay_rejected_after_success",
      "SoLean.Examples.AAPQIntegration.domain_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.signature_non_malleability_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.key_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQSource.integratedCryptoAssumptions_cover_all_oracle_theorems",
      "SoLean.Examples.AAPQSource.integratedCryptoAssumptionSupportGraph_covers_assumption_references",
      "SoLean.Examples.AAWallet.fullFlow_success_implies_validate_success",
      "SoLean.Examples.AAWallet.fullFlow_success_records_opHash",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_success_implies_validateIntegrated_success",
      "SoLean.Examples.AAPQIntegration.validateAndExecuteViaCall_eq_validateAndExecute",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_success_records_opHash",
      "SoLean.Examples.AAPQSource.BehaviorReflection.executePhase_reflects_executeUserOp",
      "SoLean.Examples.AAPQSource.BehaviorReflection.integratedFullBehaviorSummary_reflects_validateAndExecuteFlow",
      "SoLean.Examples.AAPQSource.BehaviorReflection.reflectedValidateAndExecute_eq_validateAndExecute",
      "SoLean.Examples.AAPQSource.BehaviorReflection.integratedV1FullBehaviorSummary_reflects_validateAndExecuteV1Flow",
      "SoLean.Examples.AAPQSource.BehaviorReflection.reflectedValidateAndExecuteV1_eq_validateAndExecuteV1",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_implies_verifier_accepted",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_records_authorized_opHash",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_success_structure",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_replay_rejected",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_domain_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_signature_non_malleability_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_key_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_reverts_when_validateIntegrated_reverts",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_reverts_iff_validateIntegrated_reverts",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wrapper_storage",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wallet_configuration",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_preserves_wallet_wrapperAddress",
      "SoLean.Examples.AAWallet.validateProgram_preserves_wrapperAddressSlot",
      "SoLean.Examples.AAPQIntegration.wallet_program_success_implies_validate_program_success",
      "SoLean.Examples.AAPQEvmCall.parse_build_verifier_calldata",
      "SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_wrong_selector",
      "SoLean.Examples.AAPQEvmCall.parseVerifierCalldata_rejects_short_calldata",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_success_matches_validateIntegrated",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_is_success_iff_validateIntegrated_is_success",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_wallet_step_isolated_from_oracle",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_preserves_wallet_configuration",
      "SoLean.Examples.AAPQEvmCall.WrapperCodeBound_eq_canonical",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaEvmCall_depends_only_on_wrapper_oracle",
      "SoLean.Examples.AAPQEvmCall.validateIntegratedViaReentrantEvmCall_eq_nonReentrant_under_noCallback",
      "SoLean.EVM.encode_length",
      "SoLean.EVM.encode_head_is_selector",
      "SoLean.EVM.decode_encode_calldataABI",
      "SoLean.Examples.StructuredVerifier.toBool_eq_under_respectsBool",
      "SoLean.Examples.StructuredVerifier.allFieldsEqualStructuredVerifier_respects_bool",
      "SoLean.Examples.StructuredVerifier.decide_isSome_of_toBool",
      "SoLean.Examples.StructuredVerifier.witness_extractable_under_respectsBool",
      "SoLean.Examples.StructuredVerifier.validateIntegrated_success_extracts_witness",
      "SoLean.Examples.StructuredVerifier.validateAndExecute_success_extracts_witness",
      "SoLean.Examples.StructuredVerifier.validateAndExecute_success_extracts_witness_with_authorized_opHash",
      "SoLean.Examples.LatticePublicKey.compress_cons",
      "SoLean.Examples.LatticePublicKey.compress_degree_independent",
      "SoLean.Examples.LatticePublicKey.compress_injectiveOnHead",
      "SoLean.Examples.LatticePublicKey.coordinate_uniqueness_under_compressionInjective",
      "SoLean.Examples.SchemeParameters.falcon512_ne_mlDsa44",
      "SoLean.Examples.SchemeParameters.falcon512_publicKey_size_ne_mlDsa44_publicKey_size",
      "SoLean.Examples.SchemeParameters.falcon512_sigUInt256_ne_mlDsa44_sigUInt256",
      "SoLean.Examples.SchemeParameters.falcon512_pkUInt256_ne_mlDsa44_pkUInt256",
      "SoLean.Examples.SchemeParameters.wrapper_calibrated_for_one_scheme_rejects_other_signature_length",
      "SoLean.Examples.SchemeParameters.falcon512_calibrated_wrapper_rejects_mlDsa44_signature_length",
      "SoLean.Examples.SchemeParameters.validateAndExecute_falcon512_calibrated_rejects_mlDsa44_signature_length",
      "SoLean.Examples.FalconSimpleWallet.falconSimpleWallet_composite_safety",
      "SoLean.Examples.FalconSimpleWallet.falconSimpleWalletDeployment_rejects_mlDsa44_signature_length",
      "SoLean.Examples.FalconSimpleWallet.validateAndExecute_preserves_walletStoresWrapperAddress",
      "SoLean.Examples.FalconSimpleWallet.validateAndExecute_preserves_deploymentInvariant",
      "SoLean.Examples.AAWallet.validateV1_success_properties",
      "SoLean.Examples.AAPQIntegration.walletProgramV1_success_implies_walletProgram_success",
      "SoLean.Examples.AAPQIntegration.walletProgramV1_success_expectedWrapperAddress",
      "SoLean.Examples.AAPQIntegration.validateIntegratedV1_success_implies_validateIntegrated_success",
      "SoLean.Examples.AAPQIntegration.validateIntegratedV1_success_expectedWrapperAddress",
      "SoLean.Examples.AAPQIntegration.validateAndExecuteV1_success_implies_validateIntegratedV1_success",
      "SoLean.Examples.AAPQIntegration.validateAndExecuteV1_success_structure",
      "SoLean.Examples.AAPQIntegration.validateAndExecuteV1_success_implies_validateAndExecute_success",
      "SoLean.Examples.FalconSimpleWallet.falconSimpleWallet_v1_composite_safety",
      "SoLean.Examples.ProtocolBoundaries.bundlerEcdsaDependence_trivial",
      "SoLean.Examples.ProtocolBoundaries.eip7702EcdsaKeyValidity_trivial",
      "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_eq_under_enough_gas",
      "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_outOfGas_when_insufficient",
      "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWithGas_is_success_iff_validateIntegrated_is_success",
      "SoLean.Examples.AAPQEvmCallGas.enoughGasAfter6364Forwarding_implies_enoughGas",
      "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWith6364Gas_eq_under_enoughGas",
      "SoLean.Examples.AAPQEvmCallGas.validateIntegratedViaEvmCallWith6364Gas_eq_unrestricted_under_enoughGas",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_key_separation",
      "SoLean.Examples.ToyVerifier.allFieldsEqualEnv_satisfies_oracle_assumptions",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_key_separation",
      "SoLean.Examples.ToyVerifier.keyDomainBindingEnv_satisfies_oracle_assumptions",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_domain_separation",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_signature_binding",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_key_separation",
      "SoLean.Examples.ToyVerifier.DerivedSignatureModel.toEnv_satisfies_oracle_assumptions"
    ]),
    ("unsupported", stringsJson [
      "real PQ cryptographic security",
      "real external calls between wallet and wrapper",
      "real ABI decoding",
      "real calldata, memory, events, gas, reentrancy",
      "Solidity parsing",
      "Yul emission",
      "solc bridge comparison"
    ]),
    ("version", .num 1)
  ]

def aapqSourceCertificateJson : String :=
  renderJson aapqSourceCertificate

def aapqBehaviorSummary : Json :=
  AAPQBehavior.summaryJson Examples.AAPQSource.integratedBehaviorSummary

def aapqBehaviorSummaryJson : String :=
  renderJson aapqBehaviorSummary

def aapqFullBehaviorSummary : Json :=
  AAPQBehavior.summaryJson Examples.AAPQSource.integratedFullBehaviorSummary

def aapqFullBehaviorSummaryJson : String :=
  renderJson aapqFullBehaviorSummary

def aapqV1FullBehaviorSummary : Json :=
  AAPQBehavior.summaryJsonWithLean
    "SoLean.Examples.AAPQSource.integratedV1FullBehaviorSummary"
    Examples.AAPQSource.integratedV1FullBehaviorSummary

def aapqV1FullBehaviorSummaryJson : String :=
  renderJson aapqV1FullBehaviorSummary

/--
Closed enumeration of every phase the v1 trace manifest can label an
entry with. Adding a new phase requires extending this inductive, which
keeps the Python audit's expected phase set in sync with Lean.
-/
inductive TracePhase where
  | wrapper
  | keyMatch
  | walletV1
  | execute
deriving Repr, DecidableEq

def TracePhase.toString : TracePhase -> String
  | .wrapper  => "wrapper"
  | .keyMatch => "keyMatch"
  | .walletV1 => "walletV1"
  | .execute  => "execute"

def allTracePhases : List TracePhase :=
  [.wrapper, .keyMatch, .walletV1, .execute]

/--
Recognized effect for one Lean-owned AA/PQ v1 trace entry.

- `guard k`     — the source statement enforces an invariant of `GuardKind` `k`.
- `delegates t` — the source statement is a call to a sibling function named
                  `t` whose body is itself in the trace.
- `finalWrite n s` — the source statement is the final write to slot `s`,
                  storage-visible as `n`.
- `phaseCall`   — the source statement is the integration's call into the
                  phase named by the surrounding trace entry's `phase` field.
-/
inductive TraceEffect where
  | guard (kind : Examples.AAPQSource.GuardKind)
  | delegates (target : String)
  | finalWrite (name : String) (slot : Nat)
  | phaseCall
deriving Repr

/--
Per-statement entry for the Lean-owned AA/PQ v1 trace manifest.

`phase` is one of `wrapper`, `keyMatch`, `walletV1`, `execute`. `leanProof` is
the Lean theorem the Python audit must report alongside this trace entry.
`effect` pins the recognized effect kind (guard / delegates / finalWrite /
phaseCall) and its per-kind shape data (guard kind, slot/name, target).
-/
structure AAPQV1TraceEntry where
  index    : Nat
  contract : String
  function : String
  rule     : String
  phase    : String
  effect   : TraceEffect
  leanProof : String
deriving Repr

namespace AAPQV1Trace

def wrapperProof : String :=
  "SoLean.Examples.PQVerifierWrapper.verify_success_properties"

def keyMatchProof : String :=
  "SoLean.Examples.AAPQIntegration.wallet_program_success_properties"

def walletV1Proof : String :=
  "SoLean.Examples.AAWallet.validateV1_success_properties"

def executeProof : String :=
  "SoLean.Examples.AAWallet.executeUserOp"

def v1FlowProof : String :=
  "SoLean.Examples.AAPQSource.BehaviorReflection." ++
    "integratedV1FullBehaviorSummary_reflects_validateAndExecuteV1Flow"

def ruleProofs : List AAPQV1TraceEntry :=
  [ { index := 0,  contract := "PQVerifierWrapper", function := "verify",
      rule := "wrapperPublicKeyLengthGuard", phase := "wrapper",
      effect := .guard .lengthCheck,
      leanProof := wrapperProof },
    { index := 1,  contract := "PQVerifierWrapper", function := "verify",
      rule := "wrapperSignatureLengthGuard", phase := "wrapper",
      effect := .guard .lengthCheck,
      leanProof := wrapperProof },
    { index := 2,  contract := "PQVerifierWrapper", function := "verify",
      rule := "wrapperDomainGuard", phase := "wrapper",
      effect := .guard .domainCheck,
      leanProof := wrapperProof },
    { index := 3,  contract := "PQVerifierWrapper", function := "verify",
      rule := "wrapperVerifierGuard", phase := "wrapper",
      effect := .guard .verifierCheck,
      leanProof := wrapperProof },
    { index := 4,  contract := "AAWallet", function := "validateUserOp",
      rule := "walletWrapperAddressGuard", phase := "walletV1",
      effect := .guard .wrapperAddressCheck,
      leanProof := walletV1Proof },
    { index := 5,  contract := "AAWallet", function := "validateUserOp",
      rule := "walletDelegateToBaseValidation", phase := "walletV1",
      effect := .delegates "AAWallet._validateUserOp",
      leanProof := walletV1Proof },
    { index := 6,  contract := "AAWallet", function := "_validateUserOp",
      rule := "walletEntryPointGuard", phase := "walletV1",
      effect := .guard .entryPointCheck,
      leanProof := walletV1Proof },
    { index := 7,  contract := "AAWallet", function := "_validateUserOp",
      rule := "walletNonceGuard", phase := "walletV1",
      effect := .guard .nonceCheck,
      leanProof := walletV1Proof },
    { index := 8,  contract := "AAWallet", function := "_validateUserOp",
      rule := "walletDomainGuard", phase := "walletV1",
      effect := .guard .domainCheck,
      leanProof := walletV1Proof },
    { index := 9,  contract := "AAWallet", function := "_validateUserOp",
      rule := "walletVerifierGuard", phase := "walletV1",
      effect := .guard .verifierCheck,
      leanProof := walletV1Proof },
    { index := 10, contract := "AAWallet", function := "_validateUserOp",
      rule := "walletNonceIncrement", phase := "walletV1",
      effect := .finalWrite "nonce" Examples.AAWallet.nonceSlot,
      leanProof := walletV1Proof },
    { index := 11, contract := "AAWallet", function := "executeUserOp",
      rule := "walletExecuteRecordsOpHash", phase := "execute",
      effect := .finalWrite "lastOpHash" Examples.AAWallet.lastOpHashSlot,
      leanProof := executeProof },
    { index := 12, contract := "AAPQIntegration", function := "validateAndExecuteV1",
      rule := "integrationWrapperVerifyCall", phase := "wrapper",
      effect := .phaseCall,
      leanProof := v1FlowProof },
    { index := 13, contract := "AAPQIntegration", function := "validateAndExecuteV1",
      rule := "integrationKeyCommitmentGuard", phase := "keyMatch",
      effect := .guard .keyCommitmentCheck,
      leanProof := keyMatchProof },
    { index := 14, contract := "AAPQIntegration", function := "validateAndExecuteV1",
      rule := "integrationWalletV1Call", phase := "walletV1",
      effect := .phaseCall,
      leanProof := v1FlowProof },
    { index := 15, contract := "AAPQIntegration", function := "validateAndExecuteV1",
      rule := "integrationExecuteCall", phase := "execute",
      effect := .phaseCall,
      leanProof := v1FlowProof } ]

def effectJson (phase : String) : TraceEffect -> Json
  | .guard kind => .obj [
      ("guard", .str (Examples.AAPQSource.GuardKind.toString kind)),
      ("kind", .str "guard"),
      ("phase", .str phase)
    ]
  | .delegates target => .obj [
      ("kind", .str "delegates"),
      ("phase", .str phase),
      ("target", .str target)
    ]
  | .finalWrite name slot => .obj [
      ("kind", .str "finalWrite"),
      ("name", .str name),
      ("phase", .str phase),
      ("slot", .num slot)
    ]
  | .phaseCall => .obj [
      ("kind", .str "phaseCall"),
      ("phase", .str phase)
    ]

def entryJson (entry : AAPQV1TraceEntry) : Json :=
  .obj [
    ("contract", .str entry.contract),
    ("effect", effectJson entry.phase entry.effect),
    ("function", .str entry.function),
    ("index", .num entry.index),
    ("leanProof", .str entry.leanProof),
    ("phase", .str entry.phase),
    ("rule", .str entry.rule)
  ]

/--
Closed enumeration of every recognized v1 trace rule. Adding a new rule to
the manifest requires extending this inductive, which then forces
`allTraceRuleIds_cover_expectedTrustedRules` below to be re-proved.
-/
inductive TraceRuleId where
  | wrapperPublicKeyLengthGuard
  | wrapperSignatureLengthGuard
  | wrapperDomainGuard
  | wrapperVerifierGuard
  | walletWrapperAddressGuard
  | walletDelegateToBaseValidation
  | walletEntryPointGuard
  | walletNonceGuard
  | walletDomainGuard
  | walletVerifierGuard
  | walletNonceIncrement
  | walletExecuteRecordsOpHash
  | integrationWrapperVerifyCall
  | integrationKeyCommitmentGuard
  | integrationWalletV1Call
  | integrationExecuteCall
deriving Repr, DecidableEq

def TraceRuleId.toString : TraceRuleId -> String
  | .wrapperPublicKeyLengthGuard    => "wrapperPublicKeyLengthGuard"
  | .wrapperSignatureLengthGuard    => "wrapperSignatureLengthGuard"
  | .wrapperDomainGuard             => "wrapperDomainGuard"
  | .wrapperVerifierGuard           => "wrapperVerifierGuard"
  | .walletWrapperAddressGuard      => "walletWrapperAddressGuard"
  | .walletDelegateToBaseValidation => "walletDelegateToBaseValidation"
  | .walletEntryPointGuard          => "walletEntryPointGuard"
  | .walletNonceGuard               => "walletNonceGuard"
  | .walletDomainGuard              => "walletDomainGuard"
  | .walletVerifierGuard            => "walletVerifierGuard"
  | .walletNonceIncrement           => "walletNonceIncrement"
  | .walletExecuteRecordsOpHash     => "walletExecuteRecordsOpHash"
  | .integrationWrapperVerifyCall   => "integrationWrapperVerifyCall"
  | .integrationKeyCommitmentGuard  => "integrationKeyCommitmentGuard"
  | .integrationWalletV1Call        => "integrationWalletV1Call"
  | .integrationExecuteCall         => "integrationExecuteCall"

def allTraceRuleIds : List TraceRuleId :=
  [ .wrapperPublicKeyLengthGuard,
    .wrapperSignatureLengthGuard,
    .wrapperDomainGuard,
    .wrapperVerifierGuard,
    .walletWrapperAddressGuard,
    .walletDelegateToBaseValidation,
    .walletEntryPointGuard,
    .walletNonceGuard,
    .walletDomainGuard,
    .walletVerifierGuard,
    .walletNonceIncrement,
    .walletExecuteRecordsOpHash,
    .integrationWrapperVerifyCall,
    .integrationKeyCommitmentGuard,
    .integrationWalletV1Call,
    .integrationExecuteCall ]

def expectedTrustedRules : List String :=
  allTraceRuleIds.map TraceRuleId.toString

def expectedTracePhases : List String :=
  allTracePhases.map TracePhase.toString

/--
Lean-side coverage theorem: the enumerated `allTraceRuleIds`, projected
through `TraceRuleId.toString`, exactly equals the `rule` strings carried
by `ruleProofs`. Any drift between the enumeration and the per-entry
strings breaks this `rfl` at build time.
-/
theorem allTraceRuleIds_cover_expectedTrustedRules :
    allTraceRuleIds.map TraceRuleId.toString =
      ruleProofs.map AAPQV1TraceEntry.rule := by
  rfl

def phaseProofsJson : Json :=
  .obj [
    ("execute", .str executeProof),
    ("keyMatch", .str keyMatchProof),
    ("walletV1", .str walletV1Proof),
    ("wrapper", .str wrapperProof)
  ]

/-- Sorted, deduplicated union of every Lean proof referenced by the manifest. -/
def proofReferences : List String :=
  [ "SoLean.Artifacts.AAPQV1Trace.allTraceRuleIds_cover_expectedTrustedRules",
    "SoLean.Examples.AAPQIntegration.wallet_program_success_properties",
    v1FlowProof,
    executeProof,
    walletV1Proof,
    wrapperProof ]

end AAPQV1Trace

def aapqV1TraceManifest : Json :=
  .obj [
    ("expectedTracePhases", stringsJson AAPQV1Trace.expectedTracePhases),
    ("expectedTrustedRules", stringsJson AAPQV1Trace.expectedTrustedRules),
    ("kind", .str "aapqV1TraceManifest"),
    ("phaseProofs", AAPQV1Trace.phaseProofsJson),
    ("proofReferences", stringsJson AAPQV1Trace.proofReferences),
    ("traceRuleProofs", .arr (AAPQV1Trace.ruleProofs.map AAPQV1Trace.entryJson)),
    ("v1FlowProof", .str AAPQV1Trace.v1FlowProof),
    ("version", .num 3)
  ]

def aapqV1TraceManifestJson : String :=
  renderJson aapqV1TraceManifest

end Artifacts
end SoLean
