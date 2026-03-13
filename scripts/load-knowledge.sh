#!/bin/bash
# load-knowledge.sh — Dynamic knowledge slice loading for agents
#
# Usage: bash scripts/load-knowledge.sh <agent-name> <project-type>
#
# Assembles a combined knowledge payload for a specific agent by:
# 1. Always including the agent's domain-specific slice from knowledge/slices/
# 2. Always including knowledge/opnet-troubleshooting.md
# 3. Conditionally including sections of knowledge/opnet-bible.md based on agent role
# 4. Including non-stale [LEARNED] patterns from learning/patterns.yaml
# 5. Capping output at 400 lines max (truncating least-relevant sections first)
#
# Agent role mapping for opnet-bible.md section filtering:
#   contract-dev       -> full bible (all sections)
#   frontend-dev       -> [FRONTEND] sections only
#   backend-dev        -> [BACKEND] sections only
#   auditor            -> [SECURITY] sections only
#   adversarial-auditor -> [SECURITY] sections only
#   deployer           -> [DEPLOYMENT] sections only
#   e2e-tester         -> [DEPLOYMENT] sections only
#   loop-builder       -> full bible (all sections)
#   Other agents       -> no bible sections
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_NAME="${1:-}"
PROJECT_TYPE="${2:-generic}"
MAX_LINES=400

if [[ -z "$AGENT_NAME" ]]; then
  echo "Usage: bash scripts/load-knowledge.sh <agent-name> <project-type>" >&2
  exit 1
fi

# Map agent name to its knowledge slice file
SLICE_FILE=""
case "$AGENT_NAME" in
  opnet-contract-dev)      SLICE_FILE="$SCRIPT_DIR/knowledge/slices/contract-dev.md" ;;
  opnet-frontend-dev)      SLICE_FILE="$SCRIPT_DIR/knowledge/slices/frontend-dev.md" ;;
  opnet-backend-dev)       SLICE_FILE="$SCRIPT_DIR/knowledge/slices/backend-dev.md" ;;
  opnet-auditor)           SLICE_FILE="$SCRIPT_DIR/knowledge/slices/security-audit.md" ;;
  opnet-adversarial-auditor) SLICE_FILE="$SCRIPT_DIR/knowledge/slices/security-audit.md" ;;
  opnet-deployer)          SLICE_FILE="$SCRIPT_DIR/knowledge/slices/deployment.md" ;;
  opnet-e2e-tester)        SLICE_FILE="$SCRIPT_DIR/knowledge/slices/e2e-testing.md" ;;
  opnet-adversarial-tester) SLICE_FILE="$SCRIPT_DIR/knowledge/slices/e2e-testing.md" ;;
  opnet-ui-tester)         SLICE_FILE="$SCRIPT_DIR/knowledge/slices/ui-testing.md" ;;
  cross-layer-validator)   SLICE_FILE="$SCRIPT_DIR/knowledge/slices/cross-layer-validation.md" ;;
  loop-explorer)           SLICE_FILE="$SCRIPT_DIR/knowledge/slices/project-setup.md" ;;
  loop-reviewer)           SLICE_FILE="$SCRIPT_DIR/knowledge/slices/integration-review.md" ;;
  loop-builder)            SLICE_FILE="" ;;
  *)                       SLICE_FILE="" ;;
esac

# Map agent name to bible section filter tags
BIBLE_TAGS=""
case "$AGENT_NAME" in
  opnet-contract-dev)      BIBLE_TAGS="CONTRACT FRONTEND BACKEND DEPLOYMENT SECURITY" ;;
  loop-builder)            BIBLE_TAGS="CONTRACT FRONTEND BACKEND DEPLOYMENT SECURITY" ;;
  opnet-frontend-dev)      BIBLE_TAGS="FRONTEND" ;;
  opnet-backend-dev)       BIBLE_TAGS="BACKEND" ;;
  opnet-auditor)           BIBLE_TAGS="SECURITY" ;;
  opnet-adversarial-auditor) BIBLE_TAGS="SECURITY" ;;
  opnet-deployer)          BIBLE_TAGS="DEPLOYMENT" ;;
  opnet-e2e-tester)        BIBLE_TAGS="DEPLOYMENT" ;;
  opnet-adversarial-tester) BIBLE_TAGS="DEPLOYMENT" ;;
  *)                       BIBLE_TAGS="" ;;
esac

# Use temp files instead of large bash variables to avoid cross-platform
# pipe issues (SIGPIPE under pipefail, bash version differences)
_TMPDIR=$(mktemp -d)
trap 'rm -rf "$_TMPDIR"' EXIT

# Collect section file paths in order of relevance (most relevant first)
# Section 1: Agent-specific slice (highest relevance)
# Section 2: Troubleshooting guide
# Section 3: Bible sections matching role
# Section 4: Learned patterns
SECTION_FILES=()
SECTION_NAMES=()

# Section 1: Agent-specific slice
if [[ -n "$SLICE_FILE" && -f "$SLICE_FILE" ]]; then
  SECTION_FILES+=("$SLICE_FILE")
  SECTION_NAMES+=("agent-slice")
fi

# Section 2: Troubleshooting
TROUBLESHOOTING_FILE="$SCRIPT_DIR/knowledge/opnet-troubleshooting.md"
if [[ -f "$TROUBLESHOOTING_FILE" ]]; then
  SECTION_FILES+=("$TROUBLESHOOTING_FILE")
  SECTION_NAMES+=("troubleshooting")
fi

# Section 3: Bible sections (extracted to temp file)
BIBLE_FILE="$SCRIPT_DIR/knowledge/opnet-bible.md"
_BIBLE_TMP="$_TMPDIR/bible.md"
if [[ -n "$BIBLE_TAGS" && -f "$BIBLE_FILE" ]]; then
  python3 -c "
import sys, re

bible_path = sys.argv[1]
tags = sys.argv[2].split()

with open(bible_path) as f:
    content = f.read()

# Find all section blocks
pattern = r'<!-- BEGIN-SECTION-(\d+)\s+(.*?)-->(.*?)<!-- END-SECTION-\1 -->'
matches = re.findall(pattern, content, re.DOTALL)

output_parts = []
for section_num, tag_str, section_content in matches:
    # Parse tags: [CONTRACT] [FRONTEND] [BACKEND] etc
    section_tags = re.findall(r'\[([A-Z]+)\]', tag_str)
    # Check if any of the agent's tags match
    if any(t in section_tags for t in tags):
        output_parts.append(section_content.strip())

print('\n\n'.join(output_parts))
" "$BIBLE_FILE" "$BIBLE_TAGS" > "$_BIBLE_TMP" 2>/dev/null || true
  if [[ -s "$_BIBLE_TMP" ]]; then
    SECTION_FILES+=("$_BIBLE_TMP")
    SECTION_NAMES+=("bible")
  fi
fi

# Section 4: Learned patterns (extracted to temp file)
PATTERNS_FILE="$SCRIPT_DIR/learning/patterns.yaml"
_LEARNED_TMP="$_TMPDIR/learned.md"
if [[ -f "$PATTERNS_FILE" ]]; then
  python3 -c "
try:
    import yaml
except ImportError:
    import sys; sys.exit(0)
import sys

patterns_file = sys.argv[1]
project_type = sys.argv[2]

with open(patterns_file) as f:
    data = yaml.safe_load(f)

if not data:
    sys.exit(0)

patterns = data.get('patterns', [])
if not patterns:
    sys.exit(0)

output = ['## [LEARNED] Patterns from Past Sessions', '']
count = 0
for p in patterns:
    # Skip stale patterns
    if p.get('stale', False):
        continue
    # Include patterns relevant to the project type or with high occurrence
    tech_stack = p.get('tech_stack', [])
    occurrence = p.get('occurrence_count', 1)
    if project_type in tech_stack or occurrence >= 3 or project_type == 'generic':
        desc = p.get('description', '')
        fix = p.get('fix', '')
        pat_id = p.get('id', '')
        line = f'- **{pat_id}**: {desc}'
        if fix:
            line += f' -- Fix: {fix}'
        output.append(line)
        count += 1

if count > 0:
    print('\n'.join(output))
" "$PATTERNS_FILE" "$PROJECT_TYPE" > "$_LEARNED_TMP" 2>/dev/null || true
  if [[ -s "$_LEARNED_TMP" ]]; then
    SECTION_FILES+=("$_LEARNED_TMP")
    SECTION_NAMES+=("learned-patterns")
  fi
fi

# If no sections were collected, exit cleanly
if [[ ${#SECTION_FILES[@]} -eq 0 ]]; then
  exit 0
fi

# Combine all sections into a single output file
_OUTPUT="$_TMPDIR/output.md"
_FIRST=true
for _f in "${SECTION_FILES[@]}"; do
  if [[ "$_FIRST" != "true" ]]; then
    printf '\n\n' >> "$_OUTPUT"
  fi
  cat "$_f" >> "$_OUTPUT"
  _FIRST=false
done

# Count lines and truncate if needed (remove least-relevant sections first)
LINE_COUNT=$(wc -l < "$_OUTPUT" | tr -d ' ')

if [[ "$LINE_COUNT" -gt "$MAX_LINES" ]]; then
  _TRUNCATED="$_TMPDIR/truncated.md"
  REMAINING=$MAX_LINES

  for i in "${!SECTION_FILES[@]}"; do
    if [[ "$REMAINING" -le 0 ]]; then
      break
    fi
    SECTION_LINES=$(wc -l < "${SECTION_FILES[$i]}" | tr -d ' ')

    # Add separator between sections (not before the first)
    if [[ "$i" -gt 0 ]]; then
      printf '\n\n' >> "$_TRUNCATED"
      REMAINING=$((REMAINING - 2))
    fi

    if [[ "$SECTION_LINES" -le "$REMAINING" ]]; then
      cat "${SECTION_FILES[$i]}" >> "$_TRUNCATED"
      REMAINING=$((REMAINING - SECTION_LINES))
    else
      # Partial inclusion of this section
      head -n "$((REMAINING - 1))" "${SECTION_FILES[$i]}" >> "$_TRUNCATED"
      printf '[TRUNCATED: %s section exceeded %d line budget]\n' "${SECTION_NAMES[$i]}" "$MAX_LINES" >> "$_TRUNCATED"
      REMAINING=0
    fi
  done

  cat "$_TRUNCATED"
else
  cat "$_OUTPUT"
fi
