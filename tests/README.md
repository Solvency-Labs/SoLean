# Tests

There is no standalone test suite yet.

Current checks:

- `lake build` checks the Lean DSL, semantics, examples, and Counter theorem.
- `python3 -m compileall scripts` checks the placeholder Python tools parse.
- `python3 -m unittest discover -s tests` checks the Yul normalizer and current
  normalized-text equivalence behavior.

Future tests should add small golden files for normalization and equivalence
checking before adding broader generated examples.
