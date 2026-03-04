---
description: "Resume an interrupted loop from its last checkpoint"
allowed-tools: ["Bash(bash:*)", "Bash(git:*)"]
---

# The Loop — Resume

Resume an interrupted loop session from its last checkpoint. Use this after context exhaustion, timeouts, or manual cancellation when you want to continue where you left off.

## Steps

### 1. Find State File

Check for state files in order:
1. `.claude/loop/state.yaml`
2. `.claude/loop/state.local.md` (legacy fallback)

If neither exists, report: "No loop session found. Start a new one with /buidl."

### 2. Parse State

Read from the state file:
- `session_name` — identifies the session directory
- `status` — current status (done/failed/cancelled/timed_out are terminal; anything else is resumable)
- `current_phase` — where we left off
- `cycle` — current build-review cycle
- `max_cycles` — cycle limit
- `worktree_path` — path to the git worktree
- `worktree_branch` — branch name
- `project_type` — opnet or generic
- `agent_status` — which agents have completed (for build phase)
- `tokens_used` — tokens consumed so far
- `pr_url` — PR URL if one was created

### 3. Verify Environment

1. Check the worktree still exists at `worktree_path`. If not:
   - Check if the branch exists: `git show-ref --verify refs/heads/<branch>`
   - If branch exists: recreate worktree with `git worktree add <path> <branch>`
   - If branch is gone: report "Worktree and branch are gone. Start fresh with /buidl."
2. Check the session directory exists: `.claude/loop/sessions/<name>/`

### 4. Check for Checkpoint

Look for `.claude/loop/sessions/<name>/checkpoint.md`. If it exists, read it for:
- Phases completed
- Key decisions made
- Last agent dispatched
- Recommended next action

### 5. Report Position

Display to the user:

```
Loop Resume
───────────
Session:      [name]
Status:       [status]
Phase:        [current_phase]
Cycle:        [cycle] / [max_cycles]
Worktree:     [path]
Branch:       [branch]
PR:           [url or "not created yet"]
Tokens used:  [tokens_used]
Checkpoint:   [found/not found]

Resuming from: [phase description]
```

### 6. Resume Based on Phase

Update state: set `status` to the appropriate active status for the phase.

Use `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-state.sh key=value` for all state updates.

**challenge** → Re-read `.claude/loop/sessions/<name>/challenge.md` if it exists and continue the challenge Q&A. If challenge.md is complete, advance to specify.

**specify** → Check if spec files exist in `sessions/<name>/spec/`. If all three (requirements.md, design.md, tasks.md) exist, present them for approval. If incomplete, continue generating.

**explore** → Re-launch the explorer agents. Previous context.md is likely stale after a context reset.

**build** → This is the most common resume point. Read `agent_status` from state to determine which agents completed:
- For each agent with status `pending` or `in_progress`: dispatch it
- For each agent with status `done`: skip it (artifacts should exist)
- Follow the same execution plan logic as Phase 4 in the main buidl command
- Read `current_step` to know where in the plan to resume

**review** → Re-launch the loop-reviewer with the current PR.

**done/failed/cancelled/timed_out** → These are terminal states. Report the final status and ask:
- "Start a new loop with /buidl?"
- "Clean up with /buidl-clean?"

### 7. Continue Execution

After resuming into the correct phase, follow the same phase logic as defined in the main `/buidl` command. The stop-hook will manage subsequent cycles automatically.
