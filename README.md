# buidl — Multi-Agent Development Plugin for Claude Code

[![Plugin Tests](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml/badge.svg)](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml)

A Claude Code plugin that turns a single prompt into a production-ready, audited, deployed, and on-chain tested application. 14 specialized agents handle smart contract development, frontend, backend, security audit, adversarial invariant testing, cross-layer validation, deployment, real on-chain E2E testing, adversarial E2E testing, UI testing, and code review — coordinated by an orchestrator that manages the full lifecycle from idea to merged PR.

Built for OPNet (Bitcoin L1 smart contracts), but the core loop system works for any project. Non-OPNet projects get dynamic agent generation from templates.

## What It Does

Type `/buidl "OP-20 token with staking rewards"` and the plugin:

1. **Challenges your idea** — five gates (goal alignment, build vs buy, simplest thing, problem framing, testability) plus a pre-mortem
2. **Generates a spec** — requirements.md, design.md, tasks.md with acceptance tests
3. **Explores the codebase** — two parallel agents map structure and find relevant code
4. **Builds with specialists** — contract-dev writes the contract, frontend-dev builds the UI, backend-dev builds the API, all in parallel where possible
5. **Audits for security** — 27 real-bug patterns from btc-vision repos, plus a full checklist
6. **Deploys to testnet** — TransactionFactory deployment with gas estimation from live RPC
7. **Tests on-chain** — real transactions with real testnet BTC, every public method, multi-wallet flows
8. **Tests the UI** — Playwright headless browser, smoke tests, E2E with wallet mocking
9. **Reviews the PR** — spec compliance, security patterns, code quality
10. **Loops until passing** — reviewer findings get routed back to responsible agents, with escalating debugging pressure per cycle

The user's job is to approve the spec and merge the PR. Everything else is automated.

## Setup

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Git

### Install

```bash
git clone https://github.com/bc1plainview/buidl-opnet-plugin.git

# Run Claude Code with the plugin loaded
claude --plugin-dir /path/to/buidl-opnet-plugin/buidl
```

### Shell Aliases

**Safe mode** (interactive approval on tool use):

```bash
alias claudey="claude --plugin-dir /path/to/buidl-opnet-plugin/buidl"
```

**Autonomous mode** (skips permission prompts — for trusted local dev):

```bash
alias claudeyproj="claude --dangerously-skip-permissions --plugin-dir /path/to/buidl-opnet-plugin/buidl"
```

> **Security note:** `--dangerously-skip-permissions` grants unrestricted file, network, and shell access. Agents can read/write any file, run any shell command, and make network requests without prompting. Use only in sandboxed or local development environments where you trust the codebase. Never use on shared machines, CI runners with production secrets, or directories containing sensitive credentials.

## Commands

| Command | What it does |
|---------|-------------|
| `/buidl "idea"` | Full pipeline: idea > challenge > spec > build > review > PR |
| `/buidl path/to/spec/` | Skip to build from an existing spec directory |
| `/buidl-spec "idea"` | Spec-only mode: refine idea into spec without building |
| `/buidl-review 42` | Review an existing PR with the loop reviewer |
| `/buidl-status` | Show current loop state, tokens used, elapsed time, checkpoint |
| `/buidl-cancel` | Cancel a running loop (preserves worktree for manual work) |
| `/buidl-resume` | Resume an interrupted loop from last checkpoint |
| `/buidl-clean` | Cancel + remove worktree and branch |
| `/buidl-trace` | Show agent execution trace timeline for the current session |

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--max-cycles N` | 3 | Maximum build-review cycles before stopping |
| `--max-retries N` | 5 | Maximum retries per agent |
| `--skip-challenge` | off | Skip the challenge phase, go straight to specifying |
| `--builder-model opus\|sonnet` | inherit | Override model for builder agents |
| `--reviewer-model opus\|sonnet` | inherit | Override model for reviewer agent |
| `--max-tokens N` | unlimited | Token budget with advisory enforcement |
| `--dry-run` | off | Run Challenge + Specify + Explore, print execution plan, stop |

## Agents

### OPNet Specialists

| Agent | Role | What it produces |
|-------|------|-----------------|
| `opnet-contract-dev` | AssemblyScript smart contracts (OP-20, OP-721, custom) | Compiled WASM + ABI JSON |
| `opnet-frontend-dev` | React + Vite frontends with WalletConnect v2 | Build artifacts + smoke check pass |
| `opnet-backend-dev` | hyper-express API servers, WebSocket, MongoDB | Running server + API tests |
| `opnet-auditor` | READ-ONLY security audit against 27 real-bug patterns | Findings with PASS/FAIL verdict |
| `opnet-deployer` | TransactionFactory deployment to testnet/mainnet | Deployment receipt + E2E handoff file |
| `opnet-e2e-tester` | Real on-chain E2E tests with test wallets | Per-method pass/fail with tx hashes |
| `opnet-adversarial-auditor` | READ-ONLY invariant-based adversarial analysis | PASS/FAIL per invariant with attack sequences |
| `opnet-adversarial-tester` | Adversarial E2E tests (boundary, revert, access control, race) | Per-category pass/fail with tx hashes |
| `opnet-ui-tester` | Playwright smoke + E2E + visual regression | Test results + screenshots |

### Core Loop Agents

| Agent | Role |
|-------|------|
| `loop-builder` | General-purpose code implementation (non-OPNet projects) |
| `loop-explorer` | Codebase structure mapping and relevance analysis |
| `loop-researcher` | Web search for existing solutions (build vs buy gate) |
| `loop-reviewer` | PR review against spec + pattern checklist + critique mode |
| `cross-layer-validator` | READ-ONLY ABI-to-frontend/backend integration validation |

---

## Features

### Agent Intelligence

Agents don't just execute instructions — they self-correct, learn from past sessions, and adapt their behavior based on accumulated experience.

#### Cross-Agent Critique
After each builder agent completes, its output is routed to a different agent for independent critique. Contract-dev output goes to loop-reviewer, frontend-dev to backend-dev (or reviewer), backend-dev to frontend-dev (or reviewer), loop-builder to loop-reviewer. CRITICAL findings route back to the original builder. This replaces self-critique with independent verification, catching blind spots that self-review misses.

#### Adversarial Auditing
The adversarial auditor agent extracts invariants from requirements.md, reads contract source, and constructs specific input sequences (zero amounts, max values, access control bypass, arithmetic overflow) that could violate each invariant. FAIL verdict blocks deployment. This goes beyond pattern-matching to test whether stated guarantees actually hold.

#### Adversarial E2E Testing
After happy-path E2E tests pass, the adversarial E2E tester sends real on-chain transactions targeting boundary values, revert exploitation, access control bypass, and race conditions. Every test includes a tx hash for verification.

#### Acceptance Test Locking
During spec generation, acceptance criteria are extracted from requirements.md and turned into shell-script test stubs in `artifacts/acceptance-tests/`. These tests are approved by the user and LOCKED -- builder agents are FORBIDDEN from modifying them. The verify pipeline includes running these locked tests.

#### ABI-Lock Checkpoint
After contract-dev completes, the orchestrator computes a SHA-256 hash of abi.json and locks it in state. Before frontend/backend agents start, the hash is verified. Any mismatch blocks dispatch and triggers contract-dev re-investigation.

#### Findings Ledger
Every reviewer finding is assigned a unique ID and tracked in a structured ledger across cycles. The ledger tracks OPEN, RESOLVED, and REGRESSION statuses. Reviewers in cycle 2+ verify that previously resolved findings haven't regressed.

#### Incremental Audit
On cycle 2+, the auditor receives a `git diff` of changes since the last audit plus previous findings, instead of re-scanning the entire codebase. It focuses on the diff, checks blast radius of changes, and verifies previous findings are resolved. Cuts audit time significantly on fix cycles.

#### Dynamic Re-Planning
When an agent fails after retry, the orchestrator queries `learning/patterns.yaml` for known fix patterns matching the failure category. If a match is found, it presents a 5th option ("Apply known fix: [description]") alongside the standard 4 error-handling options. Lessons from past sessions are applied automatically instead of requiring manual intervention.

#### Execution Tracing
Every agent dispatch, completion, routing decision, and error is logged as a structured JSONL event to `artifacts/trace.jsonl`. The `/buidl-trace` command renders these events as a formatted timeline grouped by cycle — full observability into what happened, when, and why.

#### Dry-Run Mode
The `--dry-run` flag runs Challenge, Specify, and Explore phases normally, then prints the full execution plan (agents, knowledge slices, tasks, max_turns) without dispatching any agents. Preview what will happen before committing to a full build.

### Adaptive Learning

The plugin learns from every session and gets smarter over time. Three systems work together to turn past experience into better future performance.

#### Pattern Store (`learning/patterns.yaml`)
Anti-patterns and failures from retrospectives are extracted into a structured YAML store. Deduplicated by description similarity, with occurrence counts tracked across sessions. Patterns with 3+ occurrences auto-promote to relevant knowledge slices with `[LEARNED]` tags. Grep-queryable by category, tech stack, and failure type.

#### Agent Performance Scoring (`learning/agent-scores.yaml`)
Rolling averages for success rate, cycles to pass, and tokens consumed — tracked per agent and per model (opus vs sonnet). Per-agent strengths and weaknesses tracked by finding category. Scores require 5+ data points before surfacing. The orchestrator consults scores to make smarter routing and dispatch decisions.

#### Score-Based Finding Routing
Reviewer and auditor findings are routed to the agent most likely to fix them based on historical success rates. A 10-category taxonomy (css-styling, wallet-connect, contract-logic, abi-mismatch, network-config, deployment, testing, security, build-errors, backend-api) maps findings to agents via keyword matching against their strengths and weaknesses. Falls back to keyword routing when agents have fewer than 5 sessions of data.

#### Project-Type Profiles (`learning/profiles/`)
Auto-generated after 5+ completed sessions of the same project type. Profiles include common pitfalls pre-loaded from the pattern store, recommended agent config (model, max_cycles), and suggested challenge gates to skip. Regenerated at session thresholds (5, 10, 20, 50). The orchestrator loads matching profiles during both challenge and build phases.

### Enforcement

The plugin doesn't just tell agents what to do — it enforces compliance at the shell level. Instructions can be ignored; shell hooks cannot.

#### E2E Testing Hard Gate
The stop-hook physically blocks loop exit (exit code 2) when an OPNet contract has been deployed but no passing `e2e-results.json` exists. The hook re-injects the E2E tester dispatch prompt automatically. There is no way to skip this gate except the wall-clock timeout.

#### Frontend Self-Verification
Before the frontend-dev agent can declare success, it must pass three checks:
1. **Build pipeline** — `npm run lint` + `npm run typecheck` + `npm run build` (zero errors)
2. **Runtime smoke check** — starts Vite dev server, runs Playwright headless against localhost, verifies no console errors, dark background, visible content
3. **Pre-flight anti-pattern scan** — 10 grep-based checks against `src/`: Buffer usage, private key leaks, wrong network, forbidden `approve()`, spinners, emojis, hardcoded colors, missing meta tags, static feeRate, missing explorer links

#### State Guards
`guard-state.sh` (PreToolUse hook) blocks direct Write/Edit to state files during active loops. `guard-state-bash.sh` blocks Bash redirects targeting state files. All state mutations go through `scripts/write-state.sh` (temp file + atomic rename).

#### PUA Pressure Escalation
When the build-review loop cycles, debugging requirements escalate:

| Cycle | Level | Requirement |
|-------|-------|------------|
| 1 | Normal | Standard build and verify |
| 2 | Elevated | 3 different hypotheses per issue, no repeating failed approaches |
| 3 | Mandatory Checklist | 7-Point Checklist for every finding, report completion |
| 4+ | Last Chance | Full checklist + consider completely different approach or structured failure report |

### Cross-Layer Integration

#### Cross-Layer Validator
A READ-ONLY agent that validates ABI-to-frontend method mapping, parameter types, contract addresses, network config, signer configuration, and event names. Runs after all builders but before the auditor — catches integration mismatches early. 8 mismatch types with detection rules and routing decisions.

#### Issue Bus
When an agent discovers a problem in another layer (e.g., frontend-dev finds the contract ABI is missing a method), it writes a typed issue to `artifacts/issues/`. The orchestrator routes the issue to the responsible agent. Re-dispatch limit: 2 cycles per agent pair before deferring to the auditor.

Issue types: `ABI_MISMATCH`, `MISSING_METHOD`, `TYPE_MISMATCH`, `ADDRESS_FORMAT`, `NETWORK_CONFIG`, `DEPENDENCY_MISSING`.

### Resilience

#### Checkpointing and Resume
Every phase transition saves position to `checkpoint.md` with phases completed, agents finished, key decisions, and next action. If the loop is interrupted (context exhaustion, wall-clock timeout, manual cancel), run `/buidl-resume` to continue from the last checkpoint. Session state, worktree, and all artifacts are preserved.

#### Atomic State Management
All state mutations go through `scripts/write-state.sh`, which writes to a temp file then atomically renames. Guard hooks block direct writes. No raw `sed -i` on state files.

#### Cost Tracking
Token spend per agent logged to `cost-ledger.md`. Budget enforcement with `--max-tokens N`. The orchestrator checks elapsed time and token spend before each agent dispatch.

#### Starter Templates
Pre-built project scaffolds for common OPNet patterns (OP-20 token included). Template manifests with customization points (token name, symbol, decimals, features). Includes contract, tests, frontend, hooks, and build config. The orchestrator detects matching templates and offers them during the spec phase.

## Knowledge System

Each agent loads only the knowledge slice relevant to its domain:

```
knowledge/
+-- opnet-bible.md              # Full OPNet reference (2000+ lines)
+-- opnet-troubleshooting.md    # Common errors + fixes
+-- slices/
    +-- contract-dev.md         # Contract patterns, storage, events, testing
    +-- frontend-dev.md         # React patterns, wallet connect, 10 runtime error fixes
    +-- backend-dev.md          # hyper-express, threading, MongoDB, rate limiting
    +-- security-audit.md       # 27 real-bug patterns with code examples
    +-- deployment.md           # TransactionFactory, gas estimation, verification
    +-- e2e-testing.md          # On-chain testing, UTXO chaining, multi-wallet flows
    +-- ui-testing.md           # Playwright setup, visual regression, wallet mocking
    +-- transaction-simulation.md # Simulation patterns for all agent types
    +-- integration-review.md   # Cross-layer review patterns
    +-- cross-layer-validation.md # ABI-to-frontend/backend validation rules
    +-- project-setup.md        # OPNet project scaffolding
```

## 27 Real-Bug Audit Patterns

The auditor and reviewer check for 27 confirmed vulnerability patterns extracted from real bugs in btc-vision GitHub repos. Each pattern has a PAT-XX ID, severity, detection rule, fix, and PR reference.

**9 CRITICAL** (can drain funds, corrupt consensus, enable replay attacks):

| ID | Bug | Source |
|----|-----|--------|
| PAT-S1 | `value[0] as T` reads only low byte in generic deserialize | btc-runtime #137 |
| PAT-S2 | BytesReader reads at `offset+N` instead of `offset` | btc-runtime #57 |
| PAT-P1 | `${a}${b}` storage key without delimiter = collision | btc-runtime #61 |
| PAT-C1 | Signed approval without nonce = infinite replay | btc-runtime #60 |
| PAT-C3 | `decrypt()` returns ciphertext on failure = auth bypass | opnet-node #192 |
| PAT-A2 | AMM `T -= dT; B += dB` breaks k-invariant | native-swap #63 |
| PAT-A3 | Purge removes tokens but not proportional BTC | native-swap #51 |
| PAT-L1 | Provider activation after liquidity subtraction | native-swap #67 |
| PAT-G2 | Double `mutex.lock()` in async = deadlock | op-vm #77 |

**8 HIGH** | **7 MEDIUM** | **3 LOW** — full documentation with code examples in `knowledge/slices/security-audit.md`.

## Skills

| Skill | Trigger | What it does |
|-------|---------|-------------|
| `audit-from-bugs` | "audit this OPNet code" | Runs the 27-pattern security check standalone |
| `loop-guide` | "how does the loop work?" | Command reference and troubleshooting |
| `pua` | Auto-loaded by builder agents | Exhaustive problem-solving methodology with anti-rationalization |

## How the Loop Works

```
/buidl "OP-20 token with staking rewards"
        |
        v
   Phase 1: CHALLENGE
   Five gates + spec questions + pre-mortem + devil's advocate
        |  checkpoint
        v
   Phase 2: SPECIFY
   requirements.md + design.md + tasks.md
   Human approval gate (hard stop until user approves)
        |  checkpoint
        v
   Phase 3: EXPLORE
   Two explorer agents map the codebase in parallel
        |  checkpoint + cost log
        v
   Phase 4: BUILD (multi-agent orchestration)
   Orchestrator detects components, dispatches in order:
     +-- contract-dev  (first, produces ABI)       max_turns: 30
     +-- frontend-dev  (parallel with backend)     max_turns: 30
     +-- backend-dev   (parallel with frontend)    max_turns: 30
     +-- auditor       (after all builders)        max_turns: 20
     +-- adv-auditor   (after pattern audit)       max_turns: 20
     +-- deployer      (after audit PASS)          max_turns: 15
     +-- e2e-tester    (HARD GATE after deploy)    max_turns: 25
     +-- adv-e2e-tester (after happy-path E2E)     max_turns: 25
     +-- ui-tester     (after e2e PASS)            max_turns: 20
        |  checkpoint after each agent + cost log
        v
   Phase 5: REVIEW
   Reviewer checks PR against spec + 27 patterns
        |  checkpoint
        v
   Phase 6: WRAP-UP
   Retrospective saved to learning store
        |
        v
   PASS --> PR ready for human review and merge
   FAIL --> findings routed to responsible agents, loop continues
```

## Project Structure

```
buidl/
+-- .claude-plugin/
|   +-- plugin.json              # Plugin manifest (v5.0.0)
+-- agents/                      # 14 agent definitions (incl. adversarial auditor + tester)
+-- commands/                    # 9 slash commands (incl. buidl-trace)
+-- hooks/                       # Stop hook + state guards
|   +-- scripts/
+-- knowledge/                   # OPNet reference + domain slices
|   +-- slices/                  # 11 knowledge slices
+-- learning/                    # Patterns, agent scores, profiles, retrospectives
|   +-- patterns.yaml            # Structured pattern store (auto-updated)
|   +-- agent-scores.yaml        # Agent performance metrics (auto-updated)
|   +-- profiles/                # Auto-generated project-type profiles
+-- scripts/                     # Setup + state writer + learning + routing + tracing scripts
+-- skills/                      # 3 triggerable skills
|   +-- audit-from-bugs/
|   +-- loop-guide/
|   +-- pua/
+-- templates/                   # Domain agent, knowledge slice, starter templates
|   +-- starters/                # Project scaffolds (op20-token, more planned)
+-- tests/                       # 395+ structural + functional + integration tests
```

## Testing

```bash
bash tests/plugin-tests.sh
```

395+ tests across 50 categories covering shell syntax, agent structure, FORBIDDEN blocks, knowledge references, issue bus schema, version consistency, state guards, resume logic, learning system, templates, cost tracking, wall-clock timeout, max_turns, integration tests, transaction simulation, Playwright E2E, adaptive learning, cross-layer validation, starter templates, score-based routing, project-type profiles, cross-agent critique, incremental audit, dry-run mode, agent tracing, dynamic re-planning, acceptance test locking, ABI-lock, adversarial auditing, adversarial E2E testing, failure diagnosis, findings ledger, chain probe, hard gate enforcement, and regression tracking.

Tests run automatically on every push and PR via GitHub Actions.

---

## Version History

### v5.0.0 — Audit Hardening (2026-03-13)
Nine correctness, reliability, and coverage fixes from an external audit: **acceptance test locking** prevents builders from modifying verification criteria. **ABI-lock checkpoint** prevents frontend/backend drift. **Adversarial auditing** tests invariants with attack sequences. **Adversarial E2E testing** sends real edge-case transactions. **Failure diagnosis** classifies root causes when cycles are exhausted. **Findings ledger** tracks resolution and detects regressions. **Chain probe** fetches live gas parameters. **Cross-agent critique** replaces self-critique with independent verification. **Hard gate enforcement** ensures critical gates cannot be skipped.

### v4.0.0 — Agent Intelligence (2026-03-13)
Five features that close gaps in the agent intelligence loop: **incremental audit** avoids re-scanning unchanged code on fix cycles. **Dry-run mode** lets you preview the execution plan before committing. **Execution tracing** provides full observability into agent dispatch ordering. **Dynamic re-planning** applies lessons from past failures automatically.

### v3.6.0 — Smart Routing (2026-03-13)
**Score-based finding routing** means the plugin doesn't just track which agents succeed — it uses that data to route findings to the agent most likely to fix them. **Project-type profiles** mean the 6th OP-20 token build starts with knowledge of what went wrong in the first 5.

### v3.5.0 — Adaptive Learning (2026-03-13)
The plugin had a learning system that saved retrospectives but barely used them. This release adds a real feedback loop: **pattern extraction** and **agent scoring** turn every session's lessons into structured data injected into future agent prompts. **Cross-layer validation** catches the #1 source of wasted cycles (ABI mismatches) before they reach expensive downstream agents. **Starter templates** eliminate boilerplate for common project types.

### v3.4.0 — Hard Gates (2026-03-13)
Two persistent pain points solved with shell-level enforcement: (1) Agents would deploy contracts and declare success without testing them on-chain, despite "MANDATORY" in the orchestrator instructions. The **E2E testing hard gate** in the stop-hook now physically blocks exit until on-chain tests pass. (2) Frontend output consistently had runtime bugs that only surfaced during UI testing. The **runtime smoke check** and **pre-flight anti-pattern scan** catch these inside the frontend-dev agent itself.

### v3.3.0 — PUA Methodology (2026-03-13)
AI agents frequently give up too early on fixable problems. **PUA's structured escalation** and **GSD-2 debugging discipline** force agents to exhaust all options systematically before escalating. **Pressure escalation** in the stop-hook ensures debugging requirements become more rigorous as cycles progress, not more lenient.

### v3.2.0 — On-Chain E2E Testing (2026-03-07)
The Nexus marketplace C-02 bug proved that simulation-passing code can fail on-chain. The **E2E tester agent** sends real transactions with real testnet BTC, testing every public method with block confirmations. The user never has to manually test contract interactions again.

### v3.1.0 — Robustness (2026-03-04)
Bash tool guard, nested YAML support, auto-detect existing sessions, learning pruning, orphan worktree detection, transaction simulation knowledge, Playwright migration, and 10 real integration tests for write-state.sh.

### v3.0.0 — The Loop (2026-03-04)
Foundation release: atomic state management, state guard hooks, wall-clock timeout, checkpointing, resume command, cost tracking, learning system, retrospectives, dynamic agent generation, max_turns, structured error handling, and context pressure detection.

### v2.1.0 — Testing and CI (2026-03-03)
Structural test suite, GitHub Actions CI/CD, inter-agent issue bus, FORBIDDEN rules for all specialist agents, model selection flags, standalone audit skill, and loop-guide skill.

### v2.0.0 — Multi-Agent OPNet (2026-03-02)
Multi-agent orchestration for OPNet dApps (6 specialist agents), 27 real-bug audit patterns from btc-vision repos, knowledge slice system, and OPNet-specific stop-hook branching.

### v1.0.0 — Initial Release (2026-03-02)
Core loop system: challenge, specify, explore, build, review.

---

Full changelog with detailed Added/Changed/Why sections: [CHANGELOG.md](CHANGELOG.md)

## License

MIT
