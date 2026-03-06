# Retrospective: pixel-art-redesign
Date: 2026-03-06
Project Type: opnet (frontend-only)
Outcome: PASS on cycle 1
Tokens Used: ~180000
Duration: ~60 minutes

## What Worked
- CSS-first approach for visual redesigns gives massive impact with minimal component changes
- Web Audio API singleton: zero deps, procedural sounds, clean API
- Parallel agent dispatch saves significant time
- Spec-driven development with clear acceptance criteria

## What Failed
- Builder missed peripheral components (SankeyDiagram, SkeletonCard, etc.)
- Sound default was ON instead of OFF (spec violation)
- Stale font load left in HTML
- Old Playwright tests not updated

## Anti-Patterns
- Don't trust builder to update ALL files -- grep sweep for old patterns after
- Don't assume localStorage defaults are correct -- test first-visit behavior
- Don't leave stale font loads when CSS handles font loading
- Include test updates as explicit tasks in specs

## Recommendations
- Post-builder consistency check: grep for old font names, borderRadius, deprecated CSS
- For audio: verify first-visit (no localStorage) behavior
- For Playwright: list test updates as explicit spec tasks
