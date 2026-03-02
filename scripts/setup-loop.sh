#!/bin/bash
# setup-loop.sh — Initialize a Loop session
# Usage: setup-loop.sh <session-name> <max-cycles> <max-retries> <builder-model> <reviewer-model>
#
# Creates:
#   .claude/loop/sessions/<name>/  (session directory)
#   .claude/loop/state.local.md    (state file with YAML frontmatter)
#   .claude/worktrees/loop-<name>  (git worktree on branch loop/<name>)

set -euo pipefail

SESSION_NAME="${1:?Usage: setup-loop.sh <name> [max-cycles] [max-retries] [builder-model] [reviewer-model]}"
MAX_CYCLES="${2:-3}"
MAX_RETRIES="${3:-5}"
BUILDER_MODEL="${4:-inherit}"
REVIEWER_MODEL="${5:-inherit}"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
LOOP_DIR="$PROJECT_DIR/.claude/loop"
SESSION_DIR="$LOOP_DIR/sessions/$SESSION_NAME"
STATE_FILE="$LOOP_DIR/state.local.md"
WORKTREE_PATH="$PROJECT_DIR/.claude/worktrees/loop-$SESSION_NAME"
BRANCH_NAME="loop/$SESSION_NAME"

# Check for existing running loop
if [[ -f "$STATE_FILE" ]]; then
  CURRENT_STATUS=$(grep '^status:' "$STATE_FILE" | head -1 | awk '{print $2}')
  if [[ "$CURRENT_STATUS" == "running" || "$CURRENT_STATUS" == "challenging" || "$CURRENT_STATUS" == "specifying" || "$CURRENT_STATUS" == "exploring" || "$CURRENT_STATUS" == "building" || "$CURRENT_STATUS" == "reviewing" ]]; then
    CURRENT_NAME=$(grep '^session_name:' "$STATE_FILE" | head -1 | awk '{print $2}')
    echo "ERROR: A loop is already running: $CURRENT_NAME (status: $CURRENT_STATUS)" >&2
    echo "Run /buidl-cancel to stop it first, or /buidl-status to check on it." >&2
    exit 2
  fi
fi

# Check we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not in a git repository. Initialize one first: git init" >&2
  exit 2
fi

# Create session directory
mkdir -p "$SESSION_DIR/spec" "$SESSION_DIR/reviews"

# Create worktree
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "WARNING: Worktree already exists at $WORKTREE_PATH. Reusing it." >&2
else
  # Create the branch if it doesn't exist
  if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
    git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
  else
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH"
  fi
fi

# Write state file
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$STATE_FILE" << EOF
---
status: challenging
session_name: $SESSION_NAME
cycle: 0
max_cycles: $MAX_CYCLES
inner_retries: 0
max_inner_retries: $MAX_RETRIES
worktree_path: $WORKTREE_PATH
worktree_branch: $BRANCH_NAME
pr_url: ""
pr_number: ""
builder_model: $BUILDER_MODEL
reviewer_model: $REVIEWER_MODEL
started_at: $TIMESTAMP
current_phase: challenge
---
EOF

echo "Loop initialized:"
echo "  Session: $SESSION_NAME"
echo "  Session dir: $SESSION_DIR"
echo "  Worktree: $WORKTREE_PATH"
echo "  Branch: $BRANCH_NAME"
echo "  Max cycles: $MAX_CYCLES"
echo "  Max retries: $MAX_RETRIES"
