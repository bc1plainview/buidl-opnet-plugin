# Retrospective: opnet-foundry
Date: 2026-03-05
Project Type: generic (TypeScript CLI monorepo)
Outcome: PASS on cycle 1
Duration: ~45 minutes

## What Worked
- Challenge phase was thorough -- 6 gates + spec questions caught scope issues early
- Scoping to "Foundation + op-forge core" was essential -- full 90+ tasks would have blown context
- Dynamic imports for OPNet packages (peer deps) avoids bundling and version conflicts
- pnpm workspace with shared package for cross-cutting concerns
- Templates directory with Counter/OP20/OP721 scaffolds

## What Failed
- Builder agent didn't add .gitignore (staged node_modules)
- Builder agent didn't add @types/node to packages that need Node.js APIs
- Builder agent used static type assertions on dynamic imports (TransactionFactory cast failed)
- Installed @btc-vision/bitcoin was v6 (no opnetTestnet), needed dynamic network resolution

## Effective Agent Configs
- loop-researcher (10 turns): perfect for build-vs-buy gate
- loop-builder (30 turns): hit turn limit, implemented most but missed some polish

## Knowledge That Mattered
- asconfig.json exact structure from OPNet docs
- unit-test-framework API (opnet, vm.it, Assert)
- TransactionFactory.signDeployment() parameter types
- Network resolution: opnetTestnet vs testnet across package versions

## Anti-Patterns
- Don't statically type-check dynamically imported external packages
- Don't forget .gitignore in greenfield projects
- Don't assume package versions -- check what's actually installed

## Recommendations
- For next session (op-cast): start with blockchain queries (simplest), then wallet, then ABI utils
- For op-anvil: research unit-test-framework's VM internals first to understand what can be exposed
- For op-chisel: tsx-based REPL is straightforward, AssemblyScript evaluation is the hard part
