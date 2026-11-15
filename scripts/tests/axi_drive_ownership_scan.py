#!/usr/bin/env python3
"""Scan AXI SystemVerilog sources for public-net ownership violations."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Iterable, Mapping, Sequence


MASTER_SIGNALS = (
    "awid", "awaddr", "awlen", "awsize", "awburst", "awlock", "awcache",
    "awprot", "awqos", "awregion", "awvalid", "wdata", "wstrb", "wlast",
    "wvalid", "bready", "arid", "araddr", "arlen", "arsize", "arburst",
    "arlock", "arcache", "arprot", "arqos", "arregion", "arvalid", "rready",
)
SLAVE_SIGNALS = (
    "awready", "wready", "bid", "bresp", "bvalid", "arready", "rid",
    "rdata", "rresp", "rlast", "rvalid",
)
ROLE_SIGNALS = {"master": MASTER_SIGNALS, "slave": SLAVE_SIGNALS}
PUBLIC_SIGNALS = tuple(sorted(MASTER_SIGNALS + SLAVE_SIGNALS, key=len, reverse=True))

IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_$]*"
SIGNAL_ALTERNATION = "|".join(re.escape(signal) for signal in PUBLIC_SIGNALS)
POLICY_VIOLATION = 3


class ScannerToolError(Exception):
    """An input or runtime failure, distinct from a policy violation."""


def strip_comments_and_strings(text: str) -> str:
    """Replace comments and string contents with spaces while preserving lines."""
    output: list[str] = []
    index = 0
    state = "code"
    escaped = False

    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if state == "code":
            if char == "/" and next_char == "/":
                output.extend((" ", " "))
                index += 2
                state = "line_comment"
                continue
            if char == "/" and next_char == "*":
                output.extend((" ", " "))
                index += 2
                state = "block_comment"
                continue
            if char == '"':
                output.append(" ")
                index += 1
                state = "string"
                escaped = False
                continue
            output.append(char)
            index += 1
            continue

        if state == "line_comment":
            if char == "\n":
                output.append("\n")
                state = "code"
            else:
                output.append(" ")
            index += 1
            continue

        if state == "block_comment":
            if char == "*" and next_char == "/":
                output.extend((" ", " "))
                index += 2
                state = "code"
            else:
                output.append("\n" if char == "\n" else " ")
                index += 1
            continue

        if char == "\n":
            output.append("\n")
        else:
            output.append(" ")
        if escaped:
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == '"':
            state = "code"
        index += 1

    return "".join(output)


def normalize_path(path: str) -> str:
    return re.sub(r"\s+", "", path)


def clocking_block_spans(cleaned_text: str) -> list[tuple[int, int]]:
    """Locate real clocking declarations in comment/string-scrubbed source."""
    spans: list[tuple[int, int]] = []
    clocking_start = re.compile(
        rf"\b(?:default\s+)?clocking\s+{IDENTIFIER}\s*@"
    )
    clocking_end = re.compile(r"\bendclocking\b")
    previous_end = 0

    for start in clocking_start.finditer(cleaned_text):
        if start.start() < previous_end:
            continue
        end = clocking_end.search(cleaned_text, start.end())
        if end is None:
            continue
        spans.append((start.start(), end.end()))
        previous_end = end.end()
    return spans


def position_in_spans(position: int, spans: Sequence[tuple[int, int]]) -> bool:
    return any(start <= position < end for start, end in spans)


def skip_balanced_parentheses(text: str, start: int) -> int:
    """Return the first position after a balanced parenthesized region."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return len(text)


def split_top_level_commas(text: str) -> list[str]:
    """Split declarators without splitting parameter or array expressions."""
    parts: list[str] = []
    start = 0
    depths = {"(": 0, "[": 0, "{": 0}
    closing = {")": "(", "]": "[", "}": "{"}
    for index, char in enumerate(text):
        if char in depths:
            depths[char] += 1
        elif char in closing and depths[closing[char]] > 0:
            depths[closing[char]] -= 1
        elif char == "," and all(depth == 0 for depth in depths.values()):
            parts.append(text[start:index])
            start = index + 1
    parts.append(text[start:])
    return parts


def find_virtual_interface_handles(cleaned_text: str) -> set[str]:
    """Return direct handles declared with the ``virtual axi_if`` type."""
    handles: set[str] = set()
    declaration_start = re.compile(r"\bvirtual\s+(?:interface\s+)?axi_if\b")

    for match in declaration_start.finditer(cleaned_text):
        cursor = match.end()
        while cursor < len(cleaned_text) and cleaned_text[cursor].isspace():
            cursor += 1
        if cursor < len(cleaned_text) and cleaned_text[cursor] == "#":
            cursor += 1
            while cursor < len(cleaned_text) and cleaned_text[cursor].isspace():
                cursor += 1
            if cursor >= len(cleaned_text) or cleaned_text[cursor] != "(":
                continue
            cursor = skip_balanced_parentheses(cleaned_text, cursor)

        declaration_end = cleaned_text.find(";", cursor)
        if declaration_end < 0:
            continue
        declarators = cleaned_text[cursor:declaration_end]
        for declarator in split_top_level_commas(declarators):
            handle_match = re.match(rf"\s*(?P<handle>{IDENTIFIER})\b", declarator)
            if handle_match:
                handles.add(handle_match.group("handle"))
    return handles


def parenthesis_depths(text: str) -> list[int]:
    """Record lexical parenthesis depth before every source character."""
    depths = [0] * (len(text) + 1)
    depth = 0
    for index, char in enumerate(text):
        depths[index] = depth
        if char == "(":
            depth += 1
        elif char == ")" and depth > 0:
            depth -= 1
    depths[len(text)] = depth
    return depths


def statement_start(text: str, position: int, depths: Sequence[int]) -> int:
    """Find the preceding statement terminator at the candidate's lexical depth."""
    candidate_depth = depths[position]
    for index in range(position - 1, -1, -1):
        if text[index] == ";" and depths[index] == candidate_depth:
            return index + 1
    return 0


def is_relational_context(
    text: str,
    target_position: int,
    operator_position: int,
    depths: Sequence[int],
) -> bool:
    """Return true only when lexical evidence proves ``<=`` is an expression."""
    if depths[operator_position] > 0:
        return True

    start = statement_start(text, target_position, depths)
    candidate_depth = depths[target_position]
    prefix = text[start:target_position]
    assignment_operator = re.compile(
        r"<<<=|>>>=|<<=|>>=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|<=|=(?!=|>)"
    )
    for match in assignment_operator.finditer(prefix):
        if depths[start + match.start()] == candidate_depth:
            return True

    for match in re.finditer(r"\breturn\b", prefix):
        if depths[start + match.start()] == candidate_depth:
            return True
    return False


def root_is_eligible(target: str, roots: set[str], include_bare: bool) -> bool:
    if "." not in target:
        return include_bare
    root = target.rsplit(".", 1)[0]
    return root in roots or (root.startswith("this.") and root[5:] in roots)


def is_continuous_assignment(cleaned_text: str, position: int) -> bool:
    statement_start = cleaned_text.rfind(";", 0, position) + 1
    return re.search(r"\bassign\b", cleaned_text[statement_start:position]) is not None


def find_procedural_writes(
    text: str,
    include_bare: bool = False,
    roots: Sequence[str] = (),
) -> list[tuple[int, str, str]]:
    """Return public-signal procedural assignments as line/path/operator tuples."""
    cleaned = strip_comments_and_strings(text)
    eligible_roots = find_virtual_interface_handles(cleaned)
    eligible_roots.update(normalize_path(root) for root in roots)
    depths = parenthesis_depths(cleaned)
    clocking_spans = clocking_block_spans(cleaned)
    hierarchical_reference = (
        rf"{IDENTIFIER}(?:\s*\.\s*{IDENTIFIER})*\s*\.\s*"
        rf"(?:{SIGNAL_ALTERNATION})"
    )
    bare_reference = rf"(?:{SIGNAL_ALTERNATION})"
    reference = hierarchical_reference
    if include_bare:
        reference = rf"(?:{hierarchical_reference}|{bare_reference})"
    reference = (
        rf"(?<![A-Za-z0-9_$])(?P<target>{reference})(?![A-Za-z0-9_$])"
        r"(?:\s*\[[^\]\n]*\])*"
    )
    write_operators = r"<<<=|>>>=|<<=|>>=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|<=|\+\+|--|=(?!=|>)"
    postfix_pattern = re.compile(
        rf"{reference}\s*(?P<operator>{write_operators})"
    )
    prefix_pattern = re.compile(
        rf"(?P<operator>\+\+|--)\s*{reference}"
    )
    findings: list[tuple[int, int, str, str]] = []

    for pattern in (postfix_pattern, prefix_pattern):
        for match in pattern.finditer(cleaned):
            target = normalize_path(match.group("target"))
            if not root_is_eligible(target, eligible_roots, include_bare):
                continue
            if position_in_spans(match.start("target"), clocking_spans):
                continue
            if is_continuous_assignment(cleaned, match.start("target")):
                continue

            operator = match.group("operator")
            if operator == "<=" and is_relational_context(
                cleaned,
                match.start("target"),
                match.start("operator"),
                depths,
            ):
                continue

            line = cleaned.count("\n", 0, match.start("target")) + 1
            findings.append((match.start(), line, target, operator))

    findings.sort(key=lambda finding: finding[0])
    return [(line, target, operator) for _, line, target, operator in findings]


def declaration_count(cleaned_text: str, signal: str) -> int:
    declaration_pattern = re.compile(
        rf"^[ \t]*wire[ \t]+logic(?:[ \t]+\[[^\]\n]+\])*"
        rf"[ \t]+{re.escape(signal)}[ \t]*;[ \t]*$",
        re.MULTILINE,
    )
    return len(declaration_pattern.findall(cleaned_text))


def continuous_assignments(cleaned_text: str, signal: str) -> list[str]:
    statement_pattern = re.compile(r"\bassign\b(?P<body>.*?);", re.DOTALL)
    target_pattern = re.compile(
        rf"(?<![A-Za-z0-9_$.]){re.escape(signal)}\s*=(?!=)"
    )
    assignments = []
    for match in statement_pattern.finditer(cleaned_text):
        if target_pattern.search(match.group("body")):
            assignments.append(re.sub(r"\s+", "", match.group(0)))
    return assignments


def check_interface_text(
    text: str,
    role_signals: Mapping[str, Sequence[str]] = ROLE_SIGNALS,
) -> list[str]:
    """Return declaration/proxy mapping policy violations for an interface."""
    cleaned = strip_comments_and_strings(text)
    errors: list[str] = []

    for role, signals in role_signals.items():
        for signal in signals:
            declarations = declaration_count(cleaned, signal)
            if declarations != 1:
                errors.append(
                    f"expected exactly one wire logic public declaration for {signal} "
                    f"(found {declarations})"
                )

            assignments = continuous_assignments(cleaned, signal)
            expected = f"assign{signal}={role}_drive_enabled?{role}_{signal}:'z;"
            if len(assignments) != 1:
                errors.append(
                    f"expected exactly one continuous public assignment for {signal} "
                    f"(found {len(assignments)})"
                )
            elif assignments[0] != expected:
                errors.append(
                    f"wrong proxy assignment for {signal}: found {assignments[0]}"
                )

    return errors


def read_source(path_text: str) -> tuple[Path, str]:
    path = Path(path_text)
    try:
        return path, path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise ScannerToolError(f"cannot read {path}: {error}") from error


def scan_writes(paths: Iterable[str], include_bare: bool, roots: Sequence[str]) -> int:
    found = False
    for path_text in paths:
        path, text = read_source(path_text)
        for line, target, operator in find_procedural_writes(
            text, include_bare=include_bare, roots=roots
        ):
            print(f"{path}:{line}: public procedural write: {target} {operator}")
            found = True
    return POLICY_VIOLATION if found else 0


def check_interface(path_text: str) -> int:
    _, text = read_source(path_text)
    errors = check_interface_text(text)
    for error in errors:
        print(f"FAIL: {error}", file=sys.stderr)
    return POLICY_VIOLATION if errors else 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    interface_parser = subparsers.add_parser("check-interface")
    interface_parser.add_argument("path")

    writes_parser = subparsers.add_parser("scan-writes")
    writes_parser.add_argument("--include-bare", action="store_true")
    writes_parser.add_argument("--root", action="append", default=[])
    writes_parser.add_argument("paths", nargs="+")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.command == "check-interface":
            return check_interface(args.path)
        return scan_writes(args.paths, args.include_bare, args.root)
    except ScannerToolError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2
    except Exception as error:  # Keep scanner/tool faults distinct from policy matches.
        print(f"ERROR: ownership scanner failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
