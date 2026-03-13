#!/bin/bash
# extract-requirements.sh — Extract structured requirements from requirements.md
#
# Usage: bash scripts/extract-requirements.sh <requirements-md-path>
#
# Parses a requirements.md file and extracts individual requirements into
# a structured YAML format for goal-oriented evaluation.
#
# Output: artifacts/evaluation/spec-requirements.yaml
#   requirements:
#     - id: REQ-1
#       description: "..."
#       has_test: false
#       priority: must
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REQUIREMENTS_PATH="${1:-}"

if [[ -z "$REQUIREMENTS_PATH" ]]; then
  echo "Usage: bash scripts/extract-requirements.sh <requirements-md-path>"
  exit 1
fi

if [[ ! -f "$REQUIREMENTS_PATH" ]]; then
  echo "Error: Requirements file not found: $REQUIREMENTS_PATH"
  exit 1
fi

OUTPUT_DIR="${SCRIPT_DIR}/artifacts/evaluation"
mkdir -p "$OUTPUT_DIR"

export _EXTREQ_INPUT="$REQUIREMENTS_PATH"
export _EXTREQ_OUTPUT="$OUTPUT_DIR/spec-requirements.yaml"
python3 << 'PYEOF'
import sys
import re
import os

req_path = os.environ['_EXTREQ_INPUT']
output_path = os.environ['_EXTREQ_OUTPUT']

try:
    with open(req_path, 'r') as f:
        content = f.read()
except (IOError, OSError):
    content = ""

requirements = []
req_id = 0

if content.strip():
    lines = content.split('\n')

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        # Match requirement patterns:
        # - [ ] REQ-N: description
        # - REQ-N: description
        # - Numbered list: 1. description
        # - Bullet: - description (that looks like a requirement)
        # - **Must**: description

        req_match = re.match(r'^[-*]\s*\[[ x]\]\s*(REQ-\d+)[:\s]+(.+)', stripped)
        if not req_match:
            req_match = re.match(r'^(REQ-\d+)[:\s]+(.+)', stripped)
        if not req_match:
            req_match = re.match(r'^\d+\.\s+(.+)', stripped)
            if req_match:
                req_id += 1
                desc = req_match.group(1).strip()
                req_name = "REQ-{}".format(req_id)
                # Detect priority
                priority = "must"
                desc_lower = desc.lower()
                if "should" in desc_lower or "nice to have" in desc_lower:
                    priority = "should"
                elif "could" in desc_lower or "optional" in desc_lower:
                    priority = "could"

                requirements.append({
                    'id': req_name,
                    'description': desc,
                    'has_test': False,
                    'priority': priority,
                })
                continue

        if req_match and len(req_match.groups()) >= 2:
            req_name = req_match.group(1)
            desc = req_match.group(2).strip()
            priority = "must"
            desc_lower = desc.lower()
            if "should" in desc_lower or "nice to have" in desc_lower:
                priority = "should"
            elif "could" in desc_lower or "optional" in desc_lower:
                priority = "could"

            requirements.append({
                'id': req_name,
                'description': desc,
                'has_test': False,
                'priority': priority,
            })
            continue

        # Match bullet points that contain requirement-like language
        bullet_match = re.match(r'^[-*]\s+\*\*(Must|Should|Could)\*\*[:\s]+(.+)', stripped)
        if bullet_match:
            req_id += 1
            priority = bullet_match.group(1).lower()
            desc = bullet_match.group(2).strip()
            requirements.append({
                'id': "REQ-{}".format(req_id),
                'description': desc,
                'has_test': False,
                'priority': priority,
            })

# Write YAML output manually (no PyYAML dependency)
with open(output_path, 'w') as f:
    f.write("requirements:\n")
    if not requirements:
        f.write("  []\n")
    else:
        for req in requirements:
            f.write("  - id: \"{}\"\n".format(req['id']))
            # Escape quotes in description
            safe_desc = req['description'].replace('"', '\\"')
            f.write("    description: \"{}\"\n".format(safe_desc))
            f.write("    has_test: {}\n".format(str(req['has_test']).lower()))
            f.write("    priority: \"{}\"\n".format(req['priority']))

print("Extracted {} requirements to {}".format(len(requirements), output_path))
PYEOF
