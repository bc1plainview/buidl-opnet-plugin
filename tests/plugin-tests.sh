#!/bin/bash
# plugin-tests.sh — Structural validation tests for the buidl plugin
#
# Validates all invariants that have caused regressions:
# - Shell script syntax and correctness
# - Agent template structure (10 agents, 5 required sections each)
# - FORBIDDEN blocks in all 6 specialist agents
# - Knowledge slice references resolve to existing files
# - Issue bus type enum consistency across agents
# - Version consistency (plugin.json matches CHANGELOG)
# - Required file existence
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

# ─────────────────────────────────────────────────
# 2. Shell Script Correctness
# ─────────────────────────────────────────────────
echo ""
echo "=== Shell Script Correctness ==="

# sedi() must call sed, not itself (the infinite recursion bug)
if grep -q 'sedi()' hooks/scripts/stop-hook.sh; then
  # Extract the darwin branch of sedi() and check it calls sed, not sedi
  darwin_line=$(sed -n '/sedi()/,/^}/p' hooks/scripts/stop-hook.sh | grep 'darwin' -A1 | tail -1)
  if echo "$darwin_line" | grep -q 'sed -i'; then
    pass "sedi() darwin branch calls sed (not itself)"
  else
    fail "sedi() darwin branch does NOT call sed — possible infinite recursion"
  fi

  # Also verify no self-referential call in the function body
  sedi_body=$(sed -n '/^sedi()/,/^}/p' hooks/scripts/stop-hook.sh)
  # Count "sedi" occurrences in the body (should be exactly 1 — the function name itself)
  sedi_calls=$(echo "$sedi_body" | grep -c 'sedi' || true)
  if [[ "$sedi_calls" -le 1 ]]; then
    pass "sedi() body has no recursive calls"
  else
    fail "sedi() body contains recursive call to itself"
  fi
else
  fail "sedi() function not found in stop-hook.sh"
fi

# stop-hook.sh uses $'\n' not literal \n for issue injection
if grep -q '\\n---' hooks/scripts/stop-hook.sh; then
  fail "stop-hook.sh uses literal \\n (should use \$'\\n')"
else
  pass "stop-hook.sh does not use literal \\n for newlines"
fi

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
  scripts/setup-loop.sh
  commands/buidl.md
  commands/buidl-spec.md
  commands/buidl-review.md
  commands/buidl-status.md
  commands/buidl-cancel.md
  commands/buidl-clean.md
  knowledge/opnet-bible.md
  knowledge/opnet-troubleshooting.md
  knowledge/README.md
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
