# Retrospective: foundry-docs-site
Date: 2026-03-05
Project Type: generic (Astro Starlight docs site)
Outcome: PASS on cycle 1
Tokens Used: ~150k estimated
Duration: ~45 minutes

## What Worked
- Reading actual source code (op-forge CLI) before writing docs ensured accuracy — every flag, option, and default matched real implementation
- Astro Starlight is excellent for docs sites — built-in search (Pagefind), sidebar, dark mode, responsive design
- Scoping to "Foundation + Core Pages" kept the session manageable while still producing a complete, deployable site
- OPNet dark theme with amber accents looked professional out of the box with minimal custom CSS
- Vercel deployment was seamless — zero config needed beyond vercel.json

## What Failed
- **Node v25 + Starlight v0.33 incompatibility**: docsLoader() fails silently due to ERR_UNSUPPORTED_NODE_MODULES_TYPE_STRIPPING. Cost ~20 minutes of debugging. The fix is `legacy: { collections: true }` + `src/content/config.ts` (not `src/content.config.ts`).
- **Builder agent only created ~60% of pages**: Had to manually create 8 missing pages (cast, anvil, chisel, config refs, FAQ, troubleshooting, snapshot). Builder ran out of turns or lost track of remaining tasks.
- **Social config breaking change**: Starlight v0.33 changed `social` from object to array format. Builder used the old format.
- **State file CWD issue**: write-state.sh uses relative path `./.claude/loop/state.yaml` which fails when CWD is the worktree, not the main repo.

## Effective Agent Configs
- loop-builder with 30 turns was insufficient for 25+ page docs site — consider 40+ turns or splitting into multiple builder passes
- loop-researcher (background, 10 turns) was effective for build-vs-buy gate

## Knowledge That Mattered
- op-forge source code was the primary knowledge source — reading actual CLI implementations produced accurate docs
- Starlight v0.33 docs were needed but not available in knowledge base — had to debug the social config and Node v25 issues empirically

## Anti-Patterns
- **Don't trust builder to create all files**: For content-heavy projects (many markdown files), verify file count after builder completes and fill gaps immediately
- **Don't assume latest Node works with all frameworks**: Node v25's type stripping breaks Starlight's module system. Pin to Node 22 LTS or use legacy collections mode.
- **Don't use `src/content.config.ts` with legacy mode**: Must be `src/content/config.ts` (inside content directory)

## Recommendations
- For future docs sites: start with the legacy collections approach on Node v25+ to avoid the docsLoader issue entirely
- For content-heavy builder tasks: pass explicit file checklist in the builder prompt and verify completion
- Consider a dedicated "docs-builder" agent type that specializes in Starlight/docs site generation
- Always run write-state.sh from the main repo root, not from worktrees
