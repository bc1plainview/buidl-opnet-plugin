#!/bin/bash
# score-build.sh — Goal-oriented build evaluation across 4 dimensions
#
# Usage: bash scripts/score-build.sh
#
# Evaluates the current build across 4 dimensions:
#   1. spec_coverage (0-100%): requirements with tests / total requirements
#   2. security_delta (integer): new open findings count (0 = no regression)
#   3. mutation_score (0-100%): from mutation-score.json
#   4. code_health (0-100%): 100 - (weighted_penalties * 5), floor 0
#
# Thresholds: spec >= 90%, security <= 0, mutation >= 70%, health >= 60%
#
# Output: artifacts/evaluation/progress-tracker.yaml
#
# Exit codes:
#   0 — Success
#   1 — Error during evaluation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

OUTPUT_DIR="${SCRIPT_DIR}/artifacts/evaluation"
mkdir -p "$OUTPUT_DIR"

export _SCOREBUILD_ROOT="$SCRIPT_DIR"
export _SCOREBUILD_OUTPUT="$OUTPUT_DIR/progress-tracker.yaml"
python3 << 'PYEOF'
import sys
import json
import os
import re

script_dir = os.environ['_SCOREBUILD_ROOT']
output_path = os.environ['_SCOREBUILD_OUTPUT']

# --- Dimension 1: spec_coverage ---
spec_coverage = 0
total_reqs = 0
tested_reqs = 0

spec_req_path = os.path.join(script_dir, "artifacts", "evaluation", "spec-requirements.yaml")
if os.path.exists(spec_req_path):
    with open(spec_req_path, 'r') as f:
        content = f.read()
    # Count requirements
    req_lines = re.findall(r'^\s+- id:', content, re.MULTILINE)
    total_reqs = len(req_lines)
    # Count those with has_test: true
    tested_lines = re.findall(r'has_test:\s*true', content)
    tested_reqs = len(tested_lines)
    if total_reqs > 0:
        spec_coverage = round((tested_reqs / total_reqs) * 100)

# --- Dimension 2: security_delta ---
security_delta = 0

findings_path = os.path.join(script_dir, "artifacts", "findings-ledger.md")
if os.path.exists(findings_path):
    with open(findings_path, 'r') as f:
        content = f.read()
    # Count OPEN findings
    open_count = len(re.findall(r'\|\s*OPEN\s*\|', content))
    security_delta = open_count

# --- Dimension 3: mutation_score ---
mutation_pct = 0

mutation_path = os.path.join(script_dir, "artifacts", "testing", "mutation-score.json")
if os.path.exists(mutation_path):
    try:
        with open(mutation_path, 'r') as f:
            mutation_data = json.load(f)
        mutation_pct = round(mutation_data.get('mutation_score', 0) * 100)
    except (json.JSONDecodeError, KeyError):
        mutation_pct = 0

# --- Dimension 4: code_health ---
# Penalties: lint errors, type errors, build warnings
weighted_penalties = 0

# Check for build result
for build_result_path in [
    os.path.join(script_dir, "artifacts", "contract", "build-result.json"),
    os.path.join(script_dir, "artifacts", "frontend", "build-result.json"),
    os.path.join(script_dir, "artifacts", "backend", "build-result.json"),
]:
    if os.path.exists(build_result_path):
        try:
            with open(build_result_path, 'r') as f:
                build_data = json.load(f)
            if build_data.get('status') != 'success':
                weighted_penalties += 5
            warnings = build_data.get('warnings', 0)
            if isinstance(warnings, int):
                weighted_penalties += warnings
        except (json.JSONDecodeError, KeyError):
            weighted_penalties += 2

# Check findings for code quality issues
if os.path.exists(findings_path):
    with open(findings_path, 'r') as f:
        content = f.read()
    # Count convention/nit findings as minor penalties
    minor_count = len(re.findall(r'\|\s*(?:OPEN|REGRESSION)\s*\|', content))
    weighted_penalties += minor_count

code_health = max(0, 100 - (weighted_penalties * 5))

# --- Thresholds ---
spec_threshold = 90
security_threshold = 0
mutation_threshold = 70
health_threshold = 60

spec_pass = spec_coverage >= spec_threshold
security_pass = security_delta <= security_threshold
mutation_pass = mutation_pct >= mutation_threshold
health_pass = code_health >= health_threshold

all_pass = spec_pass and security_pass and mutation_pass and health_pass
overall_verdict = "PASS" if all_pass else "FAIL"

# Failed dimensions
failed_dims = []
if not spec_pass:
    failed_dims.append("spec_coverage")
if not security_pass:
    failed_dims.append("security_delta")
if not mutation_pass:
    failed_dims.append("mutation_score")
if not health_pass:
    failed_dims.append("code_health")

# Write YAML output
with open(output_path, 'w') as f:
    f.write("dimensions:\n")
    f.write("  spec_coverage:\n")
    f.write("    score: {}\n".format(spec_coverage))
    f.write("    threshold: {}\n".format(spec_threshold))
    f.write("    pass: {}\n".format(str(spec_pass).lower()))
    f.write("    detail: \"{}/{} requirements with tests\"\n".format(tested_reqs, total_reqs))
    f.write("  security_delta:\n")
    f.write("    score: {}\n".format(security_delta))
    f.write("    threshold: {}\n".format(security_threshold))
    f.write("    pass: {}\n".format(str(security_pass).lower()))
    f.write("    detail: \"{} open findings\"\n".format(security_delta))
    f.write("  mutation_score:\n")
    f.write("    score: {}\n".format(mutation_pct))
    f.write("    threshold: {}\n".format(mutation_threshold))
    f.write("    pass: {}\n".format(str(mutation_pass).lower()))
    f.write("    detail: \"{}% mutants killed\"\n".format(mutation_pct))
    f.write("  code_health:\n")
    f.write("    score: {}\n".format(code_health))
    f.write("    threshold: {}\n".format(health_threshold))
    f.write("    pass: {}\n".format(str(health_pass).lower()))
    f.write("    detail: \"{} weighted penalties\"\n".format(weighted_penalties))
    f.write("overall_verdict: \"{}\"\n".format(overall_verdict))
    f.write("failed_dimensions:\n")
    if failed_dims:
        for dim in failed_dims:
            f.write("  - \"{}\"\n".format(dim))
    else:
        f.write("  []\n")

# Print compact table
print("Build Score Card")
print("+" + "-"*20 + "+" + "-"*8 + "+" + "-"*10 + "+" + "-"*6 + "+")
print("| {:<18} | {:<6} | {:<8} | {:<4} |".format("Dimension", "Score", "Thresh", "Pass"))
print("+" + "-"*20 + "+" + "-"*8 + "+" + "-"*10 + "+" + "-"*6 + "+")
print("| {:<18} | {:<6} | {:<8} | {:<4} |".format("spec_coverage", "{}%".format(spec_coverage), ">={}%".format(spec_threshold), "Y" if spec_pass else "N"))
print("| {:<18} | {:<6} | {:<8} | {:<4} |".format("security_delta", str(security_delta), "<={}".format(security_threshold), "Y" if security_pass else "N"))
print("| {:<18} | {:<6} | {:<8} | {:<4} |".format("mutation_score", "{}%".format(mutation_pct), ">={}%".format(mutation_threshold), "Y" if mutation_pass else "N"))
print("| {:<18} | {:<6} | {:<8} | {:<4} |".format("code_health", "{}%".format(code_health), ">={}%".format(health_threshold), "Y" if health_pass else "N"))
print("+" + "-"*20 + "+" + "-"*8 + "+" + "-"*10 + "+" + "-"*6 + "+")
print("Overall: {}".format(overall_verdict))
if failed_dims:
    print("Failed: {}".format(", ".join(failed_dims)))
PYEOF
