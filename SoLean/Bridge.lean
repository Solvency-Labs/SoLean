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
end Bridge
end SoLean
