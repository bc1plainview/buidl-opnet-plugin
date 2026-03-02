---
description: "Review an existing PR with the loop reviewer agent"
argument-hint: "<PR-number> [path/to/spec/]"
---

# The Loop — Review Only Mode

You are running The Loop in review-only mode. This launches the reviewer agent on an existing PR.

## Input

Arguments: `$ARGUMENTS`

Parse:
- First argument: PR number (required)
- Second argument: path to spec directory (optional — if provided, reviewer checks spec compliance)

## Run Review

1. Verify the PR exists: `gh pr view <number>`
2. If a spec path was provided, read the spec documents (requirements.md, design.md, tasks.md).
3. Launch the `loop-reviewer` agent with:
   - The PR number
   - The spec documents (if provided)
   - Instruction to run `gh pr diff <number>` to read the changes

4. Present the reviewer's findings.

## Output

Display the reviewer's structured output:
- VERDICT (PASS/FAIL)
- CRITICAL / MAJOR / MINOR / NITS findings
- SPEC COMPLIANCE (if spec was provided)
- SUMMARY

This is a one-shot review — no iteration loop. If the user wants the full build-review cycle, they should use `/buidl`.
