namespace SoLean

def uint256MaxValue : Nat :=
  2 ^ 256 - 1

/--
`UInt256` is a bounded natural number.

The first prototype models Solidity 0.8.x checked arithmetic, not EVM
wraparound arithmetic. Arithmetic operations that would leave the range
`0 <= value <= 2^256 - 1` return `none` and are interpreted as reverts by the
execution semantics.
-/
structure UInt256 where
  toNat : Nat
  isValid : toNat <= uint256MaxValue

namespace UInt256

def maxValue : Nat :=
  uint256MaxValue

def inBounds (value : UInt256) : Prop :=
  value.toNat <= maxValue

def zero : UInt256 :=
  { toNat := 0, isValid := Nat.zero_le maxValue }

def one : UInt256 :=
  { toNat := 1, isValid := by decide }

instance : OfNat UInt256 0 where
  ofNat := zero

theorem ext {a b : UInt256} (h : a.toNat = b.toNat) : a = b := by
  cases a with
  | mk aValue aValid =>
    cases b with
    | mk bValue bValid =>
      simp at h
      subst bValue
      congr

instance : DecidableEq UInt256 := fun a b =>
  if h : a.toNat = b.toNat then
    isTrue (ext h)
  else
    isFalse (fun hEq => h (by cases hEq; rfl))

instance : Repr UInt256 where
  reprPrec value _ := repr value.toNat

instance : LE UInt256 where
  le a b := a.toNat <= b.toNat

instance : LT UInt256 where
  lt a b := a.toNat < b.toNat

instance decidableLE (a b : UInt256) : Decidable (a <= b) :=
  inferInstanceAs (Decidable (a.toNat <= b.toNat))

instance decidableLT (a b : UInt256) : Decidable (a < b) :=
  inferInstanceAs (Decidable (a.toNat < b.toNat))

def ofNat? (value : Nat) : Option UInt256 :=
  if h : value <= maxValue then
    some { toNat := value, isValid := h }
  else
    none

def checkedAdd (a b : UInt256) : Option UInt256 :=
  if h : a.toNat + b.toNat <= maxValue then
    some { toNat := a.toNat + b.toNat, isValid := h }
  else
    none

def checkedSub (a b : UInt256) : Option UInt256 :=
  if _h : b.toNat <= a.toNat then
    some
      { toNat := a.toNat - b.toNat,
        isValid := Nat.le_trans (Nat.sub_le a.toNat b.toNat) a.isValid }
  else
    none

def gt (a b : UInt256) : Bool :=
  decide (a > b)

def ge (a b : UInt256) : Bool :=
  decide (a >= b)

@[simp]
theorem zero_toNat : zero.toNat = 0 :=
  rfl

@[simp]
theorem one_toNat : one.toNat = 1 :=
  rfl

theorem checkedAdd_toNat {a b result : UInt256}
    (h : checkedAdd a b = some result) :
    result.toNat = a.toNat + b.toNat := by
  unfold checkedAdd at h
  split at h
  · cases h
    rfl
  · contradiction

theorem checkedAdd_ge_right {a b result : UInt256}
    (h : checkedAdd a b = some result) :
    b <= result := by
  show b.toNat <= result.toNat
  rw [checkedAdd_toNat h]
  rw [Nat.add_comm]
  exact Nat.le_add_right b.toNat a.toNat

theorem checkedAdd_ge_left {a b result : UInt256}
    (h : checkedAdd a b = some result) :
    a <= result := by
  show a.toNat <= result.toNat
  rw [checkedAdd_toNat h]
  exact Nat.le_add_right a.toNat b.toNat

theorem checkedSub_toNat {a b result : UInt256}
    (h : checkedSub a b = some result) :
    result.toNat = a.toNat - b.toNat := by
  unfold checkedSub at h
  split at h
  · cases h
    rfl
  · contradiction

theorem sub_le_sub_right {a b c : UInt256} (h : a <= b) :
    a.toNat - c.toNat <= b.toNat - c.toNat := by
  exact Nat.sub_le_sub_right h c.toNat

end UInt256

end SoLean
