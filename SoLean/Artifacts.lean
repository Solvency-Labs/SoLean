import SoLean.Bridge
import SoLean.Examples.AAPQSource
import SoLean.Examples.CounterCompiler
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

def integratedContractJson
    (contract : SoLean.Source.Shape.IntegratedContract) : Json :=
  .obj [
    ("integration", .obj [
      ("flow", integratedFlow),
      ("name", .str contract.integrationName),
      ("params", .arr (contract.params.map paramJson))
    ]),
    ("kind", .str "aapqIntegratedSource"),
    ("lean", .str "SoLean.Examples.AAPQSource.integratedContract"),
    ("name", .str contract.name),
    ("pragma", .str contract.pragma),
    ("wallet", contractJson contract.wallet),
    ("wrapper", contractJson contract.wrapper)
  ]

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

def summaryJson (summary : SoLean.Examples.AAPQSource.BehaviorSummary) : Json :=
  .obj [
    ("function", .str summary.function),
    ("kind", .str "aapqBehaviorSummary"),
    ("lean", .str "SoLean.Examples.AAPQSource.integratedBehaviorSummary"),
    ("object", .str summary.object),
    ("params", stringsJson summary.params),
    ("phases", .arr (summary.phases.map phaseJson)),
    ("version", .num 2)
  ]

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
    ("verifierModelCalibrations", .arr [
      AAPQBehavior.toyVerifierCalibrationJson,
      AAPQBehavior.keyDomainBindingCalibrationJson,
      AAPQBehavior.derivedSignatureCalibrationJson
    ]),
    ("expectedBehaviorSummary",
      AAPQBehavior.summaryJson Examples.AAPQSource.integratedBehaviorSummary),
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
      "SoLean.Examples.AAPQSource.wrapperSource_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.integratedSource_instantiates_to_existing_model",
      "SoLean.Examples.AAPQSource.BehaviorReflection.wrapperPhase_reflects_verifyProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.keyMatchPhase_reflects_keyMatchesWalletProgram",
      "SoLean.Examples.AAPQSource.BehaviorReflection.walletPhase_reflects_validateProgram",
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

end Artifacts
end SoLean
