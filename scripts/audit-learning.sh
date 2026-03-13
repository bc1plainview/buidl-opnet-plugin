#!/bin/bash
# audit-learning.sh — Print a health report of the learning system
#
# Usage: bash scripts/audit-learning.sh
#
# Reports:
# - Pattern count (total, stale, active, promoted)
# - Agent scores summary (sessions, success rates)
# - Profile count and types
# - Prune log summary (if exists)
#
# Exit codes:
#   0 — Success

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/learning/patterns.yaml"
SCORES_FILE="$SCRIPT_DIR/learning/agent-scores.yaml"
PROFILES_DIR="$SCRIPT_DIR/learning/profiles"
PRUNE_LOG="$SCRIPT_DIR/learning/prune-log.yaml"

echo "Learning System Health Report"
echo "============================="
echo ""

# 1. Patterns
echo "--- Patterns ---"
if [[ -f "$PATTERNS_FILE" ]]; then
  python3 -c "
import yaml, sys

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

patterns = data.get('patterns', []) if data else []
total = len(patterns)
stale = sum(1 for p in patterns if p.get('stale', False))
active = total - stale
promoted = sum(1 for p in patterns if p.get('promoted_to_knowledge', False))
high_freq = sum(1 for p in patterns if p.get('occurrence_count', 0) >= 3)

print(f'Total patterns:    {total}')
print(f'Active:            {active}')
print(f'Stale:             {stale}')
print(f'Promoted:          {promoted}')
print(f'High frequency:    {high_freq} (3+ occurrences)')

if patterns:
    categories = {}
    for p in patterns:
        cat = p.get('category', 'unknown')
        categories[cat] = categories.get(cat, 0) + 1
    print(f'Categories:        {dict(sorted(categories.items()))}')
" "$PATTERNS_FILE" 2>/dev/null
else
  echo "patterns.yaml: NOT FOUND"
fi
echo ""

# 2. Agent Scores
echo "--- Agent Scores ---"
if [[ -f "$SCORES_FILE" ]]; then
  python3 -c "
import yaml, sys

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

agents = data.get('agents', {}) if data else {}
if not agents:
    print('No agent score data yet.')
    sys.exit(0)

print(f'Agents tracked:    {len(agents)}')
print('')
print(f'{\"Agent\":<30} {\"Sessions\":>8} {\"Success\":>8} {\"Avg Cycles\":>10}')
print('-' * 60)
for name, info in sorted(agents.items()):
    sessions = info.get('sessions_completed', 0)
    rate = info.get('success_rate', 0.0)
    cycles = info.get('avg_cycles_to_pass', 0)
    strengths = len(info.get('strengths', []))
    weaknesses = len(info.get('weaknesses', []))
    print(f'{name:<30} {sessions:>8} {rate:>7.1%} {cycles:>10.1f}')
" "$SCORES_FILE" 2>/dev/null
else
  echo "agent-scores.yaml: NOT FOUND"
fi
echo ""

# 3. Profiles
echo "--- Profiles ---"
if [[ -d "$PROFILES_DIR" ]]; then
  PROFILE_COUNT=$(find "$PROFILES_DIR" -name '*.yaml' -not -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "Profile count:     $PROFILE_COUNT"
  if [[ "$PROFILE_COUNT" -gt 0 ]]; then
    echo "Types:"
    for f in "$PROFILES_DIR"/*.yaml; do
      [[ -f "$f" ]] || continue
      PTYPE=$(basename "$f" .yaml)
      SESSIONS=$(python3 -c "
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
print(d.get('sessions_count', '?'))
" "$f" 2>/dev/null || echo "?")
      echo "  - $PTYPE ($SESSIONS sessions)"
    done
  fi
else
  echo "profiles/ directory: NOT FOUND"
fi
echo ""

# 4. Prune Log
echo "--- Prune Log ---"
if [[ -f "$PRUNE_LOG" ]]; then
  python3 -c "
import yaml, sys

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

entries = data.get('pruned', []) if data else []
print(f'Total pruned:      {len(entries)}')
if entries:
    latest = entries[-1]
    print(f'Latest prune:      {latest.get(\"date\", \"unknown\")} -- {latest.get(\"reason\", \"\")}')
" "$PRUNE_LOG" 2>/dev/null
else
  echo "No prune log yet (learning/prune-log.yaml not found)"
fi
echo ""

echo "============================="
echo "Report generated at: $(date '+%Y-%m-%d %H:%M:%S')"
