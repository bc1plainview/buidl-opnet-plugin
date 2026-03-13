#!/bin/bash
# generate-profiles.sh — Generate project-type profiles from accumulated session data
#
# Usage: bash scripts/generate-profiles.sh
#
# Scans learning/*.md retrospectives for project types, counts sessions per type,
# and generates/updates profile YAML files when session count >= threshold.
#
# Profiles are written to learning/profiles/<type>.yaml.
# Regenerated (not appended) at thresholds: 5, 10, 20, 50.
#
# Exit codes:
#   0 — Success
#   1 — Missing learning directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LEARNING_DIR="$SCRIPT_DIR/learning"
PROFILES_DIR="$LEARNING_DIR/profiles"
PATTERNS_FILE="$LEARNING_DIR/patterns.yaml"
SCORES_FILE="$LEARNING_DIR/agent-scores.yaml"

if [[ ! -d "$LEARNING_DIR" ]]; then
  echo "Error: learning directory not found at $LEARNING_DIR" >&2
  exit 1
fi

mkdir -p "$PROFILES_DIR"

# Scan retrospectives for project types and count sessions per type
# Retrospective format has "Project Type: <type>" on a line
RETRO_FILES=$(find "$LEARNING_DIR" -maxdepth 1 -name "*.md" -not -name "README.md" 2>/dev/null || true)

if [[ -z "$RETRO_FILES" ]]; then
  echo "No retrospectives found in $LEARNING_DIR"
  exit 0
fi

# Count sessions per project type
# Also collect session names per type
python3 -c "
import os, sys, re, yaml
from collections import defaultdict
from datetime import date

learning_dir = sys.argv[1]
profiles_dir = sys.argv[2]
patterns_file = sys.argv[3]
scores_file = sys.argv[4]

# Scan retrospectives
type_sessions = defaultdict(list)  # project_type -> [session_name, ...]
type_outcomes = defaultdict(list)   # project_type -> [pass/fail, ...]

for fname in os.listdir(learning_dir):
    if not fname.endswith('.md') or fname == 'README.md':
        continue
    fpath = os.path.join(learning_dir, fname)
    try:
        with open(fpath) as f:
            content = f.read()
    except Exception:
        continue

    # Extract project type
    ptype_match = re.search(r'^Project Type:\s*(\S+)', content, re.MULTILINE)
    if not ptype_match:
        continue
    ptype = ptype_match.group(1).lower()

    # Extract session name
    session_match = re.search(r'^# Retrospective:\s*(.+)$', content, re.MULTILINE)
    session_name = session_match.group(1).strip() if session_match else fname.replace('.md', '')

    # Extract outcome
    outcome_match = re.search(r'^Outcome:\s*(.+)$', content, re.MULTILINE)
    outcome = outcome_match.group(1).strip() if outcome_match else 'unknown'

    type_sessions[ptype].append(session_name)
    type_outcomes[ptype].append(outcome)

# Load patterns
patterns = []
if os.path.isfile(patterns_file):
    try:
        with open(patterns_file) as f:
            pdata = yaml.safe_load(f)
        patterns = pdata.get('patterns', []) if pdata else []
    except Exception:
        patterns = []

# Load agent scores
agent_scores = {}
if os.path.isfile(scores_file):
    try:
        with open(scores_file) as f:
            sdata = yaml.safe_load(f)
        agent_scores = sdata.get('agents', {}) if sdata else {}
    except Exception:
        agent_scores = {}

# Thresholds for profile generation
thresholds = [5, 10, 20, 50]
today = date.today().isoformat()
generated = 0

for ptype, sessions in type_sessions.items():
    count = len(sessions)

    # Check if we should generate/regenerate
    should_generate = False
    profile_path = os.path.join(profiles_dir, f'{ptype}.yaml')

    if os.path.isfile(profile_path):
        # Existing profile — regenerate at threshold crossings
        try:
            with open(profile_path) as f:
                existing = yaml.safe_load(f)
            old_count = existing.get('sessions_count', 0)
            for t in thresholds:
                if old_count < t <= count:
                    should_generate = True
                    break
        except Exception:
            should_generate = count >= 5
    else:
        should_generate = count >= 5

    if not should_generate:
        continue

    # ─── Generate profile ───

    # Find matching patterns
    common_pitfalls = []
    for p in patterns:
        tech_stack = p.get('tech_stack', [])
        category = p.get('category', '')
        # Match by project type in tech_stack or by category relevance
        if ptype in tech_stack or any(ptype in t for t in tech_stack):
            common_pitfalls.append({
                'id': p.get('id', ''),
                'description': p.get('description', ''),
                'fix': p.get('fix', ''),
            })

    # Determine recommended model (highest success rate among models used)
    recommended_model = 'inherit'
    best_model_rate = 0.0
    for agent_name, agent_data in agent_scores.items():
        for mh in agent_data.get('model_history', []):
            if mh.get('sessions', 0) >= 3 and mh.get('success_rate', 0.0) > best_model_rate:
                best_model_rate = mh['success_rate']
                recommended_model = mh['model']

    # Determine which challenge gates can be skipped
    skip_gates = []
    if count >= 5:
        skip_gates.append('build_vs_buy')  # we know we're building for this type
    if count >= 10:
        skip_gates.append('goal_alignment')  # well-established project pattern

    # Determine typical cycles from outcomes
    pass_count = sum(1 for o in type_outcomes[ptype] if 'PASS' in o.upper())
    pass_rate = pass_count / count if count > 0 else 0
    recommended_max_cycles = 2 if pass_rate >= 0.7 else 3

    # Per-agent performance for this project type (approximate from global scores)
    agent_perf = {}
    for agent_name, agent_data in agent_scores.items():
        if agent_data.get('sessions_completed', 0) >= 3:
            agent_perf[agent_name] = {
                'success_rate': agent_data.get('success_rate', 0.0),
                'avg_cycles': agent_data.get('avg_cycles_to_pass', 0),
            }

    profile = {
        'project_type': ptype,
        'sessions_count': count,
        'generated_at': today,
        'source_sessions': sessions,
        'common_pitfalls': common_pitfalls,
        'recommended_config': {
            'builder_model': recommended_model,
            'skip_challenge_gates': skip_gates,
            'max_cycles': recommended_max_cycles,
        },
        'agent_performance': agent_perf,
    }

    with open(profile_path, 'w') as f:
        yaml.dump(profile, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    generated += 1
    print(f'Generated profile: {ptype} ({count} sessions)')

if generated == 0:
    print('No profiles generated (no project type has reached the threshold)')
else:
    print(f'Profile generation complete: {generated} profiles updated')
" "$LEARNING_DIR" "$PROFILES_DIR" "$PATTERNS_FILE" "$SCORES_FILE"
