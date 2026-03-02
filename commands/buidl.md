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
- This determines which agents are spawned in Phase 4
- Record the answers for the orchestrator

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

Launch TWO `loop-explorer` agents in parallel:

**Explorer A — Structure:**
Prompt: "Map the structure, architecture, conventions, and build toolchain for this project. Return a structured summary with key files, naming conventions, test patterns, and build commands."

**Explorer B — Relevance:**
Prompt: "Find code related to this feature spec: [paste spec objective and key requirements]. Find existing implementations to reuse, integration points, test examples to follow, and potential conflicts. The spec is: [paste requirements.md summary]."

**OPNet Enhancement:** If this is an OPNet project (detected from package.json deps, asconfig.json, or challenge answers), include in both explorer prompts:
- "Read `${CLAUDE_PLUGIN_ROOT}/knowledge/slices/project-setup.md` for OPNet architecture context."
- "Check for existing OPNet patterns: contract structure, wallet-connect hooks, provider singletons."

When both return, merge their outputs into `.claude/loop/sessions/<name>/context.md`.

---

## PHASE 4: BUILD — Multi-Agent Orchestration

**Goal:** Implement the spec using specialized agents, each scoped to their domain.

Update state: `current_phase: build`, `status: building`, `cycle: 1`

### Step 0: Project Type Detection

Detect what kind of project this is:

```
Check the spec and existing codebase:

1. If spec mentions "contract", "token", "OP-20", "OP-721", "AssemblyScript", "btc-runtime",
   OR asconfig.json exists, OR challenge answers indicate contract:
   → components.contract = true

2. If spec mentions "frontend", "UI", "React", "wallet", "dApp interface",
   OR vite.config.ts exists, OR challenge answers indicate frontend:
   → components.frontend = true

3. If spec mentions "backend", "API", "server", "indexer", "hyper-express",
   OR challenge answers indicate backend needed:
   → components.backend = true

4. If NONE of the above are OPNet-specific:
   → project_type = "generic" (use legacy loop-builder flow)
   → Skip to Legacy Build section below
```

Update state with detected components.

### Step 1: Generate Execution Plan

Based on detected components, build an ordered execution plan:

**Contract-only project:**
```
Step 1: opnet-contract-dev → compile + test
Step 2: opnet-auditor → audit contract
Step 3: opnet-deployer → deploy to testnet (if audit PASS)
```

**Frontend-only project (existing contract):**
```
Step 1: opnet-frontend-dev → build frontend
Step 2: opnet-auditor → audit frontend
Step 3: opnet-ui-tester → smoke + E2E tests
```

**Full-stack project (contract + frontend, optional backend):**
```
Step 1: opnet-contract-dev → compile + test + export ABI
Step 2 (parallel after ABI ready):
  - opnet-frontend-dev → build frontend (imports ABI)
  - opnet-backend-dev → build backend (imports ABI) [if needed]
Step 3: opnet-auditor → audit ALL code
Step 4: opnet-deployer → deploy contract (if audit PASS)
Step 5: opnet-ui-tester → smoke + E2E tests (needs deployed address)
```

Write the execution plan to the state file.

### Step 2: Execute the Plan

For each step in the execution plan, the orchestrator:

1. **Validates preconditions** — check that required artifacts exist from previous steps
2. **Spawns the agent** — launch with Agent tool, providing spec, context, and artifact paths
3. **Checks results** — validate output artifacts after agent completes
4. **Routes failures** — if an agent fails, determine if it can retry or needs upstream fix

#### Agent Dispatch Template

For each agent in the plan, construct the prompt:

```
You are working in: [WORKTREE_PATH]

## Your Task
[Extract relevant tasks from tasks.md for this agent's domain]

## Spec
[Include requirements.md content]

## Design
[Include design.md content relevant to this agent's domain]

## Codebase Context
[Include context.md if available]

## Artifacts from Previous Steps
[List available artifacts with paths]
- ABI: [path to abi.json, if contract step completed]
- Deployment receipt: [path to receipt.json, if deployer completed]

## Knowledge
Read your knowledge file FIRST: ${CLAUDE_PLUGIN_ROOT}/knowledge/slices/[agent-slice].md

## Output
Write your artifacts to: .claude/loop/sessions/[name]/artifacts/[domain]/
```

#### Step 2a: Contract Development (if components.contract = true)

Launch `opnet-contract-dev` agent:
- Knowledge: `knowledge/slices/contract-dev.md`
- Working directory: `[WORKTREE]/contracts/` or `[WORKTREE]/src/`
- Output: ABI JSON to `artifacts/contract/abi.json`, build result to `artifacts/contract/build-result.json`

**Validation after completion:**
- `artifacts/contract/build-result.json` must have `"status": "success"`
- ABI JSON must exist and be valid JSON
- If failed: retry once, then report failure and stop

#### Step 2b: Frontend + Backend Development (parallel, after ABI ready)

**Frontend** — Launch `opnet-frontend-dev` agent:
- Knowledge: `knowledge/slices/frontend-dev.md`
- Import: ABI from `artifacts/contract/abi.json`
- Working directory: `[WORKTREE]/frontend/`
- Output: `artifacts/frontend/build-result.json`

**Backend** (if components.backend = true) — Launch `opnet-backend-dev` agent in parallel:
- Knowledge: `knowledge/slices/backend-dev.md`
- Import: ABI from `artifacts/contract/abi.json`
- Working directory: `[WORKTREE]/backend/`
- Output: `artifacts/backend/build-result.json`

**Validation after completion:**
- Both `build-result.json` files must have `"status": "success"`
- If either fails: retry once, then report failure and stop

#### Step 2c: Security Audit

Launch `opnet-auditor` agent:
- Knowledge: `knowledge/slices/security-audit.md`
- Scope: ALL source files across all components
- Output: `artifacts/audit/findings.md`

**Decision after audit:**

- If VERDICT is **PASS** (no CRITICAL/HIGH): proceed to deployment
- If VERDICT is **FAIL**:
  - Parse findings to identify the responsible agent for each CRITICAL/HIGH issue
  - Route contract findings to `opnet-contract-dev`
  - Route frontend findings to `opnet-frontend-dev`
  - Route backend findings to `opnet-backend-dev`
  - After fixes: re-run auditor
  - Max audit cycles: 2 (if still FAIL after 2, report to user and stop)

#### Step 2d: Deployment (after audit PASS)

**Testnet deployment is automatic. Mainnet requires user approval.**

For mainnet, present AskUserQuestion:
- "The audit passed. Deploy to mainnet? This uses real BTC for gas."
- Options: "Deploy to mainnet", "Deploy to testnet only", "Skip deployment"

Launch `opnet-deployer` agent:
- Knowledge: `knowledge/slices/deployment.md`
- Import: Compiled WASM from contract build
- Network: testnet (or mainnet if approved)
- Output: `artifacts/deployment/receipt.json`

**Validation after completion:**
- `receipt.json` must have `"status": "success"` and a valid `contractAddress`
- If failed: check error table in deployment knowledge, retry once

After successful deployment, update frontend config with the deployed contract address.

#### Step 2e: UI Testing (after deployment)

Launch `opnet-ui-tester` agent:
- Knowledge: `knowledge/slices/ui-testing.md`
- Import: Deployed contract address from `artifacts/deployment/receipt.json`
- Import: Frontend dev server port from `artifacts/frontend/build-result.json`
- Output: `artifacts/testing/results.json`, `artifacts/testing/screenshots/`

**Decision after tests:**
- If all tests pass: proceed to commit + PR
- If tests fail:
  - Route UI failures to `opnet-frontend-dev` for fixes
  - After fixes: re-run UI tester
  - Max test cycles: 2

### Step 3: Commit, Push, and Create PR

After all agents complete successfully:

1. Stage all changes in the worktree
2. Commit with a descriptive message summarizing all work done
3. Push to the loop branch
4. If cycle 1: create PR via `gh pr create`
   - Title: concise feature description
   - Body: include summary, audit findings, deployment receipt, test results, explorer links
5. If cycle 2+: the push updates the existing PR

Record `pr_url` and `pr_number` in the state file.

### Legacy Build (for non-OPNet projects)

If `project_type = "generic"`, fall back to the original single-agent builder:

Launch the `loop-builder` agent with:
1. The three spec documents
2. The codebase context
3. The worktree path
4. Any reviewer findings from previous cycles
5. The project's CLAUDE.md if it exists

---

## PHASE 5: REVIEW

**Goal:** Audit the PR with a read-only reviewer.

Update state: `current_phase: review`, `status: reviewing`

Launch the `loop-reviewer` agent. Give it:

1. The three spec documents.
2. The PR number (so it can run `gh pr diff`).
3. The codebase context.
4. For OPNet projects: also include the integration-review knowledge slice (`knowledge/slices/integration-review.md`).

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
- Include deployment receipt and explorer links if available.
- The loop is complete.

**If VERDICT is FAIL:**
- Check if cycle < max_cycles.
- If yes: the Stop hook will catch the exit and re-inject the builder prompt with findings. The loop continues automatically.
  - For OPNet projects: route reviewer findings to specific agents based on the finding category (contract/frontend/backend/integration).
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
[Brief summary — which components: contract, frontend, backend]

### Agents Used
[List each agent that ran and its outcome]

### Audit Results
[Verdict and summary of findings]

### Deployment
[Network, contract address, explorer links — or "skipped" if no deployment]

### UI Test Results
[Pass/fail summary — or "skipped" if no frontend]

### Review Results
[Final verdict and any remaining findings]

### Files Modified
[List from the PR]

### Next Steps
[If PASSED: "PR is ready for human review and merge."]
[If FAILED: "These findings remain unresolved: ..." with the specific issues]
```
