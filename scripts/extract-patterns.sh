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

# Detect current plugin version from plugin.json
PLUGIN_JSON="$SCRIPT_DIR/.claude-plugin/plugin.json"
CURRENT_VERSION="0.0.0"
if [[ -f "$PLUGIN_JSON" ]]; then
  CURRENT_VERSION=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])" 2>/dev/null || echo "0.0.0")
fi
CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)

# Extract anti-patterns section (between "## Anti-Patterns" and next "##")
# || true prevents pipefail exit when grep finds no matches
ANTI_PATTERNS=$(sed -n '/^## Anti-Patterns/,/^## /{/^## Anti-Patterns/d;/^## /d;p}' "$RETRO_FILE" | grep '^- ' | sed 's/^- //' || true)

# Extract what-failed section
WHAT_FAILED=$(sed -n '/^## What Failed/,/^## /{/^## What Failed/d;/^## /d;p}' "$RETRO_FILE" | grep '^- ' | sed 's/^- //' || true)

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

  # Search existing patterns for a match — pass all data via stdin, not interpolation
  EXISTING_LINE=$(echo "$MATCH_KEY" | python3 -c "
import yaml, sys
match_key = sys.stdin.read().strip()
patterns_file = sys.argv[1]
with open(patterns_file) as f:
    data = yaml.safe_load(f)
patterns = data.get('patterns', []) if data else []
if not patterns:
    patterns = []
for i, p in enumerate(patterns):
    desc = p.get('description', '').lower()
    desc_clean = ''.join(c for c in desc if c.isalnum() or c == ' ')
    if match_key[:30] in desc_clean[:50] or desc_clean[:30] in match_key[:50]:
        print(f'{i}|{p.get(\"id\", \"\")}|{p.get(\"occurrence_count\", 1)}')
        break
" "$PATTERNS_FILE" 2>/dev/null || echo "")

  if [[ -n "$EXISTING_LINE" ]]; then
    # Update existing pattern: increment count, add session
    IDX=$(echo "$EXISTING_LINE" | cut -d'|' -f1)
    PAT_ID=$(echo "$EXISTING_LINE" | cut -d'|' -f2)
    OLD_COUNT=$(echo "$EXISTING_LINE" | cut -d'|' -f3)
    NEW_COUNT=$((OLD_COUNT + 1))

    # Pass all variable data via command-line args, not string interpolation
    python3 -c "
import yaml, sys
patterns_file = sys.argv[1]
idx = int(sys.argv[2])
new_count = int(sys.argv[3])
today = sys.argv[4]
session_name = sys.argv[5]
version = sys.argv[6]
current_major = int(sys.argv[7])

with open(patterns_file) as f:
    data = yaml.safe_load(f)
patterns = data.get('patterns', [])
patterns[idx]['occurrence_count'] = new_count
patterns[idx]['last_seen'] = today
patterns[idx]['last_seen_version'] = version

# Compute stale flag based on major version comparison
pat_version = patterns[idx].get('last_seen_version', version)
pat_major = int(pat_version.split('.')[0]) if pat_version else 0
patterns[idx]['stale'] = (current_major - pat_major) >= 2

sessions = patterns[idx].get('source_sessions', [])
if session_name not in sessions:
    sessions.append(session_name)
    patterns[idx]['source_sessions'] = sessions
if new_count >= 3:
    patterns[idx]['promoted_to_knowledge'] = True
data['patterns'] = patterns
with open(patterns_file, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" "$PATTERNS_FILE" "$IDX" "$NEW_COUNT" "$TODAY" "$SESSION_NAME" "$CURRENT_VERSION" "$CURRENT_MAJOR" 2>/dev/null

    UPDATED=$((UPDATED + 1))

    # Auto-promote if count >= 3: append to relevant knowledge slice with [LEARNED] tag
    if [[ "$NEW_COUNT" -ge 3 ]]; then
      # Read category from the existing pattern to map to the right knowledge slice
      SLICE_FILE=""
      CATEGORY_FOR_SLICE=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for p in data.get('patterns', []):
    if p.get('id') == sys.argv[2]:
        print(p.get('category', 'orchestration'))
        break
" "$PATTERNS_FILE" "$PAT_ID" 2>/dev/null || echo "orchestration")
      case "$CATEGORY_FOR_SLICE" in
        frontend)   SLICE_FILE="$SCRIPT_DIR/knowledge/slices/frontend-dev.md" ;;
        contract)   SLICE_FILE="$SCRIPT_DIR/knowledge/slices/contract-dev.md" ;;
        backend)    SLICE_FILE="$SCRIPT_DIR/knowledge/slices/backend-dev.md" ;;
        deployment) SLICE_FILE="$SCRIPT_DIR/knowledge/slices/deployment.md" ;;
        testing)    SLICE_FILE="$SCRIPT_DIR/knowledge/slices/e2e-testing.md" ;;
        *)          SLICE_FILE="$SCRIPT_DIR/knowledge/slices/integration-review.md" ;;
      esac

      if [[ -f "$SLICE_FILE" ]]; then
        # Check if this pattern is already in the slice
        if ! grep -q "$PAT_ID" "$SLICE_FILE" 2>/dev/null; then
          printf '\n## [LEARNED] %s\n\n%s\n' "$PAT_ID" "$pattern" >> "$SLICE_FILE"
          echo "  PROMOTED: $PAT_ID (count=$NEW_COUNT) — appended to $(basename "$SLICE_FILE")"
        else
          echo "  PROMOTED: $PAT_ID (count=$NEW_COUNT) — already in $(basename "$SLICE_FILE")"
        fi
      else
        echo "  PROMOTED: $PAT_ID (count=$NEW_COUNT) — no slice file found for category"
      fi
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

    # Pass all variable data via stdin JSON + command-line args
    printf '%s' "$pattern" | python3 -c "
import yaml, sys, json

patterns_file = sys.argv[1]
pat_id = sys.argv[2]
category = sys.argv[3]
project_type = sys.argv[4]
failure_type = sys.argv[5]
session_name = sys.argv[6]
today = sys.argv[7]
version = sys.argv[8]
description = sys.stdin.read()

with open(patterns_file) as f:
    data = yaml.safe_load(f)
if not data:
    data = {'patterns': []}
patterns = data.get('patterns', [])
if patterns is None:
    patterns = []
patterns.append({
    'id': pat_id,
    'category': category,
    'tech_stack': [project_type],
    'failure_type': failure_type,
    'description': description,
    'fix': '',
    'source_sessions': [session_name],
    'occurrence_count': 1,
    'promoted_to_knowledge': False,
    'first_seen': today,
    'last_seen': today,
    'last_seen_version': version,
    'stale': False
})
data['patterns'] = patterns
with open(patterns_file, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" "$PATTERNS_FILE" "$PAT_ID" "$CATEGORY" "$PROJECT_TYPE" "$FAILURE_TYPE" "$SESSION_NAME" "$TODAY" "$CURRENT_VERSION" 2>/dev/null

    ADDED=$((ADDED + 1))
  fi
done <<< "$ALL_PATTERNS"

# Prune if pattern count exceeds 200 (remove lowest-frequency + oldest)
python3 -c "
import yaml, sys

patterns_file = sys.argv[1]
max_patterns = 200

with open(patterns_file) as f:
    data = yaml.safe_load(f)
patterns = data.get('patterns', [])
if not patterns or len(patterns) <= max_patterns:
    sys.exit(0)

# Sort by occurrence_count (ascending), then last_seen (ascending) — prune from bottom
patterns.sort(key=lambda p: (p.get('occurrence_count', 0), p.get('last_seen', '')))
pruned = len(patterns) - max_patterns
patterns = patterns[pruned:]
data['patterns'] = patterns

with open(patterns_file, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
print(f'Pruned {pruned} low-frequency patterns (cap: {max_patterns})')
" "$PATTERNS_FILE"

echo "Pattern extraction complete: $ADDED added, $UPDATED updated from $SESSION_NAME"
