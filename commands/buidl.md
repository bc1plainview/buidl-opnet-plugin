---
description: "Full dev lifecycle: idea → challenge → spec → build → review → ship"
argument-hint: '"raw idea" or path/to/spec/ [--max-cycles N] [--max-retries N] [--skip-challenge] [--max-tokens N] [--dry-run]'
---

# The Loop

You are orchestrating The Loop — a full development pipeline from idea to PR. Follow each phase in order. Do not skip phases unless explicitly instructed.

## RULES

These rules apply throughout the entire pipeline:

1. **State writes**: NEVER write directly to `state.yaml` or `state.local.md`. Always use: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh key=value`
2. **Checkpointing**: After EVERY phase transition, write a checkpoint (see Checkpoint Protocol below).
3. **Cost tracking**: After EVERY agent dispatch, log to cost-ledger.md and update `tokens_used` in state.
4. **max_turns per agent type**: Builders=30, Reviewers=15, Explorers=15, Researchers=10, Auditors=20, Deployers=15, UI Testers=20. Always pass `max_turns` when dispatching agents.
5. **Structured errors**: When an agent fails, retry once with error context. On second failure, query `scripts/query-pattern.sh` for a known fix. If found, present 5 options (apply known fix, retry differently, skip, amend spec, cancel). If not found, present 4 options (retry differently, skip, amend spec, cancel). Never ask open-ended "what should I do?" questions.
6. **Context pressure**: If you detect context pressure (responses getting shorter, tool calls failing), immediately checkpoint and tell the user to run `/buidl-resume`.
7. **Summaries across phases**: Never hold raw agent output across phase boundaries. Summarize, save to artifacts, then discard the raw output.

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
- `--max-tokens N` (default unlimited -- if set, track and enforce token budget)
- `--dry-run` (run Challenge + Specify + Explore normally, then print the execution plan without dispatching agents)

### Auto-Detect Existing Session

Before setup, check if a loop session already exists:

```bash
STATE_FILE=".claude/loop/state.yaml"
LEGACY_STATE=".claude/loop/state.local.md"
```

If either file exists:
1. Read `status` and `session_name` from the state file.
2. If status is an active phase (challenging, specifying, exploring, building, reviewing, auditing, deploying, testing):
   - Tell the user: "A loop session '`<session_name>`' is already active (status: `<status>`). Would you like to resume it?"
   - Use AskUserQuestion with options:
     1. **Resume existing** -- runs `/buidl-resume` logic
     2. **Cancel and start fresh** -- runs `/buidl-cancel` then continues with new setup
     3. **Cancel, clean, and start fresh** -- runs `/buidl-clean` then continues with new setup
3. If status is `done` or `cancelled`: proceed with new setup (the old session is finished).

## Setup

1. Generate a session name from the idea (kebab-case, 2-4 words, e.g., "staking-rewards" or "dark-mode").
2. Run the setup script:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh <session-name> <max-cycles> <max-retries> <builder-model> <reviewer-model>
   ```
3. Store the session directory path and worktree path for use throughout.

If setup fails (not a git repo, loop already running), report the error and stop.

### Initialize Cost Ledger

Create `.claude/loop/sessions/<name>/cost-ledger.md`:
```markdown
# Cost Ledger: <session-name>

| Timestamp | Agent | Phase | Tokens | Cumulative |
|-----------|-------|-------|--------|------------|
```

### Initialize Decisions Register

Create `.claude/loop/sessions/<name>/decisions.md` using the template at `${CLAUDE_PLUGIN_ROOT}/templates/decisions.md`. This is an append-only log of architectural and pattern decisions made during the session. Agents append to it; the orchestrator and reviewer read it.

## Checkpoint Protocol

After every phase transition, write `.claude/loop/sessions/<name>/checkpoint.md`:

```markdown
# Checkpoint: <session-name>
Updated: <ISO timestamp>

## Position
- Phase: <current phase>
- Cycle: <N> / <max>
- Step: <current step within phase>

## Phases Completed
- [x] challenge (or skipped)
- [x] specify
- [ ] explore
- [ ] build
- [ ] review

## Agents Completed
<list of agents that finished with pass/fail>

## Key Decisions
<important choices made during the session — tech stack, architecture, scope changes>

## Next Action
<what the orchestrator should do next if resuming>
```

Also update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=<phase> status=<status>`

After each checkpoint, log a trace event:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> checkpoint orchestrator <phase> <cycle> "Phase transition to <phase>"
```

## Cost Tracking Protocol

After every agent dispatch completes:
1. Append a row to `cost-ledger.md` with timestamp, agent name, phase, and estimated tokens.
2. Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh tokens_used=<cumulative>`
3. If `--max-tokens` was set and cumulative exceeds the budget: present AskUserQuestion with options "Continue (budget is advisory)", "Cancel loop".

## Learning Consultation (Phase 4 Step 0)

Before dispatching builders, consult the adaptive learning system:

### Step 0a: Pattern Store
1. Read `${CLAUDE_PLUGIN_ROOT}/learning/patterns.yaml`.
2. Filter patterns by: project type (opnet/generic), tech stack match, and category (contract/frontend/backend).
3. For each matching pattern, include its `description` and `fix` in the relevant agent's dispatch prompt.
4. Patterns with `promoted_to_knowledge: true` are already in knowledge slices — no need to duplicate.

### Step 0b: Agent Performance Scores + Routing Preparation
1. Read `${CLAUDE_PLUGIN_ROOT}/learning/agent-scores.yaml`.
2. For each agent to be dispatched, check:
   - If `sessions_completed >= 5`: include success rate, strengths, and weaknesses in the dispatch prompt.
   - If `success_rate < 0.5` and `sessions_completed >= 5`: suggest model upgrade to user ("frontend-dev has a 40% success rate on Sonnet — consider using `--builder-model opus`").
3. Agent scores are informational — do not auto-switch models without user approval.
4. Note agent strengths and weaknesses for use in finding routing (Phase 5). The `route-finding.sh` script will use these to make smarter routing decisions when the reviewer returns findings.

### Step 0c: Retrospectives (existing)
1. List all `.md` files in `${CLAUDE_PLUGIN_ROOT}/learning/` directory.
2. If any exist, read their "What Worked" and "Anti-Patterns" sections.
3. If a retrospective matches the current project type or tech stack, incorporate its lessons into agent prompts.

### Step 0d: Starter Templates
1. Check `${CLAUDE_PLUGIN_ROOT}/templates/starters/` for directories matching the project type.
2. If a matching template exists (e.g., `op20-token/` for an OP-20 project):
   - Read `template.yaml` to understand customization points.
   - Include the template path in the agent dispatch prompt with instruction: "Clone from this template and customize according to the spec. Do NOT modify the template files themselves."
3. This is advisory — agents may choose to build from scratch if the template doesn't fit.

### Step 0e: Project-Type Profiles
1. Check `${CLAUDE_PLUGIN_ROOT}/learning/profiles/` for a YAML file matching the detected project type.
2. If a matching profile exists (e.g., `op20-token.yaml`):
   - Read the profile and extract `common_pitfalls` and `recommended_config`.
   - Include common pitfalls in ALL agent dispatch prompts as "Known pitfalls for this project type."
   - If the profile recommends a builder model different from the current setting, mention it to the user (advisory only).
   - If `skip_challenge_gates` is non-empty, note these for Phase 1 (the orchestrator already offered to skip during challenge).
3. Profile data is advisory — do not auto-apply recommended config without user approval.

All steps are advisory — do not block on missing data.

---

## PHASE 1: CHALLENGE

**Goal:** Turn a vague idea into a concrete, challenged set of requirements.

Update state: `current_phase: challenge`, `status: challenging`

### Profile Pre-Check

Before running the gates, check for an existing project-type profile:
1. If the idea text mentions a known project type (e.g., "OP-20", "token", "NFT", "marketplace"):
   - Check `${CLAUDE_PLUGIN_ROOT}/learning/profiles/` for a matching profile YAML.
   - If found with `sessions_count >= 5`:
     - Present: "Based on [N] previous [type] builds, here are the common pitfalls: [list from common_pitfalls]."
     - Present: "The profile suggests skipping these challenge gates: [skip_challenge_gates]."
     - Ask: "Want to use this profile and skip to spec, or run the full challenge?"
     - Options: "Use profile, skip to spec" / "Use profile pitfalls but run full challenge" / "Ignore profile"
   - If the user chooses to skip: jump to Phase 2 with the profile's pitfalls pre-loaded.
2. If no matching profile exists, proceed with the full challenge.

### Gate Classification

Gates are classified as SOFT or HARD:
- **SOFT gates (1-4):** Goal Alignment, Build vs Buy, Simplest Thing, Problem Not Solution. When `--skip-challenge` is set, these are SKIPPED (logged to trace as "skipped via --skip-challenge").
- **HARD gates (5-6):** Testability, OPNet Classification. These ALWAYS run, even when `--skip-challenge` is set. If a hard gate fails, the loop STOPS regardless of any skip flag.

When `--skip-challenge` is set:
1. Log each skipped soft gate: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> checkpoint orchestrator challenge <cycle> "Skipped soft gate N via --skip-challenge"`
2. Run hard gates (5-6) normally — user must answer.
3. If a hard gate fails and the user does not override, STOP the loop.

### Round 1: The Five Gates

Run these gates in order using AskUserQuestion. If any gate fails, explain why and give the user the choice to override or stop.

**Gate 1 — Goal Alignment (SOFT):**
Ask: "Which active priority or goal does this advance? If it doesn't connect to anything you're currently focused on, it might be a distraction."
- Present known priorities if available from CLAUDE.md or context.
- If user says "none" → warn but allow override.

**Gate 2 — Build vs Buy (SOFT):**
While asking the next question, launch a `loop-researcher` agent in the background to search for existing solutions:
- Give the researcher the raw idea text.
- It will search the web for existing tools, libraries, or services that cover 80%+ of the need.

Ask: "Before we build, let me check if something already exists that does this."
- When researcher returns, present findings.
- If 80%+ coverage found → recommend using the existing solution. User can override.

**Gate 3 — Simplest Thing (SOFT):**
Ask: "What's the absolute minimum version of this that delivers value? Describe the smallest thing that closes the loop."

**Gate 4 — Problem, Not Solution (SOFT):**
Ask: "What problem does this solve? Not what feature you want — what pain are you addressing, and who feels it?"

**Gate 5 — Testability (HARD):**
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

### Gate 6 — OPNet Classification (HARD — if Bitcoin/OPNet detected):
Ask: "Is this a contract, frontend, backend, or full-stack project? What network (mainnet/testnet/regtest)? What token standard if applicable (OP20/OP721/custom)?"
- This determines which agents are spawned in Phase 4
- Record the answers for the orchestrator

### Save Challenge Output

Write the full Q&A to `.claude/loop/sessions/<name>/challenge.md`. This is the raw material for Phase 2.

**Checkpoint:** Write checkpoint.md with phases_completed=[challenge], next_action="generate spec".

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

### Chain Probe (OPNet projects only)

If this is an OPNet project (detected from challenge answers mentioning OPNet/OP-20/OP-721/contract, or `package.json` containing `@btc-vision/` or `opnet` dependencies):

1. Run the chain probe before finalizing the spec:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/chain-probe.sh .claude/loop/sessions/<name>/artifacts [rpc-url]
   ```
2. Read the resulting `artifacts/chain-state.json`.
3. If `probe_status` is `"success"`:
   - Include `block_height` and `gas_parameters` in `design.md` under a "Deployment Constraints" section.
   - Reference the chain state in the spec context for gas estimation and network selection.
4. If `probe_status` is `"failed"`:
   - Log the failure but do NOT block spec generation.
   - Note in design.md: "Chain probe failed -- gas parameters should be fetched at deployment time."

### Generate Acceptance Tests

After `tasks.md` is generated, extract acceptance criteria and generate test stubs:

1. Read `requirements.md` and extract every acceptance criterion from each user story.
2. For each criterion, generate a shell-script test stub in `artifacts/acceptance-tests/`:
   - File naming: `test-{story-number}-{criterion-slug}.sh`
   - Use the existing `pass()`/`fail()`/`check()` helper convention.
   - Each test should contain: setup, action, assertion, and a clear description.
   - Tests can start as stubs (with `echo "TODO: implement"` and a `fail` call) to be filled in by builders.
3. Generate an `artifacts/acceptance-tests/run-all.sh` that sources each test file.
4. Include the generated acceptance tests in the Human Approval Gate below -- the user must review and approve these tests alongside the spec documents.

Example acceptance test stub:
```bash
#!/bin/bash
# Test: US-1 Acceptance Criterion 1
# When [action], then [expected outcome]

DESCRIPTION="[user story]: [criterion description]"

# TODO: Implement test logic
# check "$DESCRIPTION" [test command]
fail "$DESCRIPTION -- not yet implemented"
```

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
- Approve as-is → proceed to Phase 2B (if OPNet contract) or Phase 3
- Request changes → edit the documents and re-present
- Cancel → stop the loop

---

### Phase 2B: Formal Specification (TLA+)

**Condition:** Only runs when the project includes a contract component (detected from spec or challenge answers). Skip for frontend-only or generic projects.

After requirements.md is generated and approved by the user:

1. Ensure TLA+ tooling is available: `bash scripts/setup-tla.sh`
2. Dispatch `spec-writer` agent (max_turns: 15) with `spec/requirements.md` as input
3. Agent generates `artifacts/spec/<ContractName>.tla` and `artifacts/spec/<ContractName>.cfg`
4. Run `bash scripts/run-spec-loop.sh artifacts/spec/<ContractName>.tla 5`
5. If loop exits 0 (clean): proceed to Phase 3. Log: "Spec verified: N states checked, 0 violations"
6. If loop exits 2 (violations found, iteration limit not reached):
   - Read `artifacts/spec/repair-signal.json`
   - Re-dispatch `spec-writer` with the violations file as explicit context
   - Repeat from step 4
7. If loop exits 1 (max iterations reached without clean spec):
   - BLOCK Phase 3 entirely
   - Report to user: "Specification could not be verified after 5 iterations. Design-level conflict detected. Requires human review."
   - Dump `artifacts/spec/loop-log.md` for diagnosis
   - Do NOT proceed to codegen on a failed spec

**What the spec-writer does with violation feedback:**
Agent receives: the original spec + the TLC counterexample trace + the violated invariant name.
Agent must: identify which invariant is violated, trace through the counterexample to find the logical error in the design, fix the spec (not just add ASSUME statements to suppress the check), and explain the fix in a comment.

FORBIDDEN: removing invariants to make TLC pass. Every invariant in the initial spec must survive to the final verified spec.

**Checkpoint:** Write checkpoint.md with phases_completed=[challenge, specify], next_action="explore codebase".

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

**Checkpoint:** Write checkpoint.md with phases_completed=[challenge, specify, explore], next_action="build with agents".

Log cost for each explorer agent to cost-ledger.md.

---

## PHASE 4: BUILD — Multi-Agent Orchestration

**Goal:** Implement the spec using specialized agents, each scoped to their domain.

Update state: `current_phase: build`, `status: building`, `cycle: 1`

### Step 0: Project Type Detection + Learning Consultation

**Learning check:** Before detection, scan `${CLAUDE_PLUGIN_ROOT}/learning/` for past retrospectives. If any match the project type or tech stack detected below, note their lessons for agent prompts.

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
Step 4: opnet-e2e-tester → REAL on-chain tests against deployed contract (MANDATORY)
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
Step 5: opnet-e2e-tester → REAL on-chain tests (MANDATORY before declaring ready)
Step 6: opnet-ui-tester → smoke + Playwright E2E tests (needs deployed address)
```

**CRITICAL RULE: On-chain E2E testing (opnet-e2e-tester) is NEVER skipped for projects that deploy contracts. The user should NEVER have to manually test contract interactions. The agent does ALL testing — read methods, write methods, payable methods, multi-wallet flows — using real testnet transactions with real block confirmations.**

Write the execution plan to the state file.

### Step 2: Execute the Plan

**Dry-Run Check:** If `--dry-run` flag is set, do NOT dispatch any agents. Instead, print the execution plan:

```
DRY RUN: Execution Plan
========================
The following agents WOULD be dispatched:

Step 1: [agent-name]
  Knowledge: [slice path]
  Tasks: [task summary]
  max_turns: [N]

Step 2: [agent-name]
  Knowledge: [slice path]
  Tasks: [task summary]
  max_turns: [N]
  Parallel with: [other agent, if applicable]

...

Total agents: [N]
Estimated max_turns: [sum]
```

Then stop. Do not proceed to agent dispatch or any subsequent phase.

**Normal Execution:** For each step in the execution plan, the orchestrator:

1. **Validates preconditions** -- check that required artifacts exist from previous steps
2. **Traces the dispatch** -- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> dispatch <agent-name> build <cycle> "Starting <agent-name>"`
3. **Spawns the agent** -- launch with Agent tool, providing spec, context, and artifact paths
4. **Traces completion** -- `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> complete <agent-name> build <cycle> "<outcome summary>"`
5. **Checks results** -- validate output artifacts after agent completes
6. **Routes failures** -- if an agent fails, determine if it can retry or needs upstream fix

#### Agent Dispatch Template

For each agent in the plan, construct the prompt and pass the appropriate `max_turns`:

| Agent Type | max_turns |
|-----------|-----------|
| Builders (contract-dev, frontend-dev, backend-dev, loop-builder) | 30 |
| Auditors (opnet-auditor) | 20 |
| Adversarial Auditors (opnet-adversarial-auditor) | 20 |
| Deployers (opnet-deployer) | 15 |
| E2E Testers (opnet-e2e-tester) | 25 |
| Adversarial E2E Testers (opnet-adversarial-tester) | 25 |
| UI Testers (opnet-ui-tester) | 20 |
| Reviewers (loop-reviewer) | 15 |
| Reviewers in critique mode (loop-reviewer) | 10 |
| Explorers (loop-explorer) | 15 |
| Researchers (loop-researcher) | 10 |
| Spec Writers (spec-writer) | 15 |

**Check elapsed time** before each agent dispatch. Read `started_at` and `max_duration` from state. If elapsed >= max_duration, checkpoint and stop.

Prompt template:

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
Load your knowledge payload FIRST: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh [agent-name] [project-type]`
This assembles your domain slice from knowledge/slices/[agent-slice].md, troubleshooting guide, relevant bible sections, and learned patterns.

## Problem-Solving Discipline
Read the PUA methodology: ${CLAUDE_PLUGIN_ROOT}/skills/pua/SKILL.md — this governs your debugging, escalation, and proactivity standards.

## Lessons from Past Sessions
[Include relevant lessons from learning/ retrospectives, if any]

## Output
Write your artifacts to: .claude/loop/sessions/[name]/artifacts/[domain]/
```

**Cross-Agent Critique (after each builder completes):**

After each builder agent completes, route its output to a different agent for critique mode review. This replaces self-critique with independent verification.

Critique routing table:
| Builder | Critique Agent |
|---------|---------------|
| `opnet-contract-dev` | `loop-reviewer` (critique mode) |
| `opnet-frontend-dev` | `opnet-backend-dev` (if present) OR `loop-reviewer` (critique mode) |
| `opnet-backend-dev` | `opnet-frontend-dev` (if present) OR `loop-reviewer` (critique mode) |
| `loop-builder` | `loop-reviewer` (critique mode) |

Critique dispatch:
1. After builder completes, dispatch the critique agent with: builder's output artifacts, spec documents, and instruction "Review in critique mode."
2. Critique agent writes `artifacts/cross-critique.md`.
3. If critique finds CRITICAL findings: route them back to the original builder for fixes before proceeding.
4. If critique finds only MINOR/NITS: proceed to next step (findings are logged for the reviewer).
5. Max critique-fix cycles per builder: 1 (to prevent infinite loops).

**After each agent completes:** Log to cost-ledger.md, update tokens_used in state.

**If an agent fails:**
1. Retry once, including the error output in the retry prompt.
2. Log a trace event: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> error <agent-name> build <cycle> "Agent failed after retry"`
3. If retry also fails, run the **Structured Repair Phases** (Agentless Pattern):

   **Phase R1 -- LOCALIZE** (max_turns: 5, READ-ONLY):
   Run failure localization on the agent's error output:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/localize-failure.sh <failure-log-path>
   ```
   This produces `artifacts/localization.json` with: file, function, line_range, suspected_cause, confidence, failure_category. The reviewer is dispatched in **localize mode** (see loop-reviewer.md Localize Mode). Output is localization.json only -- NO code generation.

   **Phase R2 -- PATCH** (max_turns: 10):
   Dispatch the domain agent (the one that failed) with ONLY the localized context:
   - The localization.json file
   - The specific file and line range identified
   - Instruction: "Generate up to 3 candidate patches for the issue at {file}:{line_range}. Each patch should be a minimal fix addressing: {suspected_cause}."
   The agent produces up to 3 candidate patches in `artifacts/repair/patch-1.diff`, `patch-2.diff`, `patch-3.diff`.

   **Phase R3 -- VALIDATE** (automated):
   For each candidate patch:
   1. Apply the patch to a temp copy
   2. Run the full test suite
   3. If contract: run mutation testing
   4. Score the result: tests passing + mutation score
   Pick the best-scoring patch and apply it. If no patch passes tests, fall through to the manual options below.

4. If R1/R2/R3 produced a working fix, continue the loop. Otherwise, check for a known fix pattern:
   ```bash
   PATTERN_MATCH=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/query-pattern.sh "<failure-category>" "<keywords>" 2>/dev/null || true)
   ```
5. If a pattern match is found (`PATTERN_MATCH` is non-empty), present AskUserQuestion with 5 numbered options:
   - "Apply known fix: [description from pattern match]"
   - "Retry with a different approach"
   - "Skip this agent and continue"
   - "Amend the spec to work around this"
   - "Cancel the loop"
   If the user selects "Apply known fix", apply the fix from the pattern, log a replan trace event, and retry the agent.
6. If no pattern match is found, present AskUserQuestion with 4 numbered options:
   - "Retry with a different approach"
   - "Skip this agent and continue"
   - "Amend the spec to work around this"
   - "Cancel the loop"
7. Never ask open-ended questions like "what should I do?"

#### Step 2a: Contract Development (if components.contract = true)

Launch `opnet-contract-dev` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-contract-dev <project-type>` (loads contract-dev.md slice + bible + troubleshooting + patterns)
- Working directory: `[WORKTREE]/contracts/` or `[WORKTREE]/src/`
- Output: ABI JSON to `artifacts/contract/abi.json`, build result to `artifacts/contract/build-result.json`

**Validation after completion:**
- `artifacts/contract/build-result.json` must have `"status": "success"`
- ABI JSON must exist and be valid JSON
- If failed: retry once, then report failure and stop

**ABI Lock Checkpoint:**
After contract-dev completes successfully:
1. Compute the ABI hash: `ABI_HASH=$(shasum -a 256 artifacts/contract/abi.json | awk '{print $1}')`
2. Store via write-state.sh: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh abi_hash=$ABI_HASH abi_locked=true`
3. Log: "ABI locked with hash: $ABI_HASH"

This hash is verified before frontend/backend dispatch to detect unauthorized ABI modifications.

**Generate Repo Map (after ABI lock):**
After contract-dev completes and ABI is locked, generate the hierarchical repo map:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-repo-map.sh artifacts/contract/abi.json "" ""
```
This creates `artifacts/repo-map.md` with the Contract Layer populated from the ABI. Frontend and Backend layers will be populated after those agents complete. All domain agents reference this map for cross-layer awareness.

#### Issue Check: Post-Contract (CONDITIONAL)

**Only runs when `components.count >= 2` (multi-component build). Single-component builds skip this.**

After contract-dev completes, scan `artifacts/issues/` for new open issues:

```
1. Read all files in artifacts/issues/ with frontmatter status: open
2. For each issue:
   a. Parse the "to" field to identify the target agent
   b. Check redispatch_count["{from}->{to}"] in state
   c. If count >= 2: log "Re-dispatch limit reached for {from}->{to}, deferring to auditor"
   d. If count < 2: increment count, dispatch target agent with the issue file as input context
3. After re-dispatch completes, check for new issues (bounded by the 2-cycle limit)
4. Update state via write-state.sh with new redispatch_count values
```

If issues were found and resolved, continue to Step 2b. If issues are deferred, they'll be caught by the auditor in Step 2c.

#### ABI Lock Verification (before Step 2b)

Before dispatching frontend or backend agents, verify the ABI has not been modified:
1. Read `abi_locked` and `abi_hash` from state.
2. If `abi_locked` is `true`:
   - Compute current hash: `CURRENT_HASH=$(shasum -a 256 artifacts/contract/abi.json | awk '{print $1}')`
   - Compare with stored `abi_hash`.
   - If mismatch: **BLOCK** frontend/backend dispatch. Log "ABI MISMATCH: expected $abi_hash, got $CURRENT_HASH". Re-dispatch `opnet-contract-dev` to investigate.
   - If match: proceed normally.

#### Step 2b: Frontend + Backend Development (parallel, after ABI ready)

**Frontend** — Launch `opnet-frontend-dev` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-frontend-dev <project-type>` (loads frontend-dev.md slice + bible + troubleshooting + patterns)
- Import: ABI from `artifacts/contract/abi.json`
- Working directory: `[WORKTREE]/frontend/`
- Output: `artifacts/frontend/build-result.json`

**Backend** (if components.backend = true) — Launch `opnet-backend-dev` agent in parallel:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-backend-dev <project-type>` (loads backend-dev.md slice + bible + troubleshooting + patterns)
- Import: ABI from `artifacts/contract/abi.json`
- Working directory: `[WORKTREE]/backend/`
- Output: `artifacts/backend/build-result.json`

**Validation after completion:**
- Both `build-result.json` files must have `"status": "success"`
- If either fails: retry once, then report failure and stop

#### Issue Check: Post-Frontend/Backend (CONDITIONAL)

**Only runs when `components.count >= 2` (multi-component build). Single-component builds skip this.**

After frontend-dev and/or backend-dev complete, scan `artifacts/issues/` for new open issues:

```
1. Read all files in artifacts/issues/ with frontmatter status: open
2. For each issue:
   a. Parse the "to" field to identify the target agent
   b. Check redispatch_count["{from}->{to}"] in state
   c. If count >= 2: log "Re-dispatch limit reached, deferring to auditor"
   d. If count < 2: increment count, dispatch target agent with the issue file as input
3. After re-dispatch, check for new issues (bounded by 2-cycle limit)
4. Update state via write-state.sh with new redispatch_count values
```

Common issue flows at this stage:
- frontend-dev → contract-dev: ABI_MISMATCH, MISSING_METHOD (frontend tried to call a method that doesn't exist or has wrong params)
- backend-dev → contract-dev: TYPE_MISMATCH, ABI_MISMATCH
- frontend-dev → backend-dev: NETWORK_CONFIG, ADDRESS_FORMAT

If the same agent pair has already been re-dispatched twice, defer to the auditor — it will catch remaining issues.

#### Step 2b.5: Cross-Layer Validation (CONDITIONAL — multi-component builds only)

**Only runs when `components.count >= 2` (multi-component build). Single-component builds skip this.**

Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=validating status=validating`

Launch `cross-layer-validator` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh cross-layer-validator <project-type>` (loads cross-layer-validation.md slice + troubleshooting + patterns)
- Import: ABI from `artifacts/contract/abi.json`
- Scope: ALL frontend and backend source files
- Output: `artifacts/validation/cross-layer-report.md`
- `max_turns: 15`

**Decision after validation:**
- If MISMATCH findings exist: route each to the responsible builder agent (check the "Route to" field)
- After fixes: re-run cross-layer validator (max 2 cycles)
- WARNING findings are passed to the auditor as context in the next step
- PASS findings confirm correct integration

This step catches ABI mismatches, wrong method names, parameter type errors, contract address inconsistencies, and network config conflicts BEFORE the auditor runs — saving entire audit cycles.

**Regenerate Repo Map (after builders complete):**
After all builders and cross-layer validation are done, regenerate the repo map with all layers populated:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-repo-map.sh artifacts/contract/abi.json "[WORKTREE]/frontend" "[WORKTREE]/backend"
```
The updated `artifacts/repo-map.md` now has Contract, Frontend, and Backend layers plus cross-layer integrity checks. The auditor and reviewer reference this map for integration context.

#### Step 2c: Security Audit

**Incremental Audit (cycle >= 2):** If this is cycle 2 or later, construct the auditor prompt with incremental context:
1. Run `git diff` in the worktree to capture changes since the last audit.
2. Read the previous audit findings from `artifacts/audit/findings.md`.
3. Include both in the auditor prompt with the instruction: "Focus on the diff + blast radius. Verify previous findings resolved."
4. Log a trace event: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> dispatch opnet-auditor build <cycle> "Incremental audit: diff-based review"`

**Full Audit (cycle 1):** Standard full-codebase audit.

Launch `opnet-auditor` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-auditor <project-type>` (loads security-audit.md slice + bible + troubleshooting + patterns)
- Scope: ALL source files across all components (cycle 1) or diff + blast radius (cycle 2+)
- Import: Cross-layer validation report from `artifacts/validation/cross-layer-report.md` (if available -- pass WARNING findings as additional context)
- Import (cycle 2+): `git diff` output and previous `artifacts/audit/findings.md`
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

#### Step 2c.5: Adversarial Audit (after pattern audit, before deployment)

Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=adversarial_auditing status=adversarial_auditing`

**Fuzz Case Generation:** Before dispatching the adversarial auditor, generate boundary test cases:
```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/fuzz-contract.sh artifacts/contract/abi.json
```
This creates `artifacts/testing/fuzz-cases.json` with systematic boundary values for every method parameter.

Launch `opnet-adversarial-auditor` agent:
- Knowledge: Contract ABI from `artifacts/contract/abi.json`
- Import: Spec documents from `spec/` directory (for invariant extraction)
- Import: Contract source files
- Import: Fuzz cases from `artifacts/testing/fuzz-cases.json` (if generated)
- Output: `artifacts/audit/adversarial-findings.md`
- `max_turns: 20`

The adversarial auditor:
1. Reads requirements.md and extracts all invariants
2. Reads contract source code
3. For each invariant, constructs specific input sequences that could violate it
4. Produces structured findings with PASS/FAIL verdict per invariant

**Decision after adversarial audit:**
- If overall verdict is **PASS**: proceed to deployment (Step 2d)
- If overall verdict is **FAIL**:
  - Route FAIL findings to `opnet-contract-dev` for fixes
  - After fixes: re-run adversarial auditor (max 2 cycles)
  - If still FAIL after 2 cycles: report to user and stop
  - **FAIL verdict BLOCKS deployment. No exceptions.**

#### Step 2d: Deployment (after audit PASS)

**Testnet deployment is automatic. Mainnet requires user approval.**

For mainnet, present AskUserQuestion:
- "The audit passed. Deploy to mainnet? This uses real BTC for gas."
- Options: "Deploy to mainnet", "Deploy to testnet only", "Skip deployment"

Launch `opnet-deployer` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-deployer <project-type>` (loads deployment.md slice + bible + troubleshooting + patterns)
- Import: Compiled WASM from contract build
- Network: testnet (or mainnet if approved)
- Output: `artifacts/deployment/receipt.json`

**Validation after completion:**
- `receipt.json` must have `"status": "success"` and a valid `contractAddress`
- If failed: check error table in deployment knowledge, retry once

After successful deployment, update frontend config with the deployed contract address.

#### Step 2e: On-Chain E2E Testing (MANDATORY — after deployment)

**This step is NON-NEGOTIABLE. The stop-hook ENFORCES this gate — if deployment_address is set and e2e-results.json does not exist, the loop CANNOT proceed to review.**

Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=e2e_testing status=e2e_testing`

**Precondition checklist (ALL must pass before dispatching):**
- [ ] `artifacts/deployment/receipt.json` exists and has `"status": "success"`
- [ ] `deployment_address` is set in state (non-empty)
- [ ] `artifacts/contract/abi.json` exists and is valid JSON
- [ ] `artifacts/deployment/e2e-handoff.json` exists (written by deployer)
- [ ] At least one wallet .env file exists in the deploy directory, OR the handoff has `walletEnvPaths: {}`

If the handoff file is missing, read `receipt.json` directly and construct the E2E tester prompt manually. **Do NOT skip E2E testing because the handoff file is missing.**

Launch `opnet-e2e-tester` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-e2e-tester <project-type>` (loads e2e-testing.md slice + bible + troubleshooting + patterns)
- Import: Deployed contract address from `artifacts/deployment/e2e-handoff.json` (or `receipt.json`)
- Import: Contract ABI from `artifacts/contract/abi.json`
- Import: Spec documents (requirements.md, tasks.md) for expected behavior
- Import: Test wallet credentials from `walletEnvPaths` in handoff
- Output: `artifacts/testing/e2e-results.json`, `artifacts/testing/e2e-plan.md`

The E2E tester:
1. Inventories all public contract methods from the ABI
2. Writes test scripts that send REAL transactions on testnet
3. Tests every method: read-only, state-changing, AND payable
4. For multi-party flows (marketplace, swap, etc.): uses separate wallets for each role
5. Waits for block confirmations — broadcast alone is not a pass
6. Verifies final on-chain state matches expected values from the spec

**Why simulation is not enough:** The OPNet node provides `output.to` as bech32 in real transactions but ML-DSA hex in simulation. `output.scriptPublicKey` is null in real transactions. Contracts that only validate against simulation format will pass simulation but revert on-chain. This agent catches those bugs.

**Postcondition checklist (ALL must pass after agent completes):**
- [ ] `artifacts/testing/e2e-results.json` exists
- [ ] `e2e-results.json` has a `"status"` field (either `"pass"` or `"fail"`)
- [ ] If status is `"pass"`: all `tests.*.failed` counts are 0
- [ ] If status is `"fail"`: failure details include tx hashes and error descriptions

**Decision after E2E tests:**
- If all on-chain tests pass: proceed to UI testing (Step 2f)
- If on-chain tests fail:
  - Route contract failures to `opnet-contract-dev` for fixes
  - After fixes: re-deploy and re-run E2E tester
  - Max E2E test cycles: 2 (if still FAIL, report to user and stop)
  - NEVER skip on-chain E2E failures — they represent real bugs that burn BTC

**Human blocker check:** If E2E tests require funded test wallets that don't exist yet, surface this to the user ONCE with exact instructions (which address to fund, how many sats needed). This is the ONE thing the user may need to do. Everything else is automated.

#### Step 2e.5: Adversarial E2E Testing (after happy-path E2E, before UI testing)

Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=adversarial_testing status=adversarial_testing`

Launch `opnet-adversarial-tester` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-adversarial-tester <project-type>` (loads e2e-testing.md slice + bible + troubleshooting + patterns)
- Import: Contract ABI from `artifacts/contract/abi.json`
- Import: Deployed contract address from `artifacts/deployment/receipt.json`
- Import: Spec documents for expected behavior
- Import: Happy-path E2E results from `artifacts/testing/e2e-results.json`
- Output: `artifacts/testing/adversarial-e2e-results.json`
- `max_turns: 25`

The adversarial E2E tester sends REAL transactions targeting:
1. Boundary values (zero, max, exact-balance amounts)
2. Revert exploitation (missing prerequisites, expired params, double-calls)
3. Access control bypass (non-owner calls, contract-caller attacks)
4. Race conditions (conflicting parallel transactions, double-spend attempts)

**Decision after adversarial E2E tests:**
- If all tests match expectations: proceed to UI testing (Step 2f)
- If unexpected behavior found:
  - Route contract failures to `opnet-contract-dev` for fixes
  - After fixes: re-deploy and re-run adversarial tester
  - Max adversarial E2E test cycles: 2

#### Step 2f: UI Testing (after on-chain E2E passes)

Launch `opnet-ui-tester` agent:
- Knowledge: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/load-knowledge.sh opnet-ui-tester <project-type>` (loads ui-testing.md slice + troubleshooting + patterns)
- Import: Deployed contract address from `artifacts/deployment/receipt.json`
- Import: Frontend dev server port from `artifacts/frontend/build-result.json`
- Output: `artifacts/testing/ui-results.json`, `artifacts/testing/screenshots/`

**Decision after tests:**
- If all tests pass: proceed to commit + PR
- If tests fail:
  - Route UI failures to `opnet-frontend-dev` for fixes
  - After fixes: re-run UI tester
  - Max test cycles: 3 (increased from 2 — frontend bugs often take multiple fix cycles)

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

### Generic Build (for non-OPNet projects)

If `project_type = "generic"`, use dynamic agent generation:

#### Option A: Dynamic Domain Agents (if spec is complex enough)

1. **Determine required roles** from the spec: what domains are involved? (e.g., API, database, auth, frontend, testing)
2. **Check learning store** for past configs matching this tech stack.
3. **Generate domain agents** to the session's `agents/` directory using `${CLAUDE_PLUGIN_ROOT}/templates/domain-agent.md` as the template. Fill in:
   - Agent name and role
   - Domain-specific constraints
   - Relevant knowledge (from spec, codebase context, or generated knowledge slices)
4. **Optionally generate knowledge slices** to `sessions/<name>/knowledge/` using `${CLAUDE_PLUGIN_ROOT}/templates/knowledge-slice.md`.
5. **Show the user** the generated agent list and ask for approval before dispatching.
6. **Execute** using the same orchestration pattern as OPNet flow: ordered steps, validation, error handling.

#### Option B: Single Builder (for simple specs)

If the spec has fewer than 5 tasks and touches a single domain, fall back to the `loop-builder` agent with:
1. The three spec documents
2. The codebase context
3. The worktree path
4. Any reviewer findings from previous cycles
5. The project's CLAUDE.md if it exists
6. `max_turns: 30`

---

## PHASE 5: REVIEW

**Goal:** Audit the PR with a read-only reviewer.

Update state: `current_phase: review`, `status: reviewing`

### Mutation Gate (before reviewer dispatch)

If a contract was built in this session (`components.contract = true`), run mutation testing before the reviewer:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mutate-contract.sh <contract-src-path> <test-dir>
```

Read `artifacts/testing/mutation-score.json` and check the verdict:
- If `mutation_score < 0.70` (verdict: FAIL): DO NOT dispatch the reviewer. Instead, route back to `opnet-contract-dev` with the survivors list. Include: "Mutation testing failed: {killed}/{total} mutants killed (score: {mutation_score}). These mutations survived — your tests do not cover them: {survivors}. Add tests to kill these mutants before proceeding."
- If `mutation_score >= 0.70` (verdict: PASS): proceed to reviewer dispatch.
- If mutation-score.json does not exist or has errors: log a warning and proceed (do not block on mutation infrastructure issues).

### Reviewer Dispatch

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
  - Log a trace event for each finding: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> finding loop-reviewer review <cycle> "<finding summary>" --category <category>`
  - **Score-based routing (v3.6):** For each CRITICAL or MAJOR finding, use `route-finding.sh` to determine the best agent:
    ```bash
    bash ${CLAUDE_PLUGIN_ROOT}/scripts/route-finding.sh "<finding description>" "<candidate-agents>"
    ```
    The script returns `agent_name|confidence|reasoning`. If confidence >= 0.6, route to that agent. If confidence < 0.6 (keyword fallback), use the traditional category-based routing as a safety net.
  - Log a trace event for each routing decision: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/trace-event.sh <session-dir> route orchestrator review <cycle> "Routed finding to <agent> (confidence: <N>)"`
  - For OPNet projects: candidate agents are `opnet-contract-dev,opnet-frontend-dev,opnet-backend-dev`.
  - For generic projects: candidate agents are derived from the agents that were dispatched in this session.
  - After routing, write a categorized findings file to `artifacts/findings-categorized.md` for use by `update-scores.sh --findings` during wrap-up. Format per finding: `agent: <name> | category: <category> | outcome: pending`
  - **Structured Repair (v7.0):** When routing findings to agents, use the R1/R2/R3 repair phases instead of raw re-dispatch. Run `localize-failure.sh` on the failure context first (Phase R1), then dispatch the agent with localized context only (Phase R2), then validate candidate patches (Phase R3). This replaces "re-run agent with failure context" for more targeted repairs.
- If no (max cycles reached): update state to `failed`. Generate failure diagnosis and print remaining findings with the PR URL. The human takes over.

### Findings Ledger

After Phase 5 review completes (every cycle), parse the reviewer's findings and maintain a structured ledger:

1. Read the review output from `reviews/cycle-<N>.md`.
2. For each finding, assign a unique ID: `F-001`, `F-002`, etc. (incrementing across cycles).
3. Write or update `artifacts/findings-ledger.md` in this format:

```markdown
# Findings Ledger

| ID | Cycle Found | Cycle Resolved | Status | Finding | File | Agent |
|----|-------------|----------------|--------|---------|------|-------|
| F-001 | 1 | - | OPEN | [description] | [file:line] | [responsible agent] |
| F-002 | 1 | 2 | RESOLVED | [description] | [file:line] | [responsible agent] |
| F-003 | 2 | - | REGRESSION | [description] | [file:line] | [responsible agent] |
```

4. Status values: `OPEN` (new finding), `RESOLVED` (fixed in a later cycle), `REGRESSION` (was resolved but reappeared).
5. **3-cycle archiving rule**: For findings where `(current_cycle - cycle_found) > 3`, move them to an "Archived Findings" section at the bottom of the ledger. Archived findings are not checked for regression — they are historical records only.
6. For cycle 2+ reviewer dispatch: include the ledger in the prompt with instruction: "Check all RESOLVED findings for regression. Mark regressions as CRITICAL with [REGRESSION] tag."

### Goal-Oriented Build Scoring

After each review cycle (pass or fail), run the build scoring script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/score-build.sh
```

This evaluates 4 dimensions and writes `artifacts/evaluation/progress-tracker.yaml`:

| Dimension | Threshold | Route on Fail |
|-----------|-----------|---------------|
| spec_coverage | >= 90% | loop-reviewer (spec gaps) |
| security_delta | <= 0 | opnet-auditor (open findings) |
| mutation_score | >= 70% | opnet-contract-dev (untested paths) |
| code_health | >= 60% | responsible builder (quality issues) |

Display the compact score table in the review summary. ALL thresholds must be met for the build to be considered complete. Failed dimensions route to the responsible agent with specific remediation context.

If `spec-requirements.yaml` does not exist yet, run `extract-requirements.sh` first:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-requirements.sh <requirements-md-path>
```

### Structured Failure Diagnosis

When `cycle >= max_cycles` and the verdict is FAIL, generate `artifacts/failure-diagnosis.md`:

```markdown
# Failure Diagnosis

## Classification
[One of: spec_problem, implementation_problem, test_problem, infrastructure_problem]

## Evidence
- [Specific evidence supporting the classification]
- [Patterns across cycles that point to root cause]

## Unresolved Findings
[List all OPEN findings from the findings ledger]

## Cycle History
[Brief summary of what was attempted in each cycle and why it failed]

## Recommended Next Step
[Concrete recommendation: amend spec, manual fix at specific file:line, infrastructure change, etc.]
```

Classification guide:
- `spec_problem`: Requirements are contradictory, ambiguous, or impossible to implement as stated
- `implementation_problem`: Code bugs that agents couldn't fix within cycle budget
- `test_problem`: Tests are flawed or expectations don't match spec
- `infrastructure_problem`: Build toolchain, dependency, or environment issues

Include the failure diagnosis path in the summary output.

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

### On-Chain E2E Test Results
[Per-method pass/fail, tx hashes, block numbers, final state verification — or "skipped" if no deployment]
[Include explorer links for every on-chain test transaction]

### UI Test Results
[Pass/fail summary — or "skipped" if no frontend]

### Review Results
[Final verdict and any remaining findings]

### Files Modified
[List from the PR]

### Failure Diagnosis (if FAILED)
[Classification, evidence, and recommended next step from artifacts/failure-diagnosis.md]

### Findings Ledger Summary
[Open: N, Resolved: N, Regression: N — from artifacts/findings-ledger.md]

### Next Steps
[If PASSED: "PR is ready for human review and merge."]
[If FAILED: "These findings remain unresolved: ..." with the specific issues and the failure diagnosis]
```

---

## PHASE 6: WRAP-UP (Retrospective)

**Goal:** Capture lessons learned for future sessions.

This phase runs automatically after Phase 5 completes (whether PASS or FAIL).

### Generate Retrospective

Write a retrospective to TWO locations:

**1. Session copy:** `.claude/loop/sessions/<name>/retrospective.md`
**2. Learning store:** `${CLAUDE_PLUGIN_ROOT}/learning/<session-name>.md`

Format:

```markdown
# Retrospective: <session-name>
Date: <ISO timestamp>
Project Type: <opnet|generic>
Outcome: <PASS on cycle N | FAILED after N cycles>
Tokens Used: <from state>
Duration: <elapsed minutes>

## What Worked
- [Effective patterns, good agent configs, successful strategies]

## What Failed
- [Agents that struggled, approaches that didn't work, time sinks]

## Effective Agent Configs
- [Which agents were most/least useful, optimal dispatch order]

## Knowledge That Mattered
- [Which knowledge slices were critical, what was missing]

## Anti-Patterns
- [Things to avoid next time — specific to this project type/stack]

## Recommendations
- [Concrete suggestions for similar future projects]
```

### Update Adaptive Learning System

After writing the retrospective, update the pattern store and agent scores:

1. **Extract patterns** from the retrospective:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/extract-patterns.sh ${CLAUDE_PLUGIN_ROOT}/learning/<session-name>.md
   ```
   This reads anti-patterns and failures, appends them to `learning/patterns.yaml`, deduplicates, and auto-promotes patterns with 3+ occurrences to knowledge slices.

2. **Update agent scores** from the session state:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/update-scores.sh .claude/loop/state.yaml <pass|fail> --findings .claude/loop/sessions/<name>/artifacts/findings-categorized.md
   ```
   This reads agent_status from state, computes rolling metrics (success rate, avg cycles, tokens), and updates `learning/agent-scores.yaml`. When `--findings` is provided, it also parses finding categories and updates agent strengths/weaknesses arrays.

3. **Generate/update project-type profiles:**
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/generate-profiles.sh
   ```
   This scans all retrospectives, counts sessions per project type, and generates profile YAML files in `learning/profiles/` when session count crosses thresholds (5, 10, 20, 50). Profiles include common pitfalls, recommended config, and per-agent performance data.

All three scripts are idempotent — safe to re-run if interrupted.

### Final Checkpoint

Write final checkpoint.md with all phases completed and outcome.

Update state: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh current_phase=wrapped_up`
