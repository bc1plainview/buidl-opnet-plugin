#!/bin/bash
# query-pattern.sh — Query patterns.yaml for patterns matching a failure category
#
# Usage: bash scripts/query-pattern.sh <category> [keywords...]
#
# Returns: pattern_id|description|fix (pipe-delimited, like route-finding.sh)
# Exit 0 if match found, exit 1 if no match
#
# Categories: contract, frontend, backend, deployment, testing
# Keywords narrow the search within the category.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/learning/patterns.yaml"

CATEGORY="${1:-}"

if [[ -z "$CATEGORY" ]]; then
  echo "Usage: bash scripts/query-pattern.sh <category> [keywords...]" >&2
  exit 1
fi

# Guard: patterns.yaml may not exist
if [[ ! -f "$PATTERNS_FILE" ]]; then
  exit 1
fi

# Collect optional keywords
shift
KEYWORDS=()
if [[ $# -gt 0 ]]; then
  KEYWORDS=("$@")
fi

# Query patterns via Python (safe argv, no interpolation)
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
    # Match on category or domain
    if category.lower() not in p_category.lower() and category.lower() not in p_domain.lower():
        continue

    # If keywords provided, check description and fix for keyword matches
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
" "$PATTERNS_FILE" "$CATEGORY" ${KEYWORDS[@]+"${KEYWORDS[@]}"} 2>/dev/null

exit $?
