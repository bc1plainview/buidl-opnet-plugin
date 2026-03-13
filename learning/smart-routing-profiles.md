# Retrospective: smart-routing-profiles
Date: 2026-03-13
Project Type: generic
Outcome: PASS on cycle 2
Tokens Used: ~60000
Duration: ~45 minutes

## What Worked
- Shell script architecture with embedded Python (sys.argv for data, never interpolation) is solid and testable
- The 10-category fixed taxonomy makes routing predictable and easy to test
- candidate_or_first helper pattern elegantly solves the "don't return agents not in candidate list" problem
- Functional tests that actually invoke the scripts caught real issues (sessions_count collision with existing retrospectives)
- Reviewer caught real bugs: keyword fallback ignoring candidates, mixed-case keywords that would never match after lowercasing

## What Failed
- Initial implementation had keyword fallback returning hardcoded agent names even when those agents weren't in the candidate list — a significant logic error
- First version of generate-profiles.sh functional test used "opnet" as mock project type, which collided with real retrospectives already in learning/

## Effective Agent Configs
- loop-builder with max_turns=30: sufficient for this scope (2 new scripts + modifications to 6 existing files)
- loop-reviewer with max_turns=15: caught 5 real issues in cycle 1, verified all fixes in cycle 2

## Knowledge That Mattered
- Understanding of set -euo pipefail interactions with grep (must guard with || true)
- macOS grep doesn't support -P flag (use -E instead)
- Python yaml module for reading/writing YAML in shell scripts

## Anti-Patterns
- Don't use hardcoded agent names in fallback paths — always validate against the provided candidate list
- Don't use mixed-case keywords in grep patterns after lowercasing the input
- Don't use real data directories for functional tests when collisions are possible — use unique identifiers

## Recommendations
- For future scripts that process YAML: continue the pattern of embedded Python with sys.argv
- When adding functional tests: always use unique/isolated test data to avoid collisions with production data
- The candidate_or_first pattern should be documented as a reusable idiom for any future routing scripts
