#!/usr/bin/env python3
"""Classify Yul text against SoLean's current restricted subset."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Callable

try:
    from .normalize_yul import normalize_text
    from .yul_subset import (
        Call,
        Expr,
        Function,
        Ident,
        IfRevert,
        Let,
        Literal,
        Stmt,
        Store,
        UnsupportedYulError,
        YulObject,
        object_to_data,
        parse_expr,
        parse_object,
    )
except ImportError:  # Allows `python scripts/classify_yul.py ...`.
    from normalize_yul import normalize_text
    from yul_subset import (
        Call,
        Expr,
        Function,
        Ident,
        IfRevert,
        Let,
        Literal,
        Stmt,
        Store,
        UnsupportedYulError,
        YulObject,
        object_to_data,
        parse_expr,
        parse_object,
    )


@dataclass(frozen=True)
class Classification:
    kind: str
    message: str

    @property
    def is_supported(self) -> bool:
        return self.kind == "supported-subset"


@dataclass(frozen=True)
class SolcObjectBlock:
    name: str
    start_line: int
    end_line: int
    depth: int
    text: str


@dataclass(frozen=True)
class SolcFunctionBlock:
    name: str
    params: tuple[str, ...]
    start_line: int
    end_line: int
    text: str
    body_lines: tuple[tuple[int, str], ...]


@dataclass(frozen=True)
class SolcInspection:
    kind: str
    message: str
    objects: tuple[SolcObjectBlock, ...]
    selected_object: SolcObjectBlock | None
    selected_classification: Classification | None

    @property
    def is_supported(self) -> bool:
        return (
            self.selected_classification is not None
            and self.selected_classification.is_supported
        )


@dataclass(frozen=True)
class SolcFunctionInspection:
    kind: str
    message: str
    selected_object: SolcObjectBlock | None
    selected_function: SolcFunctionBlock | None
    selected_classification: Classification | None

    @property
    def is_supported(self) -> bool:
        return (
            self.selected_classification is not None
            and self.selected_classification.is_supported
        )


@dataclass(frozen=True)
class SolcFunctionSummary:
    selected_object: SolcObjectBlock
    selected_function: SolcFunctionBlock
    normalized_object: YulObject
    trusted_rules: tuple[str, ...]


UNSUPPORTED_STATEMENT_PREFIXES = (
    "case ",
    "default",
    "for ",
    "leave",
    "mstore(",
    "pop(",
    "return(",
    "revert(",
    "switch ",
)
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
OBJECT_HEADER_RE = re.compile(r'object "([^"]+)" \{')
FUNCTION_HEADER_RE = re.compile(rf"function ({IDENT})\(([^)]*)\)(?: -> [^{{]+)? \{{")
TRANSPARENT_VALUE_HELPER_RULES = {
    "cleanup_t_uint256": "cleanupUint256AsIdentity",
    "convert_t_rational_0_by_1_to_t_uint256":
        "convertRationalZeroByOneToUint256AsIdentity",
    "identity": "identityHelperAsIdentity",
    "cleanup_t_rational_0_by_1": "cleanupRationalZeroByOneAsIdentity",
}


def classify_text(text: str) -> Classification:
    try:
        obj = parse_object(text)
    except UnsupportedYulError as exc:
        return _classify_unsupported(text, exc)

    return Classification(
        "supported-subset",
        f"supported restricted subset: object {obj.name}, function {obj.function.name}",
    )


def inspect_solc_text(text: str) -> SolcInspection:
    """Inspect solc-style IR and classify the selected runtime object.

    This is a trusted extraction aid, not a verified solc parser. It identifies
    object blocks by brace matching after textual normalization, prefers a
    deployed/runtime object, and then runs the normal restricted-subset
    classifier on that block.
    """

    objects = find_object_blocks(text)
    if not objects:
        return SolcInspection(
            "parse-shape-failure",
            "no Yul object blocks found in solc output",
            (),
            None,
            None,
        )

    selected = select_runtime_object(objects)
    classification = classify_text(selected.text)
    return SolcInspection(
        classification.kind,
        (
            f"selected object {selected.name} at normalized lines "
            f"{selected.start_line}-{selected.end_line}: {classification.message}"
        ),
        tuple(objects),
        selected,
        classification,
    )


def inspect_solc_function_text(text: str, function_query: str) -> SolcFunctionInspection:
    """Inspect the selected solc runtime object and classify one function body."""

    objects = find_object_blocks(text)
    if not objects:
        return SolcFunctionInspection(
            "parse-shape-failure",
            "no Yul object blocks found in solc output",
            None,
            None,
            None,
        )

    selected_object = select_runtime_object(objects)
    functions = find_function_blocks(
        selected_object.text, line_offset=selected_object.start_line - 1
    )
    selected_function = select_function(functions, function_query)
    if selected_function is None:
        return SolcFunctionInspection(
            "parse-shape-failure",
            (
                f"no function matching {function_query!r} found in selected "
                f"object {selected_object.name}"
            ),
            selected_object,
            None,
            None,
        )

    classification = classify_function_body(selected_function)
    return SolcFunctionInspection(
        classification.kind,
        (
            f"selected object {selected_object.name}; selected function "
            f"{selected_function.name} at normalized lines "
            f"{selected_function.start_line}-{selected_function.end_line}: "
            f"{classification.message}"
        ),
        selected_object,
        selected_function,
        classification,
    )


def summarize_solc_function_text(text: str, function_query: str) -> SolcFunctionSummary:
    objects = find_object_blocks(text)
    if not objects:
        raise UnsupportedYulError("no Yul object blocks found in solc output")

    selected_object = select_runtime_object(objects)
    functions = find_function_blocks(
        selected_object.text, line_offset=selected_object.start_line - 1
    )
    selected_function = select_function(functions, function_query)
    if selected_function is None:
        raise UnsupportedYulError(
            f"no function matching {function_query!r} found in selected "
            f"object {selected_object.name}"
        )

    normalized_object, trusted_rules = normalize_counter_function_body(selected_function)
    return SolcFunctionSummary(
        selected_object=selected_object,
        selected_function=selected_function,
        normalized_object=normalized_object,
        trusted_rules=trusted_rules,
    )


def solc_function_summary_to_data(summary: SolcFunctionSummary) -> dict:
    return {
        "kind": "solcFunctionSummary",
        "sourceFunction": summary.selected_function.name,
        "sourceObject": summary.selected_object.name,
        "trustedRules": list(summary.trusted_rules),
        "normalized": object_to_data(summary.normalized_object),
    }


def find_object_blocks(text: str) -> list[SolcObjectBlock]:
    lines = normalize_text(text).splitlines()
    stack: list[tuple[str, int, int]] = []
    blocks: list[SolcObjectBlock] = []
    depth = 0

    for index, line in enumerate(lines, start=1):
        object_match = OBJECT_HEADER_RE.fullmatch(line)
        if object_match is not None:
            stack.append((object_match.group(1), index, depth))

        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][2]:
            name, start_line, object_depth = stack.pop()
            block_text = "\n".join(lines[start_line - 1 : index]) + "\n"
            blocks.append(
                SolcObjectBlock(
                    name=name,
                    start_line=start_line,
                    end_line=index,
                    depth=object_depth,
                    text=block_text,
                )
            )

    return sorted(blocks, key=lambda block: (block.start_line, block.depth))


def find_function_blocks(text: str, line_offset: int = 0) -> list[SolcFunctionBlock]:
    lines = normalize_text(text).splitlines()
    stack: list[tuple[str, tuple[str, ...], int, int]] = []
    blocks: list[SolcFunctionBlock] = []
    depth = 0

    for index, line in enumerate(lines, start=1):
        function_match = FUNCTION_HEADER_RE.fullmatch(line)
        if function_match is not None:
            stack.append(
                (
                    function_match.group(1),
                    parse_function_params(function_match.group(2)),
                    index,
                    depth,
                )
            )

        depth += line.count("{") - line.count("}")
        while stack and depth <= stack[-1][3]:
            name, params, start_line, _function_depth = stack.pop()
            block_lines = lines[start_line - 1 : index]
            body_lines = tuple(
                (line_offset + line_number, body_line)
                for line_number, body_line in enumerate(
                    lines[start_line : index - 1], start=start_line + 1
                )
            )
            blocks.append(
                SolcFunctionBlock(
                    name=name,
                    params=params,
                    start_line=line_offset + start_line,
                    end_line=line_offset + index,
                    text="\n".join(block_lines) + "\n",
                    body_lines=body_lines,
                )
            )

    return sorted(blocks, key=lambda block: block.start_line)


def parse_function_params(raw: str) -> tuple[str, ...]:
    if not raw.strip():
        return ()
    return tuple(part.strip() for part in raw.split(","))


def select_runtime_object(objects: list[SolcObjectBlock]) -> SolcObjectBlock:
    deployed = [block for block in objects if "deployed" in block.name.lower()]
    if deployed:
        return deployed[0]
    return max(objects, key=lambda block: (block.depth, block.start_line))


def select_function(
    functions: list[SolcFunctionBlock], function_query: str
) -> SolcFunctionBlock | None:
    scored: list[tuple[int, int, SolcFunctionBlock]] = []
    for function in functions:
        score = function_match_score(function.name, function_query)
        if score is not None:
            scored.append((score, function.start_line, function))
    if not scored:
        return None
    return sorted(scored, key=lambda item: (item[0], item[1]))[0][2]


def function_match_score(name: str, function_query: str) -> int | None:
    if name == function_query:
        return 0
    if name.startswith(f"fun_{function_query}_") or name == f"fun_{function_query}":
        return 1
    if (
        name.startswith(f"external_fun_{function_query}_")
        or name == f"external_fun_{function_query}"
    ):
        return 2
    if f"_{function_query}_" in name or name.endswith(f"_{function_query}"):
        return 3
    if function_query in name:
        return 4
    return None


def classify_function_body(function: SolcFunctionBlock) -> Classification:
    try:
        from .yul_subset import parse_stmt
    except ImportError:  # Allows `python scripts/classify_yul.py ...`.
        from yul_subset import parse_stmt

    for line_number, line in function.body_lines:
        if line in {"{", "}"}:
            continue
        summarized_line = summarize_solc_inspection_line(line)
        try:
            parse_stmt(summarized_line)
        except UnsupportedYulError as exc:
            classification = _classify_unsupported(summarized_line, exc)
            return Classification(
                classification.kind,
                f"line {line_number}: {classification.message}",
            )
    return Classification(
        "supported-subset",
        f"supported restricted subset function body: {function.name}",
    )


def normalize_counter_function_body(
    function: SolcFunctionBlock,
) -> tuple[YulObject, tuple[str, ...]]:
    """Summarize the real solc Counter `fun_inc_*` body into restricted Yul.

    This is a trusted, Counter-specific inspection pass. It recognizes only the
    narrow helper pattern emitted by solc 0.8.35 for the current Counter example.
    """

    if len(function.params) != 1:
        raise UnsupportedYulError("Counter function summary expects one parameter")

    env: dict[str, Expr] = {function.params[0]: Ident("amount")}
    storage: dict[int, Expr] = {}
    emitted: list[Stmt] = []
    trusted_rules: list[str] = []
    old_x_emitted = False
    new_x_emitted = False

    def add_rule(name: str) -> None:
        if name not in trusted_rules:
            trusted_rules.append(name)

    def record_text_rules(text: str) -> None:
        if re.search(r"\b0[xX][0-9a-fA-F]+\b", text):
            add_rule("hexLiteralAsNat")

    def record_transparent_helper(name: str) -> None:
        add_rule(TRANSPARENT_VALUE_HELPER_RULES[name])

    def resolve(expr: Expr) -> Expr:
        if isinstance(expr, Ident) and expr.name in env:
            return resolve(env[expr.name])
        if isinstance(expr, Call):
            return Call(expr.name, tuple(resolve(arg) for arg in expr.args))
        return expr

    def parse_supported_expr(raw: str) -> Expr:
        record_text_rules(raw)
        return resolve(parse_expr(
            summarize_transparent_helpers(raw, record_transparent_helper)
        ))

    def literal_value(raw: str) -> int:
        expr = parse_supported_expr(raw)
        if not isinstance(expr, Literal):
            raise UnsupportedYulError(f"expected literal slot, got {raw}")
        return expr.value

    def parse_any_call(raw: str) -> tuple[str, list[str]] | None:
        match = re.fullmatch(rf"({IDENT})\((.*)\)", raw.strip())
        if match is None:
            return None
        return match.group(1), split_top_level_args(match.group(2))

    def summarize_expr(raw: str) -> Expr:
        nonlocal old_x_emitted, new_x_emitted

        record_text_rules(raw)
        text = summarize_transparent_helpers(raw.strip(), record_transparent_helper)
        call = parse_any_call(text)
        if call is not None:
            name, args = call
            if name == "read_from_storage_split_offset_0_t_uint256":
                add_rule("storageReadSlot0AsSload")
                if len(args) != 1:
                    raise UnsupportedYulError(f"{name} expects one argument")
                slot = literal_value(args[0])
                if slot in storage:
                    return storage[slot]
                if slot != 0:
                    raise UnsupportedYulError(f"unsupported storage read slot: {slot}")
                if old_x_emitted:
                    return Ident("old_x")
                emitted.append(Let("old_x", Call("sload", (Literal(slot),))))
                old_x_emitted = True
                return Ident("old_x")

            if name == "checked_add_t_uint256":
                add_rule("checkedAddUInt256AsAddWithOverflowGuard")
                if len(args) != 2:
                    raise UnsupportedYulError(f"{name} expects two arguments")
                lhs = parse_supported_expr(args[0])
                rhs = parse_supported_expr(args[1])
                if new_x_emitted:
                    raise UnsupportedYulError("multiple checked adds are unsupported")
                emitted.append(Let("new_x", Call("add", (lhs, rhs))))
                emitted.append(IfRevert(Call("lt", (Ident("new_x"), lhs))))
                new_x_emitted = True
                return Ident("new_x")

        return parse_supported_expr(text)

    def revert_condition_for_assert(cond: Expr) -> Expr:
        cond = resolve(cond)
        if isinstance(cond, Call) and cond.name == "iszero" and len(cond.args) == 1:
            return cond.args[0]
        return Call("iszero", (cond,))

    def handle_call_statement(line: str) -> bool:
        record_text_rules(line)
        call = parse_any_call(summarize_transparent_helpers(line, record_transparent_helper))
        if call is None:
            return False

        name, args = call
        if name == "require_helper":
            add_rule("requireHelperAsRevertGuard")
            if len(args) != 1:
                raise UnsupportedYulError("require_helper expects one argument")
            emitted.append(IfRevert(Call("iszero", (parse_supported_expr(args[0]),))))
            return True

        if name == "assert_helper":
            add_rule("assertHelperAsRevertGuard")
            if len(args) != 1:
                raise UnsupportedYulError("assert_helper expects one argument")
            emitted.append(
                IfRevert(revert_condition_for_assert(parse_supported_expr(args[0])))
            )
            return True

        if name == "update_storage_value_offset_0_t_uint256_to_t_uint256":
            add_rule("storageUpdateSlot0AsSstore")
            if len(args) != 2:
                raise UnsupportedYulError(f"{name} expects two arguments")
            slot = literal_value(args[0])
            if slot != 0:
                raise UnsupportedYulError(f"unsupported storage write slot: {slot}")
            value = parse_supported_expr(args[1])
            emitted.append(Store(Literal(slot), value))
            storage[slot] = value
            return True

        return False

    for _line_number, raw_line in function.body_lines:
        line = raw_line.strip()
        if not line or line in {"{", "}"}:
            continue

        let_match = re.fullmatch(rf"let ({IDENT}) := (.+)", line)
        if let_match is not None:
            env[let_match.group(1)] = summarize_expr(let_match.group(2))
            continue

        if handle_call_statement(line):
            continue

        raise UnsupportedYulError(f"unsupported Counter solc statement: {line}")

    return (
        YulObject(
            name="Counter",
            function=Function("inc", ("amount",), tuple(emitted)),
        ),
        tuple(trusted_rules),
    )


def summarize_solc_inspection_line(text: str) -> str:
    summarized = summarize_transparent_helpers(text)
    return summarize_require_helper(summarized)


def summarize_require_helper(text: str) -> str:
    match = re.fullmatch(r"require_helper\((.*)\)", text)
    if match is None:
        return text
    args = split_top_level_args(match.group(1))
    if len(args) != 1:
        return text
    condition = summarize_transparent_helpers(args[0])
    return f"if iszero({condition}) {{ revert(0, 0) }}"


def summarize_transparent_helpers(
    text: str, record_helper: Callable[[str], None] | None = None
) -> str:
    """Remove explicitly trusted one-argument solc value wrappers.

    This is only used by solc function-body inspection. It is not a general Yul
    parser and does not expand helper semantics for equivalence checking.
    """

    current = text
    while True:
        summarized = _summarize_one_transparent_helper(current, record_helper)
        if summarized == current:
            return current
        current = summarized


def _summarize_one_transparent_helper(
    text: str, record_helper: Callable[[str], None] | None
) -> str:
    for match in re.finditer(rf"\b({IDENT})\(", text):
        name = match.group(1)
        if name not in TRANSPARENT_VALUE_HELPER_RULES:
            continue
        open_index = match.end() - 1
        close_index = find_matching_paren(text, open_index)
        if close_index is None:
            continue
        args = split_top_level_args(text[open_index + 1 : close_index])
        if len(args) != 1:
            continue
        if record_helper is not None:
            record_helper(name)
        replacement = summarize_transparent_helpers(args[0], record_helper)
        return text[: match.start()] + replacement + text[close_index + 1 :]
    return text


def find_matching_paren(text: str, open_index: int) -> int | None:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def split_top_level_args(raw: str) -> list[str]:
    args: list[str] = []
    depth = 0
    start = 0
    for index, char in enumerate(raw):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            args.append(raw[start:index].strip())
            start = index + 1

    tail = raw[start:].strip()
    if tail:
        args.append(tail)
    return args


def _classify_unsupported(text: str, exc: UnsupportedYulError) -> Classification:
    lines = normalize_text(text).splitlines()
    if not lines:
        return Classification("parse-shape-failure", "empty Yul input")

    first_line = lines[0]
    if first_line.startswith("=======") or first_line in {"IR:", "Optimized IR:"}:
        return Classification(
            "unsupported-wrapper",
            f"solc output preamble is not supported: {first_line}",
        )

    object_lines = [line for line in lines if line.startswith("object ")]
    if len(object_lines) > 1:
        return Classification(
            "unsupported-wrapper",
            "multiple or nested object blocks are outside the restricted subset",
        )

    for line in lines:
        if line.startswith(UNSUPPORTED_STATEMENT_PREFIXES):
            return Classification(
                "unsupported-statement",
                f"unsupported statement form: {line}",
            )

    expression_match = re.search(
        r"unsupported expression function: ([A-Za-z_][A-Za-z0-9_]*)",
        str(exc),
    )
    if expression_match is not None:
        return Classification(
            "unsupported-expression",
            f"unsupported expression function: {expression_match.group(1)}",
        )

    if "unsupported statement:" in str(exc):
        return Classification("unsupported-statement", str(exc))

    unsupported_expr = re.search(r"unsupported expression: ([^;\n]+)", str(exc))
    if unsupported_expr is not None:
        return Classification(
            "unsupported-expression",
            f"unsupported expression form: {unsupported_expr.group(1)}",
        )

    return Classification("parse-shape-failure", str(exc))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Yul file to classify")
    parser.add_argument(
        "--inspect-solc",
        action="store_true",
        help="Classify the selected runtime/deployed object inside solc-style IR",
    )
    parser.add_argument(
        "--inspect-function",
        metavar="NAME",
        help=(
            "Within solc-style IR, select the runtime/deployed object and "
            "classify the generated function body matching NAME"
        ),
    )
    parser.add_argument(
        "--summarize-function",
        metavar="NAME",
        help=(
            "Within solc-style IR, summarize the generated function body "
            "matching NAME into the current canonical Counter restricted Yul shape"
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.source.exists():
        print(f"parse-shape-failure: source file not found: {args.source}")
        return 2

    text = args.source.read_text()
    if args.summarize_function:
        try:
            summary = summarize_solc_function_text(text, args.summarize_function)
        except UnsupportedYulError as exc:
            print(f"unsupported solc function summary: {exc}")
            return 2
        print(
            json.dumps(
                solc_function_summary_to_data(summary),
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.inspect_function:
        inspection = inspect_solc_function_text(text, args.inspect_function)
        print(f"{inspection.kind}: {inspection.message}")
        if inspection.selected_object is not None:
            print(
                "selected object: "
                f"{inspection.selected_object.name}@"
                f"{inspection.selected_object.start_line}-"
                f"{inspection.selected_object.end_line}"
            )
        if inspection.selected_function is not None:
            print(
                "selected function: "
                f"{inspection.selected_function.name}@"
                f"{inspection.selected_function.start_line}-"
                f"{inspection.selected_function.end_line}"
            )
        return 0 if inspection.is_supported else 2

    if args.inspect_solc:
        inspection = inspect_solc_text(text)
        print(f"{inspection.kind}: {inspection.message}")
        if inspection.objects:
            objects = ", ".join(
                f"{block.name}@{block.start_line}-{block.end_line}"
                for block in inspection.objects
            )
            print(f"objects: {objects}")
        return 0 if inspection.is_supported else 2

    classification = classify_text(text)
    print(f"{classification.kind}: {classification.message}")
    return 0 if classification.is_supported else 2


if __name__ == "__main__":
    raise SystemExit(main())
