---
description: "Show agent execution trace for the current loop session"
allowed-tools: ["Bash(bash:*)"]
---

# The Loop -- Trace

Show the execution trace for the current or most recent loop session.

## Steps

1. Check for state files in order:
   - `.claude/loop/state.yaml` (preferred)
   - `.claude/loop/state.local.md` (legacy fallback)
2. If neither exists, say "No loop is currently running."
3. Read `session_name` from the state file.
4. Check for trace file at `.claude/loop/sessions/<name>/artifacts/trace.jsonl`.
5. If trace file does not exist, say "No trace events recorded for this session."
6. If trace file exists, parse each JSONL line and render:

```
Agent Execution Trace: <session-name>
======================================

Timestamp            Event      Agent                Phase      Cycle  Details
-------------------  ---------  -------------------  ---------  -----  -------
2026-03-13T10:00:00Z dispatch   opnet-contract-dev   build      1      Starting contract development
2026-03-13T10:05:30Z complete   opnet-contract-dev   build      1      Build passed, ABI exported
2026-03-13T10:05:31Z dispatch   opnet-frontend-dev   build      1      Starting frontend development
...

Summary
-------
Total events: [N]
Agents dispatched: [list]
Errors: [count or "none"]
```

7. If `--tokens` data is present on events, include a token usage column.
8. If `--category` data is present on events, include it in the details.
9. Group events by cycle if multiple cycles exist, with a separator between cycles.
