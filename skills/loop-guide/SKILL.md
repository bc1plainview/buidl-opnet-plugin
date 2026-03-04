---
name: loop-guide
description: |
  This skill should be used when the user describes a new feature idea, wants to start a new project, mentions wanting to build something, or asks about the buidl commands. Proactively suggest the appropriate /buidl command when the user's intent matches. Examples of triggers: "I want to build...", "I have an idea for...", "Let's add...", "How do I use the loop?", "What commands does the loop have?", "build an OPNet contract", "OP20 token", "OP721 NFT", "Bitcoin smart contract", "OPNet frontend", "wallet integration", "NativeSwap", "MotoSwap", "OPNet dApp"
---

# The Loop — Usage Guide (v3.0)

The Loop is a development lifecycle plugin. It turns ideas into production-ready PRs through structured interrogation, specification, and autonomous build-review cycles. v3 adds checkpointing, cost tracking, resume capability, and a learning system.

## When to suggest each command:

### `/buidl "idea description"`
Suggest when the user:
- Describes a new feature idea ("I want to add staking rewards")
- Wants to build something from scratch
- Has a rough concept but hasn't specified it yet

This runs the FULL pipeline: challenge the idea -> generate a spec -> explore the codebase -> build in isolation -> review -> iterate until clean -> retrospective -> produce a PR.

### `/buidl path/to/spec/`
Suggest when the user:
- Already has spec documents (requirements.md, design.md, tasks.md)
- Previously ran `/buidl-spec` and now wants to build
- Has a well-defined spec from another source

This skips the challenge and specify phases and goes straight to explore -> build -> review.

### `/buidl-spec "idea description"`
Suggest when the user:
- Wants to refine an idea but isn't ready to build yet
- Wants to think through requirements before committing to building
- Says things like "let me think about this first" or "I need to plan this out"

This runs ONLY the challenge and specify phases, producing spec documents without building anything.

### `/buidl-review <PR-number>`
Suggest when the user:
- Wants to review an existing PR
- Says "review PR 42" or "check this PR"
- Wants automated code review on existing work

### `/buidl-resume`
Suggest when the user:
- Had a loop interrupted (context exhaustion, timeout, manual cancel)
- Says "continue where I left off" or "pick up the loop"
- Sees a message about running `/buidl-resume`

Reads the checkpoint and state file to continue from the last phase.

### `/buidl-status`
Suggest when the user asks about the current loop state or seems unsure where things stand. Shows tokens used, elapsed time, and checkpoint info.

### `/buidl-cancel`
Suggest when the user wants to stop a running loop but keep the work.

### `/buidl-clean`
Suggest when the user wants to stop AND remove the worktree and branch.

## How it works (for explaining to the user):

1. **Challenge** -- The Loop interrogates your idea. It runs through 5 gates (goal alignment, build vs buy, simplest thing, problem framing, testability), asks structured spec questions, then runs a pre-mortem and plays devil's advocate. This catches gaps before they become bugs. *Checkpoint saved.*

2. **Specify** -- From your answers, it generates three documents: requirements.md (what), design.md (how), tasks.md (work breakdown). It validates these against a quality checklist and asks you to approve before building. *Checkpoint saved.*

3. **Explore** -- Two agents analyze the codebase in parallel: one maps the structure and conventions, one finds code relevant to the spec. This gives the builder context. *Checkpoint saved. Cost logged.*

4. **Build** -- Specialized agents work in an isolated git worktree (your main branch is never touched). For OPNet: contract-dev, frontend-dev, backend-dev, auditor, deployer, and UI tester each handle their domain. For generic projects: dynamic domain agents are generated from templates. Each agent has a max_turns limit. *Checkpoint after each agent. Cost logged per agent.*

5. **Review** -- A reviewer agent reads the PR diff (read-only, can't touch code). It checks spec compliance, correctness, security, test quality, and conventions. If it fails, findings are routed back to responsible agents for the next cycle. *Checkpoint saved.*

6. **Wrap-up** -- A retrospective is generated and saved to the learning store. Future sessions consult past retrospectives for matching project types.

## Key flags:
- `--max-cycles N` (default 3) -- how many build-review cycles before stopping
- `--max-retries N` (default 5) -- how many verify-fix attempts per cycle
- `--max-tokens N` (optional) -- token budget; if exceeded, asks to continue or cancel
- `--skip-challenge` -- skip the interrogation phase (use when you know exactly what you want)
- `--builder-model opus|sonnet` -- which model runs the builder
- `--reviewer-model opus|sonnet` -- which model runs the reviewer

## Resilience features (v3):
- **Checkpointing** -- every phase transition saves position for resume
- **Cost tracking** -- token spend logged per agent in cost-ledger.md
- **Wall-clock timeout** -- default 60 min max, gracefully saves for resume
- **Learning** -- retrospectives from past sessions inform future builds
- **Atomic state** -- all state writes go through write-state.sh (temp + rename)
