---
description: "Refine an idea into a spec without building"
argument-hint: '"raw idea description"'
---

# The Loop — Spec Only Mode

You are running The Loop in spec-only mode. This runs Phase 1 (Challenge) and Phase 2 (Specify) only — no building, no PR. The output is a set of spec documents ready for a future `/buidl` invocation.

## Input

Idea: `$ARGUMENTS`

## Setup

1. Generate a session name from the idea (kebab-case, 2-4 words).
2. Create the session directory: `.claude/loop/sessions/<name>/spec/`

## PHASE 1: CHALLENGE

Run the full challenge interrogation as described in the main `/buidl` command:

### Round 1: The Five Gates
1. **Goal alignment** — which priority does this advance?
2. **Build vs buy** — launch a `loop-researcher` agent in background to check for existing solutions.
3. **Simplest thing** — what's the minimum viable version?
4. **Problem, not solution** — what pain are you addressing?
5. **Testability** — write one acceptance test now.

### Round 2: Spec Questions
1. Who uses this?
2. What's the happy path? (step by step)
3. What can go wrong?
4. What should this NOT do?
5. Dependencies and constraints?

Push back on vague answers. "Fast" needs a number. "Handle errors" needs specifics.

### Round 3: Pre-Mortem + Devil's Advocate
- Generate 3-5 failure scenarios, ask which are real risks.
- Challenge 2-3 design choices with simpler alternatives.
- Flag internal inconsistencies.

Save Q&A to `.claude/loop/sessions/<name>/challenge.md`.

## PHASE 2: SPECIFY

Generate the three spec documents from the Q&A:

1. **requirements.md** — objective, user stories with acceptance criteria, boundaries (always/ask/never), out of scope, risks & mitigations.
2. **design.md** — architecture, files to modify/create, dependencies, technical decisions with rationale.
3. **tasks.md** — verify commands (auto-detect from package.json if possible), implementation tasks, test tasks.

Write all three to `.claude/loop/sessions/<name>/spec/`.

### Spec Quality Gate
Validate completeness, clarity, and scope. Fix gaps or ask the user.

### Present to User
Show all three documents. Explain:

"The spec is ready at `.claude/loop/sessions/<name>/spec/`. When you're ready to build, run:
```
/buidl .claude/loop/sessions/<name>/spec/
```
This will skip straight to the explore and build phases."
