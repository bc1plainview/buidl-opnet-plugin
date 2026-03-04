#!/bin/bash
# stop-hook.sh — Iteration control for The Loop
#
# Called by Claude Code's Stop hook. Checks if the build-review loop
# should continue or if the session can exit.
#
# Handles both legacy single-builder flow and multi-agent OPNet flow.
# Uses write-state.sh for all state mutations (no direct sed on state files).
#
# Exit codes:
#   0 — Allow exit (loop done, passed, cancelled, or no loop running)
#   2 — Block exit (loop still running, re-inject prompt)

set -euo pipefail

# Locate write-state.sh relative to this script
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
WRITE_STATE="$SCRIPT_DIR/scripts/write-state.sh"

# Read hook input from stdin
INPUT=$(cat)

PROJECT_DIR=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null || echo "")
if [[ -z "$PROJECT_DIR" ]]; then
  exit 0
fi

# Find state file: prefer state.yaml, fall back to state.local.md
STATE_FILE=""
if [[ -f "$PROJECT_DIR/.claude/loop/state.yaml" ]]; then
  STATE_FILE="$PROJECT_DIR/.claude/loop/state.yaml"
elif [[ -f "$PROJECT_DIR/.claude/loop/state.local.md" ]]; then
  STATE_FILE="$PROJECT_DIR/.claude/loop/state.local.md"
fi

# No state file = no loop running
[[ -z "$STATE_FILE" ]] && exit 0

# Export for write-state.sh
export STATE_FILE

# Parse state (allow graceful fallback if any field is missing)
STATUS=$(grep '^status:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
SESSION_NAME=$(grep '^session_name:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
CYCLE=$(grep '^cycle:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
MAX_CYCLES=$(grep '^max_cycles:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
PHASE=$(grep '^current_phase:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
PROJECT_TYPE=$(grep '^project_type:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)

# If critical fields are empty, state file is malformed — allow exit
if [[ -z "$STATUS" || -z "$SESSION_NAME" || -z "$CYCLE" || -z "$MAX_CYCLES" ]]; then
  exit 0
fi

# Only block exit during active loop phases
case "$STATUS" in
  challenging|specifying|exploring|building|reviewing|auditing|deploying|testing)
    ;;
  *)
    # Not in an active loop phase — allow exit
    exit 0
    ;;
esac

# ── Wall-clock timeout check ──
STARTED_AT=$(grep '^started_at:' "$STATE_FILE" | head -1 | sed 's/^started_at: //' || true)
MAX_DURATION=$(grep '^max_duration:' "$STATE_FILE" | head -1 | awk '{print $2}' || true)
MAX_DURATION="${MAX_DURATION:-60}"

if [[ -n "$STARTED_AT" ]]; then
  # Cross-platform epoch conversion
  if [[ "$OSTYPE" == darwin* ]]; then
    START_EPOCH=$(date -jf '%Y-%m-%dT%H:%M:%SZ' "$STARTED_AT" '+%s' 2>/dev/null || echo "0")
  else
    START_EPOCH=$(date -d "$STARTED_AT" '+%s' 2>/dev/null || echo "0")
  fi
  NOW_EPOCH=$(date '+%s')

  if [[ "$START_EPOCH" -gt 0 ]]; then
    ELAPSED_MIN=$(( (NOW_EPOCH - START_EPOCH) / 60 ))
    if [[ "$ELAPSED_MIN" -ge "$MAX_DURATION" ]]; then
      bash "$WRITE_STATE" status=done current_phase=timed_out
      echo "{\"decision\": \"approve\", \"reason\": \"Loop timed out after ${ELAPSED_MIN} minutes (max: ${MAX_DURATION}). Session preserved for manual continuation or /buidl-resume.\"}" >&2
      exit 0
    fi
  fi
fi

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
  bash "$WRITE_STATE" status=done current_phase=done
  echo '{"decision": "approve", "reason": "Loop complete. Reviewer passed the PR."}' >&2
  exit 0
fi

# If max cycles reached, stop
if [[ "$CYCLE" -ge "$MAX_CYCLES" ]]; then
  bash "$WRITE_STATE" status=failed current_phase=failed
  cat >&2 << STOP_MSG
{"decision": "approve", "reason": "Loop reached max cycles ($MAX_CYCLES). Remaining findings are in $LATEST_REVIEW. The PR is open for manual review and fixing."}
STOP_MSG
  exit 0
fi

# Continue the loop — increment cycle and re-inject prompt
NEW_CYCLE=$((CYCLE + 1))
bash "$WRITE_STATE" cycle="$NEW_CYCLE" inner_retries=0 status=building current_phase=build

# Build the re-injection prompt
FINDINGS=""
if [[ -n "$LATEST_REVIEW" && -f "$LATEST_REVIEW" ]]; then
  FINDINGS=$(cat "$LATEST_REVIEW")
fi

WORKTREE_PATH=$(grep '^worktree_path:' "$STATE_FILE" | head -1 | sed 's/^worktree_path: //')

# Check for open issues from previous cycle
OPEN_ISSUES=""
ISSUES_DIR="$SESSION_DIR/artifacts/issues"
if [[ -d "$ISSUES_DIR" ]]; then
  for issue_file in "$ISSUES_DIR"/*.md; do
    [[ -f "$issue_file" ]] || continue
    if grep -q "status: open" "$issue_file" 2>/dev/null; then
      OPEN_ISSUES="${OPEN_ISSUES}"$'\n'"--- $(basename "$issue_file") ---"$'\n'"$(cat "$issue_file")"$'\n'
    fi
  done
fi

# Construct the continuation prompt based on project type
if [[ "$PROJECT_TYPE" == "opnet" ]]; then
  # OPNet multi-agent continuation
  ISSUE_SECTION=""
  if [[ -n "$OPEN_ISSUES" ]]; then
    ISSUE_SECTION="
OPEN CROSS-LAYER ISSUES (from artifacts/issues/):
$OPEN_ISSUES

Route each open issue to the responsible agent (check the 'to' field in each issue).
Re-dispatch limit: 2 cycles per agent pair. If limit reached, defer to auditor.
"
  fi

  PROMPT="The Loop: Build cycle $NEW_CYCLE of $MAX_CYCLES (OPNet Multi-Agent).

The reviewer found issues in the previous cycle. Route each finding to the responsible specialist agent:
- Contract issues → opnet-contract-dev
- Frontend issues → opnet-frontend-dev
- Backend issues → opnet-backend-dev
- Integration issues → fix in the appropriate layer
${ISSUE_SECTION}
After all fixes, re-run the audit (opnet-auditor), then re-run the full verify pipeline.

Work in the worktree at: $WORKTREE_PATH

REVIEWER FINDINGS:
$FINDINGS

Spec documents are at: $SESSION_DIR/spec/
Codebase context is at: $SESSION_DIR/context.md
Artifacts are at: $SESSION_DIR/artifacts/

Steps:
1. Parse findings and identify responsible agent for each
2. Check artifacts/issues/ for open cross-layer issues and route them
3. Spawn responsible agent(s) with their findings
4. Re-run opnet-auditor after fixes
5. If audit PASS: commit, push, update PR
6. Launch loop-reviewer for next review cycle"
else
  # Legacy single-builder continuation
  PROMPT="The Loop: Build cycle $NEW_CYCLE of $MAX_CYCLES.

The reviewer found issues in the previous cycle. Address each finding below, then re-run the full verify pipeline (lint, typecheck, build, test). When everything passes, commit, push, and update the PR.

Work in the worktree at: $WORKTREE_PATH

REVIEWER FINDINGS:
$FINDINGS

Spec documents are at: $SESSION_DIR/spec/
Codebase context is at: $SESSION_DIR/context.md

After fixing and verifying, launch the loop-reviewer agent to review the updated PR."
fi

# Use python to JSON-encode the prompt safely
JSON_PROMPT=$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "$PROMPT")

echo "{\"decision\": \"block\", \"reason\": $JSON_PROMPT}" >&2
exit 2
