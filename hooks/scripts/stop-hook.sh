#!/bin/bash
# stop-hook.sh — Iteration control for The Loop
#
# Called by Claude Code's Stop hook. Checks if the build-review loop
# should continue or if the session can exit.
#
# Exit codes:
#   0 — Allow exit (loop done, passed, cancelled, or no loop running)
#   2 — Block exit (loop still running, re-inject prompt)

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

PROJECT_DIR=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
if [[ -z "$PROJECT_DIR" ]]; then
  exit 0
fi

STATE_FILE="$PROJECT_DIR/.claude/loop/state.local.md"

# No state file = no loop running
[[ ! -f "$STATE_FILE" ]] && exit 0

# Parse state
STATUS=$(grep '^status:' "$STATE_FILE" | head -1 | awk '{print $2}')
SESSION_NAME=$(grep '^session_name:' "$STATE_FILE" | head -1 | awk '{print $2}')
CYCLE=$(grep '^cycle:' "$STATE_FILE" | head -1 | awk '{print $2}')
MAX_CYCLES=$(grep '^max_cycles:' "$STATE_FILE" | head -1 | awk '{print $2}')
PHASE=$(grep '^current_phase:' "$STATE_FILE" | head -1 | awk '{print $2}')

# Only block exit during active build-review phases
case "$STATUS" in
  building|reviewing)
    ;;
  *)
    # Not in an active loop phase — allow exit
    exit 0
    ;;
esac

SESSION_DIR="$PROJECT_DIR/.claude/loop/sessions/$SESSION_NAME"

# Check for reviewer verdict in the latest review file
LATEST_REVIEW=""
for f in "$SESSION_DIR/reviews/cycle-"*.md; do
  [[ -f "$f" ]] && LATEST_REVIEW="$f"
done

VERDICT=""
if [[ -n "$LATEST_REVIEW" && -f "$LATEST_REVIEW" ]]; then
  VERDICT=$(grep '^VERDICT:' "$LATEST_REVIEW" | head -1 | awk '{print $2}')
fi

# If reviewer passed, we're done
if [[ "$VERDICT" == "PASS" ]]; then
  sed -i '' "s/^status:.*/status: done/" "$STATE_FILE"
  sed -i '' "s/^current_phase:.*/current_phase: done/" "$STATE_FILE"
  echo '{"decision": "approve", "reason": "Loop complete. Reviewer passed the PR."}' >&2
  exit 0
fi

# If max cycles reached, stop
if [[ "$CYCLE" -ge "$MAX_CYCLES" ]]; then
  sed -i '' "s/^status:.*/status: failed/" "$STATE_FILE"
  sed -i '' "s/^current_phase:.*/current_phase: failed/" "$STATE_FILE"
  cat >&2 << STOP_MSG
{"decision": "approve", "reason": "Loop reached max cycles ($MAX_CYCLES). Remaining findings are in $LATEST_REVIEW. The PR is open for manual review and fixing."}
STOP_MSG
  exit 0
fi

# FAIL verdict or still in build phase — continue the loop
NEW_CYCLE=$((CYCLE + 1))
sed -i '' "s/^cycle:.*/cycle: $NEW_CYCLE/" "$STATE_FILE"
sed -i '' "s/^inner_retries:.*/inner_retries: 0/" "$STATE_FILE"
sed -i '' "s/^status:.*/status: building/" "$STATE_FILE"
sed -i '' "s/^current_phase:.*/current_phase: build/" "$STATE_FILE"

# Build the re-injection prompt
FINDINGS=""
if [[ -n "$LATEST_REVIEW" && -f "$LATEST_REVIEW" ]]; then
  FINDINGS=$(cat "$LATEST_REVIEW")
fi

WORKTREE_PATH=$(grep '^worktree_path:' "$STATE_FILE" | head -1 | sed 's/^worktree_path: //')

# Construct the continuation prompt
PROMPT="The Loop: Build cycle $NEW_CYCLE of $MAX_CYCLES.

The reviewer found issues in the previous cycle. Address each finding below, then re-run the full verify pipeline (lint, typecheck, build, test). When everything passes, commit, push, and update the PR.

Work in the worktree at: $WORKTREE_PATH

REVIEWER FINDINGS:
$FINDINGS

Spec documents are at: $SESSION_DIR/spec/
Codebase context is at: $SESSION_DIR/context.md

After fixing and verifying, launch the loop-reviewer agent to review the updated PR."

# Use python to JSON-encode the prompt safely
JSON_PROMPT=$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$PROMPT")

echo "{\"decision\": \"block\", \"reason\": $JSON_PROMPT}" >&2
exit 2
