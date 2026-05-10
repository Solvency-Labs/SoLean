namespace SoLean

/--
`UInt256` is modeled as `Nat` in the first prototype.

This keeps proofs lightweight while modeling the relevant Solidity 0.8.x
checked-arithmetic failures explicitly. Values are still not represented as a
bounded subtype, so case studies must state any assumptions about existing
storage values being valid `uint256` values.
-/
abbrev UInt256 := Nat

namespace UInt256

def maxValue : UInt256 :=
  2 ^ 256 - 1

def inBounds (value : UInt256) : Prop :=
  value <= maxValue

def zero : UInt256 := 0

def add (a b : UInt256) : UInt256 :=
  a + b

def sub (a b : UInt256) : UInt256 :=
  a - b

def checkedAdd (a b : UInt256) : Option UInt256 :=
  if a + b <= maxValue then
    some (a + b)
  else
    none

/--
Solidity 0.8.x checked subtraction reverts on underflow. Since existing storage
values are modeled as `Nat` rather than a bounded subtype, boundedness of stored
values remains a case-study assumption for now.
-/
def checkedSub (a b : UInt256) : Option UInt256 :=
  if b <= a then
    some (a - b)
  else
    none

def gt (a b : UInt256) : Bool :=
  decide (a > b)

def ge (a b : UInt256) : Bool :=
  decide (a >= b)

theorem amount_le_add_left (x amount : UInt256) : amount <= x + amount := by
  rw [Nat.add_comm]
  exact Nat.le_add_right amount x

theorem sub_le_sub_right {a b c : UInt256} (h : a <= b) :
    a - c <= b - c := by
  exact Nat.sub_le_sub_right h c

end UInt256

end SoLean
