# Changelog

## [3.2.0] - 2026-03-07

### Added
- **On-chain E2E tester agent** (`opnet-e2e-tester`): New agent that runs REAL on-chain transactions against deployed contracts using test wallets. Tests every public method — read-only, state-changing, and payable — with actual testnet BTC and block confirmations. Supports multi-wallet flows (seller/buyer, staker/claimer) and UTXO chaining.
- **E2E testing knowledge slice** (`knowledge/slices/e2e-testing.md`): Complete reference for on-chain E2E testing patterns, wallet setup, payable method testing, the `output.to` bech32 vs ML-DSA hex gotcha (INC-mmfi7bj9-da60c9), multi-party flow templates, and common failure table.
- **Mandatory E2E gate in orchestrator**: Step 2e in the build phase now runs `opnet-e2e-tester` BEFORE UI testing. Nothing is declared "ready" until real on-chain tests pass. This is non-negotiable for any project that deploys a contract.

### Changed
- **Execution plans updated**: All three plan templates (contract-only, frontend-only, full-stack) now include the E2E tester in the correct position after deployment.
- **Deployer agent**: Added Step 8 (E2E test handoff) — deployer now ensures receipt includes everything the E2E tester needs.
- **Agent dispatch table**: Added `opnet-e2e-tester` with `max_turns: 25`.
- **Summary output**: Includes on-chain E2E test results section with per-method pass/fail, tx hashes, and explorer links.
- **README**: Updated agent count (7 → 8), pipeline diagram, knowledge slice list. Description emphasizes "fully tested" and "user never has to manually test."
- **Knowledge README**: Added `e2e-testing.md` to the slice list and domain rules.

### Why
The Nexus marketplace C-02 bug proved that simulation-passing code can fail on-chain. The `output.to` field is ML-DSA hex during simulation but bech32 during real execution — invisible to every testing method except real on-chain transactions. This gap cost days of manual debugging. The E2E tester agent eliminates this class of bugs entirely. The user should never have to manually test contract interactions again.

## [3.1.0] - 2026-03-04

### Added
- **Bash tool guard**: `hooks/scripts/guard-state-bash.sh` -- closes the bypass where `echo > state.yaml` via Bash tool could circumvent Write/Edit guards. Exempts write-state.sh itself.
- **Nested YAML support**: `write-state.sh --nested key.path=value` uses Python for safe nested key updates (e.g., `agent_status.contract-dev=done`).
- **Auto-detect existing session**: `/buidl` now checks for active sessions before setup and offers resume/cancel/clean options.
- **Learning pruning**: `setup-loop.sh` caps learning store at 20 most recent retrospectives, auto-pruning old ones.
- **Orphan worktree detection**: `/buidl-status` flags worktrees with no active state. `/buidl-clean` offers to remove them.
- **Transaction simulation knowledge slice**: `knowledge/slices/transaction-simulation.md` -- covers getContract simulation, deployment simulation, regtest local dev loop, gas estimation, and frontend simulation patterns.
- **Playwright E2E testing**: Replaced Puppeteer with Playwright across UI tester agent and ui-testing knowledge slice. Added visual regression testing, fixtures with wallet mock injection, `playwright.config.ts` setup, and dogfooding guidance.
- **Integration tests**: 10 real integration tests for write-state.sh (full write, partial update, nested mode, error cases, atomicity).

### Changed
- `opnet-ui-tester.md`: Fully rewritten for Playwright. FORBIDDEN section now explicitly bans Puppeteer.
- `ui-testing.md`: Rewritten with Playwright patterns, visual regression, reduced-motion emulation, dogfooding section.
- `opnet-deployer.md`: Added Write/Edit tools, Step 2 simulation, references transaction-simulation.md.
- `opnet-frontend-dev.md`: References transaction-simulation.md for frontend simulation patterns.
- `opnet-auditor.md`: Fixed Rule 8 contradiction (read-only agent can't save files).
- Test suite expanded from 166 to 203 tests across 23 categories.

### Fixed
- Guard bypass via Bash tool (redirect operators targeting state files).
- `opnet-frontend-dev.md`: Replaced `contractCache.get(key)!` with proper null check (TypeScript Law violation).
- `loop-guide/SKILL.md`: Updated with all v3 features (was stale after v3.0.0 release).

## [3.0.0] - 2026-03-04

### Added
- **Atomic state management**: `scripts/write-state.sh` — all state mutations go through a single script that writes to a temp file then atomically renames. No more raw `sed -i` on state files.
- **State guard hook**: `hooks/scripts/guard-state.sh` — PreToolUse hook blocks direct Write/Edit to state files during active loops, enforcing the write-state.sh pattern.
- **Wall-clock timeout**: Stop hook checks elapsed time against `max_duration` (default 60 min). Timed-out sessions can be resumed.
- **Checkpointing**: After every phase transition, writes `checkpoint.md` with phases completed, agents finished, key decisions, and next action.
- **Resume command**: `/buidl-resume` reads state + checkpoint to continue interrupted sessions from their last phase.
- **Cost tracking**: `cost-ledger.md` append-only log of token spend per agent dispatch. `--max-tokens N` flag for budget enforcement.
- **Learning system**: `learning/` directory stores retrospectives from completed sessions. Phase 4 Step 0 consults past retrospectives for matching project types.
- **Phase 6 (Wrap-up)**: Auto-generates retrospective after loop completion (pass or fail), saved to both session dir and learning store.
- **Dynamic agent generation**: Generic (non-OPNet) projects can now generate domain-specific agents from `templates/domain-agent.md` instead of falling back to a single loop-builder.
- **Knowledge slice template**: `templates/knowledge-slice.md` for generating project-specific knowledge for dynamic agents.
- **max_turns per agent type**: Builders=30, Reviewers=15, Explorers=15, Researchers=10, Auditors=20, Deployers=15, UI Testers=20.
- **Structured error handling**: Agent failures get one retry, then 4 numbered options (retry differently, skip, amend spec, cancel). No more open-ended questions.
- **Context pressure detection**: Orchestrator checkpoints and suggests `/buidl-resume` when context pressure is detected.
- **PreToolUse hook config** in hooks.json for Write|Edit tool matching.

### Changed
- **State file format**: Migrated from `state.local.md` (YAML frontmatter) to `state.yaml` (pure YAML). All commands support dual-file fallback for in-flight sessions.
- **setup-loop.sh**: Uses write-state.sh for atomic initial write. Creates `agents/` and `knowledge/` dirs in session directory. Adds `max_duration`, `tokens_used`, `phases_completed` fields.
- **stop-hook.sh**: Completely rewritten — removed `sedi()` function, all state writes go through write-state.sh. Added wall-clock timeout check with cross-platform epoch conversion.
- **buidl-status.md**: Reads state.yaml (fallback state.local.md), shows tokens_used, elapsed time, checkpoint info.
- **buidl-cancel.md**: Uses write-state.sh for status update, mentions /buidl-resume.
- **buidl-clean.md**: Cleans both state.yaml and state.local.md if they exist.
- **buidl.md**: Added RULES section, checkpoint protocol, cost tracking protocol, learning consultation, max_turns table, structured error handling, upgraded generic mode with dynamic agents.

### Removed
- `sedi()` function from stop-hook.sh (replaced by write-state.sh)
- Direct `sed -i` state mutations (all go through write-state.sh now)
- Raw frontmatter delimiters (`---`) in state files

## [2.1.0] - 2026-03-03

### Added
- Structural test suite: `tests/plugin-tests.sh` with 117 invariant checks across 8 categories
- GitHub Actions CI/CD: `.github/workflows/plugin-tests.yml` runs on every push and PR
- CI badge and Testing section in README
- Inter-agent issue bus: typed markdown messages in `artifacts/issues/` with YAML frontmatter routing
- Orchestrator mid-cycle re-dispatch with 2-cycle limit per agent pair
- FORBIDDEN rules in deployer and UI-tester agents (now 6/6 specialist agents)
- Backend knowledge slice expanded to 985 lines: threading, MongoDB, rate limiting, circuit breaker, health checks
- Runtime model selection flags (`--builder-model`, `--reviewer-model`)
- Standalone `audit-from-bugs` skill
- `loop-guide` skill for command reference
- Troubleshooting guide (`knowledge/opnet-troubleshooting.md`)
- LICENSE file (MIT)
- Knowledge hierarchy documentation in `knowledge/README.md`

### Changed
- Deployer model upgraded from Haiku to Sonnet
- All 10 agents standardized to canonical template: Constraints -> Step 0 -> Process -> Output Format -> Rules
- Stop-hook rewritten with OPNet multi-agent branch and issue injection
- `sed -i` calls made cross-platform (macOS + Linux)

### Fixed
- `sed -i ''` BSD-only syntax replaced with cross-platform function
- `sedi()` infinite recursion bug on macOS (called itself instead of `sed`)
- Literal `\n` in stop-hook.sh replaced with `$'\n'` ANSI-C quoting
- Orphan bullet points in backend-dev and frontend-dev agent constraints
- False-positive OPNet classification for non-OPNet React/Vite projects in setup-loop.sh
- stop-hook.sh crash on malformed state file (grep without fallback under `set -eo pipefail`)
- Auditor Issue Bus section gave impossible write instructions (agent is READ-ONLY)
- plugin.json version mismatch with CHANGELOG (was `2.0.0-opnet`, now `2.1.0`)

## [2.0.0] - 2026-03-02

### Added
- Multi-agent orchestration for OPNet dApps (contract-dev, frontend-dev, backend-dev, auditor, deployer, ui-tester)
- 27 real-bug audit patterns from btc-vision repos (9 CRITICAL, 8 HIGH, 7 MEDIUM, 3 LOW)
- Knowledge slice system (8 domain-specific slices)
- OPNet-specific stop-hook branching
- README with setup instructions

### Changed
- Plugin version bumped to 2.0.0-opnet

## [1.0.0] - 2026-03-02

- Initial release: core loop system (challenge -> specify -> explore -> build -> review)
