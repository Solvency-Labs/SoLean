# Shared Source Shape Vocabulary

`SoLean.Source.Shape` contains the shared Solidity-shaped vocabulary used by
Lean-owned source artifacts.

Current shared types:

- `Param`
- `StorageSlot`
- `Contract`
- `IntegratedContract`

These types are audit metadata. They do not parse Solidity and they do not
claim semantic equivalence with Solidity source. Their job is to make source
artifacts name the same contract, storage, and parameter structure in a
consistent Lean-owned shape.

## Current Uses

- Counter source artifacts use `Source.Shape.Contract`, `Param`, and
  `StorageSlot` while preserving the existing Counter JSON schema.
- `SoLean.Examples.AAPQSource` uses the same vocabulary for its wallet,
  wrapper, and integrated two-contract source description.

The AA/PQ behavior-summary DSL remains in `AAPQSource` because it is
case-study-specific: wrapper/key-match/wallet phases, guards, and final writes
are not yet a general source language.

## Non-Claims

This refactor does not add:

- verified Solidity parsing;
- new accepted Solidity syntax;
- external-call semantics;
- Yul generation or equivalence;
- a general source language for all contracts.

The value of the refactor is trust reduction by vocabulary sharing: Counter and
AA/PQ source artifacts no longer maintain separate definitions for the same
basic source-shape concepts.
