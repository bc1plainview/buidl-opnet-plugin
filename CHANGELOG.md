# Changelog

## [2.1.0] - 2026-03-03

### Added
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
- Literal `\n` in stop-hook.sh replaced with `$'\n'` ANSI-C quoting
- Orphan bullet points in backend-dev and frontend-dev agent constraints

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
