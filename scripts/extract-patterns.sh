#!/bin/bash
# extract-patterns.sh — Extract patterns from a session retrospective into the pattern store
#
# Usage: bash scripts/extract-patterns.sh <retrospective-file>
#
# Reads the retrospective markdown, extracts "Anti-Patterns" and "What Failed"
# sections, and appends structured patterns to learning/patterns.yaml.
# Deduplicates by description similarity. Auto-promotes patterns with 3+ occurrences
# to the relevant knowledge slice with a [LEARNED] tag.
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/learning/patterns.yaml"
RETRO_FILE="${1:-}"

if [[ -z "$RETRO_FILE" || ! -f "$RETRO_FILE" ]]; then
  echo "Usage: bash scripts/extract-patterns.sh <retrospective-file>" >&2
  exit 1
fi

# Ensure patterns file exists
if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "Error: patterns.yaml not found at $PATTERNS_FILE" >&2
  exit 1
fi

# Extract session name from retrospective
SESSION_NAME=$(grep '^# Retrospective:' "$RETRO_FILE" | head -1 | sed 's/^# Retrospective: //' || echo "unknown")
PROJECT_TYPE=$(grep '^Project Type:' "$RETRO_FILE" | head -1 | awk '{print $3}' || echo "generic")
TODAY=$(date '+%Y-%m-%d')

# Extract anti-patterns section (between "## Anti-Patterns" and next "##")
ANTI_PATTERNS=$(sed -n '/^## Anti-Patterns/,/^## /{/^## Anti-Patterns/d;/^## /d;p}' "$RETRO_FILE" | grep '^- ' | sed 's/^- //')

# Extract what-failed section
WHAT_FAILED=$(sed -n '/^## What Failed/,/^## /{/^## What Failed/d;/^## /d;p}' "$RETRO_FILE" | grep '^- ' | sed 's/^- //')

# Combine both sections
ALL_PATTERNS="$ANTI_PATTERNS"
if [[ -n "$WHAT_FAILED" ]]; then
  ALL_PATTERNS="$ALL_PATTERNS"$'\n'"$WHAT_FAILED"
fi

# Skip if no patterns found
if [[ -z "$ALL_PATTERNS" ]]; then
  echo "No patterns found in $RETRO_FILE"
  exit 0
fi

# Get current max pattern ID
MAX_ID=$(grep 'id: PAT-L' "$PATTERNS_FILE" | tail -1 | sed 's/.*PAT-L0*//' | sed 's/[^0-9].*//' || echo "0")
if [[ -z "$MAX_ID" || "$MAX_ID" == "0" ]]; then
  MAX_ID=0
fi

# Process each pattern
ADDED=0
UPDATED=0

while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue

  # Normalize for comparison (lowercase, strip punctuation)
  NORMALIZED=$(echo "$pattern" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | xargs)

  # Check for existing similar pattern (first 40 chars match)
  MATCH_KEY=$(echo "$NORMALIZED" | cut -c1-40)

  # Search existing patterns for a match
  EXISTING_LINE=$(python3 -c "
import yaml, sys
with open('$PATTERNS_FILE') as f:
    data = yaml.safe_load(f)
patterns = data.get('patterns', []) if data else []
if not patterns:
    patterns = []
match_key = '''$MATCH_KEY'''
for i, p in enumerate(patterns):
    desc = p.get('description', '').lower()
    # Remove punctuation for comparison
    desc_clean = ''.join(c for c in desc if c.isalnum() or c == ' ')
    if match_key[:30] in desc_clean[:50] or desc_clean[:30] in match_key[:50]:
        print(f'{i}|{p.get(\"id\", \"\")}|{p.get(\"occurrence_count\", 1)}')
        break
" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_LINE" ]]; then
    # Update existing pattern: increment count, add session
    IDX=$(echo "$EXISTING_LINE" | cut -d'|' -f1)
    PAT_ID=$(echo "$EXISTING_LINE" | cut -d'|' -f2)
    OLD_COUNT=$(echo "$EXISTING_LINE" | cut -d'|' -f3)
    NEW_COUNT=$((OLD_COUNT + 1))

    python3 -c "
import yaml
with open('$PATTERNS_FILE') as f:
    data = yaml.safe_load(f)
patterns = data.get('patterns', [])
idx = $IDX
patterns[idx]['occurrence_count'] = $NEW_COUNT
patterns[idx]['last_seen'] = '$TODAY'
sessions = patterns[idx].get('source_sessions', [])
if '$SESSION_NAME' not in sessions:
    sessions.append('$SESSION_NAME')
    patterns[idx]['source_sessions'] = sessions
if $NEW_COUNT >= 3:
    patterns[idx]['promoted_to_knowledge'] = True
data['patterns'] = patterns
with open('$PATTERNS_FILE', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" 2>/dev/null

    UPDATED=$((UPDATED + 1))

    # Auto-promote if count >= 3
    if [[ "$NEW_COUNT" -ge 3 ]]; then
      echo "  PROMOTED: $PAT_ID (count=$NEW_COUNT) — eligible for knowledge slice update"
    fi
  else
    # Add new pattern
    MAX_ID=$((MAX_ID + 1))
    PAT_ID=$(printf "PAT-L%03d" "$MAX_ID")

    # Detect category from content
    CATEGORY="orchestration"
    if echo "$pattern" | grep -qi "frontend\|react\|vite\|css\|ui\|wallet"; then
      CATEGORY="frontend"
    elif echo "$pattern" | grep -qi "contract\|wasm\|assembly\|storage\|op-20\|op20"; then
      CATEGORY="contract"
    elif echo "$pattern" | grep -qi "backend\|api\|server\|express\|mongo"; then
      CATEGORY="backend"
    elif echo "$pattern" | grep -qi "deploy\|gas\|transaction\|testnet"; then
      CATEGORY="deployment"
    elif echo "$pattern" | grep -qi "test\|e2e\|playwright\|smoke"; then
      CATEGORY="testing"
    fi

    # Detect failure type
    FAILURE_TYPE="process"
    if echo "$pattern" | grep -qi "runtime\|crash\|console error"; then
      FAILURE_TYPE="runtime_error"
    elif echo "$pattern" | grep -qi "build\|compile\|lint"; then
      FAILURE_TYPE="build_error"
    elif echo "$pattern" | grep -qi "type\|typescript\|interface"; then
      FAILURE_TYPE="type_error"
    elif echo "$pattern" | grep -qi "security\|leak\|private key\|exploit"; then
      FAILURE_TYPE="security"
    elif echo "$pattern" | grep -qi "config\|env\|network\|port"; then
      FAILURE_TYPE="config"
    elif echo "$pattern" | grep -qi "logic\|bug\|incorrect\|wrong"; then
      FAILURE_TYPE="logic"
    fi

    python3 -c "
import yaml
with open('$PATTERNS_FILE') as f:
    data = yaml.safe_load(f)
if not data:
    data = {'patterns': []}
patterns = data.get('patterns', [])
if patterns is None:
    patterns = []
patterns.append({
    'id': '$PAT_ID',
    'category': '$CATEGORY',
    'tech_stack': ['$PROJECT_TYPE'],
    'failure_type': '$FAILURE_TYPE',
    'description': '''$(echo "$pattern" | sed "s/'/\\\\'/g")''',
    'fix': '',
    'source_sessions': ['$SESSION_NAME'],
    'occurrence_count': 1,
    'promoted_to_knowledge': False,
    'first_seen': '$TODAY',
    'last_seen': '$TODAY'
})
data['patterns'] = patterns
with open('$PATTERNS_FILE', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" 2>/dev/null

    ADDED=$((ADDED + 1))
  fi
done <<< "$ALL_PATTERNS"

echo "Pattern extraction complete: $ADDED added, $UPDATED updated from $SESSION_NAME"
