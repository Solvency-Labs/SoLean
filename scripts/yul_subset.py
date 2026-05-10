"""Tiny Yul-like subset used by the prototype scripts.

This is intentionally not a full Yul parser. It accepts only the deterministic
subset emitted by `solean_to_yul.py` and documented in `docs/yul-subset.md`.
"""

from __future__ import annotations

from dataclasses import dataclass
import re

try:
    from .normalize_yul import normalize_text
except ImportError:  # Allows direct execution of sibling scripts.
    from normalize_yul import normalize_text


class UnsupportedYulError(ValueError):
    """Raised when input is outside the supported prototype subset."""


@dataclass(frozen=True)
class Expr:
    text: str


@dataclass(frozen=True)
class Let:
    name: str
    expr: Expr


@dataclass(frozen=True)
class Store:
    slot: Expr
    value: Expr


@dataclass(frozen=True)
class IfRevert:
    cond: Expr


Stmt = Let | Store | IfRevert


@dataclass(frozen=True)
class Function:
    name: str
    params: tuple[str, ...]
    body: tuple[Stmt, ...]


@dataclass(frozen=True)
class YulObject:
    name: str
    function: Function


IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
SUPPORTED_CALLS = {
    "add": 2,
    "gt": 2,
    "iszero": 1,
    "lt": 2,
    "sload": 1,
}


def counter_object() -> YulObject:
    """Return the hand-authored Counter subset AST."""

    return YulObject(
        name="Counter",
        function=Function(
            name="inc",
            params=("amount",),
            body=(
                IfRevert(Expr("iszero(gt(amount, 0))")),
                Let("old_x", Expr("sload(0)")),
                Let("new_x", Expr("add(old_x, amount)")),
                IfRevert(Expr("lt(new_x, old_x)")),
                Store(Expr("0"), Expr("new_x")),
                IfRevert(Expr("lt(new_x, amount)")),
            ),
        ),
    )


def render_object(obj: YulObject) -> str:
    lines = [
        f'object "{obj.name}" {{',
        "  code {",
        f"    function {obj.function.name}({', '.join(obj.function.params)}) {{",
    ]
    for stmt in obj.function.body:
        lines.append(f"      {render_stmt(stmt)}")
    lines.extend(["    }", "  }", "}"])
    return "\n".join(lines) + "\n"


def render_stmt(stmt: Stmt) -> str:
    if isinstance(stmt, Let):
        return f"let {stmt.name} := {stmt.expr.text}"
    if isinstance(stmt, Store):
        return f"sstore({stmt.slot.text}, {stmt.value.text})"
    if isinstance(stmt, IfRevert):
        return f"if {stmt.cond.text} {{ revert(0, 0) }}"
    raise TypeError(f"unsupported statement: {stmt!r}")


def parse_object(text: str) -> YulObject:
    lines = normalize_text(text).splitlines()
    if len(lines) < 5:
        raise UnsupportedYulError("expected object/code/function wrapper")

    object_match = re.fullmatch(r'object "([^"]+)" \{', lines[0])
    if object_match is None:
        raise UnsupportedYulError("expected object header")
    if lines[1] != "code {":
        raise UnsupportedYulError("expected code block")

    function_match = re.fullmatch(rf"function ({IDENT})\(([^)]*)\) \{{", lines[2])
    if function_match is None:
        raise UnsupportedYulError("expected single function header")

    if lines[-3:] != ["}", "}", "}"]:
        raise UnsupportedYulError("expected function/code/object closing braces")

    params = tuple(_parse_params(function_match.group(2)))
    body = tuple(parse_stmt(line) for line in lines[3:-3])
    return YulObject(
        name=object_match.group(1),
        function=Function(function_match.group(1), params, body),
    )


def _parse_params(raw: str) -> list[str]:
    if not raw.strip():
        return []
    params = [part.strip() for part in raw.split(",")]
    for param in params:
        if re.fullmatch(IDENT, param) is None:
            raise UnsupportedYulError(f"unsupported parameter: {param}")
    return params


def parse_stmt(line: str) -> Stmt:
    let_match = re.fullmatch(rf"let ({IDENT}) := (.+)", line)
    if let_match:
        return Let(let_match.group(1), parse_expr(let_match.group(2)))

    store_match = re.fullmatch(r"sstore\((.+), (.+)\)", line)
    if store_match:
        return Store(parse_expr(store_match.group(1)), parse_expr(store_match.group(2)))

    if_match = re.fullmatch(r"if (.+) \{ revert\(0, 0\) \}", line)
    if if_match:
        return IfRevert(parse_expr(if_match.group(1)))

    raise UnsupportedYulError(f"unsupported statement: {line}")


def parse_expr(raw: str) -> Expr:
    text = raw.strip()
    _validate_expr(text)
    return Expr(text)


def _validate_expr(text: str) -> None:
    if re.fullmatch(r"[0-9]+", text) or re.fullmatch(IDENT, text):
        return

    name, args = _split_call(text)
    expected = SUPPORTED_CALLS.get(name)
    if expected is None:
        raise UnsupportedYulError(f"unsupported expression function: {name}")
    if len(args) != expected:
        raise UnsupportedYulError(
            f"{name} expects {expected} argument(s), got {len(args)}"
        )
    for arg in args:
        _validate_expr(arg)


def _split_call(text: str) -> tuple[str, list[str]]:
    match = re.fullmatch(rf"({IDENT})\((.*)\)", text)
    if match is None:
        raise UnsupportedYulError(f"unsupported expression: {text}")

    args = _split_args(match.group(2))
    return match.group(1), args


def _split_args(raw: str) -> list[str]:
    args: list[str] = []
    depth = 0
    start = 0
    for index, char in enumerate(raw):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth < 0:
                raise UnsupportedYulError("unbalanced expression parentheses")
        elif char == "," and depth == 0:
            args.append(raw[start:index].strip())
            start = index + 1

    if depth != 0:
        raise UnsupportedYulError("unbalanced expression parentheses")

    tail = raw[start:].strip()
    if tail:
        args.append(tail)
    return args
