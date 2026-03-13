# buidl — Multi-Agent Development Plugin for Claude Code

[![Plugin Tests](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml/badge.svg)](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml)

A Claude Code plugin that turns a single prompt into a production-ready, audited, deployed, and on-chain tested application. 12 specialized agents handle smart contract development, frontend, backend, security audit, cross-layer validation, deployment, real on-chain E2E testing, UI testing, and code review — coordinated by an orchestrator that manages the full lifecycle from idea to merged PR.

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

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--max-cycles N` | 3 | Maximum build-review cycles before stopping |
| `--max-retries N` | 5 | Maximum retries per agent |
| `--skip-challenge` | off | Skip the challenge phase, go straight to specifying |
| `--builder-model opus\|sonnet` | inherit | Override model for builder agents |
| `--reviewer-model opus\|sonnet` | inherit | Override model for reviewer agent |
| `--max-tokens N` | unlimited | Token budget with advisory enforcement |

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
| `opnet-ui-tester` | Playwright smoke + E2E + visual regression | Test results + screenshots |

### Core Loop Agents

| Agent | Role |
|-------|------|
| `loop-builder` | General-purpose code implementation (non-OPNet projects) |
| `loop-explorer` | Codebase structure mapping and relevance analysis |
| `loop-researcher` | Web search for existing solutions (build vs buy gate) |
| `loop-reviewer` | PR review against spec + pattern checklist |
| `cross-layer-validator` | READ-ONLY ABI-to-frontend/backend integration validation |

## Adaptive Learning System (v3.5)

The plugin learns from every session and gets smarter over time.

### Pattern Store (`learning/patterns.yaml`)
- Anti-patterns and failures from retrospectives are extracted into a structured YAML store
- Deduplicated by description similarity; occurrence counts tracked across sessions
- Patterns with 3+ occurrences auto-promote to relevant knowledge slices with `[LEARNED]` tags
- Grep-queryable by category, tech stack, failure type

### Agent Performance Scoring (`learning/agent-scores.yaml`)
- Rolling averages for success rate, cycles to pass, and tokens consumed per agent
- Per-model breakdowns (opus vs sonnet performance tracking)
- Scores require 5+ data points before surfacing in `/buidl-status`
- Orchestrator consults scores to inform agent dispatch order

### Cross-Layer Validator
- Validates ABI-to-frontend method mapping, parameter types, contract addresses, network config
- Runs after all builders but before the auditor — catches integration mismatches early
- 8 mismatch types with detection rules and routing decisions
- READ-ONLY agent (cannot modify files)

### Starter Templates (`templates/starters/`)
- Pre-built project scaffolds for common OPNet patterns (OP-20 token included)
- Template manifests with customization points (token name, symbol, decimals, features)
- Includes contract, tests, frontend, hooks, and build config
- Orchestrator detects matching templates and offers them during spec phase

## Enforcement Mechanisms

The plugin doesn't just tell agents what to do — it enforces compliance at the shell level:

### E2E Testing Hard Gate (v3.4)

The stop-hook physically blocks loop exit (exit code 2) when:
- An OPNet contract has been deployed (deployment_address exists in state)
- But no `e2e-results.json` exists in artifacts (tests haven't run)
- OR the E2E results have a non-pass status

The hook re-injects the E2E tester dispatch prompt automatically. There is no way to skip this gate except the wall-clock timeout.

### Frontend Self-Verification (v3.4)

Before the frontend-dev agent can declare success, it must pass three checks:

1. **Build pipeline** — `npm run lint` + `npm run typecheck` + `npm run build` (zero errors)
2. **Runtime smoke check** — starts Vite dev server, runs Playwright headless against localhost, verifies no console errors, dark background, visible content
3. **Pre-flight anti-pattern scan** — 10 grep-based checks against `src/`: Buffer usage, private key leaks, wrong network, forbidden `approve()`, spinners, emojis, hardcoded colors, missing meta tags, static feeRate, missing explorer links

### State Guards

- `guard-state.sh` (PreToolUse hook) blocks direct Write/Edit to state files during active loops
- `guard-state-bash.sh` blocks Bash redirects targeting state files
- All state mutations go through `scripts/write-state.sh` (temp file + atomic rename)

### PUA Pressure Escalation (v3.3)

When the build-review loop cycles, debugging requirements escalate:

| Cycle | Level | Requirement |
|-------|-------|------------|
| 1 | Normal | Standard build and verify |
| 2 | Elevated | 3 different hypotheses per issue, no repeating failed approaches |
| 3 | Mandatory Checklist | 7-Point Checklist for every finding, report completion |
| 4+ | Last Chance | Full checklist + consider completely different approach or structured failure report |

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
     +-- deployer      (after audit PASS)          max_turns: 15
     +-- e2e-tester    (HARD GATE after deploy)    max_turns: 25
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

### Cross-Layer Issue Resolution

When an agent discovers a problem in another layer (e.g., frontend-dev finds the contract ABI is missing a method), it writes a typed issue to `artifacts/issues/`. The orchestrator routes the issue to the responsible agent. Re-dispatch limit: 2 cycles per agent pair before deferring to the auditor.

Issue types: `ABI_MISMATCH`, `MISSING_METHOD`, `TYPE_MISMATCH`, `ADDRESS_FORMAT`, `NETWORK_CONFIG`, `DEPENDENCY_MISSING`.

### Interruption Recovery

If the loop is interrupted (context exhaustion, wall-clock timeout, manual cancel), run `/buidl-resume` to continue from the last checkpoint. Session state, worktree, and all artifacts are preserved.

## Resilience Features

| Feature | Version | Description |
|---------|---------|-------------|
| Atomic state writes | v3.0 | All mutations through write-state.sh (temp + mv). Guard hooks block direct writes. |
| Checkpointing | v3.0 | Every phase transition saves position. Resume from any point. |
| Wall-clock timeout | v3.0 | Configurable max duration (default 60 min). Graceful save on timeout. |
| Cost tracking | v3.0 | Token spend per agent in cost-ledger.md. Budget enforcement with --max-tokens. |
| Learning system | v3.0 | Retrospectives saved to learning/. Future sessions consult past lessons. |
| Adaptive learning | v3.5 | Pattern extraction, agent scoring, auto-promotion to knowledge slices. |
| Cross-layer validation | v3.5 | ABI-to-frontend/backend integration checking between build and audit. |
| Starter templates | v3.5 | Pre-built scaffolds for OP-20 tokens (more planned). |
| Dynamic agents | v3.0 | Non-OPNet projects generate domain agents from templates. |
| On-chain E2E testing | v3.2 | Real transactions with test wallets. Every method tested. Multi-wallet flows. |
| PUA methodology | v3.3 | Exhaustive problem-solving with anti-rationalization and pressure escalation. |
| GSD-2 debugging | v3.3 | Hypothesis-first debugging, one variable at a time, structured failure reports. |
| E2E hard gate | v3.4 | Shell-level enforcement: loop cannot exit until on-chain tests pass. |
| Frontend smoke check | v3.4 | Playwright runtime verification before declaring frontend success. |
| Pre-flight scan | v3.4 | 10 anti-pattern grep checks block completion on known bad patterns. |

## Project Structure

```
buidl/
+-- .claude-plugin/
|   +-- plugin.json              # Plugin manifest (v3.5.0)
+-- agents/                      # 12 agent definitions (incl. cross-layer-validator)
+-- commands/                    # 7 slash commands
+-- hooks/                       # Stop hook + state guards
|   +-- scripts/
+-- knowledge/                   # OPNet reference + domain slices
|   +-- slices/                  # 10 knowledge slices
+-- learning/                    # Patterns, agent scores, retrospectives
|   +-- patterns.yaml            # Structured pattern store (auto-updated)
|   +-- agent-scores.yaml        # Agent performance metrics (auto-updated)
+-- scripts/                     # Setup + atomic state writer + learning scripts
+-- skills/                      # 3 triggerable skills
|   +-- audit-from-bugs/
|   +-- loop-guide/
|   +-- pua/
+-- templates/                   # Domain agent, knowledge slice, starter templates
|   +-- starters/                # Project scaffolds (op20-token, more planned)
+-- tests/                       # 272 structural + integration tests
```

## Testing

```bash
bash tests/plugin-tests.sh
```

272 tests across 26 categories:

| Category | What it checks |
|----------|----------------|
| Shell syntax | `bash -n` on all 5 scripts |
| Shell correctness | write-state.sh usage, atomic patterns, no literal `\n` |
| Agent structure | 5 required sections in all 11 agents |
| FORBIDDEN blocks | Present in all 6 specialist agents |
| Knowledge refs | All slice paths resolve to existing files |
| Issue bus schema | 7 issue types consistent across 4 agents |
| Version consistency | plugin.json matches CHANGELOG first entry |
| File existence | All required files (agents, commands, scripts, knowledge, templates) |
| State guard | guard-state.sh + guard-state-bash.sh active phase coverage |
| Resume command | Dual state file support, checkpoint reference |
| Learning system | Directory structure, pruning, retrospective integration |
| Templates | Placeholder validation in domain-agent + knowledge-slice |
| Cost tracking | Ledger format, token budget enforcement |
| Wall-clock timeout | Cross-platform date handling, max_duration initialization |
| max_turns | Agent dispatch limits, structured error handling |
| Dual state files | state.yaml + state.local.md support across all commands |
| Integration tests | 10 real write-state.sh tests (full, partial, nested, error cases) |
| Transaction simulation | Knowledge slice existence and section coverage |
| Playwright E2E | Puppeteer banned, Playwright patterns in UI tester + knowledge |
| Auto-detect session | Existing session detection with resume/cancel options |
| Learning pruning | Cap at 20 retrospectives |
| Orphan worktrees | Detection in status, cleanup in clean |
| Guard-state-bash | Bash tool redirect blocking |
| Adaptive learning | Pattern store schema, extraction scripts, agent scores format |
| Cross-layer validator | Agent definition, knowledge slice, mismatch type coverage |
| Starter templates | Template manifest, contract template, frontend template, hook files |

Tests run automatically on every push and PR via GitHub Actions.

## License

MIT
