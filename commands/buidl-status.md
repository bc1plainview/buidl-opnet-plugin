---
description: "Show current loop state"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop — Status

Show the current state of The Loop.

## Steps

1. Read `.claude/loop/state.local.md`.
2. If no state file exists, say "No loop is currently running."
3. If a state file exists, display:

```
Loop Status
───────────
Session:   [name]
Status:    [status]
Phase:     [current_phase]
Cycle:     [cycle] / [max_cycles]
Worktree:  [path]
Branch:    [branch]
PR:        [url or "not created yet"]
Started:   [timestamp]
```

4. If there are review files in the session directory, show the latest verdict.
5. If the status is `done` or `failed`, include the summary.
