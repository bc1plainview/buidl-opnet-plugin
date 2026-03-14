#!/bin/bash
# run-spec-loop.sh — Verification loop: run TLC, if violations found feed
# counterexample back to agent, agent fixes the spec, repeat until clean
# or max-iterations reached.
#
# This is the core of the TLA+ integration -- the agent loops fixing the SPEC
# (not the code) until the design is provably consistent.
#
# Usage: bash scripts/run-spec-loop.sh <path-to-spec.tla> [max-iterations]
#
# Output: artifacts/spec/verification-result.json (final state)
#         artifacts/spec/loop-log.md (trace of all iterations)
#
# Exit codes:
#   0 — Spec verified clean
#   1 — Max iterations reached without clean spec
#   2 — Violations found, repair needed (buidl reads repair-signal.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPEC_PATH="${1:-}"
MAX_ITER="${2:-5}"
OUT_DIR="artifacts/spec"
LOG="$OUT_DIR/loop-log.md"
ITER=0

if [[ -z "$SPEC_PATH" ]]; then
    echo "Usage: bash scripts/run-spec-loop.sh <path-to-spec.tla> [max-iterations]" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "# TLA+ Verification Loop Log" > "$LOG"
echo "Spec: $SPEC_PATH | Max iterations: $MAX_ITER" >> "$LOG"
echo "" >> "$LOG"

while [[ "$ITER" -lt "$MAX_ITER" ]]; do
    ITER=$((ITER + 1))
    echo "## Iteration $ITER" >> "$LOG"

    bash "$SCRIPT_DIR/scripts/verify-spec.sh" "$SPEC_PATH" || true

    STATUS=$(python3 -c "import sys, json; print(json.load(open(sys.argv[1]))['status'])" "$OUT_DIR/verification-result.json")

    echo "Status: $STATUS" >> "$LOG"

    if [[ "$STATUS" == "pass" ]]; then
        echo "Spec verified clean after $ITER iteration(s)." >> "$LOG"
        echo "SPEC_VERIFIED=true" >> "$LOG"
        exit 0
    fi

    # Extract violations and feed back to spec-writer agent via artifacts
    cp "$OUT_DIR/verification-result.json" "$OUT_DIR/violations-iter-$ITER.json"
    echo "Violations found -- routing back to spec-writer." >> "$LOG"

    # Signal to buidl that spec needs repair (buidl reads this file)
    python3 -c "
import json, sys
signal = {'needs_repair': True, 'iteration': int(sys.argv[1]), 'violations_file': 'artifacts/spec/violations-iter-' + sys.argv[1] + '.json'}
print(json.dumps(signal))
" "$ITER" > "$OUT_DIR/repair-signal.json"

    # In the buidl loop, seeing repair-signal.json triggers re-dispatch of spec-writer
    # with the violations as context. This script exits non-zero to signal failure.
    exit 2
done

echo "Max iterations ($MAX_ITER) reached without clean spec." >> "$LOG"
exit 1
