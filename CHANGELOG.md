# Changelog

## [8.0.0] - 2026-03-14

### Added
- **TLA+ Formal Specification Phase (Phase 2B)**: Before any contract code is generated, a `spec-writer` agent produces a TLA+ formal specification of the contract's state machine. TLC (the official TLA+ model checker) exhaustively verifies every invariant. If violations are found, the agent repairs the spec in a feedback loop (up to 5 iterations) before proceeding. If the spec cannot be verified, codegen is blocked entirely.
- `agents/spec-writer.md`: New agent specialized in OPNet TLA+ specs. Covers partial revert patterns, NativeSwap reservation system, queue-based DEX models, and balance conservation invariants.
- `scripts/setup-tla.sh`: One-time TLC model checker download.
- `scripts/verify-spec.sh`: Runs TLC against a spec, outputs structured JSON.
- `scripts/parse-tlc-output.py`: Parses TLC stdout into machine-readable violation traces.
- `scripts/run-spec-loop.sh`: Verification-repair loop with configurable max iterations.
- `tools/tla/`: TLC jar location (downloaded by setup-tla.sh, gitignored).

### Changed
- `commands/buidl.md`: Phase 2 now includes Phase 2B (formal verification). Phase 3 is blocked if spec cannot be verified. Spec-writer added to max_turns table (15 turns).
- `agents/opnet-contract-dev.md`: Must read and preserve verified spec invariants before writing any code.
- `.gitignore`: Added `tools/tla/` for downloaded TLC jar.

### Why
TLA+ catches design-level bugs that tests cannot: race conditions between Bitcoin L1 state and contract state, partial revert edge cases, reservation ordering violations. These bugs exist in the requirements before any code is written. Tests only catch bugs in code that already exists. Formal verification catches the logical impossibilities upstream. Pattern from @KingBootoshi / Bootoshi (2026-03-14): agents generate the TLA+ spec, TLC verifies it, agents loop fixing it.

## [7.0.0] - 2026-03-13

### Added
- **Mutation testing as loop exit gate** (`scripts/mutate-contract.sh`): Applies 20 sed-level mutation operators to contract source files. For each mutant: creates a temp copy, applies the mutation, compiles, runs tests. If tests fail, the mutant is killed (good). If tests pass or compilation fails, the mutant survived (bad). Outputs `artifacts/testing/mutation-score.json` with total_mutants, killed, survived, compile_errors, mutation_score (0-1), threshold (0.70), verdict (PASS/FAIL), and survivors list. Phase 5 runs this gate before the reviewer -- score below 0.70 routes back to contract-dev with the survivors list.
- **Structured repair phases** (Agentless R1/R2/R3 pattern): Replaces "re-run agent with failure context" with three targeted phases. Phase R1 (LOCALIZE): max_turns 5, READ-ONLY, reviewer in localize mode produces localization.json. Phase R2 (PATCH): max_turns 10, domain agent receives localized context only, generates up to 3 candidate patches. Phase R3 (VALIDATE): automated, runs tests and mutation on each candidate, picks the best.
- **Failure localization script** (`scripts/localize-failure.sh`): Parses failure logs to extract file, function, line_range, suspected_cause, confidence, and failure_category. Outputs `artifacts/localization.json`.
- **Localize Mode** (`agents/loop-reviewer.md`): New reviewer mode for Phase R1 -- strict 5-turn READ-ONLY process. Produces localization.json only. Code generation is FORBIDDEN.
- **Goal-oriented build evaluation** (`scripts/score-build.sh`): Evaluates builds across 4 dimensions: spec_coverage (requirements with tests / total, threshold 90%), security_delta (open findings count, threshold 0), mutation_score (from mutation-score.json, threshold 70%), code_health (100 minus weighted penalties, threshold 60%). Outputs `artifacts/evaluation/progress-tracker.yaml`. All thresholds must be met. Failed dimensions route to responsible agents.
- **Requirements extraction** (`scripts/extract-requirements.sh`): Parses requirements.md and extracts individual requirements into `artifacts/evaluation/spec-requirements.yaml` with id, description, has_test, and priority fields.
- **Hierarchical cross-layer repo map** (`scripts/build-repo-map.sh`): Generates `artifacts/repo-map.md` with Contract Layer (from abi.json: methods, events, storage slots), Frontend Layer (components, hooks, services, contract calls), Backend Layer (routes, services, contract calls), and Cross-Layer Integrity Checks (missing methods, uncalled methods). Target under 300 lines.
- **Autoresearch optimize mode** (`commands/buidl-optimize.md`): New `/buidl-optimize` command for automated metric optimization. Supports gas, bundle_size, test_time, and throughput metrics. Runs a hypothesis-implement-benchmark-keep/revert cycle up to 10 times. Outputs summary.md, best-result.json, and auto-creates a PR with kept changes.

### Changed
- **Orchestrator Phase 5** (`commands/buidl.md`): Mutation gate runs before reviewer dispatch. If mutation score < 0.70, routes back to contract-dev with survivors. Score-build runs after each review cycle, displaying a compact 4-dimension score table. All thresholds must be met for build completion.
- **Orchestrator agent failure handling** (`commands/buidl.md`): Agent failures now go through R1/R2/R3 structured repair before falling back to manual options. Localization produces targeted context, domain agents generate candidate patches, and validation picks the best one automatically.
- **Orchestrator Phase 4** (`commands/buidl.md`): Repo map generated after ABI lock (contract layer only), regenerated after all builders complete (all layers populated).
- **Orchestrator FAIL routing** (`commands/buidl.md`): Uses R1/R2/R3 structured repair for targeted fixes instead of raw agent re-dispatch with full failure context.
- **All 12 domain agent files**: Updated Step 0 / knowledge loading to reference `artifacts/repo-map.md` for cross-layer context. Agents: cross-layer-validator, loop-builder, loop-explorer, loop-researcher, loop-reviewer, opnet-auditor, opnet-backend-dev, opnet-contract-dev, opnet-deployer, opnet-e2e-tester, opnet-frontend-dev, opnet-ui-tester.
- **buidl-status** (`commands/buidl-status.md`): Shows mutation score ("Mutation: 83% (15/18 killed)") and 4-dimension build score card when available. Steps renumbered from 7-10 to 9-12.
- **loop-reviewer** (`agents/loop-reviewer.md`): Added Localize Mode section after Critique Mode.
- **Plugin version**: 6.0.0 -> 7.0.0

### Why
Four gaps identified in the build verification and repair systems. (1) The loop had no way to measure test quality -- tests could pass while missing entire categories of bugs. Mutation testing quantifies test effectiveness by checking whether tests detect deliberate code changes. (2) When agents failed, the entire failure context was re-injected, leading to unfocused repair attempts. Structured R1/R2/R3 phases localize the failure first, then generate targeted patches, then validate them automatically. (3) The reviewer produced a single PASS/FAIL verdict with no multi-dimensional visibility. Goal-oriented evaluation scores across 4 dimensions (spec coverage, security, mutation, code health) with clear thresholds and routing for each. (4) Agents had no shared map of how contract methods connected to frontend calls and backend routes. The hierarchical repo map provides cross-layer visibility, and integrity checks automatically detect missing or extra method calls.

## [6.0.0] - 2026-03-13

### Added
- **Dynamic knowledge slice loading** (`scripts/load-knowledge.sh`): Assembles role-specific knowledge payloads per agent. Always includes the agent's domain slice and troubleshooting guide. Conditionally includes tagged sections of `knowledge/opnet-bible.md` based on agent role (contract-dev=full, frontend-dev=[FRONTEND] only, backend-dev=[BACKEND] only, auditor=[SECURITY] only, deployer=[DEPLOYMENT] only). Includes non-stale [LEARNED] patterns from `learning/patterns.yaml`. Caps output at 400 lines max, truncating least-relevant sections first with a truncation note.
- **Opnet bible section tagging**: All 12 sections of `knowledge/opnet-bible.md` tagged with HTML comment markers (`BEGIN-SECTION-N [TAGS]` / `END-SECTION-N`) for role-based filtering. Tags: [CONTRACT], [FRONTEND], [BACKEND], [SECURITY], [DEPLOYMENT].
- **Property-based fuzz case generator** (`scripts/fuzz-contract.sh`): Reads ABI JSON, extracts @method signatures and param types, generates boundary test cases (u256: [0, 1, 2^128, 2^256-1, 2^256-2], address: [zero, contract, caller], bool: [true, false]), generates all single-param boundary combinations plus 10 random valid-type combinations, and outputs `artifacts/testing/fuzz-cases.json`. Does NOT send transactions.
- **Stale pattern pruning** (`scripts/update-scores.sh --prune`): Removes agent entries with >30 sessions or success_rate <0.2 with 10+ data points. Logs removals to `learning/prune-log.yaml`.
- **Pattern staleness tracking** (`scripts/extract-patterns.sh`): Adds `last_seen_version` field to new patterns and `stale: true` flag based on major version comparison (2+ major versions behind = stale).
- **Learning system health report** (`scripts/audit-learning.sh`): Prints pattern counts (total/stale/active/promoted), agent scores summary, profile count, and prune log. Available via `/buidl-learning` command.
- **buidl-learning command** (`commands/buidl-learning.md`): New `/buidl-learning` slash command that runs the learning health report.

### Changed
- **Agent knowledge loading**: All 14 agent .md files updated to reference `scripts/load-knowledge.sh` for dynamic knowledge assembly instead of static file references. Slice names retained as comments for orphan detection.
- **Orchestrator dispatch** (`commands/buidl.md`): Phase 4 agent dispatches now call `load-knowledge.sh` to assemble agent-specific knowledge payloads.
- **Orchestrator Step 2c.5** (`commands/buidl.md`): Adversarial audit step now runs `fuzz-contract.sh` to generate fuzz cases before dispatching the adversarial auditor.
- **Adversarial auditor agent**: Step 3 now references `fuzz-cases.json` as input for invariant testing.
- **Adversarial E2E tester agent**: Step 1 now reads `fuzz-cases.json` for boundary value transaction testing.
- **buidl-status**: Now includes a one-line learning health summary.
- **Plugin version**: 5.0.0 -> 6.0.0

### Why
Three gaps identified in the knowledge and learning systems. (1) Agents loaded the full 2000-line bible regardless of role, wasting context budget. Dynamic loading filters to role-relevant sections, keeping payloads under 400 lines. (2) Adversarial auditing tested invariants but had no systematic boundary value generation. The fuzz case generator creates structured test cases from ABI signatures, covering the exact boundary values that cause real bugs (u256 overflow, zero addresses, max values). (3) The pattern store grew without bounds and had no staleness tracking. Patterns from major versions ago may no longer be relevant. Version-based staleness and pruning keep the learning system lean.

## [5.0.0] - 2026-03-13

### Added
- **Acceptance test generation** (`commands/buidl.md` Phase 2): After tasks.md is generated, the orchestrator extracts acceptance criteria from requirements.md and generates shell-script test stubs to `artifacts/acceptance-tests/`. Tests use pass()/fail()/check() convention and are included in the human approval gate. All 4 builder agents have a FORBIDDEN rule preventing modification of these locked tests.
- **ABI-lock checkpoint** (`commands/buidl.md` Phase 4): After contract-dev completes, the orchestrator computes `shasum -a 256` of abi.json, stores the hash in state as `abi_hash` with `abi_locked=true`. Before frontend/backend dispatch, the hash is verified. Mismatch blocks dispatch and re-dispatches contract-dev.
- **Adversarial auditor agent** (`agents/opnet-adversarial-auditor.md`): READ-ONLY agent that extracts invariants from requirements.md, reads contract source, constructs specific input sequences that could violate each invariant, and produces structured PASS/FAIL findings. FAIL verdict blocks deployment.
- **Adversarial E2E tester agent** (`agents/opnet-adversarial-tester.md`): Sends real on-chain transactions targeting boundary values, revert exploitation, access control bypass, and race conditions. Runs after happy-path E2E tests, before UI testing.
- **Structured failure diagnosis** (`commands/buidl.md` Phase 5): When max cycles reached with FAIL verdict, generates `artifacts/failure-diagnosis.md` with classification (spec_problem, implementation_problem, test_problem, infrastructure_problem), evidence, cycle history, and recommended next step.
- **Findings ledger** (`commands/buidl.md` Phase 5): After each review, findings are assigned unique IDs (F-001, F-002...) and tracked in `artifacts/findings-ledger.md` with pipe-delimited table. Statuses: OPEN, RESOLVED, REGRESSION. For cycle 2+, reviewer checks resolved findings for regression.
- **Chain probe script** (`scripts/chain-probe.sh`): Queries OPNet RPC for gas parameters, block height, and network. Writes to `artifacts/chain-state.json`. Handles RPC failure gracefully (probe_status: "failed", continues). Runs in Phase 2 for OPNet projects.
- **Cross-agent critique** (`commands/buidl.md` Phase 4): After each builder completes, output is routed to a different agent for critique. Routing: contract-dev to loop-reviewer, frontend-dev to backend-dev (or reviewer), backend-dev to frontend-dev (or reviewer), loop-builder to loop-reviewer. CRITICAL findings route back to original builder.
- **Critique mode** (`agents/loop-reviewer.md`): Lightweight review mode (max_turns 10) focused on spec compliance. Writes `artifacts/cross-critique.md`.
- **Regression check** (`agents/loop-reviewer.md`): Reviewer reads findings-ledger.md, verifies RESOLVED findings are still fixed, marks regressions as CRITICAL with [REGRESSION] tag.
- **Hard gate enforcement** (`commands/buidl.md` Phase 1): Gates 1-4 classified as SOFT, gates 5-6 as HARD. When --skip-challenge is set, soft gates are skipped (logged to trace), hard gates always run. Hard gate failure stops the loop.

### Changed
- **Self-critique replaced by cross-critique**: Removed Step 5.7 from opnet-contract-dev.md, Step 6.9 from opnet-frontend-dev.md, Step 4.7 from opnet-backend-dev.md, Step 3.7 from loop-builder.md. Cross-critique is handled by the orchestrator after each builder completes.
- **Builder agents FORBIDDEN sections**: All 4 builder agents now include a rule preventing modification of files in `artifacts/acceptance-tests/`.
- **Agent dispatch table**: Added adversarial auditor (max_turns: 20), adversarial E2E tester (max_turns: 25), and reviewer critique mode (max_turns: 10).
- **Hook scripts**: stop-hook.sh, guard-state.sh, and guard-state-bash.sh now include `adversarial_auditing` and `adversarial_testing` in active phase lists.
- **buidl-status**: Shows ABI-lock status (locked/unlocked with hash) and findings ledger summary (open/resolved/regression counts).
- **Plugin version**: 4.0.0 -> 5.0.0

### Why
Nine correctness, reliability, and coverage gaps identified in an external audit. (1) Acceptance tests can now be locked before building, preventing builders from modifying the verification criteria. (2) ABI-lock prevents frontend/backend drift from the contract ABI. (3) Adversarial auditing tests invariants with attack sequences, not just pattern matching. (4) Adversarial E2E testing sends real edge-case transactions that happy-path tests miss. (5) Failure diagnosis classifies root causes when the loop exhausts its cycle budget. (6) Findings ledger tracks resolution and detects regressions across cycles. (7) Chain probe fetches live gas parameters before spec generation. (8) Cross-agent critique replaces self-critique with independent verification. (9) Hard gate enforcement ensures critical gates cannot be skipped.

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
