# SimpleVault Case Study

The SimpleVault case study models deposits and withdrawals over two storage
slots:

- `totalAssets` at slot `0`.
- `totalShares` at slot `1`.

## Invariant

The verified invariant is:

```text
totalShares <= totalAssets
```

This corresponds to the Solidity assertions written as
`totalAssets >= totalShares`.

## Deposit

The modeled `deposit(assets)` checks `assets > 0`, performs checked additions
to both storage slots, and asserts the invariant. The proof shows that every
successful execution preserves the invariant. Overflow in either addition
reverts with `Failure.arithmeticFailed`.

## Withdraw

The modeled `withdraw(shares)` checks:

- `shares > 0`
- `totalShares >= shares`
- `totalAssets >= shares`

It then performs checked subtraction from both storage slots and asserts the
invariant. The proof shows that every successful execution preserves the
invariant. Underflow reverts with `Failure.arithmeticFailed`, though the
modeled `require` guards rule it out on the successful path.

## Limitations

- The model is hand-written, not generated from Solidity.
- The proof is about the SoLean semantics, not solc output.
- The model does not include ERC-4626 rounding, fees, external calls,
  reentrancy, access control, events, or gas.
- The placeholder Yul pipeline is not a semantic equivalence proof.
