---
description: "Cancel a running loop"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop — Cancel

Cancel the currently running loop. The worktree and all session artifacts are preserved for manual continuation.

## Steps

1. Check for state files in order:
   - `.claude/loop/state.yaml` (preferred)
   - `.claude/loop/state.local.md` (legacy fallback)
2. If no state file is found, say "No loop is running." and stop.
3. If a loop is running:
   - Update the state file using write-state.sh: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh status=cancelled`
   - Report what was preserved:
     - Session directory: `.claude/loop/sessions/<name>/`
     - Worktree: `.claude/worktrees/loop-<name>/`
     - Branch: `loop/<name>`
     - PR (if created): the URL
   - Explain: "The worktree and branch are preserved. To clean up completely, run `/buidl-clean`. To resume, run `/buidl-resume`."
