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

## Restricted Yul Proof

The Counter case study now also has a hand-written restricted Yul model in
`SoLean/Examples/CounterYul.lean`.

The theorem `counter_refines_solean_success` proves that whenever the SoLean
Counter model succeeds, the restricted Yul Counter model succeeds with the same
final storage.

The theorem `counter_yul_success_assertion` proves the assertion property
directly for successful executions of the restricted Yul Counter model.

## Compiler Proof

The Counter case study now has a tiny verified compiler slice in
`SoLean/Examples/CounterCompiler.lean`.

The generic `counterFunction` source program has one parameter, `amount`.
The theorem `counter_instantiates_to_existing_model` proves that instantiating
it with an `amount` gives the existing SoLean `Counter.incProgram amount`.

The theorem `compile_counter_eq_counter_yul` proves that compiling this source
function produces the existing restricted Yul Counter program.

The theorem `compiled_counter_refines_solean_success` combines those pieces:
successful executions of the instantiated SoLean Counter source are reproduced
by the compiled restricted Yul program with the same final storage.

## Limitations

- The model is hand-written, not generated from Solidity.
- The proof is about the SoLean semantics, not solc output.
- The Solidity-to-SoLean script parses only a tiny Counter subset and references
  the hand-written Lean model.
- The restricted Yul proof is about hand-written Lean Yul data, not yet about
  parsed Python emitter output or real `solc` output.
- The compiler proof covers only the tiny Counter source shape.
- The Python Yul checker can compare a tiny symbolic state-transform summary
  and can still run bounded Counter-shaped traces, but neither mode is a proof
  of Yul equivalence.
