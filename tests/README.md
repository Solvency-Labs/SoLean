# Tests

Current checks:

- `lake build` checks the Lean DSL, semantics, examples, and Counter theorem.
- `python3 -m compileall scripts tests` checks that the placeholder Python tools
  and tests parse.
- `python3 -m unittest discover -s tests` checks the Yul normalizer, typed
  restricted-subset renderer/parser, bounded trace checker behavior, explicit
  AST/text checker modes, Counter Yul structural/golden alignment, and
  Counter-only Solidity sketch.

Future tests should add small golden files for normalization and equivalence
checking before adding broader generated examples.
