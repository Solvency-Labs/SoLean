#!/usr/bin/env python3
"""Counter-only Solidity-to-SoLean sketch.

This is not a general Solidity parser. It tokenizes and validates one tiny
Counter-shaped subset, then emits a reference to the hand-written Lean model.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import re
import sys
from pathlib import Path


COUNTER_SNIPPET = """-- Counter-only sketch generated from examples/Counter.sol.
-- This references the hand-written model; it is not a verified Solidity parser.
import SoLean.Examples.Counter

#check SoLean.Examples.Counter.incProgram
#check SoLean.Examples.Counter.inc_assertion_safe
"""


class UnsupportedSolidityError(ValueError):
    """Raised when the Solidity input is outside the tiny Counter subset."""


@dataclass(frozen=True)
class Var:
    name: str


@dataclass(frozen=True)
class Number:
    value: int


SmallExpr = Var | Number


@dataclass(frozen=True)
class Comparison:
    left: SmallExpr
    op: str
    right: SmallExpr


@dataclass(frozen=True)
class Require:
    cond: Comparison


@dataclass(frozen=True)
class AddAssign:
    target: str
    source: str


@dataclass(frozen=True)
class Assert:
    cond: Comparison


Statement = Require | AddAssign | Assert


@dataclass(frozen=True)
class StateVar:
    typ: str
    visibility: str
    name: str


@dataclass(frozen=True)
class FunctionDef:
    name: str
    param_type: str
    param_name: str
    visibility: str
    body: tuple[Statement, ...]


@dataclass(frozen=True)
class Contract:
    pragma_version: str
    name: str
    state_vars: tuple[StateVar, ...]
    functions: tuple[FunctionDef, ...]


TOKEN_RE = re.compile(
    r">=|\+=|\^|[{}();]|\+|>|=|[0-9]+(?:\.[0-9]+)*|[A-Za-z_][A-Za-z0-9_]*"
)


class Parser:
    def __init__(self, tokens: list[str]) -> None:
        self.tokens = tokens
        self.index = 0

    def parse_contract(self) -> Contract:
        self.expect("pragma")
        self.expect("solidity")
        self.expect("^")
        version = self.expect_version()
        self.expect(";")
        self.expect("contract")
        name = self.expect_ident()
        self.expect("{")

        state_vars: list[StateVar] = []
        functions: list[FunctionDef] = []
        while not self.consume("}"):
            token = self.peek()
            if token == "uint256":
                state_vars.append(self.parse_state_var())
            elif token == "function":
                functions.append(self.parse_function())
            else:
                raise UnsupportedSolidityError(
                    f"expected uint256 state variable or function, got {token!r}"
                )

        self.expect_eof()
        return Contract(version, name, tuple(state_vars), tuple(functions))

    def parse_state_var(self) -> StateVar:
        typ = self.expect("uint256")
        visibility = self.expect("public")
        name = self.expect_ident()
        self.expect(";")
        return StateVar(typ, visibility, name)

    def parse_function(self) -> FunctionDef:
        self.expect("function")
        name = self.expect_ident()
        self.expect("(")
        param_type = self.expect("uint256")
        param_name = self.expect_ident()
        self.expect(")")
        visibility = self.expect("public")
        self.expect("{")

        body: list[Statement] = []
        while not self.consume("}"):
            body.append(self.parse_statement())
        return FunctionDef(name, param_type, param_name, visibility, tuple(body))

    def parse_statement(self) -> Statement:
        token = self.peek()
        if token == "require":
            self.advance()
            self.expect("(")
            cond = self.parse_comparison()
            self.expect(")")
            self.expect(";")
            return Require(cond)
        if token == "assert":
            self.advance()
            self.expect("(")
            cond = self.parse_comparison()
            self.expect(")")
            self.expect(";")
            return Assert(cond)

        target = self.expect_ident()
        self.expect("+=")
        source = self.expect_ident()
        self.expect(";")
        return AddAssign(target, source)

    def parse_comparison(self) -> Comparison:
        left = self.parse_small_expr()
        op = self.advance()
        if op not in {">", ">="}:
            raise UnsupportedSolidityError(f"unsupported comparison operator: {op}")
        right = self.parse_small_expr()
        return Comparison(left, op, right)

    def parse_small_expr(self) -> SmallExpr:
        token = self.advance()
        if re.fullmatch(r"[0-9]+", token):
            return Number(int(token))
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token):
            return Var(token)
        raise UnsupportedSolidityError(f"unsupported expression token: {token}")

    def expect(self, token: str) -> str:
        actual = self.advance()
        if actual != token:
            raise UnsupportedSolidityError(f"expected {token!r}, got {actual!r}")
        return actual

    def expect_ident(self) -> str:
        token = self.advance()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", token) is None:
            raise UnsupportedSolidityError(f"expected identifier, got {token!r}")
        return token

    def expect_version(self) -> str:
        token = self.advance()
        if re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", token) is None:
            raise UnsupportedSolidityError(f"expected semantic version, got {token!r}")
        return token

    def expect_eof(self) -> None:
        if self.index != len(self.tokens):
            raise UnsupportedSolidityError(
                f"unexpected trailing token: {self.tokens[self.index]!r}"
            )

    def consume(self, token: str) -> bool:
        if self.peek() == token:
            self.index += 1
            return True
        return False

    def peek(self) -> str:
        if self.index >= len(self.tokens):
            raise UnsupportedSolidityError("unexpected end of input")
        return self.tokens[self.index]

    def advance(self) -> str:
        token = self.peek()
        self.index += 1
        return token


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    source = re.sub(r"//.*", " ", source)
    return source


def tokenize(source: str) -> list[str]:
    clean = strip_comments(source)
    tokens: list[str] = []
    index = 0
    while index < len(clean):
        if clean[index].isspace():
            index += 1
            continue
        match = TOKEN_RE.match(clean, index)
        if match is None:
            raise UnsupportedSolidityError(
                f"unsupported character near: {clean[index:index + 20]!r}"
            )
        tokens.append(match.group(0))
        index = match.end()
    return tokens


def parse_counter(source: str) -> Contract:
    contract = Parser(tokenize(source)).parse_contract()
    validate_counter(contract)
    return contract


def validate_counter(contract: Contract) -> None:
    expected = Contract(
        pragma_version="0.8.20",
        name="Counter",
        state_vars=(StateVar("uint256", "public", "x"),),
        functions=(
            FunctionDef(
                name="inc",
                param_type="uint256",
                param_name="amount",
                visibility="public",
                body=(
                    Require(Comparison(Var("amount"), ">", Number(0))),
                    AddAssign("x", "amount"),
                    Assert(Comparison(Var("x"), ">=", Var("amount"))),
                ),
            ),
        ),
    )
    if contract != expected:
        raise UnsupportedSolidityError(
            "expected exactly Counter.x and inc(amount) with require/add/assert"
        )


def is_supported_counter(source: str) -> bool:
    try:
        parse_counter(source)
    except UnsupportedSolidityError:
        return False
    return True


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Solidity source file")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Write the generated Lean sketch to this file instead of stdout",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.source.exists():
        print(f"error: source file not found: {args.source}", file=sys.stderr)
        return 2

    source = args.source.read_text()
    try:
        parse_counter(source)
    except UnsupportedSolidityError as exc:
        print(f"unsupported Solidity input: {exc}", file=sys.stderr)
        return 2

    if args.output:
        args.output.write_text(COUNTER_SNIPPET)
    else:
        print(COUNTER_SNIPPET, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
