#!/bin/bash
# update-scores.sh — Update agent performance scores after a session completes
#
# Usage: bash scripts/update-scores.sh <state-file> <session-outcome>
#   state-file: path to the session's state.yaml
#   session-outcome: "pass" or "fail"
#
# Reads agent_status from the state file, updates rolling metrics in
# learning/agent-scores.yaml for each agent that was dispatched.
# The session-outcome parameter determines whether overall session success
# is factored into per-agent scoring when individual agent status is ambiguous.
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
# Pass state file path via argv, not interpolation
DISPATCHED_AGENTS=$(python3 -c "
import yaml, sys
state_file = sys.argv[1]
with open(state_file) as f:
    state = yaml.safe_load(f)
agent_status = state.get('agent_status', {})
for agent, status in agent_status.items():
    if status not in ('pending', ''):
        print(f'{agent}|{status}')
" "$STATE_FILE" 2>/dev/null || echo "")

if [[ -z "$DISPATCHED_AGENTS" ]]; then
  echo "No dispatched agents found in state file"
  exit 0
fi

# Count dispatched agents for per-agent token share calculation
DISPATCHED_COUNT=$(echo "$DISPATCHED_AGENTS" | grep -c '|' || echo "1")

UPDATED=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  AGENT=$(echo "$line" | cut -d'|' -f1)
  STATUS=$(echo "$line" | cut -d'|' -f2)

  # Determine if this agent succeeded
  # Individual agent status takes priority; session outcome is fallback for ambiguous states
  AGENT_SUCCESS=0
  if [[ "$STATUS" == "done" || "$STATUS" == "pass" || "$STATUS" == "success" ]]; then
    AGENT_SUCCESS=1
  elif [[ "$STATUS" == "dispatched" || "$STATUS" == "unknown" ]]; then
    # Ambiguous status: use session-level outcome as fallback
    if [[ "$OUTCOME" == "pass" ]]; then
      AGENT_SUCCESS=1
    fi
  fi

  # Determine model used
  MODEL="$BUILDER_MODEL"
  if [[ "$MODEL" == "inherit" ]]; then
    MODEL="sonnet"
  fi

  # Update scores — pass all variable data via command-line args
  python3 -c "
import yaml, sys

scores_file = sys.argv[1]
agent_name = sys.argv[2]
agent_success = int(sys.argv[3])
cycle = int(sys.argv[4])
total_tokens = int(sys.argv[5])
dispatched_count = max(int(sys.argv[6]), 1)
model = sys.argv[7]

with open(scores_file) as f:
    data = yaml.safe_load(f)

agents = data.get('agents', {})
if agent_name not in agents:
    agents[agent_name] = {
        'sessions_completed': 0,
        'success_rate': 0.0,
        'avg_cycles_to_pass': 0,
        'avg_tokens': 0,
        'strengths': [],
        'weaknesses': [],
        'model_history': []
    }

a = agents[agent_name]
old_count = a.get('sessions_completed', 0)
new_count = old_count + 1
a['sessions_completed'] = new_count

# Rolling average for success rate
old_rate = a.get('success_rate', 0.0)
a['success_rate'] = round(((old_rate * old_count) + agent_success) / new_count, 3)

# Rolling average for cycles
old_cycles = a.get('avg_cycles_to_pass', 0)
a['avg_cycles_to_pass'] = round(((old_cycles * old_count) + cycle) / new_count, 1)

# Rolling average for tokens (approximate per-agent share)
per_agent_tokens = total_tokens // dispatched_count
old_tokens = a.get('avg_tokens', 0)
a['avg_tokens'] = int(((old_tokens * old_count) + per_agent_tokens) / new_count)

# Update model history
model_history = a.get('model_history', [])
found = False
for mh in model_history:
    if mh.get('model') == model:
        old_mh_count = mh.get('sessions', 0)
        new_mh_count = old_mh_count + 1
        mh['sessions'] = new_mh_count
        old_mh_rate = mh.get('success_rate', 0.0)
        mh['success_rate'] = round(((old_mh_rate * old_mh_count) + agent_success) / new_mh_count, 3)
        found = True
        break
if not found:
    model_history.append({
        'model': model,
        'sessions': 1,
        'success_rate': float(agent_success)
    })
a['model_history'] = model_history

agents[agent_name] = a
data['agents'] = agents

with open(scores_file, 'w') as f:
    yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
" "$SCORES_FILE" "$AGENT" "$AGENT_SUCCESS" "$CYCLE" "$TOKENS" "$DISPATCHED_COUNT" "$MODEL" 2>/dev/null

  UPDATED=$((UPDATED + 1))
done <<< "$DISPATCHED_AGENTS"

echo "Agent scores updated: $UPDATED agents from session (outcome=$OUTCOME, cycle=$CYCLE)"
