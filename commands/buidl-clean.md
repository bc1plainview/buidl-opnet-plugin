---
description: "Cancel loop and remove worktree + branch"
allowed-tools: ["Bash(bash:*)", "Bash(git:*)"]
---

# The Loop — Clean

Cancel the current loop AND remove the worktree and branch. This is destructive — use `/buidl-cancel` if you want to preserve the work.

## Steps

1. Read `.claude/loop/state.local.md`.
2. If no state file exists, say "No loop to clean up."
3. If a state file exists:
   - Ask the user to confirm: "This will remove the worktree at [path] and delete the branch [branch]. The session directory with spec artifacts will be kept. Continue?"
   - If confirmed:
     - Remove the worktree: `git worktree remove <path> --force`
     - Delete the branch: `git branch -D <branch>`
     - Remove the state file
     - Report what was cleaned up and what was kept (session directory with specs)
   - If not confirmed: stop
