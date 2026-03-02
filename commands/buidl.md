---
description: "Full dev lifecycle: idea → challenge → spec → build → review → ship"
argument-hint: '"raw idea" or path/to/spec/ [--max-cycles N] [--max-retries N] [--skip-challenge]'
---

# The Loop

You are orchestrating The Loop — a full development pipeline from idea to PR. Follow each phase in order. Do not skip phases unless explicitly instructed.

## Parse Input

Arguments: `$ARGUMENTS`

Determine the mode:
- If the argument is a **path to a directory** containing spec files (requirements.md, design.md, tasks.md): **SPEC MODE** — skip to Phase 3 (Explore).
- If the argument is a **quoted string or raw text**: **IDEA MODE** — start from Phase 1 (Challenge).
- If `--skip-challenge` flag is present: skip Phase 1, go straight to Phase 2 with the raw idea.

Parse optional flags:
- `--max-cycles N` (default 3)
- `--max-retries N` (default 5)
- `--skip-challenge` (skip Phase 1)
- `--builder-model opus|sonnet` (default inherit)
- `--reviewer-model opus|sonnet` (default inherit)

## Setup

1. Generate a session name from the idea (kebab-case, 2-4 words, e.g., "staking-rewards" or "dark-mode").
2. Run the setup script:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh <session-name> <max-cycles> <max-retries> <builder-model> <reviewer-model>
   ```
3. Store the session directory path and worktree path for use throughout.

If setup fails (not a git repo, loop already running), report the error and stop.

---

## PHASE 1: CHALLENGE

**Goal:** Turn a vague idea into a concrete, challenged set of requirements.

Update state: `current_phase: challenge`, `status: challenging`

### Round 1: The Five Gates

Run these gates in order using AskUserQuestion. If any gate fails, explain why and give the user the choice to override or stop.

**Gate 1 — Goal Alignment:**
Ask: "Which active priority or goal does this advance? If it doesn't connect to anything you're currently focused on, it might be a distraction."
- Present known priorities if available from CLAUDE.md or context.
- If user says "none" → warn but allow override.

**Gate 2 — Build vs Buy:**
While asking the next question, launch a `loop-researcher` agent in the background to search for existing solutions:
- Give the researcher the raw idea text.
- It will search the web for existing tools, libraries, or services that cover 80%+ of the need.

Ask: "Before we build, let me check if something already exists that does this."
- When researcher returns, present findings.
- If 80%+ coverage found → recommend using the existing solution. User can override.

**Gate 3 — Simplest Thing:**
Ask: "What's the absolute minimum version of this that delivers value? Describe the smallest thing that closes the loop."

**Gate 4 — Problem, Not Solution:**
Ask: "What problem does this solve? Not what feature you want — what pain are you addressing, and who feels it?"

**Gate 5 — Testability:**
Ask: "Write one acceptance test right now. 'When [I do X], then [Y should happen].' If you can't write one, the idea isn't concrete enough yet."

### Round 2: Spec Questions

Ask these using AskUserQuestion. Group related questions to minimize back-and-forth. Use your knowledge of the codebase (if any) to pre-populate suggestions.

1. **Who uses this?** — persona, context, how often.
2. **What's the happy path?** — step by step. "First the user does X, then they see Y, then Z happens."
3. **What can go wrong?** — error cases, edge cases, failure modes. Propose likely ones based on the domain.
4. **What should this NOT do?** — explicit out-of-scope boundaries.
5. **Dependencies and constraints?** — external services, libraries, performance targets, security requirements.

If any answer is vague (e.g., "it should be fast", "handle errors properly"), push back:
- "How fast? Under 200ms? Under 1 second?"
- "Which errors? What should the user see when they happen?"

### Round 3: Pre-Mortem + Devil's Advocate

Based on everything gathered so far, generate 3-5 plausible failure scenarios:
- "Imagine this shipped and failed. What went wrong?"
- Present each scenario and ask: "Is this a real risk? If yes, what's the mitigation?"

Then challenge 2-3 design choices:
- "You said [X], but what if we just [simpler alternative]?"
- "This and this seem to potentially conflict — which takes priority?"

### Gate 6 — OPNet Classification (if Bitcoin/OPNet detected):
Ask: "Is this a contract, frontend, backend, or full-stack project? What network (mainnet/testnet/regtest)? What token standard if applicable (OP20/OP721/custom)?"
- This determines which section of `knowledge/opnet-bible.md` the builder must read
- Record the answers for the builder agent

### Save Challenge Output

Write the full Q&A to `.claude/loop/sessions/<name>/challenge.md`. This is the raw material for Phase 2.

---

## PHASE 2: SPECIFY

**Goal:** Generate three structured documents from the challenge Q&A.

Update state: `current_phase: specify`, `status: specifying`

### Generate requirements.md

Write to `.claude/loop/sessions/<name>/spec/requirements.md`:

```markdown
# Requirements: [Feature Name]

## Objective
[One sentence synthesized from the Q&A — what and why]

## User Stories
- As [persona], I want [action] so that [outcome]
  - Acceptance: [concrete test from the Q&A]
[Repeat for each distinct requirement]

## Boundaries
| Always | Ask First | Never |
|--------|-----------|-------|
| [from Q&A] | [from Q&A] | [from Q&A] |

## Out of Scope
[From "What should this NOT do?" answers]

## Risks & Mitigations
[From pre-mortem round — risk → mitigation pairs]
```

### Generate design.md

Write to `.claude/loop/sessions/<name>/spec/design.md`:

```markdown
# Design: [Feature Name]

## Architecture
[Component relationships, data flow, integration points — synthesized from Q&A and codebase knowledge]

## Files to Modify
[List with brief descriptions of changes needed]

## Files to Create
[List with expected contents described]

## Dependencies
[External services, libraries, existing code to reuse]

## Technical Decisions
[Key choices with rationale from the challenge phase]
```

### Generate tasks.md

Write to `.claude/loop/sessions/<name>/spec/tasks.md`:

```markdown
# Tasks: [Feature Name]

## Verify Commands
- Lint: [auto-detect from package.json or ask user]
- Typecheck: [auto-detect or ask]
- Build: [auto-detect or ask]
- Test: [auto-detect or ask]

## Implementation Tasks
- [ ] [TASK-1] [Concrete, small, testable task]
- [ ] [TASK-2] [Concrete, small, testable task]
[Order matters — earlier tasks should be buildable and testable independently]

## Test Tasks
- [ ] [TEST-1] [Test verifying TASK-1]
- [ ] [TEST-2] [Test verifying TASK-2]
```

For verify commands: check `package.json` scripts, `Makefile`, `tsconfig.json`, `.eslintrc`/`eslint.config` to auto-detect. If not found, ask the user.

### Spec Quality Gate

Validate the generated spec. Check each item:

**Completeness:**
- [ ] Every user story has an automatable acceptance test
- [ ] Error handling is explicit
- [ ] "Never" boundary list is non-empty
- [ ] Verify commands are present

**Clarity:**
- [ ] No ambiguous terms remain undefined
- [ ] Uses "must" not "should" for requirements
- [ ] At least one concrete example per major behavior

**Scope:**
- [ ] Out of scope section is non-empty
- [ ] Pre-mortem risks have mitigations

If any check fails, fix it or ask the user to fill the gap.

### Human Approval Gate

Present all three documents to the user. Ask: "Here's the spec. Review it and let me know if anything needs to change before I start building."

**This is a hard gate. Do NOT proceed until the user explicitly approves.**

The user may:
- Approve as-is → proceed to Phase 3
- Request changes → edit the documents and re-present
- Cancel → stop the loop

---

## PHASE 3: EXPLORE

**Goal:** Build deep codebase understanding before writing any code.

Update state: `current_phase: explore`, `status: exploring`

**Skip condition:** If this is a brand-new project with no existing code, skip this phase.

**OPNet condition:** If this is an OPNet project (detected from package.json deps or challenge answers), explorer agents MUST read `knowledge/opnet-bible.md` as part of their codebase analysis. The builder MUST confirm they've read the bible before writing any code.

Launch TWO `loop-explorer` agents in parallel:

**Explorer A — Structure:**
Prompt: "Map the structure, architecture, conventions, and build toolchain for this project. Return a structured summary with key files, naming conventions, test patterns, and build commands."

**Explorer B — Relevance:**
Prompt: "Find code related to this feature spec: [paste spec objective and key requirements]. Find existing implementations to reuse, integration points, test examples to follow, and potential conflicts. The spec is: [paste requirements.md summary]."

When both return, merge their outputs into `.claude/loop/sessions/<name>/context.md`.

---

## PHASE 4: BUILD

**Goal:** Implement the spec in the isolated worktree.

Update state: `current_phase: build`, `status: building`, `cycle: 1`

Launch the `loop-builder` agent. Give it:

1. The three spec documents (requirements.md, design.md, tasks.md) — read them and include in the prompt.
2. The codebase context (context.md) — read and include.
3. The worktree path — the builder must work exclusively in this directory.
4. Any reviewer findings from previous cycles (empty on first run).
5. The project's CLAUDE.md if it exists.

The builder will:
1. Plan its approach.
2. Implement task by task (TDD where practical).
3. Run the full verify pipeline.
4. Fix failures (up to max_inner_retries).
5. When green: stage, commit, push.

### Create/Update PR

After the builder pushes:
- If this is cycle 1: create a PR via `gh pr create`.
  - Title: concise feature description
  - Body: link to spec, summary of changes, test results
- If this is cycle 2+: the push updates the existing PR.

Record `pr_url` and `pr_number` in the state file.

---

## PHASE 5: REVIEW

**Goal:** Audit the PR with a read-only reviewer.

Update state: `current_phase: review`, `status: reviewing`

Launch the `loop-reviewer` agent. Give it:

1. The three spec documents.
2. The PR number (so it can run `gh pr diff`).
3. The codebase context.
4. The builder's plan.

The reviewer will produce structured findings in the format:
```
VERDICT: PASS or FAIL
CRITICAL: [findings]
MAJOR: [findings]
MINOR: [findings]
NITS: [findings]
SPEC COMPLIANCE: [checklist]
SUMMARY: [overview]
```

Save the review output to `.claude/loop/sessions/<name>/reviews/cycle-<N>.md`.

### Decision

**If VERDICT is PASS:**
- Update state: `status: done`, `current_phase: done`
- Print the PR URL.
- Print a summary: what was built, how many cycles it took, any remaining minor/nit findings.
- The loop is complete.

**If VERDICT is FAIL:**
- Check if cycle < max_cycles.
- If yes: the Stop hook will catch the exit and re-inject the builder prompt with findings. The loop continues automatically.
- If no (max cycles reached): update state to `failed`. Print remaining findings and the PR URL. The human takes over.

---

## Summary Output (when done)

When the loop completes (PASS or max cycles), provide:

```
## Loop Complete

**Status:** [PASSED on cycle N / FAILED after N cycles]
**PR:** [URL]
**Branch:** [branch name]
**Session:** .claude/loop/sessions/<name>/

### What Was Built
[Brief summary from builder]

### Review Results
[Final verdict and any remaining findings]

### Files Modified
[List from the PR]

### Next Steps
[If PASSED: "PR is ready for human review and merge."]
[If FAILED: "These findings remain unresolved: ..." with the specific issues]
```
