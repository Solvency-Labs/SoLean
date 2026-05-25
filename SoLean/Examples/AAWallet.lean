import SoLean.Specs

namespace SoLean
namespace Examples
namespace AAWallet

def nonceSlot : Slot := 0
def keyCommitmentSlot : Slot := 1
def domainSlot : Slot := 2
def entryPointSlot : Slot := 3
def lastOpHashSlot : Slot := 4
/-- Declared storage slot for the verifier wrapper's address.

The current `validateProgram` does not read this slot; it exists so the
FalconSimpleWallet deployment view can declare the wallet's
`wrapperAddress` alongside its other configuration slots. A future
milestone can extend `validateProgram` to assert the wallet's stored
wrapper address matches the address the integration actually calls. -/
def wrapperAddressSlot : Slot := 5

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

def wrapperAddressExpr : ValueExpr :=
  .slot wrapperAddressSlot

/--
Extended user operation carrying the wrapper address the integration
intends to call. This is the input shape FalconSimpleWallet v1's
`validateProgramV1` checks against the wallet's stored
`wrapperAddressSlot`.

Strictly extends `UserOp`; old code that uses `UserOp` keeps working.
-/
structure UserOpV1 extends UserOp where
  expectedWrapperAddress : UInt256
deriving Repr, DecidableEq

/--
v1 wallet validation: assert the wallet's stored wrapper address
matches the user op's declared expectation, then run the existing
`validateProgram`. The check goes *first* so a misconfigured wallet
(or a wrong-deployment UserOp) reverts before any state changes.

This is strictly stronger than `validateProgram` — successful
execution implies everything `validateProgram` did, plus that the
wallet's stored wrapper address equals `op.expectedWrapperAddress`.
-/
def validateProgramV1 (op : UserOpV1) : Stmt :=
  .seq
    (.require (.eq (.const op.expectedWrapperAddress) wrapperAddressExpr))
    (validateProgram op.toUserOp)

/--
Successful `validateProgramV1` implies:
- the wallet's stored wrapper address equals
  `op.expectedWrapperAddress` (the new v1 claim);
- the full `ValidationPost` for the underlying `UserOp` (everything
  v0 already proved: entry point, nonce, domain, verifier
  acceptance, nonce-add through checked arithmetic, key/domain/entry
  point storage unchanged).
-/
theorem validateV1_success_properties
    (env : Env) (storage finalStorage : Storage) (op : UserOpV1)
    (h :
      exec env (validateProgramV1 op) storage =
        ExecResult.success finalStorage) :
    op.expectedWrapperAddress = storage.read wrapperAddressSlot ∧
      ValidationPost op.toUserOp env storage finalStorage := by
  by_cases hAddr :
      op.expectedWrapperAddress = storage.read wrapperAddressSlot
  · have hInner :
        exec env (validateProgram op.toUserOp) storage =
          ExecResult.success finalStorage := by
      simpa [validateProgramV1, wrapperAddressExpr, exec, evalBool,
        evalValue, hAddr] using h
    exact
      ⟨hAddr,
        validate_success_properties env storage finalStorage op.toUserOp
          hInner⟩
  · simp [validateProgramV1, wrapperAddressExpr, exec, evalBool,
      evalValue, hAddr] at h

theorem validate_ensures (op : UserOp) :
    FunctionEnsures (validateProgram op) (fun _ _ => True) (validatePost op) := by
  intro env storage _
  cases h :
      exec env (validateProgram op) storage with
  | success finalStorage =>
      exact validate_success_properties env storage finalStorage op h
  | revert _ =>
      trivial

/--
Modeled execute step that records the operation hash to `lastOpHashSlot`.

This is a deliberately tiny execute model: it stores `op.opHash` in a
dedicated storage slot, giving the gate theorems below something concrete to
say about the post-execute state. It does not model real EVM execute
semantics, calldata, gas, or external calls.
-/
def executeUserOp (op : UserOp) : Stmt :=
  .assign lastOpHashSlot (.const op.opHash)

/--
Validate-then-execute composition. Successful `fullFlow` requires successful
validation followed by the modeled execute step.
-/
def fullFlow (op : UserOp) : Stmt :=
  .seq (validateProgram op) (executeUserOp op)

/--
Execution gating: successful `fullFlow` implies validation succeeded with
some intermediate storage. There is no path to execute side-effects that
bypasses validation.
-/
private theorem fullFlow_step
    (env : Env) (storage : Storage) (op : UserOp) :
    exec env (fullFlow op) storage =
      (match exec env (validateProgram op) storage with
       | .success storage' => exec env (executeUserOp op) storage'
       | .revert failure => .revert failure) := rfl

theorem fullFlow_success_implies_validate_success
    (env : Env) (storage finalStorage : Storage) (op : UserOp)
    (h :
      exec env (fullFlow op) storage = ExecResult.success finalStorage) :
    ∃ midStorage,
      exec env (validateProgram op) storage =
        ExecResult.success midStorage := by
  cases hValidate : exec env (validateProgram op) storage with
  | success midStorage => exact ⟨midStorage, rfl⟩
  | revert failure =>
      rw [fullFlow_step, hValidate] at h
      cases h

/--
After a successful `fullFlow`, the modeled execute side-effect is observable:
the wallet's `lastOpHashSlot` records the operation hash that was validated.
Combined with `fullFlow_success_implies_validate_success`, this gives the
forward direction of execution gating: observing the execute write to slot 4
requires having satisfied every modeled validation guard.
-/
theorem fullFlow_success_records_opHash
    (env : Env) (storage finalStorage : Storage) (op : UserOp)
    (h :
      exec env (fullFlow op) storage = ExecResult.success finalStorage) :
    finalStorage.read lastOpHashSlot = op.opHash := by
  cases hValidate : exec env (validateProgram op) storage with
  | success midStorage =>
      rw [fullFlow_step, hValidate] at h
      have hExec :
          ExecResult.success
              (Storage.write midStorage lastOpHashSlot op.opHash) =
            ExecResult.success finalStorage := by
        show exec env (executeUserOp op) midStorage = _
        exact h
      cases hExec
      exact Storage.read_write_same midStorage lastOpHashSlot op.opHash
  | revert failure =>
      rw [fullFlow_step, hValidate] at h
      cases h

end AAWallet
end Examples
end SoLean
