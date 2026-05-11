# Tests

Current checks:

- `lake build` checks the Lean DSL, semantics, examples, and Counter theorem.
- `python3 -m compileall scripts tests` checks that the placeholder Python tools
  and tests parse.
- `python3 -m unittest discover -s tests` checks the Yul normalizer, typed
  restricted-subset renderer/parser, symbolic state-transform checker behavior,
  bounded trace checker behavior, explicit AST/text checker modes, Counter Yul
  alignment against Lean-exported artifacts, and Counter Solidity source-shape
  alignment against Lean-exported artifacts.
- The tests also cover Yul subset classification for supported Counter Yul and
  representative unsupported solc-style wrapper/statement forms, including
  deployed-object inspection for solc-style IR.

Future tests should add small golden files for normalization and equivalence
checking before adding broader generated examples.
