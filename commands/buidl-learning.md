---
description: "Show learning system health report"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop — Learning System Health

Print a health report of the learning system, including pattern counts, agent scores, project-type profiles, and prune log.

## Steps

1. Run the audit script:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit-learning.sh
   ```
2. Display the full output to the user.
3. If patterns are stale (last_seen_version 2+ major versions behind), suggest running pruning:
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/update-scores.sh <state-file> pass --prune
   ```
