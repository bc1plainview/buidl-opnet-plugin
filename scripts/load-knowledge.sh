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
  *)                       BIBLE_TAGS="" ;;
esac

# Collect output sections in order of relevance (most relevant first)
# Section 1: Agent-specific slice (highest relevance)
# Section 2: Troubleshooting guide
# Section 3: Bible sections matching role
# Section 4: Learned patterns

SLICE_CONTENT=""
if [[ -n "$SLICE_FILE" && -f "$SLICE_FILE" ]]; then
  SLICE_CONTENT=$(cat "$SLICE_FILE")
fi

TROUBLESHOOTING_CONTENT=""
TROUBLESHOOTING_FILE="$SCRIPT_DIR/knowledge/opnet-troubleshooting.md"
if [[ -f "$TROUBLESHOOTING_FILE" ]]; then
  TROUBLESHOOTING_CONTENT=$(cat "$TROUBLESHOOTING_FILE")
fi

BIBLE_FILE="$SCRIPT_DIR/knowledge/opnet-bible.md"
BIBLE_CONTENT=""
if [[ -n "$BIBLE_TAGS" && -f "$BIBLE_FILE" ]]; then
  # Extract matching sections from the bible based on tags
  # Each section is delimited by BEGIN-SECTION-N and END-SECTION-N comments
  BIBLE_CONTENT=$(python3 -c "
import sys, re

bible_path = sys.argv[1]
tags = sys.argv[2].split()

with open(bible_path) as f:
    content = f.read()

# Find all section blocks
pattern = r'<!-- BEGIN-SECTION-(\d+)\s+\[([^\]]+(?:\]\s*\[[^\]]+)*)\]\s*-->(.*?)<!-- END-SECTION-\1 -->'
matches = re.findall(pattern, content, re.DOTALL)

output_parts = []
for section_num, tag_str, section_content in matches:
    # Parse tags: [CONTRACT] [FRONTEND] [BACKEND] etc
    section_tags = re.findall(r'\[([A-Z]+)\]', tag_str)
    # Check if any of the agent's tags match
    if any(t in section_tags for t in tags):
        output_parts.append(section_content.strip())

print('\n\n'.join(output_parts))
" "$BIBLE_FILE" "$BIBLE_TAGS" 2>/dev/null || echo "")
fi

# Extract non-stale learned patterns
PATTERNS_FILE="$SCRIPT_DIR/learning/patterns.yaml"
LEARNED_CONTENT=""
if [[ -f "$PATTERNS_FILE" ]]; then
  LEARNED_CONTENT=$(python3 -c "
import yaml, sys

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
" "$PATTERNS_FILE" "$PROJECT_TYPE" 2>/dev/null || echo "")
fi

# Assemble output in relevance order
# Priority: 1=slice, 2=troubleshooting, 3=bible, 4=learned
SECTIONS=()
SECTION_NAMES=()

if [[ -n "$SLICE_CONTENT" ]]; then
  SECTIONS+=("$SLICE_CONTENT")
  SECTION_NAMES+=("agent-slice")
fi

if [[ -n "$TROUBLESHOOTING_CONTENT" ]]; then
  SECTIONS+=("$TROUBLESHOOTING_CONTENT")
  SECTION_NAMES+=("troubleshooting")
fi

if [[ -n "$BIBLE_CONTENT" ]]; then
  SECTIONS+=("$BIBLE_CONTENT")
  SECTION_NAMES+=("bible")
fi

if [[ -n "$LEARNED_CONTENT" ]]; then
  SECTIONS+=("$LEARNED_CONTENT")
  SECTION_NAMES+=("learned-patterns")
fi

# Combine all sections
COMBINED=""
for section in "${SECTIONS[@]}"; do
  if [[ -n "$COMBINED" ]]; then
    COMBINED="$COMBINED"$'\n\n'
  fi
  COMBINED="$COMBINED$section"
done

# Count lines and truncate if needed (remove least-relevant sections first)
# Use printf to avoid echo adding trailing newline, then pipe to wc -l
LINE_COUNT=$(printf '%s\n' "$COMBINED" | wc -l | tr -d ' ')

if [[ "$LINE_COUNT" -gt "$MAX_LINES" ]]; then
  # Truncate from the end (least relevant sections first: learned, bible, troubleshooting)
  # Rebuild from highest relevance until we hit the cap
  COMBINED=""
  REMAINING=$MAX_LINES

  for i in "${!SECTIONS[@]}"; do
    SECTION_LINES=$(printf '%s\n' "${SECTIONS[$i]}" | wc -l | tr -d ' ')
    if [[ "$REMAINING" -le 0 ]]; then
      break
    fi
    if [[ "$SECTION_LINES" -le "$REMAINING" ]]; then
      if [[ -n "$COMBINED" ]]; then
        COMBINED="$COMBINED"$'\n\n'
        REMAINING=$((REMAINING - 2))
      fi
      COMBINED="$COMBINED${SECTIONS[$i]}"
      REMAINING=$((REMAINING - SECTION_LINES))
    else
      # Partial inclusion of this section
      if [[ -n "$COMBINED" ]]; then
        COMBINED="$COMBINED"$'\n\n'
        REMAINING=$((REMAINING - 2))
      fi
      PARTIAL=$(printf '%s\n' "${SECTIONS[$i]}" | head -n "$((REMAINING - 1))")
      COMBINED="$COMBINED$PARTIAL"$'\n'"[TRUNCATED: ${SECTION_NAMES[$i]} section exceeded $MAX_LINES line budget]"
      REMAINING=0
    fi
  done
fi

printf '%s\n' "$COMBINED"
