import SoLean.Specs

namespace SoLean
namespace Examples
namespace AAWallet

def nonceSlot : Slot := 0
def keyCommitmentSlot : Slot := 1
def domainSlot : Slot := 2
def entryPointSlot : Slot := 3

def nonceExpr : ValueExpr :=
  .slot nonceSlot

def keyCommitmentExpr : ValueExpr :=
  .slot keyCommitmentSlot

def domainExpr : ValueExpr :=
  .slot domainSlot

def entryPointExpr : ValueExpr :=
  .slot entryPointSlot

/--
Modeled user operation data for the first AA wallet validation case study.

All fields are `UInt256` placeholders. This model proves contract-level
validation logic only; it does not model real calldata, hashing, or PQ
signature bytes.
-/
structure UserOp where
  opHash : UInt256
  nonce : UInt256
  domain : UInt256
  signature : UInt256
deriving Repr, DecidableEq

/--
Focused AA wallet validation model.

The verifier is an abstract oracle in `Env`. Successful validation requires the
configured entry point caller, matching nonce and domain, verifier acceptance,
and a checked nonce increment.
-/
def validateProgram (op : UserOp) : Stmt :=
  .seq
    (.require (.eq .msgSender entryPointExpr))
    (.seq
      (.require (.eq (.const op.nonce) nonceExpr))
      (.seq
        (.require (.eq (.const op.domain) domainExpr))
        (.seq
          (.require
            (.verify
              keyCommitmentExpr
              (.const op.opHash)
              (.const op.domain)
              (.const op.signature)))
          (.assign nonceSlot (.add nonceExpr (.const UInt256.one))))))

def ValidationPost
    (op : UserOp) (env : Env) (storage finalStorage : Storage) : Prop :=
  env.msgSender = storage.read entryPointSlot ∧
  op.nonce = storage.read nonceSlot ∧
  op.domain = storage.read domainSlot ∧
  env.verifier
      (storage.read keyCommitmentSlot)
      op.opHash
      op.domain
      op.signature = true ∧
  UInt256.checkedAdd (storage.read nonceSlot) UInt256.one =
    some (finalStorage.read nonceSlot) ∧
  finalStorage.read keyCommitmentSlot = storage.read keyCommitmentSlot ∧
  finalStorage.read domainSlot = storage.read domainSlot ∧
  finalStorage.read entryPointSlot = storage.read entryPointSlot

/--
Successful validation implies every modeled AA guard passed.

Assumptions: this is a hand-written SoLean model with an abstract verifier
oracle. It is not EIP-4337 semantics and does not verify PQ cryptography.
-/
theorem validate_success_properties
    (env : Env) (storage finalStorage : Storage) (op : UserOp)
    (h :
      exec env (validateProgram op) storage =
        ExecResult.success finalStorage) :
    ValidationPost op env storage finalStorage := by
  by_cases hCaller : env.msgSender = storage.read entryPointSlot
  · by_cases hNonce : op.nonce = storage.read nonceSlot
    · by_cases hDomain : op.domain = storage.read domainSlot
      · by_cases hVerify :
          env.verifier
              (storage.read keyCommitmentSlot)
              op.opHash
              (storage.read domainSlot)
              op.signature = true
        · cases hAdd :
            UInt256.checkedAdd (storage.read nonceSlot) UInt256.one with
          | none =>
              simp [validateProgram, nonceExpr, keyCommitmentExpr, domainExpr,
                entryPointExpr, exec, evalBool, evalValue, hCaller, hNonce,
                hDomain, hVerify, hAdd] at h
          | some newNonce =>
              have hFinal :
                  ExecResult.success (Storage.write storage nonceSlot newNonce) =
                    ExecResult.success finalStorage := by
                simpa [validateProgram, nonceExpr, keyCommitmentExpr,
                  domainExpr, entryPointExpr, exec, evalBool, evalValue,
                  hCaller, hNonce, hDomain, hVerify, hAdd] using h
              cases hFinal
              have hVerifyPost :
                  env.verifier
                      (storage.read keyCommitmentSlot)
                      op.opHash
                      op.domain
                      op.signature = true := by
                simpa [hDomain] using hVerify
              refine ⟨hCaller, hNonce, hDomain, hVerifyPost, ?_, ?_, ?_, ?_⟩
              · simpa [nonceSlot, Storage.write] using hAdd
              · simp [nonceSlot, keyCommitmentSlot, Storage.write]
              · simp [nonceSlot, domainSlot, Storage.write]
              · simp [nonceSlot, entryPointSlot, Storage.write]
        · simp [validateProgram, nonceExpr, keyCommitmentExpr, domainExpr,
            entryPointExpr, exec, evalBool, evalValue, hCaller, hNonce,
            hDomain, hVerify] at h
      · simp [validateProgram, nonceExpr, domainExpr, entryPointExpr, exec,
          evalBool, evalValue, hCaller, hNonce, hDomain] at h
    · simp [validateProgram, nonceExpr, entryPointExpr, exec, evalBool,
        evalValue, hCaller, hNonce] at h
  · simp [validateProgram, entryPointExpr, exec, evalBool, evalValue, hCaller]
      at h

def validatePost (op : UserOp) : Post :=
  fun env storage finalStorage => ValidationPost op env storage finalStorage

theorem validate_ensures (op : UserOp) :
    FunctionEnsures (validateProgram op) (fun _ _ => True) (validatePost op) := by
  intro env storage _
  cases h :
      exec env (validateProgram op) storage with
  | success finalStorage =>
      exact validate_success_properties env storage finalStorage op h
  | revert _ =>
      trivial

end AAWallet
end Examples
end SoLean
