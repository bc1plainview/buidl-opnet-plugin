#!/bin/bash
# setup-loop.sh — Initialize a Loop session
# Usage: setup-loop.sh <session-name> <max-cycles> <max-retries> <builder-model> <reviewer-model>
#
# Creates:
#   .claude/loop/sessions/<name>/  (session directory with artifacts subdirs)
#   .claude/loop/state.yaml        (state file, written atomically via write-state.sh)
#   .claude/worktrees/loop-<name>  (git worktree on branch loop/<name>)

set -euo pipefail

SESSION_NAME="${1:?Usage: setup-loop.sh <name> [max-cycles] [max-retries] [builder-model] [reviewer-model]}"
MAX_CYCLES="${2:-3}"
MAX_RETRIES="${3:-5}"
BUILDER_MODEL="${4:-inherit}"
REVIEWER_MODEL="${5:-inherit}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRITE_STATE="$SCRIPT_DIR/write-state.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
LOOP_DIR="$PROJECT_DIR/.claude/loop"
SESSION_DIR="$LOOP_DIR/sessions/$SESSION_NAME"
STATE_FILE="$LOOP_DIR/state.yaml"
WORKTREE_PATH="$PROJECT_DIR/.claude/worktrees/loop-$SESSION_NAME"
BRANCH_NAME="loop/$SESSION_NAME"

# Check for existing running loop (check both state.yaml and legacy state.local.md)
for candidate in "$STATE_FILE" "$LOOP_DIR/state.local.md"; do
  if [[ -f "$candidate" ]]; then
    CURRENT_STATUS=$(grep '^status:' "$candidate" | head -1 | awk '{print $2}')
    case "$CURRENT_STATUS" in
      running|challenging|specifying|exploring|building|reviewing|auditing|deploying|testing)
        CURRENT_NAME=$(grep '^session_name:' "$candidate" | head -1 | awk '{print $2}')
        echo "ERROR: A loop is already running: $CURRENT_NAME (status: $CURRENT_STATUS)" >&2
        echo "Run /buidl-cancel to stop it first, or /buidl-status to check on it." >&2
        exit 2
        ;;
    esac
  fi
done

# Check we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not in a git repository. Initialize one first: git init" >&2
  exit 2
fi

# Create session directory with artifact subdirectories
mkdir -p "$SESSION_DIR/spec" "$SESSION_DIR/reviews"
mkdir -p "$SESSION_DIR/artifacts/contract"
mkdir -p "$SESSION_DIR/artifacts/frontend"
mkdir -p "$SESSION_DIR/artifacts/backend"
mkdir -p "$SESSION_DIR/artifacts/audit"
mkdir -p "$SESSION_DIR/artifacts/deployment"
mkdir -p "$SESSION_DIR/artifacts/testing/screenshots"
mkdir -p "$SESSION_DIR/artifacts/issues"
# New v3 directories for dynamic agent generation and knowledge
mkdir -p "$SESSION_DIR/agents"
mkdir -p "$SESSION_DIR/knowledge"

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

# Detect project components from existing codebase
COMPONENT_CONTRACT="false"
COMPONENT_FRONTEND="false"
COMPONENT_BACKEND="false"
PROJECT_TYPE="generic"

# Check for OPNet contract indicators
if [[ -f "$PROJECT_DIR/asconfig.json" ]] || grep -q "btc-runtime" "$PROJECT_DIR/package.json" 2>/dev/null; then
  COMPONENT_CONTRACT="true"
  PROJECT_TYPE="opnet"
fi

# Check for frontend indicators
if [[ -f "$PROJECT_DIR/vite.config.ts" ]] || [[ -f "$PROJECT_DIR/vite.config.js" ]] || grep -q '"react"' "$PROJECT_DIR/package.json" 2>/dev/null; then
  COMPONENT_FRONTEND="true"
fi

# Check for backend indicators
if grep -q "hyper-express" "$PROJECT_DIR/package.json" 2>/dev/null || [[ -d "$PROJECT_DIR/server" ]] || [[ -d "$PROJECT_DIR/backend" ]]; then
  COMPONENT_BACKEND="true"
fi

# Check OPNet packages in package.json
if grep -q "@btc-vision" "$PROJECT_DIR/package.json" 2>/dev/null || grep -q '"opnet"' "$PROJECT_DIR/package.json" 2>/dev/null; then
  PROJECT_TYPE="opnet"
fi

# Prune learning store — keep only the 20 most recent retrospectives
LEARNING_DIR="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/learning"
if [[ -d "$LEARNING_DIR" ]]; then
  RETRO_COUNT=$(find "$LEARNING_DIR" -name "*.md" -not -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$RETRO_COUNT" -gt 20 ]]; then
    # Remove oldest files beyond the cap (sorted by modification time)
    find "$LEARNING_DIR" -name "*.md" -not -name ".gitkeep" -print0 2>/dev/null \
      | xargs -0 ls -1t \
      | tail -n +"21" \
      | xargs rm -f
    echo "Pruned learning store: kept 20 most recent, removed $((RETRO_COUNT - 20)) old retrospectives."
  fi
fi

# Write state file atomically via write-state.sh
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
export STATE_FILE
bash "$WRITE_STATE" << EOF
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
project_type: $PROJECT_TYPE
max_duration: 60
tokens_used: 0
phases_completed: []
components:
  contract: $COMPONENT_CONTRACT
  frontend: $COMPONENT_FRONTEND
  backend: $COMPONENT_BACKEND
execution_plan: ""
agent_status:
  opnet-contract-dev: pending
  opnet-frontend-dev: pending
  opnet-backend-dev: pending
  opnet-auditor: pending
  opnet-deployer: pending
  opnet-ui-tester: pending
  loop-reviewer: pending
current_step: 0
audit_verdict: ""
audit_cycles: 0
deployment_address: ""
deployment_network: ""
redispatch_count: {}
issues_resolved: 0
issues_deferred: 0
EOF

echo "Loop initialized:"
echo "  Session: $SESSION_NAME"
echo "  Session dir: $SESSION_DIR"
echo "  Worktree: $WORKTREE_PATH"
echo "  Branch: $BRANCH_NAME"
echo "  Max cycles: $MAX_CYCLES"
echo "  Max retries: $MAX_RETRIES"
echo "  Max duration: 60 minutes"
echo "  Project type: $PROJECT_TYPE"
echo "  Components: contract=$COMPONENT_CONTRACT frontend=$COMPONENT_FRONTEND backend=$COMPONENT_BACKEND"
echo "  Artifacts dir: $SESSION_DIR/artifacts/"
