# Knowledge System — Hierarchy & Canonical Sources

## Architecture

```
knowledge/
├── opnet-bible.md              Master reference (71 KB, 1975 lines)
├── opnet-troubleshooting.md    Error diagnoses (16 KB, 20+ issues)
├── README.md                   This file — hierarchy rules
└── slices/
    ├── contract-dev.md         Contract agent knowledge
    ├── frontend-dev.md         Frontend agent knowledge
    ├── backend-dev.md          Backend agent knowledge
    ├── security-audit.md       Auditor + reviewer knowledge
    ├── deployment.md           Deployer agent knowledge
    ├── e2e-testing.md          On-chain E2E tester knowledge (MANDATORY gate)
    ├── ui-testing.md           UI tester knowledge
    ├── integration-review.md   Reviewer cross-layer checks
    └── project-setup.md        Shared setup reference
```

## Canonical Source Rules

When `opnet-bible.md` and a domain slice disagree, the **domain slice wins**.

Rationale: Slices are maintained per-agent and updated more frequently with domain-specific corrections. The bible is the master reference for cross-cutting concerns (package versions, network config, general TypeScript rules), but each agent's slice is authoritative for its domain.

### Precedence order (highest to lowest):

1. **Agent's assigned slice** — authoritative for that agent's domain
2. **opnet-troubleshooting.md** — authoritative for error diagnosis
3. **opnet-bible.md** — authoritative for cross-cutting rules (TypeScript Law, package versions, network config)
4. **project-setup.md** — authoritative for initial project scaffolding

### Cross-cutting rules owned by the bible:

These rules live in `opnet-bible.md` and apply to ALL agents equally. Slices should not override them:

- TypeScript Law (FORBIDDEN types: `any`, `!`, `@ts-ignore`, etc.)
- Package version pinning (`@rc` tags, `@noble/hashes` override)
- Network configuration (`networks.opnetTestnet`, NOT `networks.testnet`)
- Signer rules (frontend: null/null, backend: keypair/mldsaKeypair)
- No raw PSBT construction
- No `Buffer` (use `Uint8Array` + `BufferHelper`)

### Domain rules owned by slices:

These rules are authoritative in each slice and may extend or specialize the bible:

- `contract-dev.md`: AssemblyScript patterns, btc-runtime API, storage pointers, gas limits
- `frontend-dev.md`: React patterns, WalletConnect v2, design system, 19 known mistakes
- `backend-dev.md`: hyper-express, worker threads, MongoDB, rate limiting, health checks
- `security-audit.md`: 27 PAT-XX patterns, vulnerability catalog, audit methodology
- `deployment.md`: TransactionFactory, pre-deploy checklist, receipt format
- `e2e-testing.md`: Real on-chain testing, payable method patterns, multi-wallet flows, output.to bech32 gotcha
- `ui-testing.md`: Playwright patterns, wallet mocking, screenshot conventions
- `integration-review.md`: Cross-layer ABI checks, signer validation, network consistency

## Maintenance

When updating knowledge:

1. If the change affects a single domain: update the slice only
2. If the change affects all agents: update the bible, then verify slices don't contradict
3. If a slice contradicts the bible on a domain-specific point: the slice is correct — update the bible
4. If a slice contradicts the bible on a cross-cutting rule: the bible is correct — update the slice
