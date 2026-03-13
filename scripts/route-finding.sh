#!/bin/bash
# route-finding.sh — Route a reviewer/auditor finding to the best agent based on historical scores
#
# Usage: bash scripts/route-finding.sh <finding-description> <candidate-agents>
#   finding-description: text description of the finding (e.g., "CSS layout broken in token card")
#   candidate-agents: comma-separated list (e.g., "opnet-contract-dev,opnet-frontend-dev,opnet-backend-dev")
#
# Reads agent-scores.yaml, matches finding keywords against category taxonomy,
# checks each candidate's strengths/weaknesses for that category.
# Returns: agent_name|confidence|reasoning
#
# Falls back to keyword routing when no agent has 5+ sessions.
#
# Exit codes:
#   0 — Success (outputs routing decision)
#   1 — Missing arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCORES_FILE="$SCRIPT_DIR/learning/agent-scores.yaml"
FINDING="${1:-}"
CANDIDATES="${2:-}"

if [[ -z "$FINDING" || -z "$CANDIDATES" ]]; then
  echo "Usage: bash scripts/route-finding.sh <finding-description> <candidate-agents>" >&2
  exit 1
fi

# If scores file doesn't exist, fall back to keyword routing
if [[ ! -f "$SCORES_FILE" ]]; then
  echo "FALLBACK: No agent-scores.yaml found" >&2
  # Keyword fallback
  FINDING_LOWER=$(echo "$FINDING" | tr '[:upper:]' '[:lower:]')
  FIRST_CANDIDATE=$(echo "$CANDIDATES" | cut -d',' -f1)
  if echo "$FINDING_LOWER" | grep -qiE "css|style|layout|color|font|responsive|animation|ui|render|display|dark.?mode|glass"; then
    echo "opnet-frontend-dev|0.5|keyword-match:css-styling"
  elif echo "$FINDING_LOWER" | grep -qiE "contract|storage|selector|event|mint|burn|transfer|allowance|op-?20|op-?721|wasm|assembly"; then
    echo "opnet-contract-dev|0.5|keyword-match:contract-logic"
  elif echo "$FINDING_LOWER" | grep -qiE "api|server|websocket|database|rate.?limit|express|mongo|endpoint|cors"; then
    echo "opnet-backend-dev|0.5|keyword-match:backend-api"
  elif echo "$FINDING_LOWER" | grep -qiE "deploy|gas|utxo|broadcast|transaction.?factory"; then
    echo "opnet-deployer|0.5|keyword-match:deployment"
  elif echo "$FINDING_LOWER" | grep -qiE "test|e2e|playwright|smoke|assertion"; then
    echo "opnet-e2e-tester|0.5|keyword-match:testing"
  elif echo "$FINDING_LOWER" | grep -qiE "wallet|signer|connect|provider|network|rpc"; then
    echo "opnet-frontend-dev|0.5|keyword-match:wallet-connect"
  elif echo "$FINDING_LOWER" | grep -qiE "abi|mismatch|parameter|type.?error|interface"; then
    echo "cross-layer-validator|0.5|keyword-match:abi-mismatch"
  elif echo "$FINDING_LOWER" | grep -qiE "security|injection|overflow|reentrancy|private.?key|leak"; then
    echo "opnet-auditor|0.5|keyword-match:security"
  else
    echo "$FIRST_CANDIDATE|0.3|keyword-match:default"
  fi
  exit 0
fi

# ─── Category Taxonomy ───
# Each category has keywords that match finding descriptions.
# Categories are used to match against agent strengths/weaknesses.
CATEGORIES=(
  "css-styling:css|style|layout|color|font|responsive|animation|ui|render|display|dark.?mode|glass"
  "wallet-connect:wallet|signer|connect|provider|mldsaSigner|signing"
  "contract-logic:contract|storage|selector|event|mint|burn|transfer|allowance|op.?20|op.?721|wasm|assembly"
  "abi-mismatch:abi|mismatch|parameter|type.?error|interface|method.?not.?found"
  "network-config:network|rpc|testnet|mainnet|opnetTestnet|provider.?url"
  "deployment:deploy|gas|utxo|broadcast|transaction.?factory"
  "testing:test|e2e|playwright|smoke|assertion|coverage"
  "security:security|injection|overflow|reentrancy|private.?key|leak|exploit|vulnerability"
  "build-errors:build|compile|lint|typecheck|tsc|eslint|vite"
  "backend-api:api|websocket|database|rate.?limit|express|mongo|endpoint|cors|server"
)

# Detect the finding's category
FINDING_LOWER=$(echo "$FINDING" | tr '[:upper:]' '[:lower:]')
MATCHED_CATEGORY=""
BEST_MATCH_COUNT=0

for cat_entry in "${CATEGORIES[@]}"; do
  CAT_NAME="${cat_entry%%:*}"
  CAT_KEYWORDS="${cat_entry#*:}"

  # Count keyword matches
  MATCH_COUNT=0
  IFS='|' read -ra KW_ARRAY <<< "$CAT_KEYWORDS"
  for kw in "${KW_ARRAY[@]}"; do
    if echo "$FINDING_LOWER" | grep -qiE "$kw"; then
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done

  if [[ "$MATCH_COUNT" -gt "$BEST_MATCH_COUNT" ]]; then
    BEST_MATCH_COUNT=$MATCH_COUNT
    MATCHED_CATEGORY="$CAT_NAME"
  fi
done

if [[ -z "$MATCHED_CATEGORY" ]]; then
  MATCHED_CATEGORY="general"
fi

# Score-based routing: check agent strengths/weaknesses for the matched category
# Pass finding, candidates, matched category, and scores file to Python via argv
RESULT=$(python3 -c "
import yaml, sys

scores_file = sys.argv[1]
candidates_str = sys.argv[2]
matched_category = sys.argv[3]
min_sessions = 5
confidence_threshold = 0.6

with open(scores_file) as f:
    data = yaml.safe_load(f)

agents = data.get('agents', {})
candidates = [c.strip() for c in candidates_str.split(',')]

# Check if any candidate has enough data for score-based routing
has_scored_agents = False
best_agent = None
best_score = -1.0
best_reason = ''

for agent_name in candidates:
    agent = agents.get(agent_name, {})
    sessions = agent.get('sessions_completed', 0)

    if sessions < min_sessions:
        continue

    has_scored_agents = True
    strengths = agent.get('strengths', [])
    weaknesses = agent.get('weaknesses', [])
    success_rate = agent.get('success_rate', 0.0)

    # Calculate category-specific score
    score = success_rate  # base score is overall success rate

    # Boost if category is in strengths
    for s in strengths:
        if matched_category in s or s in matched_category:
            score += 0.2
            break

    # Penalize if category is in weaknesses
    for w in weaknesses:
        if matched_category in w or w in matched_category:
            score -= 0.3
            break

    if score > best_score:
        best_score = score
        best_agent = agent_name
        if matched_category in [s for s in strengths]:
            best_reason = f'score-based:strength-match:{matched_category}'
        elif matched_category in [w for w in weaknesses]:
            best_reason = f'score-based:despite-weakness:{matched_category}'
        else:
            best_reason = f'score-based:highest-overall:{matched_category}'

if has_scored_agents and best_agent and best_score >= confidence_threshold:
    confidence = min(round(best_score, 2), 1.0)
    print(f'{best_agent}|{confidence}|{best_reason}')
else:
    # Not enough data — signal fallback
    print('FALLBACK')
" "$SCORES_FILE" "$CANDIDATES" "$MATCHED_CATEGORY" 2>/dev/null || echo "FALLBACK")

if [[ "$RESULT" == "FALLBACK" ]]; then
  # Keyword-based fallback using the matched category
  FIRST_CANDIDATE=$(echo "$CANDIDATES" | cut -d',' -f1)
  case "$MATCHED_CATEGORY" in
    css-styling|wallet-connect)
      echo "opnet-frontend-dev|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    contract-logic)
      echo "opnet-contract-dev|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    backend-api)
      echo "opnet-backend-dev|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    abi-mismatch)
      # Could be frontend or contract — route to frontend first (more likely caller error)
      echo "opnet-frontend-dev|0.4|keyword-fallback:$MATCHED_CATEGORY" ;;
    network-config)
      echo "opnet-frontend-dev|0.4|keyword-fallback:$MATCHED_CATEGORY" ;;
    deployment)
      echo "opnet-deployer|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    testing)
      echo "opnet-e2e-tester|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    security)
      echo "opnet-auditor|0.5|keyword-fallback:$MATCHED_CATEGORY" ;;
    build-errors)
      echo "$FIRST_CANDIDATE|0.4|keyword-fallback:$MATCHED_CATEGORY" ;;
    *)
      echo "$FIRST_CANDIDATE|0.3|keyword-fallback:general" ;;
  esac
else
  echo "$RESULT"
fi
