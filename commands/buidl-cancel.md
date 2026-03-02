---
description: "Cancel a running loop"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop — Cancel

Cancel the currently running loop. The worktree and all session artifacts are preserved for manual continuation.

## Steps

1. Check if a loop is running by reading `.claude/loop/state.local.md`.
2. If no loop is running, say so and stop.
3. If a loop is running:
   - Update the state file: set `status: cancelled`
   - Report what was preserved:
     - Session directory: `.claude/loop/sessions/<name>/`
     - Worktree: `.claude/worktrees/loop-<name>/`
     - Branch: `loop/<name>`
     - PR (if created): the URL
   - Explain: "The worktree and branch are preserved. To clean up completely, run `/buidl-clean`. To resume manually, work in the worktree directory."
