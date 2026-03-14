#!/bin/bash
# verify-spec.sh — Runs TLC model checker against a TLA+ spec file
#
# Usage: bash scripts/verify-spec.sh <path-to-spec.tla>
#
# Outputs: artifacts/spec/verification-result.json
#
# {
#   "spec": "MyContract.tla",
#   "status": "pass" | "fail" | "error",
#   "states_checked": 12847,
#   "violations": [
#     {
#       "invariant": "BalanceNeverNegative",
#       "trace": [
#         "Initial state: balance=100, amount=0",
#         "Action Transfer: amount=150",
#         "Violation: balance=-50"
#       ]
#     }
#   ],
#   "warnings": [],
#   "elapsed_ms": 1423
# }
#
# TLC flags used:
#   -deadlock            check for deadlocks
#   -workers auto        use all available CPU cores
#   -maxSetSize 10000000 handle larger state spaces
#
# Exit codes:
#   0 — Verification completed (check JSON for pass/fail)
#   1 — TLC not found or missing arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_PATH="${1:-}"
TOOLS_JAR="$SCRIPT_DIR/tools/tla/tla2tools.jar"
OUT_DIR="artifacts/spec"

if [[ -z "$SPEC_PATH" ]]; then
    echo "Usage: bash scripts/verify-spec.sh <path-to-spec.tla>" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

if [[ ! -f "$TOOLS_JAR" ]]; then
    echo '{"status":"error","message":"TLC not found. Run scripts/setup-tla.sh first."}' > "$OUT_DIR/verification-result.json"
    cat "$OUT_DIR/verification-result.json"
    exit 1
fi

START_MS=$(python3 -c "import time; print(int(time.time() * 1000))")

# Run TLC. Capture output.
TLC_OUT=$(java -jar "$TOOLS_JAR" -deadlock -workers auto -maxSetSize 10000000 "$SPEC_PATH" 2>&1) || true

END_MS=$(python3 -c "import time; print(int(time.time() * 1000))")
ELAPSED=$((END_MS - START_MS))

# Parse TLC output into JSON
python3 "$SCRIPT_DIR/scripts/parse-tlc-output.py" "$TLC_OUT" "$ELAPSED" > "$OUT_DIR/verification-result.json"

cat "$OUT_DIR/verification-result.json"
