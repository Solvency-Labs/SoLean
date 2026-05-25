import SoLean.Examples.AAPQIntegration
import SoLean.Source.Shape

namespace SoLean
namespace Examples
namespace AAPQSource

abbrev StorageSlot := SoLean.Source.Shape.StorageSlot
abbrev Param := SoLean.Source.Shape.Param
abbrev Contract := SoLean.Source.Shape.Contract
abbrev IntegratedContract := SoLean.Source.Shape.IntegratedContract

def walletContract : Contract :=
  { name := "AAWallet",
    pragma := "0.8.35",
    storage := [
      { name := "nonce",
        slot := AAWallet.nonceSlot,
        typeName := "uint256" },
      { name := "keyCommitment",
        slot := AAWallet.keyCommitmentSlot,
        typeName := "uint256" },
      { name := "domain",
        slot := AAWallet.domainSlot,
        typeName := "uint256" },
      { name := "entryPoint",
        slot := AAWallet.entryPointSlot,
        typeName := "uint256" }
    ],
    functionName := "validateUserOp",
    params := [
      { name := "opHash",    typeName := "uint256" },
      { name := "nonce",     typeName := "uint256" },
      { name := "domain",    typeName := "uint256" },
      { name := "signature", typeName := "uint256" }
    ] }

def wrapperAddressStorageSlot : StorageSlot :=
  { name := "wrapperAddress",
    slot := AAWallet.wrapperAddressSlot,
    typeName := "address" }

def lastOpHashStorageSlot : StorageSlot :=
  { name := "lastOpHash",
    slot := AAWallet.lastOpHashSlot,
    typeName := "uint256" }

def expectedWrapperAddressParam : Param :=
  { name := "expectedWrapperAddress", typeName := "address" }

def falconSimpleWalletV1Contract : Contract :=
  { name := "FalconSimpleWallet",
    pragma := "0.8.35",
    storage :=
      walletContract.storage ++ [lastOpHashStorageSlot, wrapperAddressStorageSlot],
    functionName := "validateUserOp",
    params := walletContract.params ++ [expectedWrapperAddressParam] }

def walletBody (op : AAWallet.UserOp) : Stmt :=
  AAWallet.validateProgram op

theorem walletSource_instantiates_to_existing_model (op : AAWallet.UserOp) :
    walletBody op = AAWallet.validateProgram op := rfl

def walletV1Body (op : AAWallet.UserOpV1) : Stmt :=
  AAWallet.validateProgramV1 op

theorem walletV1Source_instantiates_to_existing_model
    (op : AAWallet.UserOpV1) :
    walletV1Body op = AAWallet.validateProgramV1 op := rfl

def wrapperContract : Contract :=
  { name := "PQVerifierWrapper",
    pragma := "0.8.35",
    storage := [
      { name := "expectedPublicKeyLength",
        slot := PQVerifierWrapper.expectedPublicKeyLengthSlot,
        typeName := "uint256" },
      { name := "expectedSignatureLength",
        slot := PQVerifierWrapper.expectedSignatureLengthSlot,
        typeName := "uint256" },
      { name := "expectedDomain",
        slot := PQVerifierWrapper.expectedDomainSlot,
        typeName := "uint256" }
    ],
    functionName := "verify",
    params := [
      { name := "publicKey",       typeName := "uint256" },
      { name := "publicKeyLength", typeName := "uint256" },
      { name := "message",         typeName := "uint256" },
      { name := "domain",          typeName := "uint256" },
      { name := "signature",       typeName := "uint256" },
      { name := "signatureLength", typeName := "uint256" }
    ] }

def wrapperBody (input : PQVerifierWrapper.WrapperInput) : Stmt :=
  PQVerifierWrapper.verifyProgram input

theorem wrapperSource_instantiates_to_existing_model
    (input : PQVerifierWrapper.WrapperInput) :
    wrapperBody input = PQVerifierWrapper.verifyProgram input := rfl

def integratedContract : IntegratedContract :=
  { name := "AAPQIntegration",
    pragma := "0.8.35",
    wallet := walletContract,
    wrapper := wrapperContract,
    integrationName := "validateIntegrated",
    params := [
      { name := "publicKey",        typeName := "uint256" },
      { name := "publicKeyLength",  typeName := "uint256" },
      { name := "opHash",           typeName := "uint256" },
      { name := "nonce",            typeName := "uint256" },
      { name := "domain",           typeName := "uint256" },
      { name := "signature",        typeName := "uint256" },
      { name := "signatureLength",  typeName := "uint256" }
    ] }

def integratedV1Contract : IntegratedContract :=
  { name := "AAPQIntegration",
    pragma := "0.8.35",
    wallet := falconSimpleWalletV1Contract,
    wrapper := wrapperContract,
    integrationName := "validateAndExecuteV1",
    params := integratedContract.params ++ [expectedWrapperAddressParam] }

def instantiateIntegrated
    (env : Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) : AAPQIntegration.IntegratedResult :=
  AAPQIntegration.validateIntegrated env input wrapperStorage walletStorage

theorem integratedSource_instantiates_to_existing_model
    (env : Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : Storage) :
    instantiateIntegrated env input wrapperStorage walletStorage =
      AAPQIntegration.validateIntegrated env input wrapperStorage walletStorage :=
  rfl

def instantiateIntegratedV1
    (env : Env)
    (input : AAPQIntegration.IntegratedInputV1)
    (wrapperStorage walletStorage : Storage) :
    AAPQIntegration.IntegratedFullResult :=
  AAPQIntegration.validateAndExecuteV1 env input wrapperStorage walletStorage

theorem integratedV1Source_instantiates_to_existing_model
    (env : Env)
    (input : AAPQIntegration.IntegratedInputV1)
    (wrapperStorage walletStorage : Storage) :
    instantiateIntegratedV1 env input wrapperStorage walletStorage =
      AAPQIntegration.validateAndExecuteV1 env input wrapperStorage walletStorage :=
  rfl

/--
Guard kinds observed in the integrated AA/PQ flow. The set is small and
deliberately closed: any new guard the source shape needs to recognize must be
added here, which keeps drift between docs and exported artifacts visible.
-/
inductive GuardKind where
  | entryPointCheck
  | nonceCheck
  | domainCheck
  | lengthCheck
  | verifierCheck
  | keyCommitmentCheck
  | wrapperAddressCheck
deriving Repr, DecidableEq

def GuardKind.toString : GuardKind -> String
  | .entryPointCheck    => "entryPointCheck"
  | .nonceCheck         => "nonceCheck"
  | .domainCheck        => "domainCheck"
  | .lengthCheck        => "lengthCheck"
  | .verifierCheck      => "verifierCheck"
  | .keyCommitmentCheck => "keyCommitmentCheck"
  | .wrapperAddressCheck => "wrapperAddressCheck"

/--
Structured operand DSL for guard conditions and final-write value expressions.

`Operand.slot` carries the contract role (currently `"wallet"` or
`"wrapper"`) and the storage slot name. Contract roles are matched against
the Solidity-shaped contracts in the source artifact by Python audits.
-/
inductive Operand where
  | param (name : String)
  | slot (contract : String) (slotName : String)
  | msgSender
  | const (value : Nat)
deriving Repr, DecidableEq

inductive Condition where
  | eq (lhs rhs : Operand)
  | verifier (key message domain signature : Operand)
deriving Repr, DecidableEq

inductive ValueExpression where
  | operand (op : Operand)
  | checkedAdd (lhs rhs : ValueExpression)
deriving Repr, DecidableEq

structure Guard where
  kind : GuardKind
  condition : Condition
deriving Repr, DecidableEq

structure FinalWrite where
  contract : String
  slotName : String
  slot : Slot
  value : ValueExpression
deriving Repr, DecidableEq

structure Phase where
  name : String
  contract : String
  guards : List Guard
  finalWrites : List FinalWrite
  proofReference : String
deriving Repr, DecidableEq

structure BehaviorSummary where
  object : String
  function : String
  params : List String
  phases : List Phase
deriving Repr, DecidableEq

/--
Named crypto assumption on `SoLean.Env.verifier`, surfaced in the source
certificate so the trust boundary is enumerable per assumption rather than
buried in prose.

`leanReference` names the Lean predicate (e.g.
`SoLean.Examples.AAPQIntegration.VerifierDomainSeparation`). `statement` is
the informal description shown in audit reports.
-/
structure CryptoAssumption where
  name : String
  leanReference : String
  statement : String
  theoremReferences : List String
deriving Repr, DecidableEq

structure CryptoAssumptionSupportEdge where
  assumptionName : String
  theoremReference : String
  flow : String
  layer : String
deriving Repr, DecidableEq

def integratedCryptoAssumptions : List CryptoAssumption :=
  [
    { name := "VerifierDomainSeparation",
      leanReference :=
        "SoLean.Examples.AAPQIntegration.VerifierDomainSeparation",
      statement :=
        "Env.verifier accepts each (publicKey, message, signature) under at most one domain.",
      theoremReferences := [
        "SoLean.Examples.AAPQIntegration.domain_separation_under_oracle_assumption",
        "SoLean.Examples.AAPQIntegration.validateAndExecute_domain_separation_under_oracle_assumption"
      ] },
    { name := "VerifierSignatureBinding",
      leanReference :=
        "SoLean.Examples.AAPQIntegration.VerifierSignatureBinding",
      statement :=
        "Env.verifier accepts each (publicKey, message, domain) under at most one signature.",
      theoremReferences := [
        "SoLean.Examples.AAPQIntegration.signature_non_malleability_under_oracle_assumption",
        "SoLean.Examples.AAPQIntegration.validateAndExecute_signature_non_malleability_under_oracle_assumption"
      ] },
    { name := "VerifierKeySeparation",
      leanReference :=
        "SoLean.Examples.AAPQIntegration.VerifierKeySeparation",
      statement :=
        "Env.verifier accepts each (message, domain, signature) under at most one publicKey.",
      theoremReferences := [
        "SoLean.Examples.AAPQIntegration.key_separation_under_oracle_assumption",
        "SoLean.Examples.AAPQIntegration.validateAndExecute_key_separation_under_oracle_assumption"
      ] }
  ]

/--
Enumerated identifier for each AA/PQ safety theorem that depends on a named
oracle assumption. Adding a new such theorem requires extending this
inductive — `integratedCryptoAssumptions_cover_all_oracle_theorems` below
then forces the corresponding `integratedCryptoAssumptions` entry to exist,
catching drift at compile time.
-/
inductive OracleAssumptionId where
  | domainSeparation
  | signatureBinding
  | keySeparation
deriving Repr, DecidableEq

def OracleAssumptionId.theoremReferences : OracleAssumptionId -> List String
  | .domainSeparation => [
      "SoLean.Examples.AAPQIntegration.domain_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_domain_separation_under_oracle_assumption"
    ]
  | .signatureBinding => [
      "SoLean.Examples.AAPQIntegration.signature_non_malleability_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_signature_non_malleability_under_oracle_assumption"
    ]
  | .keySeparation => [
      "SoLean.Examples.AAPQIntegration.key_separation_under_oracle_assumption",
      "SoLean.Examples.AAPQIntegration.validateAndExecute_key_separation_under_oracle_assumption"
    ]

def allOracleAssumptions : List OracleAssumptionId :=
  [.domainSeparation, .signatureBinding, .keySeparation]

/--
Lean-side coverage theorem: the `theoremReferences` listed by
`integratedCryptoAssumptions` are exactly the references named by every
`OracleAssumptionId`. Adding a new `*_under_oracle_assumption` safety
theorem without extending both `OracleAssumptionId.theoremReferences` and
`integratedCryptoAssumptions` breaks this `rfl`, giving build-time drift
detection that mirrors the Python audit at the proof layer.
-/
theorem integratedCryptoAssumptions_cover_all_oracle_theorems :
    integratedCryptoAssumptions.map CryptoAssumption.theoremReferences =
      allOracleAssumptions.map OracleAssumptionId.theoremReferences := by
  rfl

def integratedCryptoAssumptionSupportGraph :
    List CryptoAssumptionSupportEdge :=
  [
    { assumptionName := "VerifierDomainSeparation",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.domain_separation_under_oracle_assumption",
      flow := "validateIntegrated",
      layer := "integratedValidation" },
    { assumptionName := "VerifierDomainSeparation",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.validateAndExecute_domain_separation_under_oracle_assumption",
      flow := "validateAndExecute",
      layer := "integratedExecution" },
    { assumptionName := "VerifierSignatureBinding",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.signature_non_malleability_under_oracle_assumption",
      flow := "validateIntegrated",
      layer := "integratedValidation" },
    { assumptionName := "VerifierSignatureBinding",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.validateAndExecute_signature_non_malleability_under_oracle_assumption",
      flow := "validateAndExecute",
      layer := "integratedExecution" },
    { assumptionName := "VerifierKeySeparation",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.key_separation_under_oracle_assumption",
      flow := "validateIntegrated",
      layer := "integratedValidation" },
    { assumptionName := "VerifierKeySeparation",
      theoremReference :=
        "SoLean.Examples.AAPQIntegration.validateAndExecute_key_separation_under_oracle_assumption",
      flow := "validateAndExecute",
      layer := "integratedExecution" }
  ]

def CryptoAssumption.namedTheoremEdges
    (entry : CryptoAssumption) : List (String × String) :=
  entry.theoremReferences.map (fun ref => (entry.name, ref))

def CryptoAssumptionSupportEdge.namedTheoremEdge
    (entry : CryptoAssumptionSupportEdge) : String × String :=
  (entry.assumptionName, entry.theoremReference)

/--
Lean-side graph coverage theorem: every theorem reference named by
`integratedCryptoAssumptions` has exactly one corresponding support-graph edge,
in the same stable order.
-/
theorem integratedCryptoAssumptionSupportGraph_covers_assumption_references :
    integratedCryptoAssumptionSupportGraph.map
        CryptoAssumptionSupportEdge.namedTheoremEdge =
      integratedCryptoAssumptions.flatMap
        CryptoAssumption.namedTheoremEdges := by
  rfl

/--
Lean-owned ordered behavior summary of the integrated AA/PQ flow.

Each phase corresponds to a Solidity-shaped boundary in the integrated
function: the wrapper validation, the cross-contract key-match guard, and the
wallet validation. Guards are listed in source order, final writes are listed
per contract, and each phase carries the Lean theorem that backs its success
properties. This is a Solidity-level audit shape, not a Yul-level summary.
-/
private def walletSlot (slotName : String) : Operand := .slot "wallet" slotName
private def wrapperSlot (slotName : String) : Operand := .slot "wrapper" slotName
private def paramOperand (paramName : String) : Operand := .param paramName

def wrapperPhase : Phase :=
  { name := "wrapper",
    contract := "PQVerifierWrapper",
    guards := [
      { kind := .lengthCheck,
        condition :=
          .eq (paramOperand "publicKeyLength")
            (wrapperSlot "expectedPublicKeyLength") },
      { kind := .lengthCheck,
        condition :=
          .eq (paramOperand "signatureLength")
            (wrapperSlot "expectedSignatureLength") },
      { kind := .domainCheck,
        condition :=
          .eq (paramOperand "domain") (wrapperSlot "expectedDomain") },
      { kind := .verifierCheck,
        condition :=
          .verifier (paramOperand "publicKey") (paramOperand "opHash")
            (paramOperand "domain") (paramOperand "signature") }
    ],
    finalWrites := [],
    proofReference :=
      "SoLean.Examples.PQVerifierWrapper.verify_success_properties" }

def keyMatchPhase : Phase :=
  { name := "keyMatch",
    contract := "AAWallet",
    guards := [
      { kind := .keyCommitmentCheck,
        condition :=
          .eq (paramOperand "publicKey") (walletSlot "keyCommitment") }
    ],
    finalWrites := [],
    proofReference :=
      "SoLean.Examples.AAPQIntegration.wallet_program_success_properties" }

def walletPhase : Phase :=
  { name := "wallet",
    contract := "AAWallet",
    guards := [
      { kind := .entryPointCheck,
        condition := .eq .msgSender (walletSlot "entryPoint") },
      { kind := .nonceCheck,
        condition := .eq (paramOperand "nonce") (walletSlot "nonce") },
      { kind := .domainCheck,
        condition := .eq (paramOperand "domain") (walletSlot "domain") },
      { kind := .verifierCheck,
        condition :=
          .verifier (walletSlot "keyCommitment") (paramOperand "opHash")
            (paramOperand "domain") (paramOperand "signature") }
    ],
    finalWrites := [
      { contract := "AAWallet",
        slotName := "nonce",
        slot := AAWallet.nonceSlot,
        value :=
          .checkedAdd (.operand (walletSlot "nonce")) (.operand (.const 1)) }
    ],
    proofReference :=
      "SoLean.Examples.AAWallet.validate_success_properties" }

def walletV1Phase : Phase :=
  { name := "walletV1",
    contract := "AAWallet",
    guards := [
      { kind := .wrapperAddressCheck,
        condition :=
          .eq (paramOperand "expectedWrapperAddress")
            (walletSlot "wrapperAddress") },
      { kind := .entryPointCheck,
        condition := .eq .msgSender (walletSlot "entryPoint") },
      { kind := .nonceCheck,
        condition := .eq (paramOperand "nonce") (walletSlot "nonce") },
      { kind := .domainCheck,
        condition := .eq (paramOperand "domain") (walletSlot "domain") },
      { kind := .verifierCheck,
        condition :=
          .verifier (walletSlot "keyCommitment") (paramOperand "opHash")
            (paramOperand "domain") (paramOperand "signature") }
    ],
    finalWrites := [
      { contract := "AAWallet",
        slotName := "nonce",
        slot := AAWallet.nonceSlot,
        value :=
          .checkedAdd (.operand (walletSlot "nonce")) (.operand (.const 1)) }
    ],
    proofReference :=
      "SoLean.Examples.AAWallet.validateV1_success_properties" }

def integratedBehaviorSummary : BehaviorSummary :=
  { object := "AAPQIntegration",
    function := "validateIntegrated",
    params :=
      ["publicKey", "publicKeyLength", "opHash", "nonce", "domain",
       "signature", "signatureLength"],
    phases := [wrapperPhase, keyMatchPhase, walletPhase] }

def executePhase : Phase :=
  { name := "execute",
    contract := "AAWallet",
    guards := [],
    finalWrites := [
      { contract := "AAWallet",
        slotName := "lastOpHash",
        slot := AAWallet.lastOpHashSlot,
        value := .operand (paramOperand "opHash") }
    ],
    proofReference :=
      "SoLean.Examples.AAWallet.executeUserOp" }

def integratedFullBehaviorSummary : BehaviorSummary :=
  { object := "AAPQIntegration",
    function := "validateAndExecute",
    params :=
      ["publicKey", "publicKeyLength", "opHash", "nonce", "domain",
       "signature", "signatureLength"],
    phases := [wrapperPhase, keyMatchPhase, walletPhase, executePhase] }

def integratedV1FullBehaviorSummary : BehaviorSummary :=
  { object := "AAPQIntegration",
    function := "validateAndExecuteV1",
    params :=
      ["publicKey", "publicKeyLength", "opHash", "nonce", "domain",
       "signature", "signatureLength", "expectedWrapperAddress"],
    phases := [wrapperPhase, keyMatchPhase, walletV1Phase, executePhase] }

-- Semantics for the structured Operand/Condition/ValueExpression DSL under a
-- concrete AAPQIntegration.IntegratedInput. The reflection is intentionally
-- total: unrecognized parameter names, slot roles, or constants return `none`.
-- The theorems below pin the integratedBehaviorSummary phases to the proved
-- AA/PQ programs, so any future edit to a phase that drifts from the proved
-- program will break the build rather than only invalidating an artifact hash.
namespace BehaviorReflection

def constToValueExpr : Nat -> SoLean.ValueExpr
  | 0 => .const UInt256.zero
  | 1 => .const UInt256.one
  | _ => .const UInt256.zero

def operandToValueExpr
    (input : AAPQIntegration.IntegratedInput) :
    Operand -> Option SoLean.ValueExpr
  | .param "publicKey"        => some (.const input.publicKey)
  | .param "publicKeyLength"  => some (.const input.publicKeyLength)
  | .param "opHash"           => some (.const input.opHash)
  | .param "nonce"            => some (.const input.nonce)
  | .param "domain"           => some (.const input.domain)
  | .param "signature"        => some (.const input.signature)
  | .param "signatureLength"  => some (.const input.signatureLength)
  | .param _                  => none
  | .slot "wallet"  "nonce"         => some AAWallet.nonceExpr
  | .slot "wallet"  "keyCommitment" => some AAWallet.keyCommitmentExpr
  | .slot "wallet"  "domain"        => some AAWallet.domainExpr
  | .slot "wallet"  "entryPoint"    => some AAWallet.entryPointExpr
  | .slot "wallet"  "wrapperAddress" => some AAWallet.wrapperAddressExpr
  | .slot "wrapper" "expectedPublicKeyLength" =>
      some PQVerifierWrapper.expectedPublicKeyLengthExpr
  | .slot "wrapper" "expectedSignatureLength" =>
      some PQVerifierWrapper.expectedSignatureLengthExpr
  | .slot "wrapper" "expectedDomain" =>
      some PQVerifierWrapper.expectedDomainExpr
  | .slot _ _ => none
  | .msgSender => some .msgSender
  | .const n => some (constToValueExpr n)

def operandToValueExprV1
    (input : AAPQIntegration.IntegratedInputV1) :
    Operand -> Option SoLean.ValueExpr
  | .param "expectedWrapperAddress" =>
      some (.const input.expectedWrapperAddress)
  | operand => operandToValueExpr input.toIntegratedInput operand

def conditionToBoolExpr
    (input : AAPQIntegration.IntegratedInput) :
    Condition -> Option SoLean.BoolExpr
  | .eq lhs rhs =>
      match operandToValueExpr input lhs, operandToValueExpr input rhs with
      | some l, some r => some (.eq l r)
      | _, _ => none
  | .verifier key message domain signature =>
      match
        operandToValueExpr input key,
        operandToValueExpr input message,
        operandToValueExpr input domain,
        operandToValueExpr input signature with
      | some k, some m, some d, some s => some (.verify k m d s)
      | _, _, _, _ => none

def conditionToBoolExprV1
    (input : AAPQIntegration.IntegratedInputV1) :
    Condition -> Option SoLean.BoolExpr
  | .eq lhs rhs =>
      match operandToValueExprV1 input lhs, operandToValueExprV1 input rhs with
      | some l, some r => some (.eq l r)
      | _, _ => none
  | .verifier key message domain signature =>
      match
        operandToValueExprV1 input key,
        operandToValueExprV1 input message,
        operandToValueExprV1 input domain,
        operandToValueExprV1 input signature with
      | some k, some m, some d, some s => some (.verify k m d s)
      | _, _, _, _ => none

def guardToStmt
    (input : AAPQIntegration.IntegratedInput) (guard : Guard) :
    Option SoLean.Stmt :=
  match conditionToBoolExpr input guard.condition with
  | some expr => some (.require expr)
  | none => none

def guardToStmtV1
    (input : AAPQIntegration.IntegratedInputV1) (guard : Guard) :
    Option SoLean.Stmt :=
  match conditionToBoolExprV1 input guard.condition with
  | some expr => some (.require expr)
  | none => none

def valueToValueExpr
    (input : AAPQIntegration.IntegratedInput) :
    ValueExpression -> Option SoLean.ValueExpr
  | .operand op => operandToValueExpr input op
  | .checkedAdd lhs rhs =>
      match valueToValueExpr input lhs, valueToValueExpr input rhs with
      | some l, some r => some (.add l r)
      | _, _ => none

def valueToValueExprV1
    (input : AAPQIntegration.IntegratedInputV1) :
    ValueExpression -> Option SoLean.ValueExpr
  | .operand op => operandToValueExprV1 input op
  | .checkedAdd lhs rhs =>
      match valueToValueExprV1 input lhs, valueToValueExprV1 input rhs with
      | some l, some r => some (.add l r)
      | _, _ => none

def finalWriteToStmt
    (input : AAPQIntegration.IntegratedInput) (write : FinalWrite) :
    Option SoLean.Stmt :=
  match valueToValueExpr input write.value with
  | some expr => some (.assign write.slot expr)
  | none => none

def finalWriteToStmtV1
    (input : AAPQIntegration.IntegratedInputV1) (write : FinalWrite) :
    Option SoLean.Stmt :=
  match valueToValueExprV1 input write.value with
  | some expr => some (.assign write.slot expr)
  | none => none

def seqOfStmts : List SoLean.Stmt -> SoLean.Stmt
  | [] => .skip
  | [stmt] => stmt
  | stmt :: rest => .seq stmt (seqOfStmts rest)

def sequenceOptions {α : Type} : List (Option α) -> Option (List α)
  | [] => some []
  | none :: _ => none
  | some x :: rest =>
      match sequenceOptions rest with
      | some xs => some (x :: xs)
      | none => none

def phaseToStmt
    (input : AAPQIntegration.IntegratedInput) (phase : Phase) :
    Option SoLean.Stmt :=
  let guardStmts := phase.guards.map (guardToStmt input)
  let writeStmts := phase.finalWrites.map (finalWriteToStmt input)
  match sequenceOptions (guardStmts ++ writeStmts) with
  | some stmts => some (seqOfStmts stmts)
  | none => none

def phaseToStmtV1
    (input : AAPQIntegration.IntegratedInputV1) (phase : Phase) :
    Option SoLean.Stmt :=
  let guardStmts := phase.guards.map (guardToStmtV1 input)
  let writeStmts := phase.finalWrites.map (finalWriteToStmtV1 input)
  match sequenceOptions (guardStmts ++ writeStmts) with
  | some stmts => some (seqOfStmts stmts)
  | none => none

/--
The reflected `wrapperPhase` reconstructs exactly the proved
`PQVerifierWrapper.verifyProgram` for the wrapper input projected from any
`IntegratedInput`.
-/
theorem wrapperPhase_reflects_verifyProgram
    (input : AAPQIntegration.IntegratedInput) :
    phaseToStmt input wrapperPhase =
      some
        (PQVerifierWrapper.verifyProgram
          (AAPQIntegration.toWrapperInput input)) := by
  rfl

/--
The reflected `keyMatchPhase` reconstructs exactly the proved key-match guard
emitted by `AAPQIntegration.keyMatchesWalletProgram`.
-/
theorem keyMatchPhase_reflects_keyMatchesWalletProgram
    (input : AAPQIntegration.IntegratedInput) :
    phaseToStmt input keyMatchPhase =
      some (AAPQIntegration.keyMatchesWalletProgram input) := by
  rfl

/--
The reflected `walletPhase` reconstructs exactly the proved
`AAWallet.validateProgram` for the user op projected from any
`IntegratedInput`.
-/
theorem walletPhase_reflects_validateProgram
    (input : AAPQIntegration.IntegratedInput) :
    phaseToStmt input walletPhase =
      some (AAWallet.validateProgram (AAPQIntegration.toUserOp input)) := by
  rfl

/--
The reflected `walletV1Phase` reconstructs exactly the proved
`AAWallet.validateProgramV1`, including the stored-wrapper-address guard.
-/
theorem walletV1Phase_reflects_validateProgramV1
    (input : AAPQIntegration.IntegratedInputV1) :
    phaseToStmtV1 input walletV1Phase =
      some (AAWallet.validateProgramV1 (AAPQIntegration.toUserOpV1 input)) := by
  rfl

/--
The reflected `integratedBehaviorSummary` reconstructs exactly the three proved
programs composed by `AAPQIntegration.validateIntegrated`: wrapper validation,
the key-match guard, and wallet validation.
-/
theorem integratedBehaviorSummary_reflects_integratedProgram
    (input : AAPQIntegration.IntegratedInput) :
    integratedBehaviorSummary.phases.map (phaseToStmt input) =
      [ some
          (PQVerifierWrapper.verifyProgram
            (AAPQIntegration.toWrapperInput input)),
        some (AAPQIntegration.keyMatchesWalletProgram input),
        some (AAWallet.validateProgram (AAPQIntegration.toUserOp input)) ] := by
  rfl

/--
Execute the three reflected phases in the same composition pattern as
`AAPQIntegration.validateIntegrated`.

The wallet body is run as `.seq keyMatchStmt walletStmt`, matching
`AAPQIntegration.walletProgram = .seq keyMatchesWalletProgram validateProgram`.
Returns `none` if any phase fails to reflect (which cannot happen for the
concrete `integratedBehaviorSummary` — `reflectedValidateIntegrated_eq_
validateIntegrated` below shows it always returns `some ...`).
-/
def reflectedValidateIntegrated
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : SoLean.Storage) :
    Option AAPQIntegration.IntegratedResult :=
  match phaseToStmt input wrapperPhase,
        phaseToStmt input keyMatchPhase,
        phaseToStmt input walletPhase with
  | some wrapperStmt, some keyMatchStmt, some walletStmt =>
      some
        (match SoLean.exec env wrapperStmt wrapperStorage with
         | .success finalWrapperStorage =>
             match SoLean.exec env (.seq keyMatchStmt walletStmt) walletStorage with
             | .success finalWalletStorage =>
                 .success finalWrapperStorage finalWalletStorage
             | .revert failure => .revert failure
         | .revert failure => .revert failure)
  | _, _, _ => none

/--
Execution-side equivalence: running the three reflected phases of
`integratedBehaviorSummary` under any environment and storage produces the
exact same `IntegratedResult` as `AAPQIntegration.validateIntegrated`.

This lifts the reflection from a *syntactic* program equality (each phase
reflects to the proved program) to a *semantic* execution equality (composing
the reflected programs produces the same `ExecResult`).
-/
theorem reflectedValidateIntegrated_eq_validateIntegrated
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : SoLean.Storage) :
    reflectedValidateIntegrated env input wrapperStorage walletStorage =
      some
        (AAPQIntegration.validateIntegrated env input wrapperStorage walletStorage) := by
  rfl

/--
The reflected `executePhase` reconstructs exactly the proved
`AAWallet.executeUserOp` for the user op projected from any `IntegratedInput`.
-/
theorem executePhase_reflects_executeUserOp
    (input : AAPQIntegration.IntegratedInput) :
    phaseToStmt input executePhase =
      some (AAWallet.executeUserOp (AAPQIntegration.toUserOp input)) := by
  rfl

/--
The reflected `integratedFullBehaviorSummary` reconstructs the four programs
composed by `AAPQIntegration.validateAndExecute`: wrapper validation,
key-match guard, wallet validation, and the modeled execute step.
-/
theorem integratedFullBehaviorSummary_reflects_validateAndExecuteFlow
    (input : AAPQIntegration.IntegratedInput) :
    integratedFullBehaviorSummary.phases.map (phaseToStmt input) =
      [ some
          (PQVerifierWrapper.verifyProgram
            (AAPQIntegration.toWrapperInput input)),
        some (AAPQIntegration.keyMatchesWalletProgram input),
        some (AAWallet.validateProgram (AAPQIntegration.toUserOp input)),
        some (AAWallet.executeUserOp (AAPQIntegration.toUserOp input)) ] := by
  rfl

/--
The reflected v1 full behavior summary reconstructs the four programs composed
by `AAPQIntegration.validateAndExecuteV1`, with `walletV1Phase` exposing the
extra stored-wrapper-address guard.
-/
theorem integratedV1FullBehaviorSummary_reflects_validateAndExecuteV1Flow
    (input : AAPQIntegration.IntegratedInputV1) :
    integratedV1FullBehaviorSummary.phases.map (phaseToStmtV1 input) =
      [ some
          (PQVerifierWrapper.verifyProgram
            (AAPQIntegration.toWrapperInput input.toIntegratedInput)),
        some (AAPQIntegration.keyMatchesWalletProgram input.toIntegratedInput),
        some (AAWallet.validateProgramV1 (AAPQIntegration.toUserOpV1 input)),
        some
          (AAWallet.executeUserOp
            (AAPQIntegration.toUserOp input.toIntegratedInput)) ] := by
  rfl

/--
Execute the four reflected phases of `integratedFullBehaviorSummary` in the
same composition pattern as `AAPQIntegration.validateAndExecute`.
-/
def reflectedValidateAndExecute
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : SoLean.Storage) :
    Option AAPQIntegration.IntegratedFullResult :=
  match phaseToStmt input wrapperPhase,
        phaseToStmt input keyMatchPhase,
        phaseToStmt input walletPhase,
        phaseToStmt input executePhase with
  | some wrapperStmt, some keyMatchStmt, some walletStmt, some executeStmt =>
      some
        (match
            (match SoLean.exec env wrapperStmt wrapperStorage with
             | .success finalWrapperStorage =>
                 match SoLean.exec env (.seq keyMatchStmt walletStmt) walletStorage with
                 | .success finalWalletStorage =>
                     AAPQIntegration.IntegratedResult.success
                       finalWrapperStorage finalWalletStorage
                 | .revert failure => .revert failure
             | .revert failure => .revert failure) with
         | .success postWrapper postWallet =>
             match SoLean.exec env executeStmt postWallet with
             | .success finalWalletStorage =>
                 AAPQIntegration.IntegratedFullResult.success
                   postWrapper finalWalletStorage
             | .revert failure => .revert failure
         | .revert failure => .revert failure)
  | _, _, _, _ => none

/--
Execution-side equivalence for the full flow: running the four reflected
phases produces the same `IntegratedFullResult` as
`AAPQIntegration.validateAndExecute`.
-/
theorem reflectedValidateAndExecute_eq_validateAndExecute
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInput)
    (wrapperStorage walletStorage : SoLean.Storage) :
    reflectedValidateAndExecute env input wrapperStorage walletStorage =
      some
        (AAPQIntegration.validateAndExecute env input wrapperStorage walletStorage) := by
  rfl

/--
Execute the four reflected phases of `integratedV1FullBehaviorSummary` in the
same composition pattern as `AAPQIntegration.validateAndExecuteV1`.
-/
def reflectedValidateAndExecuteV1
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInputV1)
    (wrapperStorage walletStorage : SoLean.Storage) :
    Option AAPQIntegration.IntegratedFullResult :=
  match phaseToStmtV1 input wrapperPhase,
        phaseToStmtV1 input keyMatchPhase,
        phaseToStmtV1 input walletV1Phase,
        phaseToStmtV1 input executePhase with
  | some wrapperStmt, some keyMatchStmt, some walletStmt, some executeStmt =>
      some
        (match
            (match SoLean.exec env wrapperStmt wrapperStorage with
             | .success finalWrapperStorage =>
                 match SoLean.exec env (.seq keyMatchStmt walletStmt) walletStorage with
                 | .success finalWalletStorage =>
                     AAPQIntegration.IntegratedResult.success
                       finalWrapperStorage finalWalletStorage
                 | .revert failure => .revert failure
             | .revert failure => .revert failure) with
         | .success postWrapper postWallet =>
             match SoLean.exec env executeStmt postWallet with
             | .success finalWalletStorage =>
                 AAPQIntegration.IntegratedFullResult.success
                   postWrapper finalWalletStorage
             | .revert failure => .revert failure
         | .revert failure => .revert failure)
  | _, _, _, _ => none

/--
Execution-side equivalence for the v1 full flow: running the reflected v1
summary phases produces the same `IntegratedFullResult` as
`AAPQIntegration.validateAndExecuteV1`.
-/
theorem reflectedValidateAndExecuteV1_eq_validateAndExecuteV1
    (env : SoLean.Env)
    (input : AAPQIntegration.IntegratedInputV1)
    (wrapperStorage walletStorage : SoLean.Storage) :
    reflectedValidateAndExecuteV1 env input wrapperStorage walletStorage =
      some
        (AAPQIntegration.validateAndExecuteV1 env input wrapperStorage walletStorage) := by
  rfl

end BehaviorReflection

end AAPQSource
end Examples
end SoLean
