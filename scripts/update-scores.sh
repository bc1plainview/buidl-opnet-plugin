#!/bin/bash
# update-scores.sh — Update agent performance scores after a session completes
#
# Usage: bash scripts/update-scores.sh <state-file> <session-outcome>
#   state-file: path to the session's state.yaml
#   session-outcome: "pass" or "fail"
#
# Reads agent_status from the state file, updates rolling metrics in
# learning/agent-scores.yaml for each agent that was dispatched.
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCORES_FILE="$SCRIPT_DIR/learning/agent-scores.yaml"
STATE_FILE="${1:-}"
OUTCOME="${2:-}"

if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  echo "Usage: bash scripts/update-scores.sh <state-file> <pass|fail>" >&2
  exit 1
fi

if [[ "$OUTCOME" != "pass" && "$OUTCOME" != "fail" ]]; then
  echo "Error: outcome must be 'pass' or 'fail'" >&2
  exit 1
fi

if [[ ! -f "$SCORES_FILE" ]]; then
  echo "Error: agent-scores.yaml not found at $SCORES_FILE" >&2
  exit 1
fi

# Extract relevant fields from state
CYCLE=$(grep '^cycle:' "$STATE_FILE" | head -1 | awk '{print $2}' || echo "1")
TOKENS=$(grep '^tokens_used:' "$STATE_FILE" | head -1 | awk '{print $2}' || echo "0")
BUILDER_MODEL=$(grep '^builder_model:' "$STATE_FILE" | head -1 | awk '{print $2}' || echo "sonnet")

# Parse agent_status block to find which agents were dispatched
# Format in state.yaml:
#   agent_status:
#     opnet-contract-dev: done
#     opnet-frontend-dev: done
#     opnet-auditor: done
DISPATCHED_AGENTS=$(python3 -c "
import yaml
with open('$STATE_FILE') as f:
    state = yaml.safe_load(f)
agent_status = state.get('agent_status', {})
for agent, status in agent_status.items():
    if status not in ('pending', ''):
        print(f'{agent}|{status}')
" 2>/dev/null || echo "")

if [[ -z "$DISPATCHED_AGENTS" ]]; then
  echo "No dispatched agents found in state file"
  exit 0
fi

UPDATED=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  AGENT=$(echo "$line" | cut -d'|' -f1)
  STATUS=$(echo "$line" | cut -d'|' -f2)

  # Determine if this agent succeeded (done/pass) or failed
  AGENT_SUCCESS=0
  if [[ "$STATUS" == "done" || "$STATUS" == "pass" || "$STATUS" == "success" ]]; then
    AGENT_SUCCESS=1
  fi

  # Determine model used
  MODEL="$BUILDER_MODEL"
  if [[ "$MODEL" == "inherit" ]]; then
    MODEL="sonnet"
  fi

  # Update scores
  python3 -c "
import yaml

with open('$SCORES_FILE') as f:
    data = yaml.safe_load(f)

agents = data.get('agents', {})
if '$AGENT' not in agents:
    agents['$AGENT'] = {
        'sessions_completed': 0,
        'success_rate': 0.0,
        'avg_cycles_to_pass': 0,
        'avg_tokens': 0,
        'strengths': [],
        'weaknesses': [],
        'model_history': []
    }

a = agents['$AGENT']
old_count = a.get('sessions_completed', 0)
new_count = old_count + 1
a['sessions_completed'] = new_count

# Rolling average for success rate
old_rate = a.get('success_rate', 0.0)
a['success_rate'] = round(((old_rate * old_count) + $AGENT_SUCCESS) / new_count, 3)

# Rolling average for cycles
old_cycles = a.get('avg_cycles_to_pass', 0)
a['avg_cycles_to_pass'] = round(((old_cycles * old_count) + $CYCLE) / new_count, 1)

# Rolling average for tokens (approximate per-agent share)
total_tokens = $TOKENS
dispatched_count = len([l for l in '''$DISPATCHED_AGENTS'''.strip().split(chr(10)) if l])
per_agent_tokens = total_tokens // max(dispatched_count, 1)
old_tokens = a.get('avg_tokens', 0)
a['avg_tokens'] = int(((old_tokens * old_count) + per_agent_tokens) / new_count)

# Update model history
model = '$MODEL'
model_history = a.get('model_history', [])
found = False
for mh in model_history:
    if mh.get('model') == model:
        old_mh_count = mh.get('sessions', 0)
        new_mh_count = old_mh_count + 1
        mh['sessions'] = new_mh_count
        old_mh_rate = mh.get('success_rate', 0.0)
        mh['success_rate'] = round(((old_mh_rate * old_mh_count) + $AGENT_SUCCESS) / new_mh_count, 3)
        found = True
        break
if not found:
    model_history.append({
        'model': model,
        'sessions': 1,
        'success_rate': float($AGENT_SUCCESS)
    })
a['model_history'] = model_history

agents['$AGENT'] = a
data['agents'] = agents

with open('$SCORES_FILE', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" 2>/dev/null

  UPDATED=$((UPDATED + 1))
done <<< "$DISPATCHED_AGENTS"

echo "Agent scores updated: $UPDATED agents from session (outcome=$OUTCOME, cycle=$CYCLE)"
