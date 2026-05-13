"""Tiny Yul-like subset used by the prototype scripts.

This is intentionally not a full Yul parser or semantic model. It accepts only
the deterministic subset emitted by `solean_to_yul.py` and documented in
`docs/yul-subset.md`.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any, Union

try:
    from .normalize_yul import normalize_text
except ImportError:  # Allows direct execution of sibling scripts.
    from normalize_yul import normalize_text


class UnsupportedYulError(ValueError):
    """Raised when input is outside the supported prototype subset."""


class YulExecutionError(ValueError):
    """Raised when a supported AST cannot be executed by the tiny interpreter."""


@dataclass(frozen=True)
class Literal:
    value: int


@dataclass(frozen=True)
class Ident:
    name: str


@dataclass(frozen=True)
class Call:
    name: str
    args: tuple[Expr, ...]


Expr = Union[Literal, Ident, Call]


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


Stmt = Union[Let, Store, IfRevert]


@dataclass(frozen=True)
class Function:
    name: str
    params: tuple[str, ...]
    body: tuple[Stmt, ...]


@dataclass(frozen=True)
class YulObject:
    name: str
    function: Function


@dataclass(frozen=True)
class ExecutionResult:
    reverted: bool
    storage: dict[int, int]


@dataclass(frozen=True)
class TraceCase:
    amount: int
    slot0: int


@dataclass(frozen=True)
class TraceResult:
    reverted: bool
    slot0: int


@dataclass(frozen=True)
class TraceDiff:
    case: TraceCase
    left: TraceResult
    right: TraceResult


@dataclass(frozen=True)
class SymConst:
    value: int


@dataclass(frozen=True)
class SymParam:
    name: str


@dataclass(frozen=True)
class SymSlot:
    slot: int


@dataclass(frozen=True)
class SymCall:
    name: str
    args: tuple[SymExpr, ...]


SymExpr = Union[SymConst, SymParam, SymSlot, SymCall]


@dataclass(frozen=True)
class SymbolicSummary:
    object_name: str
    function_name: str
    params: tuple[str, ...]
    revert_conditions: tuple[SymExpr, ...]
    final_writes: tuple[tuple[int, SymExpr], ...]


@dataclass(frozen=True)
class SymbolicDiff:
    left: SymbolicSummary
    right: SymbolicSummary


IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
SUPPORTED_CALLS = {
    "add": 2,
    "gt": 2,
    "iszero": 1,
    "lt": 2,
    "sload": 1,
}
UINT256_MODULUS = 2**256
UINT256_MAX = UINT256_MODULUS - 1


def counter_object() -> YulObject:
    """Return the hand-authored Counter subset AST.

    This mirrors `SoLean.Examples.CounterYul.counterProgram` on the Lean side.
    Tests keep this Python structure aligned with that proved Counter shape.
    """

    amount = Ident("amount")
    old_x = Ident("old_x")
    new_x = Ident("new_x")
    zero = Literal(0)

    return YulObject(
        name="Counter",
        function=Function(
            name="inc",
            params=("amount",),
            body=(
                IfRevert(Call("iszero", (Call("gt", (amount, zero)),))),
                Let("old_x", Call("sload", (zero,))),
                Let("new_x", Call("add", (old_x, amount))),
                IfRevert(Call("lt", (new_x, old_x))),
                Store(zero, new_x),
                IfRevert(Call("lt", (new_x, amount))),
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


def object_to_data(obj: YulObject) -> dict[str, Any]:
    """Return a deterministic JSON-like structural view of a Yul object."""

    return {
        "object": obj.name,
        "function": {
            "name": obj.function.name,
            "params": list(obj.function.params),
            "body": [stmt_to_data(stmt) for stmt in obj.function.body],
        },
    }


def object_from_data(data: dict[str, Any]) -> YulObject:
    """Build a restricted Yul object from a Lean-exported JSON-like shape."""

    function_data = data["function"]
    return YulObject(
        name=data["object"],
        function=Function(
            function_data["name"],
            tuple(function_data["params"]),
            tuple(stmt_from_data(stmt) for stmt in function_data["body"]),
        ),
    )


def stmt_to_data(stmt: Stmt) -> dict[str, Any]:
    if isinstance(stmt, Let):
        return {
            "stmt": "let",
            "name": stmt.name,
            "expr": expr_to_data(stmt.expr),
        }
    if isinstance(stmt, Store):
        return {
            "stmt": "sstore",
            "slot": expr_to_data(stmt.slot),
            "value": expr_to_data(stmt.value),
        }
    if isinstance(stmt, IfRevert):
        return {
            "stmt": "ifRevert",
            "cond": expr_to_data(stmt.cond),
        }
    raise TypeError(f"unsupported statement: {stmt!r}")


def stmt_from_data(data: dict[str, Any]) -> Stmt:
    tag = data["stmt"]
    if tag == "let":
        return Let(data["name"], expr_from_data(data["expr"]))
    if tag == "sstore":
        return Store(expr_from_data(data["slot"]), expr_from_data(data["value"]))
    if tag == "ifRevert":
        return IfRevert(expr_from_data(data["cond"]))
    raise UnsupportedYulError(f"unsupported statement data: {tag}")


def expr_to_data(expr: Expr) -> dict[str, Any]:
    if isinstance(expr, Literal):
        return {"const": expr.value}
    if isinstance(expr, Ident):
        return {"ident": expr.name}
    if isinstance(expr, Call):
        return {
            "call": expr.name,
            "args": [expr_to_data(arg) for arg in expr.args],
        }
    raise TypeError(f"unsupported expression: {expr!r}")


def expr_from_data(data: dict[str, Any]) -> Expr:
    if "const" in data:
        return Literal(data["const"])
    if "ident" in data:
        return Ident(data["ident"])
    if "call" in data:
        return Call(data["call"], tuple(expr_from_data(arg) for arg in data["args"]))
    raise UnsupportedYulError(f"unsupported expression data: {data}")


def render_stmt(stmt: Stmt) -> str:
    if isinstance(stmt, Let):
        return f"let {stmt.name} := {render_expr(stmt.expr)}"
    if isinstance(stmt, Store):
        return f"sstore({render_expr(stmt.slot)}, {render_expr(stmt.value)})"
    if isinstance(stmt, IfRevert):
        return f"if {render_expr(stmt.cond)} {{ revert(0, 0) }}"
    raise TypeError(f"unsupported statement: {stmt!r}")


def render_expr(expr: Expr) -> str:
    if isinstance(expr, Literal):
        return str(expr.value)
    if isinstance(expr, Ident):
        return expr.name
    if isinstance(expr, Call):
        return f"{expr.name}({', '.join(render_expr(arg) for arg in expr.args)})"
    raise TypeError(f"unsupported expression: {expr!r}")


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

    if line.startswith("sstore(") and line.endswith(")"):
        name, args = _split_call(line)
        if name != "sstore" or len(args) != 2:
            raise UnsupportedYulError("expected sstore with two arguments")
        return Store(parse_expr(args[0]), parse_expr(args[1]))

    if_match = re.fullmatch(r"if (.+) \{ revert\(0, 0\) \}", line)
    if if_match:
        return IfRevert(parse_expr(if_match.group(1)))

    raise UnsupportedYulError(f"unsupported statement: {line}")


def parse_expr(raw: str) -> Expr:
    text = raw.strip()
    if re.fullmatch(r"[0-9]+", text):
        return Literal(int(text))
    if re.fullmatch(r"0[xX][0-9a-fA-F]+", text):
        return Literal(int(text, 16))
    if re.fullmatch(IDENT, text):
        return Ident(text)

    name, arg_texts = _split_call(text)
    expected = SUPPORTED_CALLS.get(name)
    if expected is None:
        raise UnsupportedYulError(f"unsupported expression function: {name}")
    if len(arg_texts) != expected:
        raise UnsupportedYulError(
            f"{name} expects {expected} argument(s), got {len(arg_texts)}"
        )
    return Call(name, tuple(parse_expr(arg) for arg in arg_texts))


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


def execute_object(
    obj: YulObject, args: dict[str, int], storage: dict[int, int]
) -> ExecutionResult:
    """Run the tiny bounded interpreter over one supported subset function."""

    env = dict(args)
    current_storage = dict(storage)
    for stmt in obj.function.body:
        if isinstance(stmt, Let):
            env[stmt.name] = eval_expr(stmt.expr, env, current_storage)
        elif isinstance(stmt, Store):
            slot = eval_expr(stmt.slot, env, current_storage)
            value = eval_expr(stmt.value, env, current_storage)
            current_storage[slot] = value % UINT256_MODULUS
        elif isinstance(stmt, IfRevert):
            if eval_expr(stmt.cond, env, current_storage) != 0:
                return ExecutionResult(reverted=True, storage=current_storage)
        else:
            raise YulExecutionError(f"unsupported statement: {stmt!r}")
    return ExecutionResult(reverted=False, storage=current_storage)


def eval_expr(expr: Expr, env: dict[str, int], storage: dict[int, int]) -> int:
    """Evaluate one typed subset expression with EVM-style UInt256 add."""

    if isinstance(expr, Literal):
        return expr.value
    if isinstance(expr, Ident):
        if expr.name not in env:
            raise YulExecutionError(f"unknown identifier: {expr.name}")
        return env[expr.name]
    if not isinstance(expr, Call):
        raise YulExecutionError(f"unsupported expression: {expr!r}")

    values = tuple(eval_expr(arg, env, storage) for arg in expr.args)
    if expr.name == "add":
        return (values[0] + values[1]) % UINT256_MODULUS
    if expr.name == "gt":
        return int(values[0] > values[1])
    if expr.name == "iszero":
        return int(values[0] == 0)
    if expr.name == "lt":
        return int(values[0] < values[1])
    if expr.name == "sload":
        return storage.get(values[0], 0)
    raise YulExecutionError(f"unsupported expression function: {expr.name}")


def counter_trace_cases() -> tuple[TraceCase, ...]:
    """Finite smoke-test inputs for the current Counter compiler path."""

    return (
        TraceCase(amount=0, slot0=0),
        TraceCase(amount=1, slot0=0),
        TraceCase(amount=3, slot0=5),
        TraceCase(amount=1, slot0=UINT256_MAX - 1),
        TraceCase(amount=1, slot0=UINT256_MAX),
        TraceCase(amount=2, slot0=UINT256_MAX - 1),
    )


def run_counter_trace(obj: YulObject, case: TraceCase) -> TraceResult:
    """Execute one Counter-shaped trace case over storage slot 0."""

    if len(obj.function.params) != 1:
        raise YulExecutionError("bounded trace checker expects one function parameter")

    param = obj.function.params[0]
    result = execute_object(obj, {param: case.amount}, {0: case.slot0})
    return TraceResult(reverted=result.reverted, slot0=result.storage.get(0, 0))


def compare_counter_traces(
    left: YulObject,
    right: YulObject,
    cases: tuple[TraceCase, ...] | None = None,
) -> list[TraceDiff]:
    """Compare two objects on the finite Counter trace set.

    This is a bounded regression checker for the prototype, not a proof of Yul
    equivalence.
    """

    diffs: list[TraceDiff] = []
    for case in cases or counter_trace_cases():
        left_result = run_counter_trace(left, case)
        right_result = run_counter_trace(right, case)
        if left_result != right_result:
            diffs.append(TraceDiff(case, left_result, right_result))
    return diffs


def summarize_symbolic(obj: YulObject) -> SymbolicSummary:
    """Summarize storage behavior for the tiny restricted subset.

    This is a deliberately small state-transform model. It tracks function
    parameters, symbolic initial storage slots, ordered revert conditions, and
    final storage writes. It is not a proof and does not simplify expressions.
    """

    env: dict[str, SymExpr] = {param: SymParam(param) for param in obj.function.params}
    storage: dict[int, SymExpr] = {}
    reverts: list[SymExpr] = []

    for stmt in obj.function.body:
        if isinstance(stmt, Let):
            env[stmt.name] = symbolic_eval_expr(stmt.expr, env, storage)
        elif isinstance(stmt, IfRevert):
            reverts.append(symbolic_eval_expr(stmt.cond, env, storage))
        elif isinstance(stmt, Store):
            slot = symbolic_eval_expr(stmt.slot, env, storage)
            if not isinstance(slot, SymConst):
                raise YulExecutionError(
                    f"symbolic checker supports only constant sstore slots: {slot!r}"
                )
            storage[slot.value] = symbolic_eval_expr(stmt.value, env, storage)
        else:
            raise YulExecutionError(f"unsupported statement: {stmt!r}")

    return SymbolicSummary(
        object_name=obj.name,
        function_name=obj.function.name,
        params=obj.function.params,
        revert_conditions=tuple(reverts),
        final_writes=tuple(sorted(storage.items())),
    )


def symbolic_eval_expr(
    expr: Expr, env: dict[str, SymExpr], storage: dict[int, SymExpr]
) -> SymExpr:
    if isinstance(expr, Literal):
        return SymConst(expr.value)
    if isinstance(expr, Ident):
        if expr.name not in env:
            raise YulExecutionError(f"unknown identifier: {expr.name}")
        return env[expr.name]
    if not isinstance(expr, Call):
        raise YulExecutionError(f"unsupported expression: {expr!r}")

    args = tuple(symbolic_eval_expr(arg, env, storage) for arg in expr.args)
    if expr.name == "sload":
        slot = args[0]
        if isinstance(slot, SymConst):
            return storage.get(slot.value, SymSlot(slot.value))
    if expr.name in SUPPORTED_CALLS:
        return SymCall(expr.name, args)
    raise YulExecutionError(f"unsupported expression function: {expr.name}")


def sym_expr_to_data(expr: SymExpr) -> dict[str, Any]:
    if isinstance(expr, SymConst):
        return {"const": expr.value}
    if isinstance(expr, SymParam):
        return {"param": expr.name}
    if isinstance(expr, SymSlot):
        return {"slot": expr.slot}
    if isinstance(expr, SymCall):
        return {
            "args": [sym_expr_to_data(arg) for arg in expr.args],
            "call": expr.name,
        }
    raise YulExecutionError(f"unsupported symbolic expression: {expr!r}")


def symbolic_summary_to_data(summary: SymbolicSummary) -> dict[str, Any]:
    """Serialize a symbolic summary into the Lean-owned behavior summary shape."""

    return {
        "finalWrites": [
            {"slot": slot, "value": sym_expr_to_data(value)}
            for slot, value in summary.final_writes
        ],
        "function": summary.function_name,
        "kind": "counterBehaviorSummary",
        "lean": "SoLean.Examples.CounterYul.counterProgram",
        "object": summary.object_name,
        "params": list(summary.params),
        "revertConditions": [
            sym_expr_to_data(cond) for cond in summary.revert_conditions
        ],
        "version": 1,
    }


def compare_symbolic_summaries(left: YulObject, right: YulObject) -> list[SymbolicDiff]:
    left_summary = summarize_symbolic(left)
    right_summary = summarize_symbolic(right)
    if left_summary == right_summary:
        return []
    return [SymbolicDiff(left_summary, right_summary)]
