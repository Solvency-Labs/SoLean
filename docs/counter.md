# Counter Case Study

The Counter case study models this Solidity fragment:

```solidity
function inc(uint256 amount) public {
    require(amount > 0);
    x += amount;
    assert(x >= amount);
}
```

## Model

The hand-written SoLean model stores `x` at storage slot `0`. It checks
`amount > 0`, performs checked `uint256` addition, writes the new value of `x`,
and models the Solidity assertion as a SoLean `assert`.

Stored values are bounded `UInt256` values, so the storage model cannot contain
out-of-range integers.

Arithmetic overflow is not ignored. If the modeled addition exceeds
`2^256 - 1`, expression evaluation fails and execution reverts with
`Failure.arithmeticFailed`.

## Proven Property

The main theorem states that whenever the modeled `inc(amount)` execution
succeeds, the final storage satisfies:

```text
amount <= x
```

This is exactly the modeled assertion `x >= amount`.

## Limitations

- The model is hand-written, not generated from Solidity.
- The proof is about the SoLean semantics, not solc output.
- The placeholder Yul output is not yet connected to the Lean model by a
  verified compiler or semantic equivalence checker.
