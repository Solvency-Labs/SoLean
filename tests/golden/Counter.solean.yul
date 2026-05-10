// Deterministic placeholder Yul-like output for SoLean.Examples.Counter.inc.
// This is not generated from Lean and is not bytecode-ready Yul.
// It mirrors the current checked-arithmetic intent for the Counter case study.
object "Counter" {
  code {
    function inc(amount) {
      if iszero(gt(amount, 0)) { revert(0, 0) }
      let old_x := sload(0)
      let new_x := add(old_x, amount)
      if lt(new_x, old_x) { revert(0, 0) }
      sstore(0, new_x)
      if lt(new_x, amount) { revert(0, 0) }
    }
  }
}
