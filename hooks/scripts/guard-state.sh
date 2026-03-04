#!/bin/bash
# guard-state.sh — PreToolUse hook that blocks direct Write/Edit to state files
#
# During active loop phases, all state mutations MUST go through write-state.sh.
# This hook prevents agents from directly writing to state.yaml or state.local.md.
#
# Exit codes:
#   0 — Allow the tool use
#   2 — Block the tool use (with message)

set -euo pipefail

INPUT=$(cat)

# Extract the file path being written/edited
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
params = data.get('tool_input', {})
print(params.get('file_path', params.get('filePath', '')))
" 2>/dev/null || echo "")

# If no file path or not targeting state files, allow
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Check if the target is a state file
case "$FILE_PATH" in
  */state.yaml|*/state.local.md)
    ;;
  *)
    exit 0
    ;;
esac

# Find the state file to check if a loop is active
PROJECT_DIR=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
if [[ -z "$PROJECT_DIR" ]]; then
  exit 0
fi

# Check both state files (prefer state.yaml)
STATE_FILE=""
if [[ -f "$PROJECT_DIR/.claude/loop/state.yaml" ]]; then
  STATE_FILE="$PROJECT_DIR/.claude/loop/state.yaml"
elif [[ -f "$PROJECT_DIR/.claude/loop/state.local.md" ]]; then
  STATE_FILE="$PROJECT_DIR/.claude/loop/state.local.md"
fi

# No state file = no active loop = allow
if [[ -z "$STATE_FILE" ]]; then
  exit 0
fi

STATUS=$(grep '^status:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)

# Block during active phases
case "$STATUS" in
  challenging|specifying|exploring|building|reviewing|auditing|deploying|testing)
    echo '{"decision":"block","reason":"Direct writes to state files are blocked during active loops. Use write-state.sh instead: bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh key=value"}' >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
