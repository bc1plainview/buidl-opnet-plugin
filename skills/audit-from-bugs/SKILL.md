---
name: audit-from-bugs
description: |
  Audit skill derived from 27 confirmed real OP_NET bugs. Triggers on: audit, review, security check, code review, PR review of OPNet code.

  Covers: btc-runtime, native-swap, opnet, opnet-node, op-vm, transaction repos.
  Categories: serialization, storage/pointer, arithmetic/AMM, access-control/crypto,
  business-logic, memory/bounds, gas/runtime, networking/indexer, type-safety.
---

# audit-from-bugs Skill

You are performing a security audit using patterns derived from 27 real OP_NET bugs. Apply ALL checks to every file you review. Do not stop at the first finding.

## Reference

Full pattern documentation with code examples: `knowledge/slices/security-audit.md` (section "Real-Bug Vulnerability Patterns")

## The 27 Checks

### SERIALIZATION (5 checks)

1. **[CRITICAL] PAT-S1: Generic integer read** — Search for `value[0] as T` in any generic read/deserialize method. This returns only the low byte of any integer. Must use `new BytesReader(value).read<T>()`. _(btc-runtime PR #137)_

2. **[CRITICAL] PAT-S2: BytesReader/BytesWriter offset** — For every `readUXX()` / `writeUXX()` method: must read/write at `currentOffset` (not `currentOffset + BYTE_LENGTH`), must increment `currentOffset += BYTE_LENGTH` after. _(btc-runtime PR #57)_

3. **[HIGH] PAT-S3: Save/load type matrix** — Build a matrix of every `writeU8/16/32/64()` in `save()` paired with `readU8/16/32/64()` in `load()`. Any mismatch = upper bytes silently truncated. _(btc-runtime PR #88)_

4. **[HIGH] PAT-S4: Hex prefix stripping** — Search for `.replace('0x', '')`. ALWAYS wrong for hex stripping. Replace with `str.startsWith('0x') ? str.slice(2) : str`. _(opnet PR #135)_

5. **[MEDIUM] PAT-S5: Implicit integer narrowing** — Every `writeU16(x)`, `writeU8(x)`, `writeU32(x)` — verify `x` is explicitly cast to the matching type or is already that type. _(btc-runtime PR #52)_

### STORAGE / POINTER (3 checks)

6. **[CRITICAL] PAT-P1: Key concatenation collision** — Any template literal joining two string keys: `` `${a}${b}` `` without a delimiter. Must use length-prefix: `` `${a.length}:${a}${b.length}:${b}` ``. _(btc-runtime PR #61)_

7. **[HIGH] PAT-P2: Conditional hash bypass** — Search for `typed.length !== 32 ? hash(typed) : typed` or similar. Always hash unconditionally. _(btc-runtime PR #61)_

8. **[HIGH] PAT-P3: verifyEnd parameter** — In `verifyEnd(size)`, condition must be `size > buffer.byteLength`, NOT `currentOffset > buffer.byteLength`. _(btc-runtime PR #60)_

### ARITHMETIC / AMM (4 checks)

9. **[HIGH] PAT-A1: Silent zero return for undefined math** — Search for `if (x.isZero()) return u256.Zero` in functions where zero input is undefined (log, sqrt of negative). Must `throw new Revert(...)`. _(btc-runtime PR #129)_

10. **[CRITICAL] PAT-A2: AMM constant-product integrity** — Any reserve update function: verify BOTH sides maintain `k = B * T`. Pattern `T -= dT; B += dB` independently is WRONG. Must: `k = B*T; T -= dT; B = k/T`. _(native-swap PR #63)_

11. **[CRITICAL] PAT-A3: Proportional reserve removal on purge/slash** — Any function removing tokens from virtual token reserve must remove proportional BTC: `btcOut = (tokens * virtualBTC) / virtualTokens`. Both updated atomically. _(native-swap PR #51)_

12. **[HIGH] PAT-L2: Trade accumulator exhaustion** — Before adding to any buy/sell accumulator, verify `total + new < projectedReserve`. Revert if accumulation would exhaust the pool. _(native-swap PR #63)_

### ACCESS CONTROL / CRYPTO (4 checks)

13. **[CRITICAL] PAT-C1: Signature replay protection** — Any `verifySignature` call: verify the signed payload includes a per-address monotonically-increasing nonce. Increment after success. _(btc-runtime PR #60)_

14. **[HIGH] PAT-C2: Selector type string accuracy** — Every `encodeSelector('funcname(type1,type2,...)')` call: cross-check every type against actual AssemblyScript parameter types. _(btc-runtime PR #61, PR #60)_

15. **[CRITICAL] PAT-C3: Decrypt returns null on failure** — Any decrypt function: return type must be `T | null`. NEVER return the original ciphertext on failure. _(opnet-node PR #192)_

16. **[HIGH] PAT-C4: EC public key prefix validation** — Any code identifying EC public key by buffer length: must also validate `buf[0] in {0x02, 0x03}` for 33 bytes, or `buf[0] === 0x04` for 65 bytes. _(opnet-node PR #225)_

### BUSINESS LOGIC (2 checks)

17. **[CRITICAL] PAT-L1: CEI order in AMM activation** — Provider activation that reads liquidity for reserve calculation must occur BEFORE any `subtract/decrease` on that provider's liquidity in the same call path. _(native-swap PR #67)_

18. **[HIGH] PAT-L3: UTXO commitment placement** — `reportUTXOUsed()` / `markUTXOSpent()` must only appear in confirmed-success paths, never at a point where both success and failure branches have merged. _(native-swap PR #48)_

### MEMORY / BOUNDS (2 checks)

19. **[HIGH] PAT-M1: Array push off-by-one** — All `push()` bounds checks: `> MAX` must be `>= MAX` for 0-indexed arrays where valid indices are `0..MAX-1`. _(btc-runtime PR #61)_

20. **[HIGH] PAT-M2: Memory padding offset** — In write-data-then-pad-to-length operations: track `bytes_written = slice.len()`, use that as padding base offset, NOT `source_buffer.len()`. _(op-vm PR #130)_

### GAS / RUNTIME (2 checks)

21. **[HIGH] PAT-G1: Gas capture before ExitData** — In any VM exit handler: `get_used_gas()` must be called BEFORE constructing the `ExitData`/`ExitResult`. _(op-vm PR #109)_

22. **[CRITICAL] PAT-G2: Mutex double-lock** — In Rust async code: search for two `mutex.lock()` calls on the same mutex within the same task/scope. Second lock while first guard is alive = deadlock. _(op-vm PR #77)_

### NETWORKING / INDEXER (2 checks)

23. **[HIGH] PAT-N1: Null-safe Buffer construction** — Any `Buffer.from(x, 'hex') || fallback` where `x` may be null/undefined: `||` doesn't catch exceptions. Must be `x ? Buffer.from(x, 'hex') : fallback`. _(opnet-node PR #218)_

24. **[HIGH] PAT-N2: Promise resolve in search loop** — Any Promise that resolves a found-item: resolve INSIDE the loop at the point of match (`resolve(item); return;`), not outside after the loop ends. _(opnet-node PR #192)_

### TYPE SAFETY (3 checks)

25. **[MEDIUM] PAT-T1: Abstract interface return types** — Every `abstract` method implementing an external interface: return type must exactly match the interface specification. _(transaction PR #86)_

26. **[MEDIUM] PAT-T2: Browser ECPair RNG** — Any `ECPair.makeRandom()` without custom `rng` option in browser-capable code: must provide `rng: (size) => Buffer.from(randomBytes(size))`. _(transaction PR #109)_

27. **[MEDIUM] PAT-T3: Reassigned variable used for fallback** — Any code pattern `x = x[key]; if (!x) x = x[fallbackKey]` — after the first assignment, `x` is no longer the original map. Preserve original reference. _(opnet PR #78)_

## Output Format

For each finding:
```
**[SEVERITY] PAT-XX: Title**
- File: path/to/file.ts
- Line: N
- Pattern: which pattern above triggered
- Evidence: the actual code fragment
- Impact: what can go wrong
- Fix: specific remediation
- Ref: original bug PR
```

Always check ALL 27 patterns. Do not stop at the first finding.

## Severity Definitions (OPNet Context)

- **CRITICAL**: Can drain funds, corrupt consensus state, enable replay attacks, cause node deadlock/crash
- **HIGH**: Can corrupt indexes, bypass authentication, cause logic errors that affect trades or balances
- **MEDIUM**: Type mismatches, browser compatibility, silent wrong behavior without financial impact
- **LOW**: Code quality, missing error messages, minor inconsistencies
