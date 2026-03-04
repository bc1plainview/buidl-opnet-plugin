#!/bin/bash
# guard-state-bash.sh — PreToolUse hook that blocks Bash commands writing to state files
#
# Catches shell bypass of the Write/Edit guard (e.g., echo > state.yaml, cat > state.yaml).
# Only blocks during active loop phases. write-state.sh is exempted.
#
# Exit codes:
#   0 — Allow the tool use
#   2 — Block the tool use (with message)

set -euo pipefail

INPUT=$(cat)

# Extract the command being run
COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('command', ''))
" 2>/dev/null || echo "")

# No command = allow
[[ -z "$COMMAND" ]] && exit 0

# Allow write-state.sh itself
case "$COMMAND" in
  *write-state.sh*) exit 0 ;;
esac

# Check if command targets state files with write operators
if echo "$COMMAND" | grep -qE '(state\.yaml|state\.local\.md)' && echo "$COMMAND" | grep -qE '(>|>>|tee |sed -i|mv .* state|cp .* state)'; then
  # Check if loop is active
  PROJECT_DIR=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
  [[ -z "$PROJECT_DIR" ]] && exit 0

  STATE_FILE=""
  if [[ -f "$PROJECT_DIR/.claude/loop/state.yaml" ]]; then
    STATE_FILE="$PROJECT_DIR/.claude/loop/state.yaml"
  elif [[ -f "$PROJECT_DIR/.claude/loop/state.local.md" ]]; then
    STATE_FILE="$PROJECT_DIR/.claude/loop/state.local.md"
  fi

  [[ -z "$STATE_FILE" ]] && exit 0

  STATUS=$(grep '^status:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)

  case "$STATUS" in
    challenging|specifying|exploring|building|reviewing|auditing|deploying|testing)
      echo '{"decision":"block","reason":"Shell commands writing to state files are blocked during active loops. Use write-state.sh instead: bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh key=value"}' >&2
      exit 2
      ;;
  esac
fi

exit 0
