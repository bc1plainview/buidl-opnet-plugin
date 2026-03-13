#!/bin/bash
# trace-event.sh — Append a structured event to the session trace log
#
# Usage: bash scripts/trace-event.sh <session-dir> <event-type> <agent> <phase> <cycle> <details> [--tokens N] [--category CAT]
#
# Event types: dispatch, complete, route, route-finding, finding, state, checkpoint, error, replan
#
# Appends one JSON line to <session-dir>/artifacts/trace.jsonl
#
# Exit codes:
#   0 — Success (event appended)
#   1 — Missing arguments or invalid event type

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SESSION_DIR="${1:-}"
EVENT_TYPE="${2:-}"
AGENT="${3:-}"
PHASE="${4:-}"
CYCLE="${5:-}"
DETAILS="${6:-}"

if [[ -z "$SESSION_DIR" || -z "$EVENT_TYPE" || -z "$AGENT" || -z "$PHASE" || -z "$CYCLE" || -z "$DETAILS" ]]; then
  echo "Usage: bash scripts/trace-event.sh <session-dir> <event-type> <agent> <phase> <cycle> <details> [--tokens N] [--category CAT]" >&2
  exit 1
fi

# Validate event type
VALID_TYPES="dispatch complete route route-finding finding state checkpoint error replan"
TYPE_VALID=false
for vt in $VALID_TYPES; do
  if [[ "$EVENT_TYPE" == "$vt" ]]; then
    TYPE_VALID=true
    break
  fi
done

if [[ "$TYPE_VALID" != "true" ]]; then
  echo "Error: Invalid event type '$EVENT_TYPE'. Valid types: $VALID_TYPES" >&2
  exit 1
fi

# Parse optional flags
TOKENS=""
CATEGORY=""
shift 6
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tokens)
      TOKENS="${2:-}"
      shift 2
      ;;
    --category)
      CATEGORY="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Ensure artifacts directory exists
mkdir -p "$SESSION_DIR/artifacts"

TRACE_FILE="$SESSION_DIR/artifacts/trace.jsonl"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON line using Python for safe JSON encoding (no interpolation)
python3 -c "
import json, sys

event = {
    'timestamp': sys.argv[1],
    'event_type': sys.argv[2],
    'agent': sys.argv[3],
    'phase': sys.argv[4],
    'cycle': int(sys.argv[5]),
    'details': sys.argv[6]
}

tokens = sys.argv[7]
category = sys.argv[8]

if tokens:
    event['tokens'] = int(tokens)
if category:
    event['category'] = category

print(json.dumps(event))
" "$TIMESTAMP" "$EVENT_TYPE" "$AGENT" "$PHASE" "$CYCLE" "$DETAILS" "$TOKENS" "$CATEGORY" >> "$TRACE_FILE"
