# buidl — Multi-Agent OPNet Development Plugin for Claude Code

[![Plugin Tests](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml/badge.svg)](https://github.com/bc1plainview/buidl-opnet-plugin/actions/workflows/plugin-tests.yml)

A Claude Code plugin that turns a single prompt into a production-ready, audited OPNet Bitcoin L1 dApp. 7 specialized agents handle contract development, frontend, backend, security audit, deployment, UI testing, and code review — coordinated by an orchestrator that manages the full lifecycle.

Built on top of the `/buidl` dev loop (idea → challenge → spec → build → review → ship), extended with OPNet-specific agents, knowledge slices, and 27 real-bug audit patterns from the btc-vision repos.

## Setup

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Git

### Install

```bash
# Clone the repo
git clone https://github.com/bc1plainview/buidl-opnet-plugin.git

# Run Claude Code with the plugin loaded
claude --plugin-dir /path/to/buidl-opnet-plugin/buidl
```

### Shell Aliases

**Safe mode** (interactive approval on tool use — recommended for first-time use):

```bash
alias claudey="claude --plugin-dir /path/to/buidl-opnet-plugin/buidl"
```

**Autonomous mode** (skips permission prompts — for trusted local development):

```bash
alias claudeyproj="claude --dangerously-skip-permissions --plugin-dir /path/to/buidl-opnet-plugin/buidl"
```

> **Security note:** `--dangerously-skip-permissions` grants unrestricted file, network, and shell access. Agents can read/write any file, run any shell command, and make network requests without prompting. This includes access to credential files (`.env`, `~/.ssh`, `~/.aws`, `~/.config`), browser profiles, and the ability to make outbound network requests. Use this only in sandboxed or local development environments where you trust the codebase. Never use this flag on shared machines, CI runners with production secrets, or directories containing sensitive credentials.

Then start with:

```bash
claudey        # safe mode: approves each tool use
claudeyproj    # autonomous mode: agents run without prompts
```

Flags:
- `--plugin-dir` — loads the plugin directly without needing marketplace installation. All commands, agents, skills, and hooks are available immediately.
- `--dangerously-skip-permissions` — bypasses all tool permission prompts. Required for autonomous multi-agent loops where 10+ agents dispatch shell commands, file reads, and writes without human intervention. See security note above.

## Commands

| Command | What it does |
|---------|-------------|
| `/buidl "idea"` | Full pipeline: idea → challenge → spec → build → review → PR |
| `/buidl path/to/spec/` | Skip to build from an existing spec directory |
| `/buidl-spec "idea"` | Spec-only mode — refine idea into spec without building |
| `/buidl-review 42` | Review an existing PR with the loop reviewer |
| `/buidl-status` | Show current loop state |
| `/buidl-cancel` | Cancel a running loop |
| `/buidl-clean` | Cancel + remove worktree and branch |

## Agents

The orchestrator dispatches work to specialized agents based on what the project needs:

| Agent | Role | Model |
|-------|------|-------|
| `opnet-contract-dev` | AssemblyScript smart contracts (OP-20, OP-721, custom) | sonnet |
| `opnet-frontend-dev` | React + Vite frontends with WalletConnect v2 | sonnet |
| `opnet-backend-dev` | hyper-express backend services | sonnet |
| `opnet-auditor` | READ-ONLY security audit (27 real-bug patterns + full checklist) | sonnet |
| `opnet-deployer` | TransactionFactory deployment to testnet/mainnet | sonnet |
| `opnet-ui-tester` | Puppeteer smoke tests + E2E + screenshot capture | sonnet |
| `loop-reviewer` | PR review against spec + 27-pattern checklist | inherit |

Supporting agents (not OPNet-specific):

| Agent | Role |
|-------|------|
| `loop-builder` | General-purpose code implementation |
| `loop-explorer` | Codebase mapping and analysis |
| `loop-researcher` | Web search for existing solutions (build vs buy) |

## Knowledge System

The plugin includes a knowledge base split into domain-specific slices so each agent loads only what it needs:

```
knowledge/
├── opnet-bible.md              # Full OPNet reference (1975 lines)
├── opnet-troubleshooting.md    # Common errors + fixes
└── slices/
    ├── contract-dev.md         # Contract agent reads this
    ├── frontend-dev.md         # Frontend agent reads this
    ├── backend-dev.md          # Backend agent reads this
    ├── security-audit.md       # Auditor reads this (includes 27 real-bug patterns)
    ├── deployment.md           # Deployer reads this
    ├── ui-testing.md           # UI tester reads this
    ├── integration-review.md   # Reviewer reads this
    └── project-setup.md        # All agents reference this
```

## 27 Real-Bug Audit Patterns

The auditor and reviewer agents check for 27 confirmed vulnerability patterns extracted from real bugs in btc-vision GitHub repos (btc-runtime, native-swap, opnet, opnet-node, op-vm, transaction). Each pattern has a PAT-XX ID, severity, detection rule, fix, and PR reference.

**9 CRITICAL patterns** (can drain funds, corrupt consensus, enable replay attacks):

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

Full pattern documentation with code examples is in `knowledge/slices/security-audit.md`.

The standalone `audit-from-bugs` skill can also be triggered by asking Claude to "audit this OPNet code" or "run the real-bug pattern check" in any conversation where the plugin is loaded.

## How the Loop Works

```
/buidl "OP-20 token with staking rewards"
        │
        ▼
   Phase 1: CHALLENGE
   Five gates + spec questions + pre-mortem
        │
        ▼
   Phase 2: SPECIFY
   requirements.md + design.md + tasks.md
        │
        ▼
   Phase 3: EXPLORE
   Two explorer agents map the codebase in parallel
        │
        ▼
   Phase 4: BUILD (multi-agent)
   Orchestrator detects components, dispatches:
     ├── contract-dev  (first, produces ABI)
     ├── frontend-dev  (parallel with backend)
     ├── backend-dev   (parallel with frontend)
     ├── auditor       (after all builders finish)
     ├── deployer      (after audit passes)
     └── ui-tester     (after deploy)
        │
        ▼
   Phase 5: REVIEW
   Reviewer checks PR against spec + 27 patterns
        │
        ▼
   PASS → PR ready for human review
   FAIL → findings routed to responsible agent, loop continues
```

## Project Structure

```
buidl/
├── .claude-plugin/
│   └── plugin.json            # Plugin manifest
├── agents/                    # 10 agent definitions
├── commands/                  # 6 slash commands
├── hooks/                     # Stop hook for loop continuation
│   └── scripts/
├── knowledge/                 # OPNet reference docs + slices
│   └── slices/
├── scripts/                   # Setup script for loop sessions
└── skills/                    # 2 triggerable skills
    ├── audit-from-bugs/
    └── loop-guide/
```

## Testing

Run the structural validation suite locally:

```bash
bash tests/plugin-tests.sh
```

The test suite validates 117 invariants across 8 categories:

| Category | What it checks |
|----------|----------------|
| Shell syntax | `bash -n` on all scripts |
| Shell correctness | `sedi()` not recursive, no literal `\n` |
| Agent structure | 5 required sections in all 10 agents |
| FORBIDDEN blocks | Present in all 6 specialist agents |
| Knowledge refs | All slice paths in agents resolve to existing files |
| Issue bus schema | 7 issue types consistent across agents |
| Version consistency | `plugin.json` matches `CHANGELOG.md` |
| File existence | All required files present |

Tests run automatically on every push and PR via GitHub Actions.

## License

MIT
