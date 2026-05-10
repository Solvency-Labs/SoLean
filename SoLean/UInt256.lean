namespace SoLean

/--
`UInt256` is modeled as `Nat` in the first prototype.

This intentionally does not model EVM 256-bit wraparound, Solidity checked
arithmetic, or overflow/underflow behavior. Case studies must state when this
approximation is being used.
-/
abbrev UInt256 := Nat

namespace UInt256

def zero : UInt256 := 0

def add (a b : UInt256) : UInt256 :=
  a + b

/--
Lean's `Nat` subtraction saturates at zero. Solidity `uint256` subtraction in
0.8.x reverts on underflow. The restricted examples should guard subtraction
with `require` until a precise checked-arithmetic model is introduced.
-/
def sub (a b : UInt256) : UInt256 :=
  a - b

def gt (a b : UInt256) : Bool :=
  decide (a > b)

def ge (a b : UInt256) : Bool :=
  decide (a >= b)

theorem amount_le_add_left (x amount : UInt256) : amount <= x + amount := by
  simpa [Nat.add_comm] using Nat.le_add_right amount x

end UInt256

end SoLean
