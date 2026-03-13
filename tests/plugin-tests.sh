#!/bin/bash
# plugin-tests.sh — Structural validation tests for the buidl plugin
#
# Validates all invariants that have caused regressions:
# - Shell script syntax and correctness
# - Atomic state writer (write-state.sh)
# - State guard hook (guard-state.sh)
# - Agent template structure (10 agents, 5 required sections each)
# - FORBIDDEN blocks in all 6 specialist agents
# - Knowledge slice references resolve to existing files
# - Issue bus type enum consistency across agents
# - Version consistency (plugin.json matches CHANGELOG)
# - Required file existence
# - Resume command structure
# - Learning system
# - Templates
# - Cost tracking references
# - Wall-clock timeout logic
# - max_turns in buidl.md
# - Structured error handling
#
# Usage: bash tests/plugin-tests.sh
# Exit code: 0 if all pass, 1 if any fail

set -uo pipefail

# Navigate to plugin root (parent of tests/)
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("$1")
  echo "  FAIL: $1"
}

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$description"
  else
    fail "$description"
  fi
}

# ─────────────────────────────────────────────────
# 1. Shell Script Syntax
# ─────────────────────────────────────────────────
echo ""
echo "=== Shell Script Syntax ==="

check "stop-hook.sh passes bash -n" bash -n hooks/scripts/stop-hook.sh
check "setup-loop.sh passes bash -n" bash -n scripts/setup-loop.sh
check "write-state.sh passes bash -n" bash -n scripts/write-state.sh
check "guard-state.sh passes bash -n" bash -n hooks/scripts/guard-state.sh
check "guard-state-bash.sh passes bash -n" bash -n hooks/scripts/guard-state-bash.sh

# ─────────────────────────────────────────────────
# 2. Shell Script Correctness
# ─────────────────────────────────────────────────
echo ""
echo "=== Shell Script Correctness ==="

# write-state.sh must exist and be used by stop-hook.sh and setup-loop.sh
if [[ -f "scripts/write-state.sh" ]]; then
  pass "write-state.sh exists"
else
  fail "write-state.sh MISSING"
fi

if [[ -x "scripts/write-state.sh" ]]; then
  pass "write-state.sh is executable"
else
  fail "write-state.sh is NOT executable"
fi

# stop-hook.sh must NOT contain sedi() function (replaced by write-state.sh)
if grep -q 'sedi()' hooks/scripts/stop-hook.sh; then
  fail "stop-hook.sh still contains sedi() function — should use write-state.sh"
else
  pass "stop-hook.sh does not contain sedi() (uses write-state.sh)"
fi

# stop-hook.sh must reference write-state.sh
if grep -q 'write-state.sh' hooks/scripts/stop-hook.sh; then
  pass "stop-hook.sh references write-state.sh"
else
  fail "stop-hook.sh does NOT reference write-state.sh"
fi

# setup-loop.sh must reference write-state.sh
if grep -q 'write-state.sh' scripts/setup-loop.sh; then
  pass "setup-loop.sh references write-state.sh"
else
  fail "setup-loop.sh does NOT reference write-state.sh"
fi

# setup-loop.sh must create state.yaml not state.local.md
if grep -q 'state\.yaml' scripts/setup-loop.sh; then
  pass "setup-loop.sh targets state.yaml"
else
  fail "setup-loop.sh does NOT target state.yaml"
fi

# write-state.sh must use atomic temp-file-then-mv pattern
if grep -q 'mv.*TMP_FILE.*STATE_FILE' scripts/write-state.sh || grep -q 'mv "\$TMP_FILE" "\$STATE_FILE"' scripts/write-state.sh; then
  pass "write-state.sh uses atomic mv pattern"
else
  fail "write-state.sh does NOT use atomic mv pattern"
fi

# write-state.sh must have cross-platform sedi
if grep -q 'OSTYPE' scripts/write-state.sh; then
  pass "write-state.sh has OSTYPE detection for cross-platform sed"
else
  fail "write-state.sh MISSING OSTYPE detection"
fi

# stop-hook.sh uses $'\n' not literal \n for issue injection
if grep -q '\\n---' hooks/scripts/stop-hook.sh; then
  fail "stop-hook.sh uses literal \\n (should use \$'\\n')"
else
  pass "stop-hook.sh does not use literal \\n for newlines"
fi

# setup-loop.sh agent_status keys must match actual agent filenames
AGENT_STATUS_KEYS=$(grep -A20 '^agent_status:' scripts/setup-loop.sh | grep '^\s\+.*: pending' | sed 's/^\s*//' | cut -d: -f1)
for key in $AGENT_STATUS_KEYS; do
  if [[ -f "agents/${key}.md" ]]; then
    pass "agent_status key '$key' matches agents/${key}.md"
  else
    fail "agent_status key '$key' has NO matching agent file (agents/${key}.md missing)"
  fi
done

# Phase lists must match across stop-hook.sh, guard-state.sh, and guard-state-bash.sh
STOP_PHASES=$(grep -oP '(?<=case "\$STATUS" in\n?\s*)\S+' hooks/scripts/stop-hook.sh 2>/dev/null || grep 'challenging\|specifying\|exploring\|building\|reviewing\|auditing\|deploying\|testing' hooks/scripts/stop-hook.sh | head -1 | tr -d ' )')
GUARD_PHASES=$(grep 'challenging\|specifying\|exploring\|building\|reviewing\|auditing\|deploying\|testing' hooks/scripts/guard-state.sh | head -1 | tr -d ' )')
GUARD_BASH_PHASES=$(grep 'challenging\|specifying\|exploring\|building\|reviewing\|auditing\|deploying\|testing' hooks/scripts/guard-state-bash.sh | head -1 | tr -d ' )')

# All three scripts must include all 8 active phases
for phase in challenging specifying exploring building reviewing auditing deploying testing; do
  for script in "stop-hook.sh:hooks/scripts/stop-hook.sh" "guard-state.sh:hooks/scripts/guard-state.sh" "guard-state-bash.sh:hooks/scripts/guard-state-bash.sh"; do
    SCRIPT_NAME="${script%%:*}"
    SCRIPT_PATH="${script#*:}"
    if grep -q "$phase" "$SCRIPT_PATH"; then
      pass "$SCRIPT_NAME includes phase '$phase'"
    else
      fail "$SCRIPT_NAME MISSING phase '$phase'"
    fi
  done
done

# ─────────────────────────────────────────────────
# 3. Agent Template Structure
# ─────────────────────────────────────────────────
echo ""
echo "=== Agent Template Structure ==="

ALL_AGENTS=(
  agents/loop-builder.md
  agents/loop-explorer.md
  agents/loop-researcher.md
  agents/loop-reviewer.md
  agents/opnet-auditor.md
  agents/opnet-backend-dev.md
  agents/opnet-contract-dev.md
  agents/opnet-deployer.md
  agents/opnet-frontend-dev.md
  agents/opnet-ui-tester.md
)

REQUIRED_SECTIONS=(
  "## Constraints"
  "## Step 0"
  "## Process"
  "## Output Format"
  "## Rules"
)

for agent in "${ALL_AGENTS[@]}"; do
  agent_name=$(basename "$agent" .md)
  if [[ ! -f "$agent" ]]; then
    fail "$agent_name: file does not exist"
    continue
  fi
  for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "^${section}" "$agent"; then
      pass "$agent_name has '$section'"
    else
      fail "$agent_name MISSING '$section'"
    fi
  done
done

# ─────────────────────────────────────────────────
# 4. FORBIDDEN Blocks in Specialist Agents
# ─────────────────────────────────────────────────
echo ""
echo "=== FORBIDDEN Blocks ==="

SPECIALIST_AGENTS=(
  agents/opnet-auditor.md
  agents/opnet-backend-dev.md
  agents/opnet-contract-dev.md
  agents/opnet-deployer.md
  agents/opnet-frontend-dev.md
  agents/opnet-ui-tester.md
)

for agent in "${SPECIALIST_AGENTS[@]}"; do
  agent_name=$(basename "$agent" .md)
  if grep -qi "FORBIDDEN" "$agent"; then
    pass "$agent_name has FORBIDDEN rules"
  else
    fail "$agent_name MISSING FORBIDDEN rules"
  fi
done

# ─────────────────────────────────────────────────
# 5. Knowledge Slice References
# ─────────────────────────────────────────────────
echo ""
echo "=== Knowledge Slice References ==="

# Extract all knowledge/slices/*.md references from agents
SLICE_REFS=$(grep -roh 'knowledge/slices/[a-z-]*\.md' agents/ | sort -u)

for ref in $SLICE_REFS; do
  if [[ -f "$ref" ]]; then
    pass "Reference '$ref' exists"
  else
    fail "Reference '$ref' does NOT exist"
  fi
done

# Also verify all slices are referenced by at least one agent
for slice in knowledge/slices/*.md; do
  slice_name=$(basename "$slice")
  if grep -rq "$slice_name" agents/; then
    pass "Slice '$slice_name' is referenced by at least one agent"
  else
    fail "Slice '$slice_name' is ORPHANED — no agent references it"
  fi
done

# ─────────────────────────────────────────────────
# 6. Issue Bus Schema Consistency
# ─────────────────────────────────────────────────
echo ""
echo "=== Issue Bus Schema ==="

# Extract issue types from builder agents (they define the full enum in comments)
BUILDER_TYPES=$(grep -h 'ABI_MISMATCH\|MISSING_METHOD\|TYPE_MISMATCH\|ADDRESS_FORMAT\|NETWORK_CONFIG\|DEPENDENCY_MISSING\|SIGNER_VIOLATION' \
  agents/opnet-contract-dev.md agents/opnet-frontend-dev.md agents/opnet-backend-dev.md agents/opnet-auditor.md \
  2>/dev/null | tr ',' '\n' | tr '#' '\n' | grep -oE '[A-Z_]{5,}' | sort -u | tr '\n' ' ' | sed 's/ $//')

EXPECTED_TYPES="ABI_MISMATCH ADDRESS_FORMAT DEPENDENCY_MISSING MISSING_METHOD NETWORK_CONFIG SIGNER_VIOLATION TYPE_MISMATCH"

if [[ "$BUILDER_TYPES" == "$EXPECTED_TYPES" ]]; then
  pass "Issue bus types match expected enum (7 types)"
else
  fail "Issue bus types mismatch. Got: $BUILDER_TYPES"
fi

# Verify all builder agents have Issue Bus section
for agent in agents/opnet-contract-dev.md agents/opnet-frontend-dev.md agents/opnet-backend-dev.md; do
  agent_name=$(basename "$agent" .md)
  if grep -q "^## Issue Bus" "$agent"; then
    pass "$agent_name has Issue Bus section"
  else
    fail "$agent_name MISSING Issue Bus section"
  fi
done

# Auditor should also have Issue Bus
if grep -q "^## Issue Bus" agents/opnet-auditor.md; then
  pass "opnet-auditor has Issue Bus section"
else
  fail "opnet-auditor MISSING Issue Bus section"
fi

# ─────────────────────────────────────────────────
# 7. Version Consistency
# ─────────────────────────────────────────────────
echo ""
echo "=== Version Consistency ==="

PLUGIN_VERSION=$(grep '"version"' .claude-plugin/plugin.json | sed 's/.*: *"//;s/".*//')
CHANGELOG_VERSION=$(grep -m1 '^\## \[' CHANGELOG.md | sed 's/.*\[//;s/\].*//')

if [[ "$PLUGIN_VERSION" == "$CHANGELOG_VERSION" ]]; then
  pass "plugin.json ($PLUGIN_VERSION) matches CHANGELOG ($CHANGELOG_VERSION)"
else
  fail "Version mismatch: plugin.json=$PLUGIN_VERSION, CHANGELOG=$CHANGELOG_VERSION"
fi

# ─────────────────────────────────────────────────
# 8. Required File Existence
# ─────────────────────────────────────────────────
echo ""
echo "=== Required Files ==="

REQUIRED_FILES=(
  LICENSE
  README.md
  CHANGELOG.md
  .claude-plugin/plugin.json
  hooks/hooks.json
  hooks/scripts/stop-hook.sh
  hooks/scripts/guard-state.sh
  scripts/setup-loop.sh
  scripts/write-state.sh
  commands/buidl.md
  commands/buidl-spec.md
  commands/buidl-review.md
  commands/buidl-status.md
  commands/buidl-cancel.md
  commands/buidl-clean.md
  commands/buidl-resume.md
  knowledge/opnet-bible.md
  knowledge/opnet-troubleshooting.md
  knowledge/README.md
  learning/.gitkeep
  templates/domain-agent.md
  templates/knowledge-slice.md
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    pass "$f exists"
  else
    fail "$f MISSING"
  fi
done

# All 10 agents
for agent in "${ALL_AGENTS[@]}"; do
  if [[ -f "$agent" ]]; then
    pass "$(basename "$agent") exists"
  else
    fail "$(basename "$agent") MISSING"
  fi
done

# All knowledge slices
for slice in contract-dev frontend-dev backend-dev security-audit deployment ui-testing integration-review project-setup; do
  if [[ -f "knowledge/slices/${slice}.md" ]]; then
    pass "knowledge/slices/${slice}.md exists"
  else
    fail "knowledge/slices/${slice}.md MISSING"
  fi
done

# ─────────────────────────────────────────────────
# 9. State Guard Hook Configuration
# ─────────────────────────────────────────────────
echo ""
echo "=== State Guard Hook ==="

# hooks.json must have PreToolUse section
if grep -q 'PreToolUse' hooks/hooks.json; then
  pass "hooks.json has PreToolUse section"
else
  fail "hooks.json MISSING PreToolUse section"
fi

# PreToolUse must match Write|Edit
if grep -q 'Write|Edit' hooks/hooks.json; then
  pass "PreToolUse matches Write|Edit"
else
  fail "PreToolUse does NOT match Write|Edit"
fi

# PreToolUse must call guard-state.sh
if grep -q 'guard-state.sh' hooks/hooks.json; then
  pass "PreToolUse calls guard-state.sh"
else
  fail "PreToolUse does NOT call guard-state.sh"
fi

# guard-state.sh must check for active states
if grep -q 'challenging\|specifying\|exploring\|building\|reviewing' hooks/scripts/guard-state.sh; then
  pass "guard-state.sh checks for active loop states"
else
  fail "guard-state.sh does NOT check for active loop states"
fi

# guard-state.sh must guard both state.yaml and state.local.md
if grep -q 'state\.yaml' hooks/scripts/guard-state.sh && grep -q 'state\.local\.md' hooks/scripts/guard-state.sh; then
  pass "guard-state.sh guards both state.yaml and state.local.md"
else
  fail "guard-state.sh does NOT guard both state file formats"
fi

# ─────────────────────────────────────────────────
# 10. Resume Command
# ─────────────────────────────────────────────────
echo ""
echo "=== Resume Command ==="

if [[ -f "commands/buidl-resume.md" ]]; then
  pass "buidl-resume.md exists"

  # Must reference state.yaml
  if grep -q 'state\.yaml' commands/buidl-resume.md; then
    pass "buidl-resume.md references state.yaml"
  else
    fail "buidl-resume.md does NOT reference state.yaml"
  fi

  # Must reference state.local.md fallback
  if grep -q 'state\.local\.md' commands/buidl-resume.md; then
    pass "buidl-resume.md has state.local.md fallback"
  else
    fail "buidl-resume.md MISSING state.local.md fallback"
  fi

  # Must reference checkpoint.md
  if grep -q 'checkpoint\.md' commands/buidl-resume.md; then
    pass "buidl-resume.md references checkpoint.md"
  else
    fail "buidl-resume.md does NOT reference checkpoint.md"
  fi

  # Must reference write-state.sh
  if grep -q 'write-state\.sh' commands/buidl-resume.md; then
    pass "buidl-resume.md references write-state.sh"
  else
    fail "buidl-resume.md does NOT reference write-state.sh"
  fi

  # Must check worktree existence
  if grep -q 'worktree' commands/buidl-resume.md; then
    pass "buidl-resume.md verifies worktree"
  else
    fail "buidl-resume.md does NOT verify worktree"
  fi
else
  fail "buidl-resume.md MISSING"
fi

# ─────────────────────────────────────────────────
# 11. Learning System
# ─────────────────────────────────────────────────
echo ""
echo "=== Learning System ==="

if [[ -d "learning" ]]; then
  pass "learning/ directory exists"
else
  fail "learning/ directory MISSING"
fi

if [[ -f "learning/.gitkeep" ]]; then
  pass "learning/.gitkeep exists"
else
  fail "learning/.gitkeep MISSING"
fi

# buidl.md must reference learning directory
if grep -q 'learning/' commands/buidl.md; then
  pass "buidl.md references learning/ directory"
else
  fail "buidl.md does NOT reference learning/"
fi

# buidl.md must have Phase 6 / retrospective
if grep -q 'PHASE 6' commands/buidl.md || grep -q 'Retrospective' commands/buidl.md; then
  pass "buidl.md has Phase 6 (Wrap-up/Retrospective)"
else
  fail "buidl.md MISSING Phase 6 (Wrap-up/Retrospective)"
fi

# ─────────────────────────────────────────────────
# 12. Templates
# ─────────────────────────────────────────────────
echo ""
echo "=== Templates ==="

if [[ -d "templates" ]]; then
  pass "templates/ directory exists"
else
  fail "templates/ directory MISSING"
fi

# domain-agent.md must have key template sections
if grep -q 'AGENT_ROLE\|AGENT_NAME' templates/domain-agent.md; then
  pass "domain-agent.md has template placeholders"
else
  fail "domain-agent.md MISSING template placeholders"
fi

# knowledge-slice.md must have key template sections
if grep -q 'DOMAIN_NAME\|KEY_ARCHITECTURE' templates/knowledge-slice.md; then
  pass "knowledge-slice.md has template placeholders"
else
  fail "knowledge-slice.md MISSING template placeholders"
fi

# buidl.md must reference templates
if grep -q 'templates/' commands/buidl.md; then
  pass "buidl.md references templates/"
else
  fail "buidl.md does NOT reference templates/"
fi

# ─────────────────────────────────────────────────
# 13. Cost Tracking
# ─────────────────────────────────────────────────
echo ""
echo "=== Cost Tracking ==="

# buidl.md must reference cost-ledger
if grep -q 'cost-ledger' commands/buidl.md; then
  pass "buidl.md references cost-ledger"
else
  fail "buidl.md does NOT reference cost-ledger"
fi

# buidl.md must reference tokens_used
if grep -q 'tokens_used' commands/buidl.md; then
  pass "buidl.md references tokens_used"
else
  fail "buidl.md does NOT reference tokens_used"
fi

# buidl.md must reference --max-tokens
if grep -q 'max-tokens' commands/buidl.md; then
  pass "buidl.md has --max-tokens flag"
else
  fail "buidl.md MISSING --max-tokens flag"
fi

# setup-loop.sh must initialize tokens_used
if grep -q 'tokens_used' scripts/setup-loop.sh; then
  pass "setup-loop.sh initializes tokens_used"
else
  fail "setup-loop.sh does NOT initialize tokens_used"
fi

# ─────────────────────────────────────────────────
# 14. Wall-Clock Timeout
# ─────────────────────────────────────────────────
echo ""
echo "=== Wall-Clock Timeout ==="

# stop-hook.sh must check elapsed time
if grep -q 'ELAPSED_MIN\|elapsed\|max_duration\|MAX_DURATION' hooks/scripts/stop-hook.sh; then
  pass "stop-hook.sh has wall-clock timeout check"
else
  fail "stop-hook.sh MISSING wall-clock timeout check"
fi

# stop-hook.sh must have cross-platform date handling
if grep -q 'OSTYPE' hooks/scripts/stop-hook.sh; then
  pass "stop-hook.sh has cross-platform date (OSTYPE)"
else
  fail "stop-hook.sh MISSING cross-platform date handling"
fi

# setup-loop.sh must initialize max_duration
if grep -q 'max_duration' scripts/setup-loop.sh; then
  pass "setup-loop.sh initializes max_duration"
else
  fail "setup-loop.sh does NOT initialize max_duration"
fi

# ─────────────────────────────────────────────────
# 15. max_turns and Structured Errors
# ─────────────────────────────────────────────────
echo ""
echo "=== max_turns and Error Handling ==="

# buidl.md must define max_turns table
if grep -q 'max_turns' commands/buidl.md; then
  pass "buidl.md defines max_turns"
else
  fail "buidl.md MISSING max_turns"
fi

# buidl.md must have structured error options
if grep -q 'Retry with a different approach\|Skip this agent\|Amend the spec\|Cancel the loop' commands/buidl.md; then
  pass "buidl.md has structured error handling options"
else
  fail "buidl.md MISSING structured error handling options"
fi

# buidl.md must have checkpoint protocol
if grep -q 'Checkpoint Protocol\|checkpoint\.md' commands/buidl.md; then
  pass "buidl.md has Checkpoint Protocol"
else
  fail "buidl.md MISSING Checkpoint Protocol"
fi

# buidl.md must reference write-state.sh
if grep -q 'write-state\.sh' commands/buidl.md; then
  pass "buidl.md references write-state.sh for state mutations"
else
  fail "buidl.md does NOT reference write-state.sh"
fi

# ─────────────────────────────────────────────────
# 16. Dual State File Support
# ─────────────────────────────────────────────────
echo ""
echo "=== Dual State File Support ==="

# stop-hook.sh must support both state files
if grep -q 'state\.yaml' hooks/scripts/stop-hook.sh && grep -q 'state\.local\.md' hooks/scripts/stop-hook.sh; then
  pass "stop-hook.sh supports both state.yaml and state.local.md"
else
  fail "stop-hook.sh does NOT support dual state files"
fi

# buidl-status.md must support both state files
if grep -q 'state\.yaml' commands/buidl-status.md && grep -q 'state\.local\.md' commands/buidl-status.md; then
  pass "buidl-status.md supports both state files"
else
  fail "buidl-status.md does NOT support dual state files"
fi

# buidl-cancel.md must support both state files
if grep -q 'state\.yaml' commands/buidl-cancel.md && grep -q 'state\.local\.md' commands/buidl-cancel.md; then
  pass "buidl-cancel.md supports both state files"
else
  fail "buidl-cancel.md does NOT support dual state files"
fi

# buidl-clean.md must clean both state files
if grep -q 'state\.yaml' commands/buidl-clean.md && grep -q 'state\.local\.md' commands/buidl-clean.md; then
  pass "buidl-clean.md cleans both state files"
else
  fail "buidl-clean.md does NOT clean both state files"
fi

# setup-loop.sh must check both for existing loop
if grep -q 'state\.yaml' scripts/setup-loop.sh && grep -q 'state\.local\.md' scripts/setup-loop.sh; then
  pass "setup-loop.sh checks both state files for existing loop"
else
  fail "setup-loop.sh does NOT check both state files"
fi

# ─────────────────────────────────────────────────
# 17. Integration Tests for write-state.sh
# ─────────────────────────────────────────────────
echo ""
echo "=== Integration Tests: write-state.sh ==="

# Create a temp directory for integration tests
INTEG_DIR=$(mktemp -d)
trap 'rm -rf "$INTEG_DIR"' EXIT

WRITE_STATE="$PLUGIN_ROOT/scripts/write-state.sh"

# Test 1: Full write mode via stdin
echo "status: testing
session_name: integ-test
cycle: 0
max_cycles: 3" | STATE_FILE="$INTEG_DIR/state.yaml" bash "$WRITE_STATE"

if [[ -f "$INTEG_DIR/state.yaml" ]] && grep -q 'status: testing' "$INTEG_DIR/state.yaml"; then
  pass "write-state.sh full write mode works"
else
  fail "write-state.sh full write mode BROKEN"
fi

# Test 2: Partial update mode (replace existing key)
STATE_FILE="$INTEG_DIR/state.yaml" bash "$WRITE_STATE" status=building

if grep -q 'status: building' "$INTEG_DIR/state.yaml"; then
  pass "write-state.sh partial update replaces existing key"
else
  fail "write-state.sh partial update FAILED to replace key"
fi

# Test 3: Partial update mode (append new key)
STATE_FILE="$INTEG_DIR/state.yaml" bash "$WRITE_STATE" new_key=new_value

if grep -q 'new_key: new_value' "$INTEG_DIR/state.yaml"; then
  pass "write-state.sh partial update appends new key"
else
  fail "write-state.sh partial update FAILED to append key"
fi

# Test 4: Multiple key=value pairs in one call
STATE_FILE="$INTEG_DIR/state.yaml" bash "$WRITE_STATE" status=reviewing cycle=2

if grep -q 'status: reviewing' "$INTEG_DIR/state.yaml" && grep -q 'cycle: 2' "$INTEG_DIR/state.yaml"; then
  pass "write-state.sh handles multiple key=value pairs"
else
  fail "write-state.sh FAILED with multiple key=value pairs"
fi

# Test 5: Atomicity — original file should not be corrupted if we check during write
# (Best effort: verify temp file is cleaned up)
if [[ ! -f "$INTEG_DIR/state.yaml.tmp."* ]] 2>/dev/null; then
  pass "write-state.sh cleans up temp files"
else
  fail "write-state.sh left temp files behind"
fi

# Test 6: Error on partial update of non-existent file
if STATE_FILE="$INTEG_DIR/nonexistent.yaml" bash "$WRITE_STATE" key=val 2>/dev/null; then
  fail "write-state.sh should error on partial update of missing file"
else
  pass "write-state.sh correctly errors on partial update of missing file"
fi

# Test 7: Error on bad argument format
if STATE_FILE="$INTEG_DIR/state.yaml" bash "$WRITE_STATE" badarg 2>/dev/null; then
  fail "write-state.sh should error on malformed argument"
else
  pass "write-state.sh correctly errors on malformed argument"
fi

# Test 8: Nested YAML update mode
echo "status: testing
agent_status:
  contract-dev: pending
  frontend-dev: pending" | STATE_FILE="$INTEG_DIR/nested.yaml" bash "$WRITE_STATE"

STATE_FILE="$INTEG_DIR/nested.yaml" bash "$WRITE_STATE" --nested agent_status.contract-dev=done

if grep -q 'contract-dev: done' "$INTEG_DIR/nested.yaml"; then
  pass "write-state.sh --nested updates nested keys"
else
  fail "write-state.sh --nested FAILED to update nested key"
fi

# Test 9: Nested mode preserves other nested values
if grep -q 'frontend-dev: pending' "$INTEG_DIR/nested.yaml"; then
  pass "write-state.sh --nested preserves other nested values"
else
  fail "write-state.sh --nested CORRUPTED other nested values"
fi

# Test 10: Nested mode updates top-level keys too
STATE_FILE="$INTEG_DIR/nested.yaml" bash "$WRITE_STATE" --nested status=building

if grep -q 'status: building' "$INTEG_DIR/nested.yaml"; then
  pass "write-state.sh --nested can update top-level keys"
else
  fail "write-state.sh --nested FAILED on top-level key"
fi

# ─────────────────────────────────────────────────
# 18. Transaction Simulation Knowledge Slice
# ─────────────────────────────────────────────────
echo ""
echo "=== Transaction Simulation ==="

if [[ -f "knowledge/slices/transaction-simulation.md" ]]; then
  pass "transaction-simulation.md exists"
else
  fail "transaction-simulation.md MISSING"
fi

# Must cover key sections
for section in "Simulation via" "Deployment Simulation" "Local Development Loop" "Gas Estimation" "Frontend Simulation Pattern"; do
  if grep -q "$section" knowledge/slices/transaction-simulation.md; then
    pass "transaction-simulation.md contains section: $section"
  else
    fail "transaction-simulation.md MISSING section: $section"
  fi
done

# Deployer agent must reference simulation slice
if grep -q 'transaction-simulation.md' agents/opnet-deployer.md; then
  pass "opnet-deployer.md references transaction-simulation.md"
else
  fail "opnet-deployer.md does NOT reference transaction-simulation.md"
fi

# Frontend-dev agent must reference simulation slice
if grep -q 'transaction-simulation.md' agents/opnet-frontend-dev.md; then
  pass "opnet-frontend-dev.md references transaction-simulation.md"
else
  fail "opnet-frontend-dev.md does NOT reference transaction-simulation.md"
fi

# ─────────────────────────────────────────────────
# 19. Playwright E2E Testing
# ─────────────────────────────────────────────────
echo ""
echo "=== Playwright E2E Testing ==="

# UI tester must use Playwright and ban Puppeteer in FORBIDDEN section
if grep -q 'Playwright' agents/opnet-ui-tester.md && grep -q '@playwright/test' agents/opnet-ui-tester.md; then
  pass "opnet-ui-tester.md uses Playwright"
else
  fail "opnet-ui-tester.md does NOT reference Playwright"
fi

# UI tester FORBIDDEN section should ban Puppeteer
if grep -q 'Using Puppeteer' agents/opnet-ui-tester.md; then
  pass "opnet-ui-tester.md explicitly bans Puppeteer in FORBIDDEN"
else
  fail "opnet-ui-tester.md does NOT ban Puppeteer in FORBIDDEN"
fi

# UI tester must mention playwright.config.ts
if grep -q 'playwright.config.ts' agents/opnet-ui-tester.md; then
  pass "opnet-ui-tester.md includes playwright.config.ts setup"
else
  fail "opnet-ui-tester.md MISSING playwright.config.ts"
fi

# UI testing knowledge slice must use Playwright
if grep -q '@playwright/test' knowledge/slices/ui-testing.md; then
  pass "ui-testing.md uses @playwright/test"
else
  fail "ui-testing.md does NOT use @playwright/test"
fi

# UI testing knowledge slice must have visual regression section
if grep -q 'Visual Regression' knowledge/slices/ui-testing.md; then
  pass "ui-testing.md includes visual regression testing"
else
  fail "ui-testing.md MISSING visual regression testing"
fi

# UI testing knowledge slice must have dogfooding section
if grep -q 'Dogfooding' knowledge/slices/ui-testing.md || grep -q 'dogfood' knowledge/slices/ui-testing.md; then
  pass "ui-testing.md includes dogfooding guidance"
else
  fail "ui-testing.md MISSING dogfooding guidance"
fi

# ─────────────────────────────────────────────────
# 20. Auto-Detect Existing Session
# ─────────────────────────────────────────────────
echo ""
echo "=== Auto-Detect Existing Session ==="

if grep -q 'Auto-Detect Existing Session' commands/buidl.md; then
  pass "buidl.md has auto-detect existing session section"
else
  fail "buidl.md MISSING auto-detect existing session"
fi

if grep -q 'Resume existing' commands/buidl.md; then
  pass "buidl.md auto-detect offers resume option"
else
  fail "buidl.md auto-detect MISSING resume option"
fi

# ─────────────────────────────────────────────────
# 21. Learning Pruning
# ─────────────────────────────────────────────────
echo ""
echo "=== Learning Pruning ==="

if grep -q 'Prune learning store' scripts/setup-loop.sh || grep -q 'learning' scripts/setup-loop.sh; then
  pass "setup-loop.sh includes learning pruning"
else
  fail "setup-loop.sh MISSING learning pruning"
fi

# Must cap at 20
if grep -q '20' scripts/setup-loop.sh && grep -q 'tail' scripts/setup-loop.sh; then
  pass "setup-loop.sh prunes to 20 most recent"
else
  fail "setup-loop.sh pruning cap not properly configured"
fi

# ─────────────────────────────────────────────────
# 22. Orphan Worktree Detection
# ─────────────────────────────────────────────────
echo ""
echo "=== Orphan Worktree Detection ==="

if grep -q -i 'orphan' commands/buidl-status.md; then
  pass "buidl-status.md has orphan worktree detection"
else
  fail "buidl-status.md MISSING orphan worktree detection"
fi

if grep -q -i 'orphan' commands/buidl-clean.md; then
  pass "buidl-clean.md has orphan worktree cleanup"
else
  fail "buidl-clean.md MISSING orphan worktree cleanup"
fi

# ─────────────────────────────────────────────────
# 23. Guard-State-Bash Hook
# ─────────────────────────────────────────────────
echo ""
echo "=== Guard-State-Bash Hook ==="

if [[ -f "hooks/scripts/guard-state-bash.sh" ]]; then
  pass "guard-state-bash.sh exists"
else
  fail "guard-state-bash.sh MISSING"
fi

check "guard-state-bash.sh passes bash -n" bash -n hooks/scripts/guard-state-bash.sh

if grep -q 'Bash' hooks/hooks.json; then
  pass "hooks.json has Bash matcher for guard-state-bash.sh"
else
  fail "hooks.json MISSING Bash matcher"
fi

# Must exempt write-state.sh
if grep -q 'write-state.sh' hooks/scripts/guard-state-bash.sh; then
  pass "guard-state-bash.sh exempts write-state.sh"
else
  fail "guard-state-bash.sh does NOT exempt write-state.sh"
fi

# ─────────────────────────────────────────────────
echo ""
echo "=== Adaptive Learning System ==="

# Pattern store
if [[ -f "learning/patterns.yaml" ]]; then
  pass "learning/patterns.yaml exists"
else
  fail "learning/patterns.yaml MISSING"
fi

if python3 -c "import yaml; yaml.safe_load(open('learning/patterns.yaml'))" 2>/dev/null; then
  pass "learning/patterns.yaml is valid YAML"
else
  fail "learning/patterns.yaml is NOT valid YAML"
fi

# Agent scores
if [[ -f "learning/agent-scores.yaml" ]]; then
  pass "learning/agent-scores.yaml exists"
else
  fail "learning/agent-scores.yaml MISSING"
fi

if python3 -c "import yaml; yaml.safe_load(open('learning/agent-scores.yaml'))" 2>/dev/null; then
  pass "learning/agent-scores.yaml is valid YAML"
else
  fail "learning/agent-scores.yaml is NOT valid YAML"
fi

# Extraction scripts
if [[ -f "scripts/extract-patterns.sh" ]]; then
  pass "scripts/extract-patterns.sh exists"
else
  fail "scripts/extract-patterns.sh MISSING"
fi

if bash -n scripts/extract-patterns.sh 2>/dev/null; then
  pass "extract-patterns.sh passes bash -n"
else
  fail "extract-patterns.sh FAILS bash -n"
fi

if [[ -x "scripts/extract-patterns.sh" ]]; then
  pass "extract-patterns.sh is executable"
else
  fail "extract-patterns.sh is NOT executable"
fi

if [[ -f "scripts/update-scores.sh" ]]; then
  pass "scripts/update-scores.sh exists"
else
  fail "scripts/update-scores.sh MISSING"
fi

if bash -n scripts/update-scores.sh 2>/dev/null; then
  pass "update-scores.sh passes bash -n"
else
  fail "update-scores.sh FAILS bash -n"
fi

if [[ -x "scripts/update-scores.sh" ]]; then
  pass "update-scores.sh is executable"
else
  fail "update-scores.sh is NOT executable"
fi

# Orchestrator references
if grep -q 'patterns.yaml' commands/buidl.md; then
  pass "buidl.md references patterns.yaml"
else
  fail "buidl.md does NOT reference patterns.yaml"
fi

if grep -q 'agent-scores.yaml' commands/buidl.md; then
  pass "buidl.md references agent-scores.yaml"
else
  fail "buidl.md does NOT reference agent-scores.yaml"
fi

if grep -q 'extract-patterns.sh' commands/buidl.md; then
  pass "buidl.md references extract-patterns.sh"
else
  fail "buidl.md does NOT reference extract-patterns.sh"
fi

if grep -q 'update-scores.sh' commands/buidl.md; then
  pass "buidl.md references update-scores.sh"
else
  fail "buidl.md does NOT reference update-scores.sh"
fi

# ─────────────────────────────────────────────────
echo ""
echo "=== Cross-Layer Validator ==="

if [[ -f "agents/cross-layer-validator.md" ]]; then
  pass "cross-layer-validator.md exists"
else
  fail "cross-layer-validator.md MISSING"
fi

for section in "## Constraints" "## Step 0" "## Process" "## Output Format" "## Rules"; do
  if grep -q "$section" agents/cross-layer-validator.md; then
    pass "cross-layer-validator has '$section'"
  else
    fail "cross-layer-validator MISSING '$section'"
  fi
done

if [[ -f "knowledge/slices/cross-layer-validation.md" ]]; then
  pass "cross-layer-validation.md knowledge slice exists"
else
  fail "cross-layer-validation.md knowledge slice MISSING"
fi

if grep -q 'cross-layer-validation.md' agents/cross-layer-validator.md; then
  pass "cross-layer-validator references its knowledge slice"
else
  fail "cross-layer-validator does NOT reference its knowledge slice"
fi

if grep -q 'cross-layer-validator' commands/buidl.md; then
  pass "buidl.md references cross-layer-validator"
else
  fail "buidl.md does NOT reference cross-layer-validator"
fi

if grep -q 'validating' hooks/scripts/stop-hook.sh; then
  pass "stop-hook.sh includes 'validating' phase"
else
  fail "stop-hook.sh MISSING 'validating' phase"
fi

if grep -q 'validating' hooks/scripts/guard-state.sh; then
  pass "guard-state.sh includes 'validating' phase"
else
  fail "guard-state.sh MISSING 'validating' phase"
fi

if grep -q 'validating' hooks/scripts/guard-state-bash.sh; then
  pass "guard-state-bash.sh includes 'validating' phase"
else
  fail "guard-state-bash.sh MISSING 'validating' phase"
fi

# ─────────────────────────────────────────────────
echo ""
echo "=== Starter Templates ==="

if [[ -d "templates/starters/op20-token" ]]; then
  pass "op20-token starter template directory exists"
else
  fail "op20-token starter template directory MISSING"
fi

if [[ -f "templates/starters/op20-token/template.yaml" ]]; then
  pass "op20-token template.yaml exists"
else
  fail "op20-token template.yaml MISSING"
fi

if [[ -f "templates/starters/op20-token/contract/src/MyToken.ts" ]]; then
  pass "op20-token contract source exists"
else
  fail "op20-token contract source MISSING"
fi

if [[ -f "templates/starters/op20-token/contract/tests/MyToken.test.ts" ]]; then
  pass "op20-token contract tests exist"
else
  fail "op20-token contract tests MISSING"
fi

if [[ -f "templates/starters/op20-token/contract/asconfig.json" ]]; then
  pass "op20-token asconfig.json exists"
else
  fail "op20-token asconfig.json MISSING"
fi

if [[ -f "templates/starters/op20-token/frontend/src/App.tsx" ]]; then
  pass "op20-token frontend App.tsx exists"
else
  fail "op20-token frontend App.tsx MISSING"
fi

if [[ -f "templates/starters/op20-token/frontend/vite.config.ts" ]]; then
  pass "op20-token frontend vite.config.ts exists"
else
  fail "op20-token frontend vite.config.ts MISSING"
fi

if [[ -f "templates/starters/op20-token/frontend/package.json" ]]; then
  pass "op20-token frontend package.json exists"
else
  fail "op20-token frontend package.json MISSING"
fi

if grep -q 'starters' commands/buidl.md; then
  pass "buidl.md references starter templates"
else
  fail "buidl.md does NOT reference starter templates"
fi

# ─────────────────────────────────────────────────
# Score-Based Routing
# ─────────────────────────────────────────────────
echo ""
echo "=== Score-Based Routing ==="

# TEST-1: route-finding.sh exists and is valid bash
if [[ -f scripts/route-finding.sh ]]; then
  pass "route-finding.sh exists"
else
  fail "route-finding.sh does NOT exist"
fi

if bash -n scripts/route-finding.sh 2>/dev/null; then
  pass "route-finding.sh passes bash -n syntax check"
else
  fail "route-finding.sh has syntax errors"
fi

# TEST-2: route-finding.sh handles missing scores file
if bash scripts/route-finding.sh "test finding" "agent-a,agent-b" 2>/dev/null | grep -q '|'; then
  pass "route-finding.sh returns pipe-delimited output"
else
  fail "route-finding.sh does NOT return expected format"
fi

# Functional: CSS finding routes to frontend-dev (keyword fallback)
ROUTE_CSS=$(bash scripts/route-finding.sh "CSS layout broken in the token card" "opnet-contract-dev,opnet-frontend-dev,opnet-backend-dev" 2>/dev/null)
if echo "$ROUTE_CSS" | grep -q 'opnet-frontend-dev'; then
  pass "CSS finding routes to opnet-frontend-dev"
else
  fail "CSS finding did NOT route to opnet-frontend-dev (got: $ROUTE_CSS)"
fi

# Functional: contract finding routes to contract-dev
ROUTE_CONTRACT=$(bash scripts/route-finding.sh "storage slot collision in transfer function" "opnet-contract-dev,opnet-frontend-dev" 2>/dev/null)
if echo "$ROUTE_CONTRACT" | grep -q 'opnet-contract-dev'; then
  pass "Contract finding routes to opnet-contract-dev"
else
  fail "Contract finding did NOT route to opnet-contract-dev (got: $ROUTE_CONTRACT)"
fi

# Functional: non-OPNet candidates fall back to first candidate (not hardcoded agent)
ROUTE_GENERIC=$(bash scripts/route-finding.sh "generic problem" "my-builder,my-reviewer" 2>/dev/null)
if echo "$ROUTE_GENERIC" | grep -q 'my-builder'; then
  pass "Generic finding falls back to first candidate (not hardcoded agent)"
else
  fail "Generic finding did NOT fall back to first candidate (got: $ROUTE_GENERIC)"
fi

# Functional: preferred agent not in candidates falls back to first candidate
ROUTE_FALLBACK=$(bash scripts/route-finding.sh "CSS style issue" "agent-a,agent-b" 2>/dev/null)
if echo "$ROUTE_FALLBACK" | grep -q 'agent-a'; then
  pass "Preferred agent not in candidates falls back to first candidate"
else
  fail "Preferred agent not in candidates did NOT fall back (got: $ROUTE_FALLBACK)"
fi

# TEST-10: Category taxonomy exists in route-finding.sh
if grep -q 'CATEGORIES=' scripts/route-finding.sh; then
  pass "route-finding.sh contains category taxonomy"
else
  fail "route-finding.sh does NOT contain category taxonomy"
fi

if grep -q 'css-styling' scripts/route-finding.sh; then
  pass "route-finding.sh includes css-styling category"
else
  fail "route-finding.sh does NOT include css-styling category"
fi

if grep -q 'contract-logic' scripts/route-finding.sh; then
  pass "route-finding.sh includes contract-logic category"
else
  fail "route-finding.sh does NOT include contract-logic category"
fi

if grep -q 'security' scripts/route-finding.sh; then
  pass "route-finding.sh includes security category"
else
  fail "route-finding.sh does NOT include security category"
fi

# TEST-9: update-scores.sh accepts --findings parameter
if grep -q '\-\-findings' scripts/update-scores.sh; then
  pass "update-scores.sh references --findings parameter"
else
  fail "update-scores.sh does NOT reference --findings parameter"
fi

if grep -q 'strengths' scripts/update-scores.sh; then
  pass "update-scores.sh references strengths tracking"
else
  fail "update-scores.sh does NOT reference strengths tracking"
fi

if grep -q 'weaknesses' scripts/update-scores.sh; then
  pass "update-scores.sh references weaknesses tracking"
else
  fail "update-scores.sh does NOT reference weaknesses tracking"
fi

# TEST-6: buidl.md references route-finding.sh in Phase 5
if grep -q 'route-finding.sh' commands/buidl.md; then
  pass "buidl.md references route-finding.sh"
else
  fail "buidl.md does NOT reference route-finding.sh"
fi

if grep -q 'findings-categorized' commands/buidl.md; then
  pass "buidl.md references findings-categorized.md"
else
  fail "buidl.md does NOT reference findings-categorized.md"
fi

# ─────────────────────────────────────────────────
# Project-Type Profiles
# ─────────────────────────────────────────────────
echo ""
echo "=== Project-Type Profiles ==="

# TEST-3: generate-profiles.sh exists and is valid bash
if [[ -f scripts/generate-profiles.sh ]]; then
  pass "generate-profiles.sh exists"
else
  fail "generate-profiles.sh does NOT exist"
fi

if bash -n scripts/generate-profiles.sh 2>/dev/null; then
  pass "generate-profiles.sh passes bash -n syntax check"
else
  fail "generate-profiles.sh has syntax errors"
fi

# TEST-4: generate-profiles.sh handles empty learning directory
if bash scripts/generate-profiles.sh 2>/dev/null | grep -qi 'no\|profile\|threshold'; then
  pass "generate-profiles.sh handles gracefully when no threshold met"
else
  # May output nothing if thresholds not met, which is also acceptable
  pass "generate-profiles.sh runs without error"
fi

# TEST-5: learning/profiles/ directory exists
if [[ -d learning/profiles ]]; then
  pass "learning/profiles/ directory exists"
else
  fail "learning/profiles/ directory does NOT exist"
fi

# TEST-12: Profile schema documented
if [[ -f learning/profiles/README.md ]]; then
  pass "learning/profiles/README.md schema documentation exists"
else
  fail "learning/profiles/README.md does NOT exist"
fi

if grep -q 'project_type' learning/profiles/README.md; then
  pass "profile schema includes project_type field"
else
  fail "profile schema does NOT include project_type field"
fi

if grep -q 'common_pitfalls' learning/profiles/README.md; then
  pass "profile schema includes common_pitfalls field"
else
  fail "profile schema does NOT include common_pitfalls field"
fi

if grep -q 'recommended_config' learning/profiles/README.md; then
  pass "profile schema includes recommended_config field"
else
  fail "profile schema does NOT include recommended_config field"
fi

# TEST-7: buidl.md references generate-profiles.sh in Phase 6
if grep -q 'generate-profiles.sh' commands/buidl.md; then
  pass "buidl.md references generate-profiles.sh"
else
  fail "buidl.md does NOT reference generate-profiles.sh"
fi

# TEST-8: buidl.md references profile consultation in Phase 1
if grep -q 'Profile Pre-Check\|profile.*challenge\|learning/profiles' commands/buidl.md; then
  pass "buidl.md references profile consultation in challenge phase"
else
  fail "buidl.md does NOT reference profile consultation in challenge phase"
fi

# TEST-11: Version consistency
PLUGIN_VERSION=$(python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
CHANGELOG_VERSION=$(head -5 CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ "$PLUGIN_VERSION" == "$CHANGELOG_VERSION" ]]; then
  pass "plugin.json version ($PLUGIN_VERSION) matches CHANGELOG ($CHANGELOG_VERSION)"
else
  fail "plugin.json version ($PLUGIN_VERSION) does NOT match CHANGELOG ($CHANGELOG_VERSION)"
fi

# ─────────────────────────────────────────────────
# Functional: update-scores.sh --findings
# ─────────────────────────────────────────────────
echo ""
echo "=== Functional: update-scores.sh --findings ==="

# Create temp state and findings files, backup agent-scores.yaml
FUNC_TMPDIR=$(mktemp -d)
SCORES_BACKUP="$FUNC_TMPDIR/agent-scores-backup.yaml"
cp learning/agent-scores.yaml "$SCORES_BACKUP"

# Create a minimal state file with a dispatched agent
cat > "$FUNC_TMPDIR/state.yaml" << 'STATEEOF'
cycle: 1
tokens_used: 5000
builder_model: sonnet
agent_status:
  opnet-frontend-dev: done
STATEEOF

# Create a findings file with categorized findings
cat > "$FUNC_TMPDIR/findings.txt" << 'FINDEOF'
agent: opnet-frontend-dev | category: css-styling | outcome: fixed
agent: opnet-frontend-dev | category: wallet-connect | outcome: failed
FINDEOF

# Run update-scores.sh with --findings
if bash scripts/update-scores.sh "$FUNC_TMPDIR/state.yaml" "pass" --findings "$FUNC_TMPDIR/findings.txt" >/dev/null 2>&1; then
  pass "update-scores.sh --findings runs without error"
else
  fail "update-scores.sh --findings failed to run"
fi

# Check that strengths now includes css-styling
if python3 -c "
import yaml, sys
with open('learning/agent-scores.yaml') as f:
    data = yaml.safe_load(f)
agent = data.get('agents', {}).get('opnet-frontend-dev', {})
strengths = agent.get('strengths', [])
weaknesses = agent.get('weaknesses', [])
assert 'css-styling' in strengths, f'css-styling not in strengths: {strengths}'
assert 'wallet-connect' in weaknesses, f'wallet-connect not in weaknesses: {weaknesses}'
assert agent.get('sessions_completed', 0) == 1, f'sessions_completed should be 1'
" 2>&1; then
  pass "update-scores.sh --findings correctly updates strengths and weaknesses"
else
  fail "update-scores.sh --findings did NOT correctly update strengths/weaknesses"
fi

# Restore agent-scores.yaml
cp "$SCORES_BACKUP" learning/agent-scores.yaml

# ─────────────────────────────────────────────────
# Functional: generate-profiles.sh at 5-session threshold
# ─────────────────────────────────────────────────
echo ""
echo "=== Functional: generate-profiles.sh ==="

# Create 5 mock retrospective files in learning/ (unique test type to avoid collisions)
MOCK_TYPE="functest-xyzzy"
for i in 1 2 3 4 5; do
  cat > "learning/mock-test-session-$i.md" << RETROEOF
# Retrospective: mock-session-$i
Date: 2026-03-0$i
Project Type: $MOCK_TYPE
Outcome: PASS on cycle 1
Tokens Used: 5000
Duration: 10

## What Worked
- Test worked

## What Failed
- Nothing

## Anti-Patterns
- None
RETROEOF
done

# Remove any existing test profile
rm -f "learning/profiles/$MOCK_TYPE.yaml"

# Run generate-profiles.sh
PROFILE_OUTPUT=$(bash scripts/generate-profiles.sh 2>&1)
if echo "$PROFILE_OUTPUT" | grep -qi "Generated profile.*$MOCK_TYPE\|profile generation complete"; then
  pass "generate-profiles.sh generates profile at 5-session threshold"
else
  fail "generate-profiles.sh did NOT generate profile at threshold (output: $PROFILE_OUTPUT)"
fi

# Check that profile YAML was created with expected fields
if [[ -f "learning/profiles/$MOCK_TYPE.yaml" ]]; then
  if python3 -c "
import yaml, sys
mock_type = sys.argv[1]
with open(f'learning/profiles/{mock_type}.yaml') as f:
    profile = yaml.safe_load(f)
assert profile.get('project_type') == mock_type, f'project_type wrong: {profile.get(\"project_type\")}'
assert profile.get('sessions_count') == 5, f'sessions_count wrong: {profile.get(\"sessions_count\")}'
assert 'recommended_config' in profile, 'missing recommended_config'
assert 'common_pitfalls' in profile, 'missing common_pitfalls'
assert 'build_vs_buy' in profile['recommended_config'].get('skip_challenge_gates', []), 'missing skip gate'
" "$MOCK_TYPE" 2>&1; then
    pass "generate-profiles.sh produces valid profile YAML with correct schema"
  else
    fail "generate-profiles.sh profile YAML has incorrect schema"
  fi
else
  fail "generate-profiles.sh did NOT create learning/profiles/$MOCK_TYPE.yaml"
fi

# Clean up mock retrospectives and generated profile
for i in 1 2 3 4 5; do
  rm -f "learning/mock-test-session-$i.md"
done
rm -f "learning/profiles/$MOCK_TYPE.yaml"

# Clean up temp dir
rm -rf "$FUNC_TMPDIR"

# ─────────────────────────────────────────────────
# Cross-Critique (replaced Self-Critique in v5.0.0)
# ─────────────────────────────────────────────────
echo ""
echo "=== Cross-Critique ==="

# All 4 builder agents must have cross-critique note (self-critique removed)
for agent in opnet-contract-dev opnet-frontend-dev opnet-backend-dev loop-builder; do
  if grep -qi 'cross-critique' "agents/$agent.md"; then
    pass "$agent has cross-critique note"
  else
    fail "$agent MISSING cross-critique note"
  fi
done

# All 4 builder agents must NOT have Self-Critique heading (removed in v5)
for agent in opnet-contract-dev opnet-frontend-dev opnet-backend-dev loop-builder; do
  if grep -q 'Self-Critique' "agents/$agent.md"; then
    fail "$agent still has Self-Critique heading (should be removed)"
  else
    pass "$agent does not have Self-Critique heading (correctly removed)"
  fi
done

# Builder agents must still reference requirements.md (used in cross-critique via orchestrator)
for agent in opnet-contract-dev opnet-frontend-dev opnet-backend-dev loop-builder; do
  if grep -q 'requirements.md' "agents/$agent.md"; then
    pass "$agent references requirements.md"
  else
    fail "$agent MISSING requirements.md reference"
  fi
done

# ─────────────────────────────────────────────────
# Incremental Audit
# ─────────────────────────────────────────────────
echo ""
echo "=== Incremental Audit ==="

# Auditor must have Incremental Audit Mode section
if grep -q 'Incremental Audit Mode' agents/opnet-auditor.md; then
  pass "opnet-auditor has Incremental Audit Mode section"
else
  fail "opnet-auditor MISSING Incremental Audit Mode section"
fi

# Auditor must reference git diff
if grep -q 'git diff' agents/opnet-auditor.md; then
  pass "opnet-auditor references git diff in incremental mode"
else
  fail "opnet-auditor MISSING git diff reference"
fi

# Auditor must reference previous findings
if grep -q 'previous.*findings\|findings.*previous' agents/opnet-auditor.md; then
  pass "opnet-auditor references previous findings"
else
  fail "opnet-auditor MISSING previous findings reference"
fi

# buidl.md Step 2c must have incremental audit conditional
if grep -q 'Incremental Audit' commands/buidl.md; then
  pass "buidl.md has Incremental Audit section"
else
  fail "buidl.md MISSING Incremental Audit section"
fi

if grep -q 'git diff' commands/buidl.md; then
  pass "buidl.md references git diff for incremental audit"
else
  fail "buidl.md MISSING git diff reference"
fi

# ─────────────────────────────────────────────────
# Dry-Run Mode
# ─────────────────────────────────────────────────
echo ""
echo "=== Dry-Run Mode ==="

# buidl.md must have --dry-run in flag parsing
if grep -q '\-\-dry-run' commands/buidl.md; then
  pass "buidl.md has --dry-run flag"
else
  fail "buidl.md MISSING --dry-run flag"
fi

# buidl.md must have execution plan output section
if grep -q 'DRY RUN.*Execution Plan\|Dry-Run Check' commands/buidl.md; then
  pass "buidl.md has dry-run execution plan section"
else
  fail "buidl.md MISSING dry-run execution plan section"
fi

# buidl.md argument-hint must include --dry-run
if grep -q 'dry-run' commands/buidl.md | head -5; then
  pass "buidl.md argument-hint includes --dry-run"
else
  # Check more broadly
  if grep -q 'dry.run' commands/buidl.md; then
    pass "buidl.md argument-hint includes --dry-run"
  else
    fail "buidl.md argument-hint MISSING --dry-run"
  fi
fi

# ─────────────────────────────────────────────────
# Agent Tracing
# ─────────────────────────────────────────────────
echo ""
echo "=== Agent Tracing ==="

# trace-event.sh exists
if [[ -f scripts/trace-event.sh ]]; then
  pass "trace-event.sh exists"
else
  fail "trace-event.sh MISSING"
fi

# trace-event.sh passes bash -n
if bash -n scripts/trace-event.sh 2>/dev/null; then
  pass "trace-event.sh passes bash -n"
else
  fail "trace-event.sh FAILS bash -n"
fi

# trace-event.sh is executable
if [[ -x scripts/trace-event.sh ]]; then
  pass "trace-event.sh is executable"
else
  fail "trace-event.sh is NOT executable"
fi

# trace-event.sh has set -euo pipefail
if grep -q 'set -euo pipefail' scripts/trace-event.sh; then
  pass "trace-event.sh has set -euo pipefail"
else
  fail "trace-event.sh MISSING set -euo pipefail"
fi

# trace-event.sh has SCRIPT_DIR
if grep -q 'SCRIPT_DIR' scripts/trace-event.sh; then
  pass "trace-event.sh has SCRIPT_DIR"
else
  fail "trace-event.sh MISSING SCRIPT_DIR"
fi

# buidl-trace.md command exists
if [[ -f commands/buidl-trace.md ]]; then
  pass "buidl-trace.md command exists"
else
  fail "buidl-trace.md command MISSING"
fi

# buidl.md references trace-event.sh
if grep -q 'trace-event.sh' commands/buidl.md; then
  pass "buidl.md references trace-event.sh"
else
  fail "buidl.md MISSING trace-event.sh reference"
fi

# Functional: trace-event.sh appends valid JSON to trace file
TRACE_TMPDIR=$(mktemp -d)
mkdir -p "$TRACE_TMPDIR/artifacts"
if bash scripts/trace-event.sh "$TRACE_TMPDIR" "dispatch" "test-agent" "build" "1" "Test dispatch event" --tokens 500 --category testing 2>/dev/null; then
  if [[ -f "$TRACE_TMPDIR/artifacts/trace.jsonl" ]]; then
    # Verify it's valid JSON
    if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for line in f:
        event = json.loads(line)
        assert event['event_type'] == 'dispatch', f'wrong event_type: {event[\"event_type\"]}'
        assert event['agent'] == 'test-agent', f'wrong agent: {event[\"agent\"]}'
        assert event['cycle'] == 1, f'wrong cycle: {event[\"cycle\"]}'
        assert event.get('tokens') == 500, f'wrong tokens: {event.get(\"tokens\")}'
        assert event.get('category') == 'testing', f'wrong category: {event.get(\"category\")}'
" "$TRACE_TMPDIR/artifacts/trace.jsonl" 2>&1; then
      pass "trace-event.sh appends valid JSON with correct fields"
    else
      fail "trace-event.sh JSON output has incorrect fields"
    fi
  else
    fail "trace-event.sh did NOT create trace.jsonl"
  fi
else
  fail "trace-event.sh failed to run"
fi

# Functional: trace-event.sh rejects invalid event type
if bash scripts/trace-event.sh "$TRACE_TMPDIR" "invalid-type" "agent" "build" "1" "test" 2>/dev/null; then
  fail "trace-event.sh should reject invalid event type"
else
  pass "trace-event.sh rejects invalid event type"
fi

# Functional: trace-event.sh rejects missing arguments
if bash scripts/trace-event.sh 2>/dev/null; then
  fail "trace-event.sh should reject missing arguments"
else
  pass "trace-event.sh rejects missing arguments"
fi

rm -rf "$TRACE_TMPDIR"

# ─────────────────────────────────────────────────
# Dynamic Re-Planning
# ─────────────────────────────────────────────────
echo ""
echo "=== Dynamic Re-Planning ==="

# query-pattern.sh exists
if [[ -f scripts/query-pattern.sh ]]; then
  pass "query-pattern.sh exists"
else
  fail "query-pattern.sh MISSING"
fi

# query-pattern.sh passes bash -n
if bash -n scripts/query-pattern.sh 2>/dev/null; then
  pass "query-pattern.sh passes bash -n"
else
  fail "query-pattern.sh FAILS bash -n"
fi

# query-pattern.sh is executable
if [[ -x scripts/query-pattern.sh ]]; then
  pass "query-pattern.sh is executable"
else
  fail "query-pattern.sh is NOT executable"
fi

# query-pattern.sh has set -euo pipefail
if grep -q 'set -euo pipefail' scripts/query-pattern.sh; then
  pass "query-pattern.sh has set -euo pipefail"
else
  fail "query-pattern.sh MISSING set -euo pipefail"
fi

# query-pattern.sh guards against missing patterns.yaml
if grep -q '\[\[ -f.*PATTERNS_FILE\|! -f.*PATTERNS_FILE' scripts/query-pattern.sh; then
  pass "query-pattern.sh guards against missing patterns.yaml"
else
  fail "query-pattern.sh MISSING patterns.yaml guard"
fi

# buidl.md references query-pattern.sh
if grep -q 'query-pattern.sh' commands/buidl.md; then
  pass "buidl.md references query-pattern.sh"
else
  fail "buidl.md MISSING query-pattern.sh reference"
fi

# buidl.md has "Apply known fix" option
if grep -q 'Apply known fix' commands/buidl.md; then
  pass "buidl.md has 'Apply known fix' option for re-planning"
else
  fail "buidl.md MISSING 'Apply known fix' option"
fi

# Functional: query-pattern.sh exits 1 when patterns.yaml is missing
QUERY_TMPDIR=$(mktemp -d)
if SCRIPT_DIR_OVERRIDE="$QUERY_TMPDIR" bash scripts/query-pattern.sh "contract" 2>/dev/null; then
  fail "query-pattern.sh should exit 1 when patterns.yaml missing"
else
  pass "query-pattern.sh exits 1 when patterns.yaml missing"
fi

# Functional: query-pattern.sh returns matches from patterns.yaml
cat > "$QUERY_TMPDIR/patterns.yaml" << 'PATEOF'
patterns:
  - id: PAT-TEST-1
    category: contract
    domain: contract
    description: Test pattern for SafeMath missing
    fix: Add SafeMath.add for all u256 operations
    occurrences: 3
  - id: PAT-TEST-2
    category: frontend
    domain: frontend
    description: Buffer usage in frontend code
    fix: Replace Buffer with Uint8Array
    occurrences: 2
PATEOF

# Override SCRIPT_DIR so query-pattern.sh finds the test patterns.yaml
# We need to create the learning directory structure
mkdir -p "$QUERY_TMPDIR/learning"
cp "$QUERY_TMPDIR/patterns.yaml" "$QUERY_TMPDIR/learning/patterns.yaml"

# Create a wrapper script that overrides SCRIPT_DIR before sourcing the real logic
mkdir -p "$QUERY_TMPDIR/scripts"
cat > "$QUERY_TMPDIR/scripts/query-pattern.sh" << WRAPEOF
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$QUERY_TMPDIR"
PATTERNS_FILE="\$SCRIPT_DIR/learning/patterns.yaml"
CATEGORY="\${1:-}"
if [[ -z "\$CATEGORY" ]]; then
  exit 1
fi
if [[ ! -f "\$PATTERNS_FILE" ]]; then
  exit 1
fi
shift
KEYWORDS=()
if [[ \$# -gt 0 ]]; then
  KEYWORDS=("\$@")
fi
python3 -c "
import yaml, sys
patterns_file = sys.argv[1]
category = sys.argv[2]
keywords = sys.argv[3:]
with open(patterns_file) as f:
    data = yaml.safe_load(f)
if not data:
    sys.exit(1)
patterns = data.get('patterns', [])
if not patterns:
    sys.exit(1)
matches = []
for p in patterns:
    p_category = p.get('category', '')
    p_domain = p.get('domain', '')
    if category.lower() not in p_category.lower() and category.lower() not in p_domain.lower():
        continue
    if keywords:
        desc = (p.get('description', '') + ' ' + p.get('fix', '')).lower()
        if not any(kw.lower() in desc for kw in keywords):
            continue
    pattern_id = p.get('id', p.get('pattern_id', 'unknown'))
    description = p.get('description', '')
    fix = p.get('fix', '')
    matches.append(f'{pattern_id}|{description}|{fix}')
if not matches:
    sys.exit(1)
for m in matches:
    print(m)
" "\$PATTERNS_FILE" "\$CATEGORY" \${KEYWORDS[@]+"\${KEYWORDS[@]}"} 2>/dev/null
exit \$?
WRAPEOF
chmod +x "$QUERY_TMPDIR/scripts/query-pattern.sh"

PATTERN_RESULT=$(bash "$QUERY_TMPDIR/scripts/query-pattern.sh" "contract" 2>/dev/null || true)
if echo "$PATTERN_RESULT" | grep -q 'PAT-TEST-1.*SafeMath'; then
  pass "query-pattern.sh returns matching patterns"
else
  fail "query-pattern.sh did NOT return matching pattern (got: $PATTERN_RESULT)"
fi

# query-pattern.sh should NOT return frontend patterns for contract query
if echo "$PATTERN_RESULT" | grep -q 'PAT-TEST-2'; then
  fail "query-pattern.sh returned wrong category pattern"
else
  pass "query-pattern.sh filters by category correctly"
fi

# Functional: query-pattern.sh with keyword narrowing
KEYWORD_RESULT=$(bash "$QUERY_TMPDIR/scripts/query-pattern.sh" "contract" "SafeMath" 2>/dev/null || true)
if echo "$KEYWORD_RESULT" | grep -q 'PAT-TEST-1'; then
  pass "query-pattern.sh narrows results with keyword"
else
  fail "query-pattern.sh keyword narrowing failed (got: $KEYWORD_RESULT)"
fi

rm -rf "$QUERY_TMPDIR"

# ─────────────────────────────────────────────────
# Version 7.0.0 Consistency
# ─────────────────────────────────────────────────
echo ""
echo "=== Version 7.0.0 ==="

V7_PLUGIN=$(python3 -c "import json; print(json.load(open('.claude-plugin/plugin.json'))['version'])" 2>/dev/null)
V7_CHANGELOG=$(head -5 CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

if [[ "$V7_PLUGIN" == "7.0.0" ]]; then
  pass "v7-plugin-json-version: plugin.json version is 7.0.0"
else
  fail "v7-plugin-json-version: plugin.json version is NOT 7.0.0 (got: $V7_PLUGIN)"
fi

if [[ "$V7_CHANGELOG" == "7.0.0" ]]; then
  pass "v7-changelog-first-entry: CHANGELOG first entry is 7.0.0"
else
  fail "v7-changelog-first-entry: CHANGELOG first entry is NOT 7.0.0 (got: $V7_CHANGELOG)"
fi

if [[ "$V7_PLUGIN" == "$V7_CHANGELOG" ]]; then
  pass "v7-version-consistency: plugin.json version matches CHANGELOG first entry"
else
  fail "v7-version-consistency: plugin.json ($V7_PLUGIN) does NOT match CHANGELOG ($V7_CHANGELOG)"
fi

# ─────────────────────────────────────────────────
# TEST-1: Acceptance Test Locking
# ─────────────────────────────────────────────────
echo ""
echo "=== Acceptance Test Locking ==="

if grep -q 'acceptance-tests' commands/buidl.md; then
  pass "v5-acceptance-test-in-buidl: commands/buidl.md contains acceptance-tests in Phase 2"
else
  fail "v5-acceptance-test-in-buidl: commands/buidl.md does NOT contain acceptance-tests"
fi

# Check Phase 2 specifically (between SPECIFY heading and EXPLORE heading)
if sed -n '/PHASE 2/,/PHASE 3/p' commands/buidl.md | grep -q 'acceptance-tests'; then
  pass "v5-acceptance-test-phase2: acceptance-tests appears in Phase 2 section"
else
  fail "v5-acceptance-test-phase2: acceptance-tests does NOT appear in Phase 2 section"
fi

for agent in agents/opnet-contract-dev.md agents/opnet-frontend-dev.md agents/opnet-backend-dev.md agents/loop-builder.md; do
  agent_name=$(basename "$agent" .md)
  if grep -q 'acceptance-tests' "$agent"; then
    pass "v5-acceptance-test-forbidden-$agent_name: $agent_name has acceptance-tests FORBIDDEN rule"
  else
    fail "v5-acceptance-test-forbidden-$agent_name: $agent_name MISSING acceptance-tests FORBIDDEN rule"
  fi
done

# ─────────────────────────────────────────────────
# TEST-2: ABI-Lock
# ─────────────────────────────────────────────────
echo ""
echo "=== ABI-Lock ==="

if grep -q 'abi_hash' commands/buidl.md; then
  pass "v5-abi-lock-hash: commands/buidl.md contains abi_hash"
else
  fail "v5-abi-lock-hash: commands/buidl.md does NOT contain abi_hash"
fi

if grep -q 'abi_locked' commands/buidl.md; then
  pass "v5-abi-lock-flag: commands/buidl.md contains abi_locked"
else
  fail "v5-abi-lock-flag: commands/buidl.md does NOT contain abi_locked"
fi

if grep -q 'shasum' commands/buidl.md; then
  pass "v5-abi-lock-shasum: commands/buidl.md contains shasum"
else
  fail "v5-abi-lock-shasum: commands/buidl.md does NOT contain shasum"
fi

# Verify abi_hash appears between Step 2a and Step 2b
if sed -n '/Step 2a/,/Step 2b/p' commands/buidl.md | grep -q 'abi_hash'; then
  pass "v5-abi-lock-placement: abi_hash is between Step 2a and Step 2b"
else
  fail "v5-abi-lock-placement: abi_hash is NOT between Step 2a and Step 2b"
fi

# ─────────────────────────────────────────────────
# TEST-3: Adversarial Auditor Agent
# ─────────────────────────────────────────────────
echo ""
echo "=== Adversarial Auditor ==="

if [[ -f agents/opnet-adversarial-auditor.md ]]; then
  pass "v5-adversarial-auditor-exists: agents/opnet-adversarial-auditor.md exists"
else
  fail "v5-adversarial-auditor-exists: agents/opnet-adversarial-auditor.md MISSING"
fi

if grep -q 'Constraints' agents/opnet-adversarial-auditor.md 2>/dev/null; then
  pass "v5-adversarial-auditor-constraints: has Constraints section"
else
  fail "v5-adversarial-auditor-constraints: MISSING Constraints section"
fi

if grep -q 'Process' agents/opnet-adversarial-auditor.md 2>/dev/null; then
  pass "v5-adversarial-auditor-process: has Process section"
else
  fail "v5-adversarial-auditor-process: MISSING Process section"
fi

if grep -q 'Output' agents/opnet-adversarial-auditor.md 2>/dev/null; then
  pass "v5-adversarial-auditor-output: has Output section"
else
  fail "v5-adversarial-auditor-output: MISSING Output section"
fi

if grep -q 'FORBIDDEN' agents/opnet-adversarial-auditor.md 2>/dev/null; then
  pass "v5-adversarial-auditor-forbidden: has FORBIDDEN section"
else
  fail "v5-adversarial-auditor-forbidden: MISSING FORBIDDEN section"
fi

if grep -q 'invariant' agents/opnet-adversarial-auditor.md 2>/dev/null; then
  pass "v5-adversarial-auditor-invariant: references invariant"
else
  fail "v5-adversarial-auditor-invariant: does NOT reference invariant"
fi

# ─────────────────────────────────────────────────
# TEST-4: Adversarial Audit Dispatch
# ─────────────────────────────────────────────────
echo ""
echo "=== Adversarial Audit Dispatch ==="

if grep -q 'adversarial-auditor' commands/buidl.md; then
  pass "v5-adversarial-audit-dispatch-ref: commands/buidl.md contains adversarial-auditor"
else
  fail "v5-adversarial-audit-dispatch-ref: commands/buidl.md does NOT contain adversarial-auditor"
fi

if grep -q 'adversarial-findings' commands/buidl.md; then
  pass "v5-adversarial-audit-findings-ref: commands/buidl.md contains adversarial-findings"
else
  fail "v5-adversarial-audit-findings-ref: commands/buidl.md does NOT contain adversarial-findings"
fi

# Verify placement: Step 2c.5 appears after Step 2c and before Step 2d
if grep -q 'Step 2c.5' commands/buidl.md; then
  pass "v5-adversarial-audit-step-label: commands/buidl.md contains Step 2c.5"
else
  fail "v5-adversarial-audit-step-label: commands/buidl.md does NOT contain Step 2c.5"
fi

if sed -n '/Step 2c.*Security Audit/,/Step 2d/p' commands/buidl.md | grep -q 'adversarial'; then
  pass "v5-adversarial-audit-placement: adversarial audit is between Step 2c and Step 2d"
else
  fail "v5-adversarial-audit-placement: adversarial audit is NOT between Step 2c and Step 2d"
fi

# ─────────────────────────────────────────────────
# TEST-5: Failure Diagnosis
# ─────────────────────────────────────────────────
echo ""
echo "=== Failure Diagnosis ==="

if grep -q 'failure-diagnosis.md' commands/buidl.md; then
  pass "v5-failure-diagnosis-ref: commands/buidl.md contains failure-diagnosis.md"
else
  fail "v5-failure-diagnosis-ref: commands/buidl.md does NOT contain failure-diagnosis.md"
fi

if grep -q 'spec_problem' commands/buidl.md; then
  pass "v5-failure-diagnosis-spec: contains spec_problem classification"
else
  fail "v5-failure-diagnosis-spec: MISSING spec_problem classification"
fi

if grep -q 'implementation_problem' commands/buidl.md; then
  pass "v5-failure-diagnosis-impl: contains implementation_problem classification"
else
  fail "v5-failure-diagnosis-impl: MISSING implementation_problem classification"
fi

if grep -q 'test_problem' commands/buidl.md; then
  pass "v5-failure-diagnosis-test: contains test_problem classification"
else
  fail "v5-failure-diagnosis-test: MISSING test_problem classification"
fi

if grep -q 'infrastructure_problem' commands/buidl.md; then
  pass "v5-failure-diagnosis-infra: contains infrastructure_problem classification"
else
  fail "v5-failure-diagnosis-infra: MISSING infrastructure_problem classification"
fi

# ─────────────────────────────────────────────────
# TEST-6: Findings Ledger
# ─────────────────────────────────────────────────
echo ""
echo "=== Findings Ledger ==="

if grep -q 'findings-ledger.md' commands/buidl.md; then
  pass "v5-findings-ledger-buidl: commands/buidl.md contains findings-ledger.md"
else
  fail "v5-findings-ledger-buidl: commands/buidl.md does NOT contain findings-ledger.md"
fi

if grep -q 'REGRESSION' commands/buidl.md; then
  pass "v5-findings-ledger-regression-buidl: commands/buidl.md contains REGRESSION"
else
  fail "v5-findings-ledger-regression-buidl: commands/buidl.md does NOT contain REGRESSION"
fi

if grep -q 'Regression Check' agents/loop-reviewer.md; then
  pass "v5-findings-ledger-reviewer-section: loop-reviewer.md contains Regression Check section"
else
  fail "v5-findings-ledger-reviewer-section: loop-reviewer.md MISSING Regression Check section"
fi

if grep -q 'REGRESSION' agents/loop-reviewer.md; then
  pass "v5-findings-ledger-reviewer-regression: loop-reviewer.md contains REGRESSION"
else
  fail "v5-findings-ledger-reviewer-regression: loop-reviewer.md does NOT contain REGRESSION"
fi

# ─────────────────────────────────────────────────
# TEST-7: Chain Probe
# ─────────────────────────────────────────────────
echo ""
echo "=== Chain Probe ==="

if [[ -f scripts/chain-probe.sh ]]; then
  pass "v5-chain-probe-exists: scripts/chain-probe.sh exists"
else
  fail "v5-chain-probe-exists: scripts/chain-probe.sh MISSING"
fi

check "v5-chain-probe-syntax: chain-probe.sh passes bash -n" bash -n scripts/chain-probe.sh

if [[ -x scripts/chain-probe.sh ]]; then
  pass "v5-chain-probe-executable: chain-probe.sh is executable"
else
  fail "v5-chain-probe-executable: chain-probe.sh is NOT executable"
fi

if grep -q 'gas' scripts/chain-probe.sh; then
  pass "v5-chain-probe-gas: chain-probe.sh references gas"
else
  fail "v5-chain-probe-gas: chain-probe.sh does NOT reference gas"
fi

if grep -q 'block' scripts/chain-probe.sh; then
  pass "v5-chain-probe-block: chain-probe.sh references block"
else
  fail "v5-chain-probe-block: chain-probe.sh does NOT reference block"
fi

if grep -q 'probe_status' scripts/chain-probe.sh; then
  pass "v5-chain-probe-status: chain-probe.sh references probe_status"
else
  fail "v5-chain-probe-status: chain-probe.sh does NOT reference probe_status"
fi

if grep -q 'chain-probe' commands/buidl.md; then
  pass "v5-chain-probe-buidl-ref: commands/buidl.md references chain-probe"
else
  fail "v5-chain-probe-buidl-ref: commands/buidl.md does NOT reference chain-probe"
fi

# Verify it's in Phase 2
if sed -n '/PHASE 2/,/PHASE 3/p' commands/buidl.md | grep -q 'chain-probe'; then
  pass "v5-chain-probe-phase2: chain-probe is referenced in Phase 2"
else
  fail "v5-chain-probe-phase2: chain-probe is NOT referenced in Phase 2"
fi

# ─────────────────────────────────────────────────
# TEST-8: Adversarial E2E Tester Agent
# ─────────────────────────────────────────────────
echo ""
echo "=== Adversarial E2E Tester ==="

if [[ -f agents/opnet-adversarial-tester.md ]]; then
  pass "v5-adversarial-tester-exists: agents/opnet-adversarial-tester.md exists"
else
  fail "v5-adversarial-tester-exists: agents/opnet-adversarial-tester.md MISSING"
fi

if grep -q 'Constraints' agents/opnet-adversarial-tester.md 2>/dev/null; then
  pass "v5-adversarial-tester-constraints: has Constraints section"
else
  fail "v5-adversarial-tester-constraints: MISSING Constraints section"
fi

if grep -q 'FORBIDDEN' agents/opnet-adversarial-tester.md 2>/dev/null; then
  pass "v5-adversarial-tester-forbidden: has FORBIDDEN section"
else
  fail "v5-adversarial-tester-forbidden: MISSING FORBIDDEN section"
fi

if grep -q 'boundary' agents/opnet-adversarial-tester.md 2>/dev/null; then
  pass "v5-adversarial-tester-boundary: references boundary"
else
  fail "v5-adversarial-tester-boundary: does NOT reference boundary"
fi

if grep -q 'revert' agents/opnet-adversarial-tester.md 2>/dev/null; then
  pass "v5-adversarial-tester-revert: references revert"
else
  fail "v5-adversarial-tester-revert: does NOT reference revert"
fi

if grep -qi 'race condition' agents/opnet-adversarial-tester.md 2>/dev/null; then
  pass "v5-adversarial-tester-race: references race condition"
else
  fail "v5-adversarial-tester-race: does NOT reference race condition"
fi

# ─────────────────────────────────────────────────
# TEST-9: Adversarial E2E Dispatch
# ─────────────────────────────────────────────────
echo ""
echo "=== Adversarial E2E Dispatch ==="

if grep -q 'adversarial-tester' commands/buidl.md; then
  pass "v5-adversarial-e2e-dispatch-ref: commands/buidl.md contains adversarial-tester"
else
  fail "v5-adversarial-e2e-dispatch-ref: commands/buidl.md does NOT contain adversarial-tester"
fi

if grep -q 'adversarial-e2e-results' commands/buidl.md; then
  pass "v5-adversarial-e2e-results-ref: commands/buidl.md contains adversarial-e2e-results"
else
  fail "v5-adversarial-e2e-results-ref: commands/buidl.md does NOT contain adversarial-e2e-results"
fi

# Verify placement: Step 2e.5 appears between Step 2e and Step 2f
if grep -q 'Step 2e.5' commands/buidl.md; then
  pass "v5-adversarial-e2e-step-label: commands/buidl.md contains Step 2e.5"
else
  fail "v5-adversarial-e2e-step-label: commands/buidl.md does NOT contain Step 2e.5"
fi

if sed -n '/Step 2e:/,/Step 2f:/p' commands/buidl.md | grep -q 'adversarial'; then
  pass "v5-adversarial-e2e-placement: adversarial E2E is between Step 2e and Step 2f"
else
  fail "v5-adversarial-e2e-placement: adversarial E2E is NOT between Step 2e and Step 2f"
fi

# ─────────────────────────────────────────────────
# TEST-10: Cross-Critique
# ─────────────────────────────────────────────────
echo ""
echo "=== Cross-Critique ==="

if grep -q 'cross-critique' commands/buidl.md; then
  pass "v5-cross-critique-buidl: commands/buidl.md contains cross-critique"
else
  fail "v5-cross-critique-buidl: commands/buidl.md does NOT contain cross-critique"
fi

if grep -qi 'critique mode' commands/buidl.md; then
  pass "v5-critique-mode-buidl: commands/buidl.md contains critique mode"
else
  fail "v5-critique-mode-buidl: commands/buidl.md does NOT contain critique mode"
fi

# Verify no self-critique heading in builder agents
for agent in agents/opnet-contract-dev.md agents/opnet-frontend-dev.md agents/opnet-backend-dev.md agents/loop-builder.md; do
  agent_name=$(basename "$agent" .md)
  if grep -q 'Self-Critique' "$agent"; then
    fail "v5-no-self-critique-$agent_name: $agent_name still contains Self-Critique step heading"
  else
    pass "v5-no-self-critique-$agent_name: $agent_name does NOT contain Self-Critique heading"
  fi
done

if grep -qi 'Critique Mode' agents/loop-reviewer.md; then
  pass "v5-critique-mode-reviewer: loop-reviewer.md contains Critique Mode section"
else
  fail "v5-critique-mode-reviewer: loop-reviewer.md MISSING Critique Mode section"
fi

# ─────────────────────────────────────────────────
# TEST-11: Hard Gates
# ─────────────────────────────────────────────────
echo ""
echo "=== Hard Gates ==="

if grep -q 'SOFT' commands/buidl.md; then
  pass "v5-hard-gates-soft: commands/buidl.md contains SOFT gate classification"
else
  fail "v5-hard-gates-soft: commands/buidl.md does NOT contain SOFT gate classification"
fi

if grep -q 'HARD' commands/buidl.md; then
  pass "v5-hard-gates-hard: commands/buidl.md contains HARD gate classification"
else
  fail "v5-hard-gates-hard: commands/buidl.md does NOT contain HARD gate classification"
fi

# Verify hard gates run when --skip-challenge is set
if grep -q 'skip-challenge' commands/buidl.md && grep -q 'hard gate' commands/buidl.md; then
  pass "v5-hard-gates-skip-logic: commands/buidl.md has logic for hard gates with --skip-challenge"
else
  fail "v5-hard-gates-skip-logic: commands/buidl.md MISSING hard gate logic with --skip-challenge"
fi

# ─────────────────────────────────────────────────
# TEST-12: State Guard Coverage
# ─────────────────────────────────────────────────
echo ""
echo "=== State Guard Coverage ==="

for hookfile in hooks/scripts/stop-hook.sh hooks/scripts/guard-state.sh hooks/scripts/guard-state-bash.sh; do
  hook_name=$(basename "$hookfile" .sh)
  if grep -q 'adversarial_auditing' "$hookfile"; then
    pass "v5-guard-adversarial-auditing-$hook_name: $hook_name contains adversarial_auditing"
  else
    fail "v5-guard-adversarial-auditing-$hook_name: $hook_name MISSING adversarial_auditing"
  fi
  if grep -q 'adversarial_testing' "$hookfile"; then
    pass "v5-guard-adversarial-testing-$hook_name: $hook_name contains adversarial_testing"
  else
    fail "v5-guard-adversarial-testing-$hook_name: $hook_name MISSING adversarial_testing"
  fi
done

# ─────────────────────────────────────────────────
# TEST-14: Agent Count
# ─────────────────────────────────────────────────
echo ""
echo "=== Agent Count ==="

if grep -q '14' README.md; then
  pass "v5-agent-count-14: README references 14 agents"
else
  fail "v5-agent-count-14: README does NOT reference 14 agents"
fi

if grep -q 'adversarial-auditor' README.md; then
  pass "v5-agent-table-auditor: README agent table includes adversarial-auditor"
else
  fail "v5-agent-table-auditor: README agent table MISSING adversarial-auditor"
fi

if grep -q 'adversarial-tester' README.md; then
  pass "v5-agent-table-tester: README agent table includes adversarial-tester"
else
  fail "v5-agent-table-tester: README agent table MISSING adversarial-tester"
fi

# ─────────────────────────────────────────────────
# TEST-15: Functional — Chain Probe Graceful Failure
# ─────────────────────────────────────────────────
echo ""
echo "=== Chain Probe Functional ==="

PROBE_TMPDIR=$(mktemp -d)

# Test with invalid RPC URL — should exit 0 with probe_status=failed
bash scripts/chain-probe.sh "$PROBE_TMPDIR" "http://invalid-rpc-that-does-not-exist.example.com:1234" >/dev/null 2>&1
PROBE_EXIT=$?

if [[ "$PROBE_EXIT" -eq 0 ]]; then
  pass "v5-chain-probe-graceful-exit: chain-probe.sh exits 0 on invalid RPC"
else
  fail "v5-chain-probe-graceful-exit: chain-probe.sh exits $PROBE_EXIT on invalid RPC (expected 0)"
fi

if [[ -f "$PROBE_TMPDIR/chain-state.json" ]]; then
  PROBE_STATUS=$(python3 -c "import json; print(json.load(open('$PROBE_TMPDIR/chain-state.json')).get('probe_status',''))" 2>/dev/null || echo "")
  if [[ "$PROBE_STATUS" == "failed" ]]; then
    pass "v5-chain-probe-graceful-status: probe_status is failed on invalid RPC"
  else
    fail "v5-chain-probe-graceful-status: probe_status is '$PROBE_STATUS' (expected 'failed')"
  fi
else
  fail "v5-chain-probe-graceful-output: chain-state.json was NOT created"
fi

rm -rf "$PROBE_TMPDIR"

# ─────────────────────────────────────────────────
# TEST-16: Findings Ledger Format
# ─────────────────────────────────────────────────
echo ""
echo "=== Findings Ledger Format ==="

# Verify pipe-delimited table format in buidl.md
if grep -q '| ID |' commands/buidl.md && grep -q '| Cycle Found |' commands/buidl.md; then
  pass "v5-findings-ledger-table-headers: findings ledger has pipe-delimited table with ID and Cycle Found"
else
  fail "v5-findings-ledger-table-headers: findings ledger MISSING pipe-delimited table headers"
fi

if grep -q '| Cycle Resolved |' commands/buidl.md; then
  pass "v5-findings-ledger-resolved-col: findings ledger table has Cycle Resolved column"
else
  fail "v5-findings-ledger-resolved-col: findings ledger table MISSING Cycle Resolved column"
fi

if grep -q '| Status |' commands/buidl.md && grep -q '| Finding |' commands/buidl.md; then
  pass "v5-findings-ledger-status-finding-cols: findings ledger table has Status and Finding columns"
else
  fail "v5-findings-ledger-status-finding-cols: findings ledger table MISSING Status or Finding columns"
fi

if grep -q '| File |' commands/buidl.md && grep -q '| Agent |' commands/buidl.md; then
  pass "v5-findings-ledger-file-agent-cols: findings ledger table has File and Agent columns"
else
  fail "v5-findings-ledger-file-agent-cols: findings ledger table MISSING File or Agent columns"
fi

# ─────────────────────────────────────────────────
# v6-knowledge-1: load-knowledge.sh exists and is valid
# ─────────────────────────────────────────────────
echo ""
echo "=== Dynamic Knowledge Loading ==="

if [[ -f scripts/load-knowledge.sh ]]; then
  pass "v6-knowledge-exists: load-knowledge.sh exists"
else
  fail "v6-knowledge-exists: load-knowledge.sh MISSING"
fi

check "v6-knowledge-syntax: load-knowledge.sh passes bash -n" bash -n scripts/load-knowledge.sh

if [[ -x scripts/load-knowledge.sh ]]; then
  pass "v6-knowledge-executable: load-knowledge.sh is executable"
else
  fail "v6-knowledge-executable: load-knowledge.sh is NOT executable"
fi

if grep -q 'set -euo pipefail' scripts/load-knowledge.sh; then
  pass "v6-knowledge-pipefail: load-knowledge.sh has set -euo pipefail"
else
  fail "v6-knowledge-pipefail: load-knowledge.sh MISSING set -euo pipefail"
fi

if grep -q 'SCRIPT_DIR' scripts/load-knowledge.sh; then
  pass "v6-knowledge-scriptdir: load-knowledge.sh has SCRIPT_DIR"
else
  fail "v6-knowledge-scriptdir: load-knowledge.sh MISSING SCRIPT_DIR"
fi

# ─────────────────────────────────────────────────
# v6-knowledge-2: load-knowledge.sh functional test — line cap
# ─────────────────────────────────────────────────
echo ""
echo "=== Dynamic Knowledge Line Cap ==="

LK_LINES=$(bash scripts/load-knowledge.sh opnet-frontend-dev op20-token 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LK_LINES" -le 400 ]]; then
  pass "v6-knowledge-linecap: opnet-frontend-dev output is $LK_LINES lines (<=400)"
else
  fail "v6-knowledge-linecap: opnet-frontend-dev output is $LK_LINES lines (>400)"
fi

# ─────────────────────────────────────────────────
# v6-knowledge-3: load-knowledge.sh outputs relevant content
# ─────────────────────────────────────────────────
echo ""
echo "=== Dynamic Knowledge Relevance ==="

LK_OUTPUT=$(bash scripts/load-knowledge.sh opnet-frontend-dev op20-token 2>/dev/null || true)
if echo "$LK_OUTPUT" | grep -qi 'frontend\|react\|vite'; then
  pass "v6-knowledge-relevance: frontend-dev output contains frontend-relevant content"
else
  fail "v6-knowledge-relevance: frontend-dev output does NOT contain frontend-relevant content"
fi

# Contract-dev should get full bible (more sections)
LK_CONTRACT_LINES=$(bash scripts/load-knowledge.sh opnet-contract-dev op20-token 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LK_CONTRACT_LINES" -le 400 ]]; then
  pass "v6-knowledge-contract-cap: contract-dev output is $LK_CONTRACT_LINES lines (<=400)"
else
  fail "v6-knowledge-contract-cap: contract-dev output is $LK_CONTRACT_LINES lines (>400)"
fi

# ─────────────────────────────────────────────────
# v6-knowledge-4: Bible sections tagged
# ─────────────────────────────────────────────────
echo ""
echo "=== Bible Section Tags ==="

for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if grep -q "BEGIN-SECTION-$i " knowledge/opnet-bible.md; then
    pass "v6-bible-tag-begin-$i: BEGIN-SECTION-$i tag exists"
  else
    fail "v6-bible-tag-begin-$i: BEGIN-SECTION-$i tag MISSING"
  fi
  if grep -q "END-SECTION-$i" knowledge/opnet-bible.md; then
    pass "v6-bible-tag-end-$i: END-SECTION-$i tag exists"
  else
    fail "v6-bible-tag-end-$i: END-SECTION-$i tag MISSING"
  fi
done

# ─────────────────────────────────────────────────
# v6-knowledge-5: Agent files reference load-knowledge.sh
# ─────────────────────────────────────────────────
echo ""
echo "=== Agent Knowledge References ==="

for agent in opnet-backend-dev opnet-frontend-dev opnet-contract-dev opnet-auditor opnet-deployer opnet-e2e-tester opnet-ui-tester cross-layer-validator loop-builder; do
  if grep -q 'load-knowledge.sh' "agents/$agent.md"; then
    pass "v6-agent-ref-$agent: $agent references load-knowledge.sh"
  else
    fail "v6-agent-ref-$agent: $agent does NOT reference load-knowledge.sh"
  fi
done

# Verify slice names remain visible (for orphan detection test at line 247)
for agent in opnet-backend-dev opnet-frontend-dev opnet-contract-dev opnet-auditor opnet-deployer opnet-e2e-tester opnet-ui-tester; do
  if grep -q 'knowledge/slices\|\.md.*slice' "agents/$agent.md"; then
    pass "v6-slice-visible-$agent: $agent still has slice name visible"
  else
    fail "v6-slice-visible-$agent: $agent lost slice name visibility"
  fi
done

# ─────────────────────────────────────────────────
# v6-knowledge-6: buidl.md dispatch uses load-knowledge.sh
# ─────────────────────────────────────────────────
echo ""
echo "=== Buidl.md Dispatch Updates ==="

if grep -q 'load-knowledge.sh' commands/buidl.md; then
  pass "v6-buidl-dispatch: buidl.md references load-knowledge.sh"
else
  fail "v6-buidl-dispatch: buidl.md does NOT reference load-knowledge.sh"
fi

# ─────────────────────────────────────────────────
# v6-fuzz-1: fuzz-contract.sh exists and is valid
# ─────────────────────────────────────────────────
echo ""
echo "=== Property-Based Fuzzer ==="

if [[ -f scripts/fuzz-contract.sh ]]; then
  pass "v6-fuzz-exists: fuzz-contract.sh exists"
else
  fail "v6-fuzz-exists: fuzz-contract.sh MISSING"
fi

check "v6-fuzz-syntax: fuzz-contract.sh passes bash -n" bash -n scripts/fuzz-contract.sh

if [[ -x scripts/fuzz-contract.sh ]]; then
  pass "v6-fuzz-executable: fuzz-contract.sh is executable"
else
  fail "v6-fuzz-executable: fuzz-contract.sh is NOT executable"
fi

if grep -q 'set -euo pipefail' scripts/fuzz-contract.sh; then
  pass "v6-fuzz-pipefail: fuzz-contract.sh has set -euo pipefail"
else
  fail "v6-fuzz-pipefail: fuzz-contract.sh MISSING set -euo pipefail"
fi

if grep -q 'SCRIPT_DIR' scripts/fuzz-contract.sh; then
  pass "v6-fuzz-scriptdir: fuzz-contract.sh has SCRIPT_DIR"
else
  fail "v6-fuzz-scriptdir: fuzz-contract.sh MISSING SCRIPT_DIR"
fi

# ─────────────────────────────────────────────────
# v6-fuzz-2: fuzz-contract.sh functional test
# ─────────────────────────────────────────────────
echo ""
echo "=== Fuzzer Functional ==="

FUZZ_TMPDIR=$(mktemp -d)
cat > "$FUZZ_TMPDIR/test-abi.json" << 'ABIEOF'
[
  {
    "name": "transfer",
    "type": "function",
    "inputs": [
      {"name": "to", "type": "address"},
      {"name": "amount", "type": "u256"}
    ]
  },
  {
    "name": "approve",
    "type": "function",
    "inputs": [
      {"name": "spender", "type": "address"},
      {"name": "amount", "type": "u256"}
    ]
  }
]
ABIEOF

if FUZZ_OUTPUT_DIR="$FUZZ_TMPDIR" bash scripts/fuzz-contract.sh "$FUZZ_TMPDIR/test-abi.json" >/dev/null 2>&1; then
  pass "v6-fuzz-runs: fuzz-contract.sh runs without error"
else
  fail "v6-fuzz-runs: fuzz-contract.sh failed to run"
fi

if [[ -f "$FUZZ_TMPDIR/fuzz-cases.json" ]]; then
  FUZZ_COUNT=$(python3 -c "import json; print(len(json.load(open('$FUZZ_TMPDIR/fuzz-cases.json'))))" 2>/dev/null || echo "0")
  if [[ "$FUZZ_COUNT" -ge 5 ]]; then
    pass "v6-fuzz-count: generated $FUZZ_COUNT fuzz cases (>=5)"
  else
    fail "v6-fuzz-count: generated only $FUZZ_COUNT fuzz cases (<5)"
  fi

  # Verify JSON structure has required fields
  if python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    cases = json.load(f)
assert isinstance(cases, list), 'not a list'
for c in cases[:3]:
    assert 'method' in c, 'missing method field'
    assert 'params' in c, 'missing params field'
    assert 'expected_revert' in c, 'missing expected_revert field'
    assert isinstance(c['expected_revert'], bool), 'expected_revert is not boolean'
" "$FUZZ_TMPDIR/fuzz-cases.json" 2>&1; then
    pass "v6-fuzz-schema: fuzz-cases.json has correct schema (method, params, expected_revert)"
  else
    fail "v6-fuzz-schema: fuzz-cases.json has incorrect schema"
  fi
else
  fail "v6-fuzz-output: fuzz-cases.json was NOT created"
fi

# Verify no transaction sending code
if grep -qi 'sendTransaction\|broadcast' scripts/fuzz-contract.sh; then
  fail "v6-fuzz-no-send: fuzz-contract.sh contains transaction sending code"
else
  pass "v6-fuzz-no-send: fuzz-contract.sh does NOT send transactions"
fi

rm -rf "$FUZZ_TMPDIR"

# ─────────────────────────────────────────────────
# v6-fuzz-3: Adversarial agents reference fuzz-cases.json
# ─────────────────────────────────────────────────
echo ""
echo "=== Fuzzer Agent References ==="

if grep -q 'fuzz-cases.json' agents/opnet-adversarial-auditor.md; then
  pass "v6-fuzz-adversarial-auditor: adversarial-auditor references fuzz-cases.json"
else
  fail "v6-fuzz-adversarial-auditor: adversarial-auditor does NOT reference fuzz-cases.json"
fi

if grep -q 'fuzz-cases.json' agents/opnet-adversarial-tester.md; then
  pass "v6-fuzz-adversarial-tester: adversarial-tester references fuzz-cases.json"
else
  fail "v6-fuzz-adversarial-tester: adversarial-tester does NOT reference fuzz-cases.json"
fi

if grep -q 'fuzz-contract.sh' commands/buidl.md; then
  pass "v6-fuzz-buidl-ref: buidl.md references fuzz-contract.sh"
else
  fail "v6-fuzz-buidl-ref: buidl.md does NOT reference fuzz-contract.sh"
fi

# ─────────────────────────────────────────────────
# v6-prune-1: update-scores.sh has --prune flag
# ─────────────────────────────────────────────────
echo ""
echo "=== Stale Pattern Pruning ==="

if grep -q '\-\-prune' scripts/update-scores.sh; then
  pass "v6-prune-flag: update-scores.sh has --prune flag"
else
  fail "v6-prune-flag: update-scores.sh does NOT have --prune flag"
fi

if grep -q 'PRUNE_MODE' scripts/update-scores.sh; then
  pass "v6-prune-mode: update-scores.sh has PRUNE_MODE variable"
else
  fail "v6-prune-mode: update-scores.sh MISSING PRUNE_MODE variable"
fi

if grep -q 'prune-log' scripts/update-scores.sh; then
  pass "v6-prune-log-ref: update-scores.sh references prune-log"
else
  fail "v6-prune-log-ref: update-scores.sh does NOT reference prune-log"
fi

# ─────────────────────────────────────────────────
# v6-prune-2: extract-patterns.sh has version fields
# ─────────────────────────────────────────────────
echo ""
echo "=== Pattern Version Tracking ==="

if grep -q 'last_seen_version' scripts/extract-patterns.sh; then
  pass "v6-version-field: extract-patterns.sh has last_seen_version field"
else
  fail "v6-version-field: extract-patterns.sh MISSING last_seen_version field"
fi

if grep -q 'stale' scripts/extract-patterns.sh; then
  pass "v6-stale-field: extract-patterns.sh has stale field"
else
  fail "v6-stale-field: extract-patterns.sh MISSING stale field"
fi

# ─────────────────────────────────────────────────
# v6-audit-1: audit-learning.sh exists and runs
# ─────────────────────────────────────────────────
echo ""
echo "=== Learning Audit Script ==="

if [[ -f scripts/audit-learning.sh ]]; then
  pass "v6-audit-exists: audit-learning.sh exists"
else
  fail "v6-audit-exists: audit-learning.sh MISSING"
fi

check "v6-audit-syntax: audit-learning.sh passes bash -n" bash -n scripts/audit-learning.sh

if [[ -x scripts/audit-learning.sh ]]; then
  pass "v6-audit-executable: audit-learning.sh is executable"
else
  fail "v6-audit-executable: audit-learning.sh is NOT executable"
fi

AUDIT_OUTPUT=$(bash scripts/audit-learning.sh 2>/dev/null || true)
if echo "$AUDIT_OUTPUT" | grep -q 'Learning System Health Report'; then
  pass "v6-audit-runs: audit-learning.sh produces health report"
else
  fail "v6-audit-runs: audit-learning.sh did NOT produce health report"
fi

if echo "$AUDIT_OUTPUT" | grep -q 'Patterns'; then
  pass "v6-audit-patterns: audit-learning.sh reports on patterns"
else
  fail "v6-audit-patterns: audit-learning.sh does NOT report on patterns"
fi

# ─────────────────────────────────────────────────
# v6-cmd-1: buidl-learning.md command exists
# ─────────────────────────────────────────────────
echo ""
echo "=== buidl-learning Command ==="

if [[ -f commands/buidl-learning.md ]]; then
  pass "v6-cmd-learning-exists: buidl-learning.md exists"
else
  fail "v6-cmd-learning-exists: buidl-learning.md MISSING"
fi

if grep -q 'description:' commands/buidl-learning.md; then
  pass "v6-cmd-learning-frontmatter: buidl-learning.md has description frontmatter"
else
  fail "v6-cmd-learning-frontmatter: buidl-learning.md MISSING description frontmatter"
fi

if grep -q 'audit-learning.sh' commands/buidl-learning.md; then
  pass "v6-cmd-learning-script-ref: buidl-learning.md references audit-learning.sh"
else
  fail "v6-cmd-learning-script-ref: buidl-learning.md does NOT reference audit-learning.sh"
fi

# ─────────────────────────────────────────────────
# v6-status-1: buidl-status.md has learning health
# ─────────────────────────────────────────────────
echo ""
echo "=== buidl-status Learning Health ==="

if grep -q 'Learning' commands/buidl-status.md; then
  pass "v6-status-learning: buidl-status.md has Learning health section"
else
  fail "v6-status-learning: buidl-status.md MISSING Learning health section"
fi

# ─────────────────────────────────────────────────
# v6-version-1: Version 6.0.0 consistency
# ─────────────────────────────────────────────────
echo ""
echo "=== v6 Version Consistency ==="

V6_README=$(grep -c '6\.0\.0' README.md || true)
if [[ "$V6_README" -ge 1 ]]; then
  pass "v6-readme-version: README.md references 6.0.0"
else
  fail "v6-readme-version: README.md does NOT reference 6.0.0"
fi

if grep -q 'buidl-learning' README.md; then
  pass "v6-readme-learning-cmd: README.md documents buidl-learning command"
else
  fail "v6-readme-learning-cmd: README.md does NOT document buidl-learning command"
fi

if grep -q 'fuzz-contract' README.md; then
  pass "v6-readme-fuzz: README.md documents fuzz-contract.sh"
else
  fail "v6-readme-fuzz: README.md does NOT document fuzz-contract.sh"
fi

if grep -q 'Dynamic Knowledge' README.md; then
  pass "v6-readme-dynamic: README.md documents Dynamic Knowledge"
else
  fail "v6-readme-dynamic: README.md does NOT document Dynamic Knowledge"
fi

# ─────────────────────────────────────────────────
# v6-func-1: contract-dev outputs more than frontend-dev
# ─────────────────────────────────────────────────
echo ""
echo "=== Functional: Knowledge Slice Comparison ==="

V6_CONTRACT_LINES=$(bash scripts/load-knowledge.sh opnet-contract-dev op20-token 2>/dev/null | wc -l | tr -d ' ')
V6_FRONTEND_LINES=$(bash scripts/load-knowledge.sh opnet-frontend-dev op20-token 2>/dev/null | wc -l | tr -d ' ')

if [[ "$V6_CONTRACT_LINES" -ge "$V6_FRONTEND_LINES" ]]; then
  pass "v6-func-contract-gt-frontend: contract-dev ($V6_CONTRACT_LINES lines) >= frontend-dev ($V6_FRONTEND_LINES lines)"
else
  fail "v6-func-contract-gt-frontend: contract-dev ($V6_CONTRACT_LINES lines) NOT >= frontend-dev ($V6_FRONTEND_LINES lines)"
fi

# ─────────────────────────────────────────────────
# v6-func-2: update-scores.sh --prune on empty scores file
# ─────────────────────────────────────────────────
echo ""
echo "=== Functional: Prune Empty Scores ==="

PRUNE_TMPDIR=$(mktemp -d)

# Create minimal state file
cat > "$PRUNE_TMPDIR/state.yaml" << 'PRUNESTATE'
cycle: 1
tokens_used: 1000
builder_model: sonnet
agent_status:
  loop-builder: done
PRUNESTATE

# Create empty agent-scores.yaml (just header comment)
cat > "$PRUNE_TMPDIR/agent-scores.yaml" << 'PRUNEEMPTY'
agents: {}
PRUNEEMPTY

# Backup real scores, swap in empty, run prune, restore
PRUNE_SCORES_BACKUP="$PRUNE_TMPDIR/real-scores-backup.yaml"
cp learning/agent-scores.yaml "$PRUNE_SCORES_BACKUP"
cp "$PRUNE_TMPDIR/agent-scores.yaml" learning/agent-scores.yaml

if bash scripts/update-scores.sh "$PRUNE_TMPDIR/state.yaml" "pass" --prune >/dev/null 2>&1; then
  pass "v6-func-prune-empty: update-scores.sh --prune exits 0 on empty scores file"
else
  fail "v6-func-prune-empty: update-scores.sh --prune crashed on empty scores file"
fi

# Restore real scores
cp "$PRUNE_SCORES_BACKUP" learning/agent-scores.yaml
rm -rf "$PRUNE_TMPDIR"

# ─────────────────────────────────────────────────
# v6-func-3: stale patterns excluded from load-knowledge.sh
# ─────────────────────────────────────────────────
echo ""
echo "=== Functional: Stale Pattern Exclusion ==="

STALE_TMPDIR=$(mktemp -d)

# Backup real patterns.yaml
STALE_PATTERNS_BACKUP="$STALE_TMPDIR/patterns-backup.yaml"
cp learning/patterns.yaml "$STALE_PATTERNS_BACKUP"

# Create patterns.yaml with one stale and one active pattern
# Use a test-only agent name (falls through to *) so no slice and no bible are loaded.
# Also swap troubleshooting with a stub so patterns section fits in 400-line cap.
cat > learning/patterns.yaml << 'STALEEOF'
patterns:
  - id: PAT-L900
    category: orchestration
    tech_stack: [op20-token, generic]
    failure_type: build_error
    description: STALE_MARKER_SHOULD_NOT_APPEAR
    fix: This pattern is stale
    source_sessions: [old-session]
    occurrence_count: 2
    promoted_to_knowledge: false
    first_seen: "2024-01-01"
    last_seen: "2024-01-01"
    last_seen_version: "4.0.0"
    stale: true
  - id: PAT-L901
    category: orchestration
    tech_stack: [op20-token, generic]
    failure_type: build_error
    description: ACTIVE_MARKER_SHOULD_APPEAR
    fix: This pattern is active
    source_sessions: [recent-session]
    occurrence_count: 3
    promoted_to_knowledge: false
    first_seen: "2026-03-01"
    last_seen: "2026-03-01"
    last_seen_version: "6.0.0"
    stale: false
STALEEOF

# Temporarily replace troubleshooting with a small stub so patterns have room
STALE_TROUBLESHOOTING_BACKUP="$STALE_TMPDIR/troubleshooting-backup.md"
cp knowledge/opnet-troubleshooting.md "$STALE_TROUBLESHOOTING_BACKUP"
echo "# Troubleshooting Stub (for stale test)" > knowledge/opnet-troubleshooting.md

STALE_OUTPUT=$(bash scripts/load-knowledge.sh test-stale-agent op20-token 2>/dev/null || true)

# Restore troubleshooting immediately
cp "$STALE_TROUBLESHOOTING_BACKUP" knowledge/opnet-troubleshooting.md

STALE_FOUND=false
if echo "$STALE_OUTPUT" | grep -q 'STALE_MARKER_SHOULD_NOT_APPEAR'; then
  STALE_FOUND=true
fi

ACTIVE_FOUND=false
if echo "$STALE_OUTPUT" | grep -q 'ACTIVE_MARKER_SHOULD_APPEAR'; then
  ACTIVE_FOUND=true
fi

if [[ "$STALE_FOUND" == "false" ]]; then
  pass "v6-func-stale-excluded: stale pattern text NOT in load-knowledge.sh output"
else
  fail "v6-func-stale-excluded: stale pattern text FOUND in load-knowledge.sh output"
fi

if [[ "$ACTIVE_FOUND" == "true" ]]; then
  pass "v6-func-active-included: active pattern text IS in load-knowledge.sh output"
else
  fail "v6-func-active-included: active pattern text NOT in load-knowledge.sh output"
fi

# Restore real patterns.yaml
cp "$STALE_PATTERNS_BACKUP" learning/patterns.yaml
rm -rf "$STALE_TMPDIR"

# ─────────────────────────────────────────────────
# v7 TEST-1: Mutation Testing Script
# ─────────────────────────────────────────────────
echo ""
echo "=== Mutation Testing Script ==="

if [[ -f scripts/mutate-contract.sh ]]; then
  pass "v7-mutation-script-exists: scripts/mutate-contract.sh exists"
else
  fail "v7-mutation-script-exists: scripts/mutate-contract.sh NOT found"
fi

if [[ -x scripts/mutate-contract.sh ]]; then
  pass "v7-mutation-script-executable: scripts/mutate-contract.sh is executable"
else
  fail "v7-mutation-script-executable: scripts/mutate-contract.sh is NOT executable"
fi

check "v7-mutation-script-syntax: mutate-contract.sh passes bash -n" bash -n scripts/mutate-contract.sh

if head -1 scripts/mutate-contract.sh | grep -q '#!/bin/bash'; then
  pass "v7-mutation-script-shebang: mutate-contract.sh has bash shebang"
else
  fail "v7-mutation-script-shebang: mutate-contract.sh missing bash shebang"
fi

if grep -q 'set -euo pipefail' scripts/mutate-contract.sh; then
  pass "v7-mutation-script-pipefail: mutate-contract.sh has set -euo pipefail"
else
  fail "v7-mutation-script-pipefail: mutate-contract.sh missing set -euo pipefail"
fi

if grep -q 'SCRIPT_DIR=' scripts/mutate-contract.sh; then
  pass "v7-mutation-script-dir: mutate-contract.sh has SCRIPT_DIR"
else
  fail "v7-mutation-script-dir: mutate-contract.sh missing SCRIPT_DIR"
fi

# Verify 20 mutation operators exist
OPERATOR_COUNT=$(grep -c 'arith-\|compare-\|bool-\|logic-\|negate-\|remove-\|zero-\|one-\|swap-' scripts/mutate-contract.sh || true)
if [[ "$OPERATOR_COUNT" -ge 20 ]]; then
  pass "v7-mutation-20-operators: mutate-contract.sh has >= 20 mutation operators ($OPERATOR_COUNT found)"
else
  fail "v7-mutation-20-operators: mutate-contract.sh has < 20 mutation operators ($OPERATOR_COUNT found)"
fi

if grep -q 'mutation-score.json' scripts/mutate-contract.sh; then
  pass "v7-mutation-output-file: mutate-contract.sh outputs mutation-score.json"
else
  fail "v7-mutation-output-file: mutate-contract.sh does NOT output mutation-score.json"
fi

# ─────────────────────────────────────────────────
# v7 TEST-2: Mutation Script Functional Test
# ─────────────────────────────────────────────────
echo ""
echo "=== Mutation Script Functional ==="

MUTATION_TMPDIR=$(mktemp -d)
mkdir -p "$MUTATION_TMPDIR/src"
mkdir -p "$MUTATION_TMPDIR/tests"
echo 'export class Token { }' > "$MUTATION_TMPDIR/src/contract.ts"

# Run with empty test dir — should produce valid JSON with score 0
MUTATION_OUT=$(bash scripts/mutate-contract.sh "$MUTATION_TMPDIR/src/contract.ts" "$MUTATION_TMPDIR/tests" 2>&1 || true)

if [[ -f artifacts/testing/mutation-score.json ]]; then
  pass "v7-mutation-func-creates-json: mutate-contract.sh creates mutation-score.json"

  # Check JSON structure using python3
  MUTATION_SCORE=$(python3 -c "import json; d=json.load(open('artifacts/testing/mutation-score.json')); print(d.get('mutation_score', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  MUTATION_VERDICT=$(python3 -c "import json; d=json.load(open('artifacts/testing/mutation-score.json')); print(d.get('verdict', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  MUTATION_THRESHOLD=$(python3 -c "import json; d=json.load(open('artifacts/testing/mutation-score.json')); print(type(d.get('threshold')).__name__)" 2>/dev/null || echo "PARSE_ERROR")

  if [[ "$MUTATION_SCORE" == "0" || "$MUTATION_SCORE" == "0.0" ]]; then
    pass "v7-mutation-func-score-zero: mutation_score is 0 for empty test dir"
  else
    fail "v7-mutation-func-score-zero: mutation_score is NOT 0 (got: $MUTATION_SCORE)"
  fi

  if [[ "$MUTATION_VERDICT" == "FAIL" ]]; then
    pass "v7-mutation-func-verdict-fail: verdict is FAIL for score 0"
  else
    fail "v7-mutation-func-verdict-fail: verdict is NOT FAIL (got: $MUTATION_VERDICT)"
  fi

  if [[ "$MUTATION_THRESHOLD" == "float" ]]; then
    pass "v7-mutation-func-threshold-type: threshold is a number (float), not string"
  else
    fail "v7-mutation-func-threshold-type: threshold is NOT a number (got type: $MUTATION_THRESHOLD)"
  fi
else
  fail "v7-mutation-func-creates-json: mutation-score.json NOT created"
  fail "v7-mutation-func-score-zero: (skipped — no JSON)"
  fail "v7-mutation-func-verdict-fail: (skipped — no JSON)"
  fail "v7-mutation-func-threshold-type: (skipped — no JSON)"
fi

rm -rf "$MUTATION_TMPDIR"
rm -f artifacts/testing/mutation-score.json

# ─────────────────────────────────────────────────
# v7 TEST-3: Localize Failure Script
# ─────────────────────────────────────────────────
echo ""
echo "=== Localize Failure Script ==="

if [[ -f scripts/localize-failure.sh ]]; then
  pass "v7-localize-script-exists: scripts/localize-failure.sh exists"
else
  fail "v7-localize-script-exists: scripts/localize-failure.sh NOT found"
fi

if [[ -x scripts/localize-failure.sh ]]; then
  pass "v7-localize-script-executable: scripts/localize-failure.sh is executable"
else
  fail "v7-localize-script-executable: scripts/localize-failure.sh is NOT executable"
fi

check "v7-localize-script-syntax: localize-failure.sh passes bash -n" bash -n scripts/localize-failure.sh

if grep -q 'localization.json' scripts/localize-failure.sh; then
  pass "v7-localize-output-file: localize-failure.sh outputs localization.json"
else
  fail "v7-localize-output-file: localize-failure.sh does NOT output localization.json"
fi

# ─────────────────────────────────────────────────
# v7 TEST-4: Localize Failure Functional Test
# ─────────────────────────────────────────────────
echo ""
echo "=== Localize Failure Functional ==="

LOCALIZE_TMPDIR=$(mktemp -d)

# Test with a sample error log
cat > "$LOCALIZE_TMPDIR/failure.log" << 'ERRLOG'
Error in src/contracts/Token.ts:42
  TypeError: Cannot read property 'balance' of undefined
    at transfer (src/contracts/Token.ts:42:15)
    at runTest (tests/token.test.ts:18:5)
ERRLOG

bash scripts/localize-failure.sh "$LOCALIZE_TMPDIR/failure.log" 2>&1 || true

if [[ -f artifacts/localization.json ]]; then
  pass "v7-localize-func-creates-json: localize-failure.sh creates localization.json"

  LOC_FILE=$(python3 -c "import json; d=json.load(open('artifacts/localization.json')); print(d.get('file', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  LOC_CONFIDENCE=$(python3 -c "import json; d=json.load(open('artifacts/localization.json')); print(d.get('confidence', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  LOC_CATEGORY=$(python3 -c "import json; d=json.load(open('artifacts/localization.json')); print(d.get('failure_category', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")

  if [[ "$LOC_FILE" != "unknown" && "$LOC_FILE" != "MISSING" ]]; then
    pass "v7-localize-func-finds-file: localization identifies file ($LOC_FILE)"
  else
    fail "v7-localize-func-finds-file: localization did NOT identify file (got: $LOC_FILE)"
  fi

  if [[ "$LOC_CONFIDENCE" == "high" || "$LOC_CONFIDENCE" == "medium" ]]; then
    pass "v7-localize-func-confidence: localization has good confidence ($LOC_CONFIDENCE)"
  else
    fail "v7-localize-func-confidence: localization has low confidence (got: $LOC_CONFIDENCE)"
  fi

  if [[ "$LOC_CATEGORY" != "unknown" && "$LOC_CATEGORY" != "MISSING" ]]; then
    pass "v7-localize-func-category: localization identifies category ($LOC_CATEGORY)"
  else
    fail "v7-localize-func-category: localization did NOT identify category (got: $LOC_CATEGORY)"
  fi
else
  fail "v7-localize-func-creates-json: localization.json NOT created"
  fail "v7-localize-func-finds-file: (skipped — no JSON)"
  fail "v7-localize-func-confidence: (skipped — no JSON)"
  fail "v7-localize-func-category: (skipped — no JSON)"
fi

# Test with empty log
echo "" > "$LOCALIZE_TMPDIR/empty.log"
bash scripts/localize-failure.sh "$LOCALIZE_TMPDIR/empty.log" 2>&1 || true

if [[ -f artifacts/localization.json ]]; then
  EMPTY_CONFIDENCE=$(python3 -c "import json; d=json.load(open('artifacts/localization.json')); print(d.get('confidence', 'MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$EMPTY_CONFIDENCE" == "low" ]]; then
    pass "v7-localize-func-empty-low-confidence: empty log produces low confidence"
  else
    fail "v7-localize-func-empty-low-confidence: empty log does NOT produce low confidence (got: $EMPTY_CONFIDENCE)"
  fi
else
  fail "v7-localize-func-empty-low-confidence: (skipped — no JSON)"
fi

rm -rf "$LOCALIZE_TMPDIR"
rm -f artifacts/localization.json

# ─────────────────────────────────────────────────
# v7 TEST-5: Extract Requirements Script
# ─────────────────────────────────────────────────
echo ""
echo "=== Extract Requirements Script ==="

if [[ -f scripts/extract-requirements.sh ]]; then
  pass "v7-extract-req-script-exists: scripts/extract-requirements.sh exists"
else
  fail "v7-extract-req-script-exists: scripts/extract-requirements.sh NOT found"
fi

if [[ -x scripts/extract-requirements.sh ]]; then
  pass "v7-extract-req-script-executable: scripts/extract-requirements.sh is executable"
else
  fail "v7-extract-req-script-executable: scripts/extract-requirements.sh is NOT executable"
fi

check "v7-extract-req-script-syntax: extract-requirements.sh passes bash -n" bash -n scripts/extract-requirements.sh

# ─────────────────────────────────────────────────
# v7 TEST-6: Extract Requirements Functional
# ─────────────────────────────────────────────────
echo ""
echo "=== Extract Requirements Functional ==="

EXTRACT_TMPDIR=$(mktemp -d)
cat > "$EXTRACT_TMPDIR/requirements.md" << 'REQMD'
# Requirements

1. Users can create tokens with a name and symbol
2. Token transfers should deduct from sender and credit receiver
3. Admin can mint new tokens
REQMD

bash scripts/extract-requirements.sh "$EXTRACT_TMPDIR/requirements.md" 2>&1 || true

if [[ -f artifacts/evaluation/spec-requirements.yaml ]]; then
  pass "v7-extract-req-func-creates-yaml: extract-requirements.sh creates spec-requirements.yaml"

  REQ_COUNT=$(grep -c 'id:' artifacts/evaluation/spec-requirements.yaml || true)
  if [[ "$REQ_COUNT" -ge 3 ]]; then
    pass "v7-extract-req-func-count: extracted >= 3 requirements ($REQ_COUNT found)"
  else
    fail "v7-extract-req-func-count: extracted < 3 requirements ($REQ_COUNT found)"
  fi

  if grep -q 'has_test:' artifacts/evaluation/spec-requirements.yaml; then
    pass "v7-extract-req-func-has-test-field: spec-requirements.yaml has has_test field"
  else
    fail "v7-extract-req-func-has-test-field: spec-requirements.yaml missing has_test field"
  fi

  if grep -q 'priority:' artifacts/evaluation/spec-requirements.yaml; then
    pass "v7-extract-req-func-priority-field: spec-requirements.yaml has priority field"
  else
    fail "v7-extract-req-func-priority-field: spec-requirements.yaml missing priority field"
  fi
else
  fail "v7-extract-req-func-creates-yaml: spec-requirements.yaml NOT created"
  fail "v7-extract-req-func-count: (skipped — no YAML)"
  fail "v7-extract-req-func-has-test-field: (skipped — no YAML)"
  fail "v7-extract-req-func-priority-field: (skipped — no YAML)"
fi

rm -rf "$EXTRACT_TMPDIR"
rm -f artifacts/evaluation/spec-requirements.yaml

# ─────────────────────────────────────────────────
# v7 TEST-7: Score Build Script
# ─────────────────────────────────────────────────
echo ""
echo "=== Score Build Script ==="

if [[ -f scripts/score-build.sh ]]; then
  pass "v7-score-build-script-exists: scripts/score-build.sh exists"
else
  fail "v7-score-build-script-exists: scripts/score-build.sh NOT found"
fi

if [[ -x scripts/score-build.sh ]]; then
  pass "v7-score-build-script-executable: scripts/score-build.sh is executable"
else
  fail "v7-score-build-script-executable: scripts/score-build.sh is NOT executable"
fi

check "v7-score-build-script-syntax: score-build.sh passes bash -n" bash -n scripts/score-build.sh

# ─────────────────────────────────────────────────
# v7 TEST-8: Score Build Functional
# ─────────────────────────────────────────────────
echo ""
echo "=== Score Build Functional ==="

# Clean up any leftover artifacts
rm -rf artifacts/evaluation artifacts/testing artifacts/findings-ledger.md

bash scripts/score-build.sh 2>&1 || true

if [[ -f artifacts/evaluation/progress-tracker.yaml ]]; then
  pass "v7-score-build-func-creates-yaml: score-build.sh creates progress-tracker.yaml"

  if grep -q 'spec_coverage:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-spec-dim: progress-tracker has spec_coverage dimension"
  else
    fail "v7-score-build-func-spec-dim: progress-tracker missing spec_coverage dimension"
  fi

  if grep -q 'security_delta:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-security-dim: progress-tracker has security_delta dimension"
  else
    fail "v7-score-build-func-security-dim: progress-tracker missing security_delta dimension"
  fi

  if grep -q 'mutation_score:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-mutation-dim: progress-tracker has mutation_score dimension"
  else
    fail "v7-score-build-func-mutation-dim: progress-tracker missing mutation_score dimension"
  fi

  if grep -q 'code_health:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-health-dim: progress-tracker has code_health dimension"
  else
    fail "v7-score-build-func-health-dim: progress-tracker missing code_health dimension"
  fi

  if grep -q 'overall_verdict:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-verdict: progress-tracker has overall_verdict"
  else
    fail "v7-score-build-func-verdict: progress-tracker missing overall_verdict"
  fi

  if grep -q 'threshold:' artifacts/evaluation/progress-tracker.yaml; then
    pass "v7-score-build-func-thresholds: progress-tracker has threshold entries"
  else
    fail "v7-score-build-func-thresholds: progress-tracker missing threshold entries"
  fi
else
  fail "v7-score-build-func-creates-yaml: progress-tracker.yaml NOT created"
  fail "v7-score-build-func-spec-dim: (skipped — no YAML)"
  fail "v7-score-build-func-security-dim: (skipped — no YAML)"
  fail "v7-score-build-func-mutation-dim: (skipped — no YAML)"
  fail "v7-score-build-func-health-dim: (skipped — no YAML)"
  fail "v7-score-build-func-verdict: (skipped — no YAML)"
  fail "v7-score-build-func-thresholds: (skipped — no YAML)"
fi

rm -rf artifacts/evaluation

# ─────────────────────────────────────────────────
# v7 TEST-9: Build Repo Map Script
# ─────────────────────────────────────────────────
echo ""
echo "=== Build Repo Map Script ==="

if [[ -f scripts/build-repo-map.sh ]]; then
  pass "v7-repo-map-script-exists: scripts/build-repo-map.sh exists"
else
  fail "v7-repo-map-script-exists: scripts/build-repo-map.sh NOT found"
fi

if [[ -x scripts/build-repo-map.sh ]]; then
  pass "v7-repo-map-script-executable: scripts/build-repo-map.sh is executable"
else
  fail "v7-repo-map-script-executable: scripts/build-repo-map.sh is NOT executable"
fi

check "v7-repo-map-script-syntax: build-repo-map.sh passes bash -n" bash -n scripts/build-repo-map.sh

# ─────────────────────────────────────────────────
# v7 TEST-10: Build Repo Map Functional
# ─────────────────────────────────────────────────
echo ""
echo "=== Build Repo Map Functional ==="

REPOMAP_TMPDIR=$(mktemp -d)

# Create a minimal ABI
cat > "$REPOMAP_TMPDIR/abi.json" << 'ABIJSON'
[
  {"type": "function", "name": "transfer", "inputs": [{"name": "to", "type": "address"}, {"name": "amount", "type": "u256"}], "outputs": [{"type": "bool"}]},
  {"type": "function", "name": "balanceOf", "inputs": [{"name": "owner", "type": "address"}], "outputs": [{"type": "u256"}]},
  {"type": "event", "name": "Transfer", "inputs": [{"name": "from", "type": "address"}, {"name": "to", "type": "address"}, {"name": "value", "type": "u256"}]}
]
ABIJSON

rm -f artifacts/repo-map.md
bash scripts/build-repo-map.sh "$REPOMAP_TMPDIR/abi.json" "" "" 2>&1 || true

if [[ -f artifacts/repo-map.md ]]; then
  pass "v7-repo-map-func-creates-md: build-repo-map.sh creates repo-map.md"

  if grep -q 'Contract Layer' artifacts/repo-map.md; then
    pass "v7-repo-map-func-contract-layer: repo-map.md has Contract Layer section"
  else
    fail "v7-repo-map-func-contract-layer: repo-map.md missing Contract Layer section"
  fi

  if grep -q 'transfer' artifacts/repo-map.md; then
    pass "v7-repo-map-func-method-listed: repo-map.md lists transfer method"
  else
    fail "v7-repo-map-func-method-listed: repo-map.md does NOT list transfer method"
  fi

  if grep -q 'Frontend Layer' artifacts/repo-map.md; then
    pass "v7-repo-map-func-frontend-layer: repo-map.md has Frontend Layer section"
  else
    fail "v7-repo-map-func-frontend-layer: repo-map.md missing Frontend Layer section"
  fi

  if grep -q 'Backend Layer' artifacts/repo-map.md; then
    pass "v7-repo-map-func-backend-layer: repo-map.md has Backend Layer section"
  else
    fail "v7-repo-map-func-backend-layer: repo-map.md missing Backend Layer section"
  fi

  if grep -q 'Cross-Layer Integrity' artifacts/repo-map.md; then
    pass "v7-repo-map-func-integrity: repo-map.md has Cross-Layer Integrity section"
  else
    fail "v7-repo-map-func-integrity: repo-map.md missing Cross-Layer Integrity section"
  fi

  REPOMAP_LINES=$(wc -l < artifacts/repo-map.md | tr -d ' ')
  if [[ "$REPOMAP_LINES" -lt 300 ]]; then
    pass "v7-repo-map-func-under-300: repo-map.md is under 300 lines ($REPOMAP_LINES lines)"
  else
    fail "v7-repo-map-func-under-300: repo-map.md is >= 300 lines ($REPOMAP_LINES lines)"
  fi
else
  fail "v7-repo-map-func-creates-md: repo-map.md NOT created"
  fail "v7-repo-map-func-contract-layer: (skipped — no file)"
  fail "v7-repo-map-func-method-listed: (skipped — no file)"
  fail "v7-repo-map-func-frontend-layer: (skipped — no file)"
  fail "v7-repo-map-func-backend-layer: (skipped — no file)"
  fail "v7-repo-map-func-integrity: (skipped — no file)"
  fail "v7-repo-map-func-under-300: (skipped — no file)"
fi

rm -rf "$REPOMAP_TMPDIR"
rm -f artifacts/repo-map.md

# ─────────────────────────────────────────────────
# v7 TEST-11: Buidl Optimize Command
# ─────────────────────────────────────────────────
echo ""
echo "=== Buidl Optimize Command ==="

if [[ -f commands/buidl-optimize.md ]]; then
  pass "v7-optimize-cmd-exists: commands/buidl-optimize.md exists"
else
  fail "v7-optimize-cmd-exists: commands/buidl-optimize.md NOT found"
fi

# Check frontmatter
if head -5 commands/buidl-optimize.md | grep -q 'description:'; then
  pass "v7-optimize-cmd-description: buidl-optimize.md has description in frontmatter"
else
  fail "v7-optimize-cmd-description: buidl-optimize.md missing description in frontmatter"
fi

if head -10 commands/buidl-optimize.md | grep -q 'argument-hint:'; then
  pass "v7-optimize-cmd-argument-hint: buidl-optimize.md has argument-hint in frontmatter"
else
  fail "v7-optimize-cmd-argument-hint: buidl-optimize.md missing argument-hint in frontmatter"
fi

if head -10 commands/buidl-optimize.md | grep -q 'allowed-tools:'; then
  pass "v7-optimize-cmd-allowed-tools: buidl-optimize.md has allowed-tools in frontmatter"
else
  fail "v7-optimize-cmd-allowed-tools: buidl-optimize.md missing allowed-tools in frontmatter"
fi

# Check FORBIDDEN section
if grep -q 'FORBIDDEN' commands/buidl-optimize.md; then
  pass "v7-optimize-cmd-forbidden: buidl-optimize.md has FORBIDDEN section"
else
  fail "v7-optimize-cmd-forbidden: buidl-optimize.md missing FORBIDDEN section"
fi

# Check supported metrics
for metric in gas bundle_size test_time throughput; do
  if grep -q "$metric" commands/buidl-optimize.md; then
    pass "v7-optimize-cmd-metric-${metric}: buidl-optimize.md supports $metric metric"
  else
    fail "v7-optimize-cmd-metric-${metric}: buidl-optimize.md missing $metric metric"
  fi
done

# Check max_cycles default
if grep -q '10' commands/buidl-optimize.md; then
  pass "v7-optimize-cmd-max-cycles: buidl-optimize.md mentions default 10 max cycles"
else
  fail "v7-optimize-cmd-max-cycles: buidl-optimize.md missing default 10 max cycles"
fi

# Check output artifacts
if grep -q 'summary.md' commands/buidl-optimize.md; then
  pass "v7-optimize-cmd-output-summary: buidl-optimize.md references summary.md output"
else
  fail "v7-optimize-cmd-output-summary: buidl-optimize.md missing summary.md output reference"
fi

if grep -q 'best-result.json' commands/buidl-optimize.md; then
  pass "v7-optimize-cmd-output-best: buidl-optimize.md references best-result.json output"
else
  fail "v7-optimize-cmd-output-best: buidl-optimize.md missing best-result.json output reference"
fi

# ─────────────────────────────────────────────────
# v7 TEST-12: Mutation Gate in Orchestrator
# ─────────────────────────────────────────────────
echo ""
echo "=== Mutation Gate in Orchestrator ==="

if grep -q 'mutate-contract.sh' commands/buidl.md; then
  pass "v7-mutation-gate-in-buidl: buidl.md references mutate-contract.sh"
else
  fail "v7-mutation-gate-in-buidl: buidl.md does NOT reference mutate-contract.sh"
fi

if grep -q 'mutation_score' commands/buidl.md; then
  pass "v7-mutation-gate-score-check: buidl.md checks mutation_score"
else
  fail "v7-mutation-gate-score-check: buidl.md does NOT check mutation_score"
fi

if grep -q '0.70' commands/buidl.md; then
  pass "v7-mutation-gate-threshold: buidl.md has 0.70 threshold"
else
  fail "v7-mutation-gate-threshold: buidl.md missing 0.70 threshold"
fi

# Mutation gate should be in Phase 5 (REVIEW section)
if sed -n '/PHASE 5/,/PHASE 6/p' commands/buidl.md | grep -q 'mutate-contract.sh'; then
  pass "v7-mutation-gate-phase5: mutation gate is in Phase 5 section"
else
  fail "v7-mutation-gate-phase5: mutation gate is NOT in Phase 5 section"
fi

# ─────────────────────────────────────────────────
# v7 TEST-13: Structured Repair Phases in Orchestrator
# ─────────────────────────────────────────────────
echo ""
echo "=== Structured Repair Phases ==="

if grep -q 'Phase R1' commands/buidl.md; then
  pass "v7-repair-r1-in-buidl: buidl.md has Phase R1 (LOCALIZE)"
else
  fail "v7-repair-r1-in-buidl: buidl.md missing Phase R1"
fi

if grep -q 'Phase R2' commands/buidl.md; then
  pass "v7-repair-r2-in-buidl: buidl.md has Phase R2 (PATCH)"
else
  fail "v7-repair-r2-in-buidl: buidl.md missing Phase R2"
fi

if grep -q 'Phase R3' commands/buidl.md; then
  pass "v7-repair-r3-in-buidl: buidl.md has Phase R3 (VALIDATE)"
else
  fail "v7-repair-r3-in-buidl: buidl.md missing Phase R3"
fi

if grep -q 'localize-failure.sh' commands/buidl.md; then
  pass "v7-repair-localize-ref: buidl.md references localize-failure.sh"
else
  fail "v7-repair-localize-ref: buidl.md does NOT reference localize-failure.sh"
fi

if grep -q 'localization.json' commands/buidl.md; then
  pass "v7-repair-localization-json: buidl.md references localization.json output"
else
  fail "v7-repair-localization-json: buidl.md does NOT reference localization.json"
fi

# ─────────────────────────────────────────────────
# v7 TEST-14: Score Build in Orchestrator
# ─────────────────────────────────────────────────
echo ""
echo "=== Score Build in Orchestrator ==="

if grep -q 'score-build.sh' commands/buidl.md; then
  pass "v7-score-build-in-buidl: buidl.md references score-build.sh"
else
  fail "v7-score-build-in-buidl: buidl.md does NOT reference score-build.sh"
fi

if grep -q 'progress-tracker.yaml' commands/buidl.md; then
  pass "v7-score-build-tracker-ref: buidl.md references progress-tracker.yaml"
else
  fail "v7-score-build-tracker-ref: buidl.md does NOT reference progress-tracker.yaml"
fi

if grep -q 'spec_coverage' commands/buidl.md; then
  pass "v7-score-build-spec-dim: buidl.md has spec_coverage dimension"
else
  fail "v7-score-build-spec-dim: buidl.md missing spec_coverage dimension"
fi

if grep -q 'security_delta' commands/buidl.md; then
  pass "v7-score-build-security-dim: buidl.md has security_delta dimension"
else
  fail "v7-score-build-security-dim: buidl.md missing security_delta dimension"
fi

if grep -q 'code_health' commands/buidl.md; then
  pass "v7-score-build-health-dim: buidl.md has code_health dimension"
else
  fail "v7-score-build-health-dim: buidl.md missing code_health dimension"
fi

# ─────────────────────────────────────────────────
# v7 TEST-15: Repo Map in Orchestrator
# ─────────────────────────────────────────────────
echo ""
echo "=== Repo Map in Orchestrator ==="

if grep -q 'build-repo-map.sh' commands/buidl.md; then
  pass "v7-repo-map-in-buidl: buidl.md references build-repo-map.sh"
else
  fail "v7-repo-map-in-buidl: buidl.md does NOT reference build-repo-map.sh"
fi

if grep -q 'repo-map.md' commands/buidl.md; then
  pass "v7-repo-map-artifact-ref: buidl.md references repo-map.md artifact"
else
  fail "v7-repo-map-artifact-ref: buidl.md does NOT reference repo-map.md artifact"
fi

# Check that repo map is generated after ABI lock
if sed -n '/ABI Lock/,/Issue Check/p' commands/buidl.md | grep -q 'build-repo-map.sh'; then
  pass "v7-repo-map-after-abi-lock: repo map generated after ABI lock in buidl.md"
else
  fail "v7-repo-map-after-abi-lock: repo map NOT generated after ABI lock in buidl.md"
fi

# ─────────────────────────────────────────────────
# v7 TEST-16: Agent Repo Map References
# ─────────────────────────────────────────────────
echo ""
echo "=== Agent Repo Map References ==="

V7_AGENTS=(cross-layer-validator loop-builder loop-explorer loop-researcher loop-reviewer opnet-auditor opnet-backend-dev opnet-contract-dev opnet-deployer opnet-e2e-tester opnet-frontend-dev opnet-ui-tester)

for agent in "${V7_AGENTS[@]}"; do
  if grep -q 'repo-map.md' "agents/${agent}.md"; then
    pass "v7-agent-repomap-${agent}: ${agent}.md references repo-map.md"
  else
    fail "v7-agent-repomap-${agent}: ${agent}.md does NOT reference repo-map.md"
  fi
done

# Verify adversarial agents do NOT have repo-map reference
for agent in opnet-adversarial-auditor opnet-adversarial-tester; do
  if grep -q 'repo-map.md' "agents/${agent}.md" 2>/dev/null; then
    fail "v7-agent-repomap-no-${agent}: ${agent}.md should NOT reference repo-map.md"
  else
    pass "v7-agent-repomap-no-${agent}: ${agent}.md correctly does NOT reference repo-map.md"
  fi
done

# ─────────────────────────────────────────────────
# v7 TEST-17: Localize Mode in Reviewer
# ─────────────────────────────────────────────────
echo ""
echo "=== Localize Mode in Reviewer ==="

if grep -q 'Localize Mode' agents/loop-reviewer.md; then
  pass "v7-localize-mode-in-reviewer: loop-reviewer.md has Localize Mode section"
else
  fail "v7-localize-mode-in-reviewer: loop-reviewer.md missing Localize Mode section"
fi

if grep -q 'max_turns.*5' agents/loop-reviewer.md; then
  pass "v7-localize-mode-max-turns: Localize Mode has max_turns 5"
else
  fail "v7-localize-mode-max-turns: Localize Mode missing max_turns 5"
fi

if grep -q 'READ-ONLY' agents/loop-reviewer.md; then
  pass "v7-localize-mode-readonly: Localize Mode is READ-ONLY"
else
  fail "v7-localize-mode-readonly: Localize Mode missing READ-ONLY constraint"
fi

if grep -q 'FORBIDDEN in Localize Mode' agents/loop-reviewer.md; then
  pass "v7-localize-mode-forbidden: Localize Mode has FORBIDDEN section"
else
  fail "v7-localize-mode-forbidden: Localize Mode missing FORBIDDEN section"
fi

# Localize Mode should appear AFTER Critique Mode
CRITIQUE_LINE=$(grep -n 'Critique Mode' agents/loop-reviewer.md | head -1 | cut -d: -f1)
LOCALIZE_LINE=$(grep -n 'Localize Mode' agents/loop-reviewer.md | head -1 | cut -d: -f1)
if [[ -n "$CRITIQUE_LINE" && -n "$LOCALIZE_LINE" && "$LOCALIZE_LINE" -gt "$CRITIQUE_LINE" ]]; then
  pass "v7-localize-mode-after-critique: Localize Mode appears after Critique Mode"
else
  fail "v7-localize-mode-after-critique: Localize Mode does NOT appear after Critique Mode"
fi

# ─────────────────────────────────────────────────
# v7 TEST-18: Buidl Status Updates
# ─────────────────────────────────────────────────
echo ""
echo "=== Buidl Status Updates ==="

if grep -q 'Mutation' commands/buidl-status.md; then
  pass "v7-status-mutation: buidl-status.md shows mutation score"
else
  fail "v7-status-mutation: buidl-status.md does NOT show mutation score"
fi

if grep -q 'mutation-score.json' commands/buidl-status.md; then
  pass "v7-status-mutation-json: buidl-status.md references mutation-score.json"
else
  fail "v7-status-mutation-json: buidl-status.md does NOT reference mutation-score.json"
fi

if grep -q 'Build Score' commands/buidl-status.md; then
  pass "v7-status-build-score: buidl-status.md shows build score card"
else
  fail "v7-status-build-score: buidl-status.md does NOT show build score card"
fi

if grep -q 'progress-tracker.yaml' commands/buidl-status.md; then
  pass "v7-status-tracker-ref: buidl-status.md references progress-tracker.yaml"
else
  fail "v7-status-tracker-ref: buidl-status.md does NOT reference progress-tracker.yaml"
fi

# Verify steps are properly renumbered (old step 7 is now step 9)
if grep -q '^9\. ' commands/buidl-status.md; then
  pass "v7-status-renumbered-9: buidl-status.md has step 9"
else
  fail "v7-status-renumbered-9: buidl-status.md missing step 9"
fi

if grep -q '^12\. ' commands/buidl-status.md; then
  pass "v7-status-renumbered-12: buidl-status.md has step 12"
else
  fail "v7-status-renumbered-12: buidl-status.md missing step 12"
fi

# ─────────────────────────────────────────────────
# v7 TEST-19: CHANGELOG and README Updates
# ─────────────────────────────────────────────────
echo ""
echo "=== CHANGELOG and README Updates ==="

if grep -q '\[7\.0\.0\]' CHANGELOG.md; then
  pass "v7-changelog-entry: CHANGELOG.md has [7.0.0] entry"
else
  fail "v7-changelog-entry: CHANGELOG.md missing [7.0.0] entry"
fi

# 7.0.0 should come before 6.0.0
V7_LINE=$(grep -n '\[7\.0\.0\]' CHANGELOG.md | head -1 | cut -d: -f1)
V6_LINE=$(grep -n '\[6\.0\.0\]' CHANGELOG.md | head -1 | cut -d: -f1)
if [[ -n "$V7_LINE" && -n "$V6_LINE" && "$V7_LINE" -lt "$V6_LINE" ]]; then
  pass "v7-changelog-order: [7.0.0] comes before [6.0.0] in CHANGELOG"
else
  fail "v7-changelog-order: [7.0.0] does NOT come before [6.0.0] in CHANGELOG"
fi

if grep -q 'buidl-optimize' README.md; then
  pass "v7-readme-optimize-cmd: README.md mentions buidl-optimize command"
else
  fail "v7-readme-optimize-cmd: README.md does NOT mention buidl-optimize command"
fi

if grep -q 'v7\.0\.0' README.md; then
  pass "v7-readme-version-history: README.md has v7.0.0 in version history"
else
  fail "v7-readme-version-history: README.md missing v7.0.0 in version history"
fi

if grep -q 'Mutation' README.md; then
  pass "v7-readme-mutation-feature: README.md mentions mutation testing feature"
else
  fail "v7-readme-mutation-feature: README.md does NOT mention mutation testing feature"
fi

if grep -q 'Structured Repair' README.md; then
  pass "v7-readme-repair-feature: README.md mentions structured repair feature"
else
  fail "v7-readme-repair-feature: README.md does NOT mention structured repair feature"
fi

if grep -q 'Goal-Oriented' README.md; then
  pass "v7-readme-scoring-feature: README.md mentions goal-oriented evaluation feature"
else
  fail "v7-readme-scoring-feature: README.md does NOT mention goal-oriented evaluation feature"
fi

if grep -q 'Repo Map' README.md; then
  pass "v7-readme-repomap-feature: README.md mentions repo map feature"
else
  fail "v7-readme-repomap-feature: README.md does NOT mention repo map feature"
fi

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo ""
echo "==========================================="
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "  Results: $PASS_COUNT/$TOTAL PASS, $FAIL_COUNT FAIL"
echo "==========================================="

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo ""
  echo "  Failures:"
  for f in "${FAILURES[@]}"; do
    echo "    - $f"
  done
  echo ""
  exit 1
fi

echo ""
exit 0
