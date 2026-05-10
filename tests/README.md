# Tests

There is no standalone test suite yet.

Current checks:

- `lake build` checks the Lean DSL, semantics, examples, and Counter theorem.
- `python3 -m compileall scripts` checks the placeholder Python tools parse.

Future tests should add small golden files for normalization and equivalence
checking before adding broader generated examples.
