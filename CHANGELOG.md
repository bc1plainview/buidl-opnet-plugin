# Changelog

## [4.0.0] - 2026-03-13

### Added
- **Agent self-critique (Reflexion)**: All 4 builder agents (opnet-contract-dev, opnet-frontend-dev, opnet-backend-dev, loop-builder) now re-read their changes against `requirements.md` before declaring done. Each writes a `self-critique.md` artifact with spec compliance checklist, issues found and fixed, and remaining concerns. Any unmet criterion blocks completion until fixed.
- **Incremental audit mode**: On cycle 2+, the auditor receives a `git diff` of changes since the last audit plus previous findings, instead of re-scanning the entire codebase. Focuses on the diff, blast radius, and verifying previous findings are resolved.
- **Dry-run mode** (`--dry-run` flag): Challenge, Specify, and Explore phases run normally. Phase 4 prints the full execution plan (agents, knowledge, tasks, max_turns) without dispatching any agents, then stops.
- **Agent execution tracing** (`scripts/trace-event.sh`): Appends structured JSONL events (dispatch, complete, route, finding, error, replan, checkpoint, state) to `artifacts/trace.jsonl`. New `/buidl-trace` command renders the trace as a formatted timeline.
- **Dynamic re-planning** (`scripts/query-pattern.sh`): When an agent fails after retry, queries `learning/patterns.yaml` for known fix patterns matching the failure category. If found, presents a 5th option ("Apply known fix") alongside the existing 4 error-handling options.
- **Trace command** (`commands/buidl-trace.md`): New `/buidl-trace` slash command that reads `trace.jsonl` and renders agent dispatch timeline, grouped by cycle.

### Changed
- **Orchestrator error handling** (`commands/buidl.md`): Agent failure flow now queries `query-pattern.sh` before presenting options. If a matching pattern exists, 5 options are shown (apply known fix, retry differently, skip, amend spec, cancel). Otherwise the existing 4 options are shown.
- **Orchestrator Phase 4 Step 2** (`commands/buidl.md`): Each agent dispatch and completion now logs trace events via `trace-event.sh`. Phase transitions log checkpoint trace events. Review findings and routing decisions are traced.
- **Auditor Step 2c** (`commands/buidl.md`): Cycle 2+ audits now pass `git diff` and previous findings to the auditor with incremental audit instructions.
- **Auditor agent** (`agents/opnet-auditor.md`): New "Incremental Audit Mode" section documents the diff-based review process for cycle 2+.
- **Plugin version**: 3.6.0 -> 4.0.0

### Why
Five features that close gaps in the agent intelligence loop. Self-critique catches spec drift before the reviewer does, saving entire review cycles. Incremental audits avoid re-scanning unchanged code, cutting audit time on fix cycles. Dry-run mode lets users preview the execution plan before committing to a full build. Execution tracing provides observability into agent dispatch ordering and timing. Dynamic re-planning applies lessons from past failures automatically instead of requiring manual intervention.

## [3.6.0] - 2026-03-13

### Added
- **Score-based finding routing** (`scripts/route-finding.sh`): Routes reviewer and auditor findings to the agent most likely to fix them based on historical success rates. Uses a fixed category taxonomy (10 categories: css-styling, wallet-connect, contract-logic, abi-mismatch, network-config, deployment, testing, security, build-errors, backend-api) matched against agent strengths/weaknesses. Falls back to keyword routing when agents have fewer than 5 sessions.
- **Strengths/weaknesses tracking** (`scripts/update-scores.sh --findings`): New `--findings` flag accepts a categorized findings file and updates per-agent strengths and weaknesses arrays in agent-scores.yaml. Categories are accumulated across sessions — successful fixes add to strengths, failures add to weaknesses.
- **Project-type profiles** (`learning/profiles/*.yaml`): Auto-generated profiles for project types with 5+ completed sessions. Profiles include common pitfalls (from patterns.yaml), recommended agent config, suggested challenge gates to skip, and per-agent performance data.
- **Profile generation script** (`scripts/generate-profiles.sh`): Scans retrospectives and patterns by project type, generates/regenerates profiles at session count thresholds (5, 10, 20, 50).
- **Profile consultation in Phase 1**: Orchestrator checks for matching profiles during the challenge phase. If found, presents common pitfalls and offers to skip challenge gates based on accumulated experience.
- **Profile loading in Phase 4**: Orchestrator pre-loads profile pitfalls into agent dispatch prompts so agents start with knowledge of known issues for this project type.

### Changed
- **Phase 5 FAIL routing** (`commands/buidl.md`): Reviewer findings now routed via `route-finding.sh` instead of hardcoded keyword matching. Score-based routing when agents have 5+ sessions; keyword fallback otherwise. Categorized findings written to `artifacts/findings-categorized.md` for post-session strengths/weaknesses tracking.
- **Phase 4 Step 0b** (`commands/buidl.md`): Agent score consultation now notes strengths and weaknesses for use in routing decisions.
- **Phase 6 wrap-up** (`commands/buidl.md`): Now calls `generate-profiles.sh` after `update-scores.sh`. Also passes `--findings` to update-scores.sh when categorized findings exist.
- **Plugin version**: 3.5.0 -> 3.6.0

### Why
Two deferred features from v3.5 that close the adaptive learning loop. Score-based routing means the plugin doesn't just track which agents succeed — it uses that data to make smarter routing decisions. When frontend-dev has historically fixed 90% of CSS issues but only 40% of WebSocket issues, CSS findings go to frontend-dev and WebSocket findings go to backend-dev. Project-type profiles mean the 6th OP-20 token build starts with knowledge of what went wrong in the first 5, which challenge gates are redundant, and which agents perform best for that project type.

## [3.5.0] - 2026-03-13

### Added
- **Adaptive learning pattern store** (`learning/patterns.yaml`): Structured YAML store for patterns auto-extracted from session retrospectives. Patterns are categorized by domain (contract/frontend/backend/deployment/testing), failure type, and tech stack. Auto-deduplicates and tracks occurrence count across sessions.
- **Pattern extraction script** (`scripts/extract-patterns.sh`): Reads a retrospective markdown file, extracts anti-patterns and failures, appends structured entries to patterns.yaml. Auto-promotes patterns with 3+ occurrences to relevant knowledge slices with `[LEARNED]` tag.
- **Agent performance scoring** (`learning/agent-scores.yaml`): Rolling metrics per agent — sessions completed, success rate, average cycles to pass review, average tokens consumed, model history with per-model success rates. Updated automatically after each session.
- **Score update script** (`scripts/update-scores.sh`): Reads session state.yaml after completion, extracts agent outcomes, computes rolling averages, updates agent-scores.yaml.
- **Cross-layer validator agent** (`agents/cross-layer-validator.md`): READ-ONLY agent that validates integration correctness across contract/frontend/backend layers. Checks ABI-to-frontend method mapping, parameter types, contract address consistency, network config alignment, signer configuration, and event names. Runs after builders, before auditor.
- **Cross-layer validation knowledge slice** (`knowledge/slices/cross-layer-validation.md`): 8 documented mismatch types with detection rules, fixes, and routing decisions. Validation checklist for frontend/backend contract calls.
- **OP-20 starter template** (`templates/starters/op20-token/`): Complete starter for OP-20 token projects — AssemblyScript contract with parameterized name/symbol/supply, unit tests, OPNet-ready Vite frontend with WalletConnect scaffold, and template.yaml manifest with customization points.
- **`validating` active phase**: Added to stop-hook, guard-state, and guard-state-bash so the loop stays blocked during cross-layer validation.

### Changed
- **Orchestrator Phase 4 Step 0** (`commands/buidl.md`): Learning consultation now has 4 sub-steps — (a) query pattern store filtered by project type, (b) check agent scores and suggest model upgrades for underperforming agents, (c) read retrospectives, (d) check starter templates for matching project type.
- **Orchestrator Phase 4 Step 2b.5** (`commands/buidl.md`): New cross-layer validation step between builders and auditor. Dispatches cross-layer-validator, routes MISMATCH findings to responsible agents, passes WARNING findings to auditor.
- **Orchestrator Phase 6** (`commands/buidl.md`): After retrospective, now calls extract-patterns.sh and update-scores.sh to update the adaptive learning system.
- **Auditor dispatch** (`commands/buidl.md`): Now imports cross-layer validation report as additional context.
- **Plugin version**: 3.4.0 -> 3.5.0

### Deferred to v3.6
- **Score-based routing** (US-6): Routing reviewer findings to agents based on historical success rates. Requires more data points before it's useful.
- **Project-type profiles** (US-8): Auto-generated profiles after 5+ projects of the same type. Needs accumulation of pattern data first.

### Why
The plugin had a learning system that saved retrospectives but barely used them — the orchestrator read them as advisory text with no structure, no indexing, and no feedback loop into agent prompts. Agents kept repeating the same mistakes across sessions. The pattern store + agent scoring creates a real feedback loop: every session's lessons are extracted, scored, and injected into future agent prompts. Cross-layer validation catches the #1 source of wasted audit/E2E cycles (ABI mismatches) before they reach expensive downstream agents. Starter templates eliminate boilerplate for the most common project type (OP-20 tokens).

## [3.4.0] - 2026-03-13

### Added
- **E2E testing hard gate in stop-hook**: Shell-level enforcement that blocks loop exit when a deployed OPNet contract has no E2E test results. The stop-hook checks for `deployment_address` in state and `e2e-results.json` in artifacts — if the contract is deployed but E2E tests haven't run, the loop is physically blocked (exit code 2) and the E2E tester prompt is re-injected. Failed E2E tests also block. This eliminates the need to manually tell agents to test deployments.
- **Frontend runtime smoke check** (`opnet-frontend-dev.md` Step 6.5): After build passes, frontend-dev now starts a Vite dev server and runs a Playwright headless check for console errors, dark background verification, and visible content rendering. Catches runtime bugs that lint/typecheck/build miss.
- **Frontend pre-flight checklist** (`opnet-frontend-dev.md` Step 6.7): 10 grep-based anti-pattern checks run against `src/` before build-result.json is written — Buffer usage, private key leaks (signer !== null), wrong network, forbidden approve(), spinners, emojis, hardcoded colors, missing meta tags, static feeRate, missing explorer links. FAIL items block completion.
- **Common Runtime Errors knowledge** (`knowledge/slices/frontend-dev.md`): 10 documented runtime error patterns (RT-1 through RT-10) covering Node.js polyfill failures, undici/fetch shim, duplicate package instances, CORS errors, React hydration mismatch, BigInt serialization, WalletConnect modal positioning, Vite dev server crashes, CSS variable undefined, and wallet-connects-but-no-interaction.
- **E2E handoff file** (`opnet-deployer.md` Step 8): Deployer now writes `artifacts/deployment/e2e-handoff.json` with structured contract address (bech32 + hex), ABI path, receipt path, wallet env paths, and RPC URL. The stop-hook reads this file to construct the E2E tester dispatch prompt.
- **`e2e_testing` active phase**: Added to stop-hook, guard-state, and guard-state-bash active phase lists so the loop stays blocked during E2E testing.

### Changed
- **Stop-hook** (`hooks/scripts/stop-hook.sh`): Added E2E testing gate (~40 lines) between wall-clock timeout and reviewer verdict check. Handles three states: no E2E results (block + dispatch), E2E failed (block + route to contract-dev), E2E passed (allow exit).
- **Guard-state hooks**: Both `guard-state.sh` and `guard-state-bash.sh` now include `e2e_testing` in their active phase case statements.
- **Orchestrator** (`commands/buidl.md`): Step 2e now includes state update (`current_phase=e2e_testing status=e2e_testing`), 5-point precondition checklist, and 4-point postcondition checklist. Step 2f max UI test cycles increased from 2 to 3.
- **Frontend-dev agent** (`agents/opnet-frontend-dev.md`): Renumbered old Step 6.5 (Proactivity Check) to Step 6.8. New Steps 6.5 (smoke check), 6.7 (pre-flight checklist) are mandatory before build-result.json is written.
- **Deployer agent** (`agents/opnet-deployer.md`): Step 8 rewritten from vague "Prepare E2E Test Handoff" to concrete "Write E2E Handoff File" with exact JSON schema and 4 rules.
- **Plugin version**: 3.3.0 → 3.4.0

### Why
Two persistent pain points: (1) E2E on-chain testing required manual intervention — agents would deploy contracts and declare success without testing them on-chain, despite orchestrator instructions saying "MANDATORY." Prompt-level instructions aren't enough; the stop-hook now physically blocks exit until E2E tests pass. (2) Frontend output consistently had runtime bugs (console errors, white backgrounds, broken rendering) that only surfaced during UI testing, wasting entire fix cycles. The runtime smoke check and pre-flight checklist catch these bugs inside the frontend-dev agent itself, before the UI tester ever runs.

## [3.3.0] - 2026-03-13

### Added
- **PUA exhaustive problem-solving skill** (`skills/pua/SKILL.md`): Adapted from the PUA plugin — Three Iron Rules (exhaust options, act before asking, take initiative), Five-Step Methodology (smell, elevate, mirror, execute, retrospect), Seven-Point Checklist for stuck situations, Anti-Rationalization Table (10 blocked excuses with required actions), Proactivity Checklist, and Pressure Escalation (L1-L4 by cycle).
- **GSD-2 debugging discipline**: Integrated into the PUA skill — form hypothesis before touching code, change one variable at a time, read error output completely, distinguish "I know" from "I assume", know when to stop (3 failures = mandatory checklist), don't fix symptoms.
- **Decisions register template** (`templates/decisions.md`): Append-only log for architectural decisions made during sessions. Agents write to it, orchestrator and reviewer read it.
- **Context budget awareness**: All builder agents now monitor context usage and checkpoint before running out.
- **Pressure escalation in stop-hook**: Cycle 2 = elevated (3 hypotheses required), Cycle 3 = mandatory 7-Point Checklist, Cycle 4+ = last chance with structured failure report option.

### Changed
- **All builder agents** (loop-builder, opnet-contract-dev, opnet-frontend-dev, opnet-backend-dev): Added PUA skill loading in Step 0, debugging discipline + proactivity check after verify pipeline, rules for exhausting options, verifying fixes, and logging decisions.
- **Auditor agent**: Added audit discipline section — read completely, distinguish know/assume, verify every finding, proactively check beyond the checklist.
- **Reviewer agent**: Added review proactivity section — check similar issues, verify root cause fixes, check verification completeness, edge cases.
- **Explorer agent**: Added thoroughness requirement from PUA Iron Rule One — exhaust all relevant areas, search multiple angles.
- **Domain agent template**: PUA skill loading, debugging discipline, proactivity check, context budget awareness, decisions register.
- **Orchestrator command** (`commands/buidl.md`): Decisions register initialization in Setup phase, PUA skill reference in agent dispatch template.
- **Stop hook** (`hooks/scripts/stop-hook.sh`): PUA pressure escalation injected into re-injection prompts for both OPNet multi-agent and legacy single-builder flows.
- **Plugin version**: 3.2.0 → 3.3.0

### Why
AI agents frequently give up too early on fixable problems — they rationalize failures ("this might be a known issue"), repeat the same broken approach, or ask the user to intervene when they have enough information to solve it themselves. PUA's structured escalation and anti-rationalization patterns, combined with GSD-2's debugging discipline, force agents to exhaust all options systematically before escalating. The pressure escalation in the stop-hook ensures that as cycles progress, the debugging requirements become more rigorous rather than more lenient.

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
