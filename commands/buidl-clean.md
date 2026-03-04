---
description: "Cancel loop and remove worktree + branch"
allowed-tools: ["Bash(bash:*)", "Bash(git:*)"]
---

# The Loop — Clean

Cancel the current loop AND remove the worktree and branch. This is destructive — use `/buidl-cancel` if you want to preserve the work.

## Steps

1. Check for state files in order:
   - `.claude/loop/state.yaml` (preferred)
   - `.claude/loop/state.local.md` (legacy fallback)
2. If no state file exists, say "No loop to clean up."
3. If a state file exists:
   - Ask the user to confirm: "This will remove the worktree at [path] and delete the branch [branch]. The session directory with spec artifacts will be kept. Continue?"
   - If confirmed:
     - Remove the worktree: `git worktree remove <path> --force`
     - Delete the branch: `git branch -D <branch>`
     - Remove BOTH state files if they exist:
       - `.claude/loop/state.yaml`
       - `.claude/loop/state.local.md`
     - Report what was cleaned up and what was kept (session directory with specs)
   - If not confirmed: stop
4. **Orphan worktree cleanup**: After cleaning the active session (or if no state file exists), run `git worktree list` and check for any worktrees under `.claude/worktrees/loop-*` that have no matching active state. If found:
   - List them and ask the user: "Found orphaned loop worktrees. Remove them?"
   - If confirmed, remove each with `git worktree remove <path> --force` and `git branch -D <branch>` if the branch still exists.
   - Report what was cleaned up.
