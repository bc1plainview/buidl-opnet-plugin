# Project-Type Profiles

Auto-generated profiles for project types with 5+ completed sessions.

## Schema

```yaml
# learning/profiles/<type>.yaml
project_type: op20-token          # kebab-case project type identifier
sessions_count: 7                 # number of sessions that informed this profile
generated_at: "2026-03-15"        # ISO date of last generation
source_sessions:                  # session names used to build this profile
  - my-token
  - reward-token
  - governance-token

common_pitfalls:                  # extracted from patterns.yaml matching this type
  - id: PAT-L001
    description: "forgot increaseAllowance instead of approve()"
    fix: "OP-20 has no approve() — use increaseAllowance/decreaseAllowance"
  - id: PAT-L005
    description: "used Number instead of BigInt for token amounts"
    fix: "always use BigInt for satoshi/token amounts"

recommended_config:
  builder_model: opus              # model with highest success rate for this type
  skip_challenge_gates:            # gates that can be skipped for experienced types
    - build_vs_buy                 # already know we're building, not buying
  max_cycles: 2                   # typical cycles needed

agent_performance:                # per-agent stats for this project type
  opnet-contract-dev:
    success_rate: 0.85
    avg_cycles: 1.2
  opnet-frontend-dev:
    success_rate: 0.70
    avg_cycles: 1.8
```

## How Profiles Are Used

1. **Phase 1 (Challenge):** Orchestrator checks for matching profile. If found with 5+ sessions, presents common pitfalls and offers to skip certain challenge gates.
2. **Phase 4 (Build):** Orchestrator pre-loads pitfalls into agent prompts. May suggest model upgrades based on per-agent performance.
3. **Phase 6 (Wrap-up):** `generate-profiles.sh` checks if any project type has crossed a session threshold and regenerates the profile.

## Regeneration

Profiles are regenerated (not appended) when the session count crosses thresholds: 5, 10, 20, 50.
Run manually: `bash scripts/generate-profiles.sh`
