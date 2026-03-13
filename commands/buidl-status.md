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
6. **Learning Health**: Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/audit-learning.sh 2>/dev/null | head -5` and display a one-line summary:
   ```
   Learning:       [N patterns (N stale) / N agents scored / N profiles]
   ```
7. **Mutation Score**: If `artifacts/testing/mutation-score.json` exists, parse and show:
   ```
   Mutation:       [X]% ([killed]/[total] killed) — [verdict]
   ```
   Example: `Mutation: 83% (15/18 killed) — PASS`
8. **Build Score Card**: If `artifacts/evaluation/progress-tracker.yaml` exists, parse and show the 4-dimension scores:
   ```
   Build Score:    spec=[X]% security=[N] mutation=[X]% health=[X]% — [verdict]
   ```
   Example: `Build Score: spec=95% security=0 mutation=83% health=80% — PASS`
9. If there are review files in the session directory, show the latest verdict.
10. If a checkpoint file exists at `.claude/loop/sessions/<name>/checkpoint.md`, show the last checkpoint timestamp and next action.
11. If the status is `done`, `failed`, `cancelled`, or `timed_out`, include the summary.
12. **Orphan worktree detection**: Run `git worktree list` and cross-reference with the active state:
   - For each worktree under `.claude/worktrees/loop-*`, check if there's a matching session in state.
   - If a worktree exists but no state file references it (or state is `done`/`cancelled`), flag it as orphaned:
   ```
   Orphaned Worktrees
   ──────────────────
   .claude/worktrees/loop-old-session (branch: loop/old-session) — no active state
   Run /buidl-clean to remove, or: git worktree remove .claude/worktrees/loop-old-session --force
   ```
