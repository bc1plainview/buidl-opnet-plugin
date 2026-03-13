#!/bin/bash
# localize-failure.sh — Failure localization from build/test logs
#
# Usage: bash scripts/localize-failure.sh <failure-log-path>
#
# Parses a failure log and extracts structured localization data:
# - File and function where the failure occurred
# - Line range of the suspected cause
# - Confidence level (high/medium/low)
# - Failure category (compile_error, test_failure, runtime_error, type_error, lint_error)
#
# Output: artifacts/localization.json
#   { file, function, line_range, suspected_cause, confidence, failure_category }
#
# Exit codes:
#   0 — Success (localization written)
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAILURE_LOG="${1:-}"

if [[ -z "$FAILURE_LOG" ]]; then
  echo "Usage: bash scripts/localize-failure.sh <failure-log-path>"
  exit 1
fi

if [[ ! -f "$FAILURE_LOG" ]]; then
  echo "Error: Failure log not found: $FAILURE_LOG"
  exit 1
fi

OUTPUT_DIR="${SCRIPT_DIR}/artifacts"
mkdir -p "$OUTPUT_DIR"

# Use Python to parse the failure log and extract localization
export _LOC_LOG_PATH="$FAILURE_LOG"
export _LOC_OUTPUT_PATH="$OUTPUT_DIR/localization.json"
python3 << 'PYEOF'
import sys
import json
import re
import os

log_path = os.environ['_LOC_LOG_PATH']
output_path = os.environ['_LOC_OUTPUT_PATH']

# Read the failure log
try:
    with open(log_path, 'r') as f:
        content = f.read()
except (IOError, OSError):
    content = ""

if not content.strip():
    # Empty log — write minimal localization
    result = {
        "file": "unknown",
        "function": "unknown",
        "line_range": [0, 0],
        "suspected_cause": "Empty failure log — no information available",
        "confidence": "low",
        "failure_category": "unknown"
    }
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
        f.write('\n')
    print(json.dumps(result, indent=2))
    sys.exit(0)

# Patterns for file:line extraction
file_line_patterns = [
    # TypeScript/JavaScript errors: file.ts(line,col) or file.ts:line:col
    r'([^\s:]+\.(?:ts|js|as))[:\(](\d+)',
    # Rust-style: --> file.rs:line:col
    r'-->\s+([^\s:]+):(\d+)',
    # Generic: at file:line
    r'at\s+([^\s:]+):(\d+)',
    # Error in file:line
    r'(?:Error|error|ERROR)\s+(?:in\s+)?([^\s:]+):(\d+)',
]

# Patterns for function names
function_patterns = [
    r'(?:function|method|fn)\s+(\w+)',
    r'(\w+)\s*\(',
    r'at\s+(\w+)\s+\(',
    r'in\s+(\w+)\s+at',
]

# Failure category detection
category_keywords = {
    'compile_error': ['compile', 'compilation', 'syntax error', 'cannot find', 'build failed',
                      'TS\d+', 'AS\d+', 'unexpected token', 'parse error'],
    'test_failure': ['test failed', 'assertion', 'expect', 'FAIL', 'test.*error',
                     'AssertionError', 'should.*but', 'expected.*received'],
    'runtime_error': ['runtime', 'uncaught', 'ReferenceError', 'TypeError',
                      'null pointer', 'segfault', 'panic', 'abort'],
    'type_error': ['type.*mismatch', 'type.*error', 'cannot assign', 'incompatible',
                   'TS2\d+', 'not assignable'],
    'lint_error': ['lint', 'eslint', 'warning.*unused', 'no-unused', 'prettier'],
}

# Extract file and line
file_found = "unknown"
line_found = 0
for pattern in file_line_patterns:
    match = re.search(pattern, content)
    if match:
        file_found = match.group(1)
        line_found = int(match.group(2))
        break

# Extract function name
function_found = "unknown"
for pattern in function_patterns:
    match = re.search(pattern, content)
    if match:
        candidate = match.group(1)
        # Filter out common non-function matches
        if candidate not in ('if', 'for', 'while', 'return', 'throw', 'new', 'import', 'from'):
            function_found = candidate
            break

# Detect category
category = "unknown"
for cat, keywords in category_keywords.items():
    for kw in keywords:
        if re.search(kw, content, re.IGNORECASE):
            category = cat
            break
    if category != "unknown":
        break

# Extract suspected cause (first error-like line)
cause_patterns = [
    r'(?:error|Error|ERROR)[:\s]+(.+?)(?:\n|$)',
    r'(?:FAIL|FAILED)[:\s]+(.+?)(?:\n|$)',
    r'(?:assert|Assert)[:\s]+(.+?)(?:\n|$)',
]
suspected_cause = "Could not determine cause from log"
for pattern in cause_patterns:
    match = re.search(pattern, content)
    if match:
        suspected_cause = match.group(1).strip()[:200]
        break

# Determine confidence
confidence = "low"
if file_found != "unknown" and line_found > 0:
    confidence = "high"
elif file_found != "unknown" or category != "unknown":
    confidence = "medium"

# Compute line range (10 lines around the error)
line_start = max(1, line_found - 5)
line_end = line_found + 5

result = {
    "file": file_found,
    "function": function_found,
    "line_range": [line_start, line_end],
    "suspected_cause": suspected_cause,
    "confidence": confidence,
    "failure_category": category
}

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')

print(json.dumps(result, indent=2))
PYEOF
