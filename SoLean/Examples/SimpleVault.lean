import SoLean.Specs

namespace SoLean
namespace Examples
namespace SimpleVault

def totalAssetsSlot : Slot := 0
def totalSharesSlot : Slot := 1

def totalAssetsExpr : ValueExpr :=
  .slot totalAssetsSlot

def totalSharesExpr : ValueExpr :=
  .slot totalSharesSlot

/--
First-pass SoLean model of `deposit`.

No safety theorem is provided yet. The expected future theorem should assume or
establish the invariant `totalAssets >= totalShares` before proving that the
post-assertion is safe.
-/
def depositProgram (assets : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const assets) (.const 0)))
    (.seq
      (.assign totalAssetsSlot (.add totalAssetsExpr (.const assets)))
      (.seq
        (.assign totalSharesSlot (.add totalSharesExpr (.const assets)))
        (.assert (.ge totalAssetsExpr totalSharesExpr))))

/--
First-pass SoLean model of `withdraw`.

`Nat` subtraction is only a placeholder for checked uint256 subtraction; the
requires mirror the Solidity guards in the example.
-/
def withdrawProgram (shares : UInt256) : Stmt :=
  .seq
    (.require (.gt (.const shares) (.const 0)))
    (.seq
      (.require (.ge totalSharesExpr (.const shares)))
      (.seq
        (.require (.ge totalAssetsExpr (.const shares)))
        (.seq
          (.assign totalAssetsSlot (.sub totalAssetsExpr (.const shares)))
          (.seq
            (.assign totalSharesSlot (.sub totalSharesExpr (.const shares)))
            (.assert (.ge totalAssetsExpr totalSharesExpr))))))

-- TODO: prove deposit and withdraw preserve `totalAssets >= totalShares`.

end SimpleVault
end Examples
end SoLean
