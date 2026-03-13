#!/bin/bash
# mutate-contract.sh — Mutation testing for contract source files
#
# Usage: bash scripts/mutate-contract.sh <contract-src-path> <test-dir>
#
# Applies 20 sed-level mutation operators to the contract source, one at a time.
# For each mutant: creates a temp copy, applies the mutation, compiles, runs tests.
# If tests fail (mutant killed) or tests pass (mutant survived).
# Compile errors count as "survived" (untested code path).
#
# Output: artifacts/testing/mutation-score.json
#   { total_mutants, killed, survived, compile_errors,
#     mutation_score (0-1), threshold (0.70), verdict (PASS/FAIL),
#     survivors[] }
#
# Exit codes:
#   0 — Success (output written regardless of verdict)
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT_SRC="${1:-}"
TEST_DIR="${2:-}"

if [[ -z "$CONTRACT_SRC" || -z "$TEST_DIR" ]]; then
  echo "Usage: bash scripts/mutate-contract.sh <contract-src-path> <test-dir>"
  echo "  contract-src-path: path to the contract source file (.ts)"
  echo "  test-dir: path to the test directory"
  exit 1
fi

if [[ ! -f "$CONTRACT_SRC" ]]; then
  echo "Error: Contract source file not found: $CONTRACT_SRC"
  exit 1
fi

if [[ ! -d "$TEST_DIR" ]]; then
  echo "Error: Test directory not found: $TEST_DIR"
  exit 1
fi

# Output directory
OUTPUT_DIR="${SCRIPT_DIR}/artifacts/testing"
mkdir -p "$OUTPUT_DIR"

# Working directory for mutants
MUTANT_DIR=$(mktemp -d)
trap 'rm -rf "$MUTANT_DIR"' EXIT

# Contract directory (for build context)
CONTRACT_DIR="$(dirname "$CONTRACT_SRC")"
CONTRACT_FILENAME="$(basename "$CONTRACT_SRC")"

TOTAL=0
KILLED=0
SURVIVED=0
COMPILE_ERRORS=0
SURVIVORS_JSON="[]"

# 20 mutation operators (sed patterns)
# Each entry: "name|sed-pattern"
OPERATORS=(
  "arith-add-to-sub|s/SafeMath\.add/SafeMath.sub/g"
  "arith-sub-to-add|s/SafeMath\.sub/SafeMath.add/g"
  "arith-mul-to-div|s/SafeMath\.mul/SafeMath.div/g"
  "arith-div-to-mul|s/SafeMath\.div/SafeMath.mul/g"
  "compare-eq-to-neq|s/==/!=/g"
  "compare-neq-to-eq|s/!=/==/g"
  "compare-gt-to-lt|s/> /< /g"
  "compare-lt-to-gt|s/< /> /g"
  "compare-gte-to-lte|s/>=/<=/"
  "compare-lte-to-gte|s/<=/>=/g"
  "bool-true-to-false|s/return true/return false/g"
  "bool-false-to-true|s/return false/return true/g"
  "logic-and-to-or|s/&&/||/g"
  "logic-or-to-and|s/||/\&\&/g"
  "negate-condition|s/if (/if (!/g"
  "remove-revert|s/Revert(/\/\/ Revert(/g"
  "zero-constant|s/u256\.One/u256.Zero/g"
  "one-constant|s/u256\.Zero/u256.One/g"
  "remove-event|s/this\.emitEvent/\/\/ this.emitEvent/g"
  "swap-args|s/\(a, b\)/(b, a)/g"
)

# Check if there are any test files
TEST_COUNT=$(find "$TEST_DIR" -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$TEST_COUNT" -eq 0 ]]; then
  TEST_COUNT=$(find "$TEST_DIR" -name "*.ts" -o -name "*.js" 2>/dev/null | wc -l | tr -d ' ')
fi

# Read the source file
SOURCE_CONTENT=$(cat "$CONTRACT_SRC")

for entry in "${OPERATORS[@]}"; do
  OP_NAME="${entry%%|*}"
  SED_PATTERN="${entry#*|}"

  # Apply mutation
  MUTATED=$(echo "$SOURCE_CONTENT" | sed "$SED_PATTERN" 2>/dev/null || echo "$SOURCE_CONTENT")

  # Skip if mutation had no effect
  if [[ "$MUTATED" == "$SOURCE_CONTENT" ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Write mutant
  MUTANT_FILE="${MUTANT_DIR}/${CONTRACT_FILENAME}"
  echo "$MUTATED" > "$MUTANT_FILE"

  # Try to compile (check if npm run build exists in the contract dir)
  BUILD_CMD=""
  if [[ -f "${CONTRACT_DIR}/package.json" ]]; then
    BUILD_CMD="cd ${CONTRACT_DIR} && cp ${MUTANT_FILE} ${CONTRACT_SRC} && npm run build 2>&1"
  elif [[ -f "${CONTRACT_DIR}/../package.json" ]]; then
    BUILD_CMD="cd ${CONTRACT_DIR}/.. && cp ${MUTANT_FILE} ${CONTRACT_SRC} && npm run build 2>&1"
  fi

  COMPILE_OK=true
  if [[ -n "$BUILD_CMD" ]]; then
    if ! eval "$BUILD_CMD" >/dev/null 2>&1; then
      COMPILE_OK=false
      COMPILE_ERRORS=$((COMPILE_ERRORS + 1))
      SURVIVED=$((SURVIVED + 1))
      SURVIVORS_JSON=$(python3 -c "
import json, sys
survivors = json.loads(sys.argv[1])
survivors.append({
    'operator': sys.argv[2],
    'reason': 'compile_error',
    'file': sys.argv[3]
})
print(json.dumps(survivors))
" "$SURVIVORS_JSON" "$OP_NAME" "$CONTRACT_SRC")
      # Restore original
      cp "$CONTRACT_SRC" "$CONTRACT_SRC" 2>/dev/null || true
      echo "$SOURCE_CONTENT" > "$CONTRACT_SRC"
      continue
    fi
  fi

  # Run tests
  TEST_CMD=""
  if [[ -f "${CONTRACT_DIR}/package.json" ]]; then
    TEST_CMD="cd ${CONTRACT_DIR} && npm test 2>&1"
  elif [[ -f "${CONTRACT_DIR}/../package.json" ]]; then
    TEST_CMD="cd ${CONTRACT_DIR}/.. && npm test 2>&1"
  else
    # No package.json - try running test files directly
    TEST_CMD="cd ${TEST_DIR} && ls *.test.* *.spec.* 2>/dev/null && echo 'test-files-found'"
  fi

  if [[ -n "$TEST_CMD" ]]; then
    if eval "$TEST_CMD" >/dev/null 2>&1; then
      # Tests passed — mutant survived (bad)
      SURVIVED=$((SURVIVED + 1))
      SURVIVORS_JSON=$(python3 -c "
import json, sys
survivors = json.loads(sys.argv[1])
survivors.append({
    'operator': sys.argv[2],
    'reason': 'tests_passed',
    'file': sys.argv[3]
})
print(json.dumps(survivors))
" "$SURVIVORS_JSON" "$OP_NAME" "$CONTRACT_SRC")
    else
      # Tests failed — mutant killed (good)
      KILLED=$((KILLED + 1))
    fi
  else
    # No test runner available — count as survived
    SURVIVED=$((SURVIVED + 1))
    SURVIVORS_JSON=$(python3 -c "
import json, sys
survivors = json.loads(sys.argv[1])
survivors.append({
    'operator': sys.argv[2],
    'reason': 'no_test_runner',
    'file': sys.argv[3]
})
print(json.dumps(survivors))
" "$SURVIVORS_JSON" "$OP_NAME" "$CONTRACT_SRC")
  fi

  # Restore original source
  echo "$SOURCE_CONTENT" > "$CONTRACT_SRC"
done

# Calculate mutation score
if [[ $TOTAL -eq 0 ]]; then
  MUTATION_SCORE=0
else
  MUTATION_SCORE=$(python3 -c "print(round($KILLED / $TOTAL, 4))")
fi

# Determine verdict
THRESHOLD="0.70"
if python3 -c "exit(0 if $MUTATION_SCORE >= $THRESHOLD else 1)"; then
  VERDICT="PASS"
else
  VERDICT="FAIL"
fi

# Write output
python3 -c "
import json, sys

result = {
    'total_mutants': int(sys.argv[1]),
    'killed': int(sys.argv[2]),
    'survived': int(sys.argv[3]),
    'compile_errors': int(sys.argv[4]),
    'mutation_score': float(sys.argv[5]),
    'threshold': float(sys.argv[6]),
    'verdict': sys.argv[7],
    'survivors': json.loads(sys.argv[8])
}

with open(sys.argv[9], 'w') as f:
    json.dump(result, f, indent=2)
    f.write('\n')

print(json.dumps(result, indent=2))
" "$TOTAL" "$KILLED" "$SURVIVED" "$COMPILE_ERRORS" "$MUTATION_SCORE" "$THRESHOLD" "$VERDICT" "$SURVIVORS_JSON" "${OUTPUT_DIR}/mutation-score.json"

echo ""
echo "Mutation testing complete: $KILLED/$TOTAL killed (score: $MUTATION_SCORE, verdict: $VERDICT)"
