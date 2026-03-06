# Retrospective: op-1155-standard
Date: 2026-03-06
Project Type: opnet (contract-only)
Outcome: PASS on cycle 1 (with 2-cycle audit)
Tokens Used: ~416000
Duration: ~75 minutes

## What Worked
- btc-runtime already exports IOP1155, events, and type hashes -- check runtime exports before implementing
- Contract-dev agent delivered 794-line base class + 34 tests in one pass
- Auditor caught real domain-separation bug (wrong type hash for approval signatures)
- 27-pattern vulnerability scan caught actual PAT-C2 violation

## What Failed
- Copy-paste bug: OP1155_TRANSFER_TYPE_HASH reused for approval signatures
- fn_name had mismatched @returns (3 declared, 1 written)
- Zero-amount guards inconsistent across paths
- Address === vs == gotcha in AssemblyScript

## Anti-Patterns
- Don't reuse type hashes across signature operation types
- Don't trust @returns decorators match BytesWriter content without verification
- Don't use === for Address comparison in AssemblyScript
- Always apply guards consistently across all code paths (single and batch)

## Recommendations
- Check btc-runtime exports before implementing from scratch
- 27-pattern audit scan is mandatory for any OPNet contract
- Cache domain separator for gas efficiency
- Batch size cap (256) should be standard
