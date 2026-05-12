import SoLean.Yul

namespace SoLean
namespace Bridge
namespace RequireHelper

/--
Source-side semantics of solc's `require_helper(cond)` helper.

This is the auditable Lean model of the trusted Python `requireHelperAsRevertGuard`
recognizer used by the Counter bridge report. The semantics is intentionally
tiny: succeed without writing state when the condition is truthy under the
restricted Lean Yul evaluator; revert otherwise, including when the condition
fails to evaluate.

This is not a model of arbitrary Solidity `require`. It captures only the
behavior that the Counter bridge rule relies on.
-/
def step (cond : Yul.Cond) (storage : Storage) (locals : Yul.Locals) :
    Yul.StepResult :=
  match Yul.evalCond storage locals cond with
  | some true => .ok storage locals
  | some false => .revert
  | none => .revert

/--
The target restricted Yul shape emitted by the Counter bridge rule for a
require helper: `if iszero(cond) { revert(0, 0) }`.
-/
def target (cond : Yul.Cond) : Yul.Stmt :=
  .ifRevert (.iszero cond)

/--
The trusted Counter bridge rule `requireHelperAsRevertGuard` is sound under
the restricted Lean Yul semantics: the source helper step and the target
revert-guard statement compute the same `StepResult` for every storage and
locals.

This does not prove that the Python solc-IR recognizer correctly identifies
`require_helper(condition)` calls inside real solc output. That is still a
trusted parser-level boundary. What this theorem does establish is that, once
recognized, replacing the helper with `if iszero(cond) { revert(0, 0) }` does
not change the modeled behavior.
-/
theorem target_refines_source
    (cond : Yul.Cond) (storage : Storage) (locals : Yul.Locals) :
    Yul.execStmt (target cond) storage locals = step cond storage locals := by
  unfold target step Yul.execStmt
  cases hCond : Yul.evalCond storage locals cond with
  | none =>
      simp [Yul.evalCond, hCond]
  | some value =>
      cases value <;> simp [Yul.evalCond, hCond]

end RequireHelper

namespace AssertHelper

/--
Source-side semantics of solc's `assert_helper(cond)` helper.

For the current Counter bridge, this is intentionally the same truthy-condition
step shape as `require_helper`: succeed without writing state when the
condition is truthy under the restricted Lean Yul evaluator, and revert
otherwise.

This is not a model of every Solidity panic/assert behavior. It captures only
the success/revert behavior that the Counter bridge rule relies on.
-/
def step (cond : Yul.Cond) (storage : Storage) (locals : Yul.Locals) :
    Yul.StepResult :=
  match Yul.evalCond storage locals cond with
  | some true => .ok storage locals
  | some false => .revert
  | none => .revert

/--
The direct restricted Yul target shape for an assertion helper:
`if iszero(cond) { revert(0, 0) }`.
-/
def target (cond : Yul.Cond) : Yul.Stmt :=
  .ifRevert (.iszero cond)

/--
The Counter solc output currently calls `assert_helper(iszero(bad))`. The
trusted Python bridge summarizes that into `if bad { revert(0, 0) }`.
-/
def targetForIszero (bad : Yul.Cond) : Yul.Stmt :=
  .ifRevert bad

/--
The direct assertion-helper rewrite is sound under the restricted Lean Yul
semantics.
-/
theorem target_refines_source
    (cond : Yul.Cond) (storage : Storage) (locals : Yul.Locals) :
    Yul.execStmt (target cond) storage locals = step cond storage locals := by
  unfold target step Yul.execStmt
  cases hCond : Yul.evalCond storage locals cond with
  | none =>
      simp [Yul.evalCond, hCond]
  | some value =>
      cases value <;> simp [Yul.evalCond, hCond]

/--
The Counter-specific assertion-helper rewrite is sound:
`assert_helper(iszero(bad))` has the same step result as
`if bad { revert(0, 0) }`.

This backs the current `assertHelperAsRevertGuard` bridge rule. It still does
not prove that the Python solc-IR recognizer correctly identifies the helper
inside real solc output; that parser-level boundary remains trusted.
-/
theorem targetForIszero_refines_source
    (bad : Yul.Cond) (storage : Storage) (locals : Yul.Locals) :
    Yul.execStmt (targetForIszero bad) storage locals =
      step (.iszero bad) storage locals := by
  unfold targetForIszero step Yul.execStmt
  cases hBad : Yul.evalCond storage locals bad with
  | none =>
      simp [Yul.evalCond, hBad]
  | some value =>
      cases value <;> simp [Yul.evalCond, hBad]

end AssertHelper

namespace CheckedAdd

/--
Source-side semantics of solc's `checked_add_t_uint256(lhs, rhs)` helper when
the result is bound to a local.

This models only the Counter bridge use case: both arguments are restricted Yul
expressions, arithmetic is Solidity-style checked `UInt256` addition, and
arithmetic failure reverts. It is not a general model of every solc helper or
panic payload.
-/
def step (target : String) (lhs rhs : Yul.Expr) (storage : Storage)
    (locals : Yul.Locals) : Yul.StepResult :=
  match Yul.evalExpr storage locals lhs, Yul.evalExpr storage locals rhs with
  | some lhsValue, some rhsValue =>
      match UInt256.checkedAdd lhsValue rhsValue with
      | some result => .ok storage (Yul.Locals.write locals target result)
      | none => .revert
  | _, _ => .revert

/--
Execute the restricted target shape used by the Counter bridge summary:
first bind the wrapping Yul `add`, then revert if the wrapped result is less
than the original left-hand side.
-/
def targetStep (target : String) (lhs rhs : Yul.Expr) (storage : Storage)
    (locals : Yul.Locals) : Yul.StepResult :=
  match Yul.execStmt (.let_ target (.add lhs rhs)) storage locals with
  | .ok storage' locals' =>
      Yul.execStmt (.ifRevert (.lt (.local target) lhs)) storage' locals'
  | .revert => .revert

/--
If checked `UInt256` addition fails, the wrapping Yul addition is below the
left-hand input. This is the arithmetic fact behind the Counter overflow guard.
-/
theorem wrapAdd_lt_of_checkedAdd_none {a b : UInt256}
    (h : UInt256.checkedAdd a b = none) :
    Yul.UInt256.wrapAdd a b < a := by
  by_cases hBound : a.toNat + b.toNat <= UInt256.maxValue
  · simp [UInt256.checkedAdd, hBound] at h
  · show (Yul.UInt256.wrapAdd a b).toNat < a.toNat
    unfold Yul.UInt256.wrapAdd Yul.UInt256.wrap
    simp
    let m := UInt256.maxValue + 1
    change (a.toNat + b.toNat) % m < a.toNat
    have ha : a.toNat <= UInt256.maxValue := by
      simpa [UInt256.maxValue] using a.isValid
    have hb : b.toNat <= UInt256.maxValue := by
      simpa [UInt256.maxValue] using b.isValid
    have hModLe : m <= a.toNat + b.toNat := by
      dsimp [m]
      omega
    have hSubLt : a.toNat + b.toNat - m < m := by
      dsimp [m]
      omega
    have hMod : (a.toNat + b.toNat) % m = a.toNat + b.toNat - m := by
      rw [Nat.mod_eq_sub_mod hModLe]
      exact Nat.mod_eq_of_lt hSubLt
    rw [hMod]
    dsimp [m]
    omega

/--
The Counter-specific checked-add bridge rule is sound under the restricted Lean
Yul semantics:

```text
let new_x := checked_add_t_uint256(old_x, amount)
```

is modeled by:

```text
let new_x := add(old_x, amount)
if lt(new_x, old_x) { revert(0, 0) }
```

This backs `checkedAddUInt256AsAddWithOverflowGuard`. It still does not prove
that the Python solc-IR recognizer correctly identifies `checked_add_t_uint256`
inside real solc output; that parser-level boundary remains trusted.
-/
theorem counterTarget_refines_source
    (storage : Storage) (locals : Yul.Locals) :
    targetStep "new_x" (.local "old_x") (.local "amount") storage locals =
      step "new_x" (.local "old_x") (.local "amount") storage locals := by
  unfold targetStep step
  cases hOld : locals "old_x" with
  | none =>
      simp [Yul.execStmt, Yul.evalExpr, hOld]
  | some oldX =>
      cases hAmount : locals "amount" with
      | none =>
          simp [Yul.execStmt, Yul.evalExpr, hOld, hAmount]
      | some amount =>
          cases hAdd : UInt256.checkedAdd oldX amount with
          | none =>
              have hOverflow : Yul.UInt256.wrapAdd oldX amount < oldX :=
                wrapAdd_lt_of_checkedAdd_none hAdd
              simp [Yul.execStmt, Yul.evalExpr, Yul.evalCond, hOld, hAmount,
                hAdd, hOverflow]
          | some result =>
              have hWrap : Yul.UInt256.wrapAdd oldX amount = result :=
                Yul.UInt256.wrapAdd_eq_of_checkedAdd hAdd
              have hOldLe : oldX <= result := UInt256.checkedAdd_ge_left hAdd
              have hNotOverflow : Not (result < oldX) := Nat.not_lt_of_ge hOldLe
              simp [Yul.execStmt, Yul.evalExpr, Yul.evalCond, hOld, hAmount,
                hAdd, hWrap, hNotOverflow]

end CheckedAdd

namespace StorageRead

/--
Source-side semantics of the current solc storage-read helper when its result
is bound to a local.

This is intentionally tiny: it models only the storage value returned by the
helper. It does not model packed storage, byte offsets, or arbitrary Solidity
storage layouts. The current Counter bridge instantiates this at slot `0`.
-/
def step (target : String) (slot : Slot) (storage : Storage)
    (locals : Yul.Locals) : Yul.StepResult :=
  .ok storage (Yul.Locals.write locals target (storage.read slot))

/--
The restricted Yul target shape for the storage-read helper:
`let target := sload(slot)`.
-/
def target (targetName : String) (slot : Slot) : Yul.Stmt :=
  .let_ targetName (.sload slot)

/--
The storage-read helper rewrite is sound under the restricted Lean Yul
semantics. This backs the current `storageReadSlot0AsSload` rule when
instantiated with slot `0`.

This does not prove that the Python solc-IR recognizer correctly identifies
the helper inside real solc output; that parser-level boundary remains trusted.
-/
theorem target_refines_source
    (targetName : String) (slot : Slot) (storage : Storage)
    (locals : Yul.Locals) :
    Yul.execStmt (target targetName slot) storage locals =
      step targetName slot storage locals := by
  simp [target, step, Yul.execStmt, Yul.evalExpr]

end StorageRead

namespace StorageWrite

/--
Source-side semantics of the current solc storage-write helper.

This is intentionally tiny: it evaluates the restricted Yul expression and
writes the resulting value to the requested slot. It does not model packed
storage, byte offsets, or arbitrary Solidity storage layouts. The current
Counter bridge instantiates this at slot `0`.
-/
def step (slot : Slot) (value : Yul.Expr) (storage : Storage)
    (locals : Yul.Locals) : Yul.StepResult :=
  match Yul.evalExpr storage locals value with
  | some evaluated => .ok (Storage.write storage slot evaluated) locals
  | none => .revert

/--
The restricted Yul target shape for the storage-write helper:
`sstore(slot, value)`.
-/
def target (slot : Slot) (value : Yul.Expr) : Yul.Stmt :=
  .sstore slot value

/--
The storage-write helper rewrite is sound under the restricted Lean Yul
semantics. This backs the current `storageUpdateSlot0AsSstore` rule when
instantiated with slot `0`.

This does not prove that the Python solc-IR recognizer correctly identifies
the helper inside real solc output; that parser-level boundary remains trusted.
-/
theorem target_refines_source
    (slot : Slot) (value : Yul.Expr) (storage : Storage)
    (locals : Yul.Locals) :
    Yul.execStmt (target slot value) storage locals =
      step slot value storage locals := by
  unfold target step Yul.execStmt
  cases hValue : Yul.evalExpr storage locals value with
  | none =>
      simp [hValue]
  | some evaluated =>
      simp [hValue]

end StorageWrite
end Bridge
end SoLean
