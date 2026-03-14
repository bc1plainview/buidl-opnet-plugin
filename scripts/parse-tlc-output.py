#!/usr/bin/env python3
"""Parse TLC stdout into structured JSON for buidl."""
import sys
import json
import re


def parse(tlc_output: str, elapsed_ms: int) -> dict:
    lines = tlc_output.splitlines()

    violations = []
    states_checked = 0
    status = "pass"

    # Extract states checked
    for line in lines:
        m = re.search(r'(\d+) states generated', line)
        if m:
            states_checked = int(m.group(1))

    # Detect invariant violations
    in_trace = False
    current_violation = None
    trace_lines = []

    for line in lines:
        if 'Invariant' in line and 'violated' in line:
            status = "fail"
            inv_match = re.search(r'Invariant (\w+) is violated', line)
            inv_name = inv_match.group(1) if inv_match else "Unknown"
            if current_violation:
                current_violation["trace"] = trace_lines
                violations.append(current_violation)
            current_violation = {"invariant": inv_name, "trace": []}
            trace_lines = []
            in_trace = True
        elif in_trace and line.strip():
            trace_lines.append(line.strip())
        elif 'Error:' in line and 'no error' not in line.lower():
            status = "fail"

    if current_violation:
        current_violation["trace"] = trace_lines
        violations.append(current_violation)

    # Detect TLC errors (not invariant violations -- spec syntax errors etc)
    if 'TLC threw an unexpected exception' in tlc_output:
        status = "error"

    return {
        "status": status,
        "states_checked": states_checked,
        "violations": violations,
        "warnings": [],
        "elapsed_ms": elapsed_ms
    }


if __name__ == "__main__":
    tlc_output = sys.argv[1] if len(sys.argv) > 1 else ""
    elapsed_ms = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    print(json.dumps(parse(tlc_output, elapsed_ms), indent=2))
