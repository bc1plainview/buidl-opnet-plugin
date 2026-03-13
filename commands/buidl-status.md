---
description: "Show current loop state"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop — Status

Show the current state of The Loop.

## Steps

1. Check for state files in order:
   - `.claude/loop/state.yaml` (preferred)
   - `.claude/loop/state.local.md` (legacy fallback)
2. If neither exists, say "No loop is currently running."
3. If a state file exists, parse and display:

```
Loop Status
───────────
Session:      [name]
Status:       [status]
Phase:        [current_phase]
Cycle:        [cycle] / [max_cycles]
Worktree:     [path]
Branch:       [branch]
PR:           [url or "not created yet"]
Started:      [timestamp]
Tokens used:  [tokens_used or "not tracked"]
Elapsed:      [computed from started_at, or "unknown"]
```

4. **ABI Lock Status**: Check state for `abi_locked` and `abi_hash`:
   ```
   ABI Lock:       [locked (hash: abc123...) / unlocked]
   ```
5. **Findings Ledger Summary**: If `artifacts/findings-ledger.md` exists, parse it and show:
   ```
   Findings:       [N open / N resolved / N regression]
   ```
6. If there are review files in the session directory, show the latest verdict.
5. If a checkpoint file exists at `.claude/loop/sessions/<name>/checkpoint.md`, show the last checkpoint timestamp and next action.
6. If the status is `done`, `failed`, `cancelled`, or `timed_out`, include the summary.
7. **Orphan worktree detection**: Run `git worktree list` and cross-reference with the active state:
   - For each worktree under `.claude/worktrees/loop-*`, check if there's a matching session in state.
   - If a worktree exists but no state file references it (or state is `done`/`cancelled`), flag it as orphaned:
   ```
   Orphaned Worktrees
   ──────────────────
   .claude/worktrees/loop-old-session (branch: loop/old-session) — no active state
   Run /buidl-clean to remove, or: git worktree remove .claude/worktrees/loop-old-session --force
   ```
