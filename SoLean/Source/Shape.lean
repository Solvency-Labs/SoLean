import SoLean.DSL

namespace SoLean
namespace Source
namespace Shape

/--
Solidity-shaped storage slot description.

This is documentation/audit data, not a verified parser output. It pins the
slot layout that Lean models assume so bridge artifacts can name trusted source
shapes explicitly.
-/
structure StorageSlot where
  name : String
  slot : Slot
  typeName : String
deriving Repr, DecidableEq

/-- Solidity-shaped function parameter description. -/
structure Param where
  name : String
  typeName : String
deriving Repr, DecidableEq

/--
Solidity-shaped single-contract description.

The body of the function is intentionally not stored here. Case-study modules
connect these source shapes to proved programs with separate theorems.
-/
structure Contract where
  name : String
  pragma : String
  storage : List StorageSlot
  functionName : String
  params : List Param
deriving Repr, DecidableEq

/--
Solidity-shaped two-contract integration description.

This captures the source-level shape shared by the current AA/PQ audit and any
future two-contract case study with separate wallet/wrapper-style boundaries.
-/
structure IntegratedContract where
  name : String
  pragma : String
  wallet : Contract
  wrapper : Contract
  integrationName : String
  params : List Param
deriving Repr, DecidableEq

end Shape
end Source
end SoLean
