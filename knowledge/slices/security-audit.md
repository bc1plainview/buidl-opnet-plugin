# OPNet Security Audit Reference

> **Role**: Security auditors reviewing OPNet smart contracts, frontends, and backends
>
> **Self-contained**: All security rules, checklists, and vulnerability patterns needed for auditing are in this file. Covers contracts, frontends, and backends.

---

## Architecture Context (Security-Relevant)

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

- **Contracts are WebAssembly** -- Compiled from AssemblyScript
- **NON-CUSTODIAL** -- Contracts NEVER hold BTC. They verify L1 tx outputs.
- **Partial reverts** -- Only consensus layer execution reverts; Bitcoin transfers are ALWAYS final. **BTC sent to a contract that reverts is GONE.** This is the single most important security property to audit for.
- **No gas token** -- Uses Bitcoin directly.
- **CSV timelocks MANDATORY** -- All addresses receiving BTC in swaps MUST use CSV (CheckSequenceVerify) to prevent transaction pinning attacks.
- **SHA-256, not Keccak-256** -- OPNet uses SHA-256 for all hashing and method selectors.
- **Buffer is GONE** -- The entire stack uses `Uint8Array` instead of Node.js `Buffer`.
- **ML-DSA only** -- ECDSA/Schnorr are deprecated. Use `Blockchain.verifySignature()`.
- **Constructor gas limit**: 20M gas (hardcoded by protocol). Regular calls: 300M default.

### The Two Address Systems

| System | Format | Used For |
|--------|--------|---------|
| Bitcoin Address | Taproot P2TR (`bc1p...`) | External identity, walletconnect |
| OPNet Address | ML-DSA public key hash (32 bytes, 0x hex) | Contract balances, internal state |

You CANNOT loop through Bitcoin addresses and transfer tokens. Contract storage uses ML-DSA addresses.

---

## Contract Security Checklist

Before deploying ANY contract, verify ALL of these:

```
[ ] All u256 operations use SafeMath (no raw +, -, *, /)
[ ] All loops are bounded (no while loops, all for loops have max iterations)
[ ] No unbounded array iterations
[ ] No iterating all map keys
[ ] State changes happen BEFORE external calls (checks-effects-interactions)
[ ] All user inputs validated
[ ] Access control properly implemented (onlyOwner, etc.)
[ ] ReentrancyGuard used where needed
[ ] No integer overflow/underflow possible
[ ] No Blockchain.block.medianTimestamp for time logic (use block.number)
[ ] No float arithmetic (f32/f64) in consensus code
[ ] No native Map<Address, T> (use AddressMemoryMap)
[ ] Blockchain.verifySignature() is the ONLY signature verification
[ ] State NOT initialized in constructor (use onDeployment)
[ ] @method() declares ALL params (no bare @method())
[ ] No ABIDataTypes import (it's a global)
[ ] CSV timelocks on all BTC-receiving swap addresses
[ ] No iterating all token holders for airdrops (use claim pattern)
[ ] No approve() -- use increaseAllowance()/decreaseAllowance()
[ ] save() called after mutations on StoredU256Array/StoredAddressArray
[ ] BytesWriter size matches actual content written
[ ] callMethod() includes super.callMethod() default case
[ ] encodeSelector uses full method signature with param types
```

---

## Frontend Security Checklist

```
[ ] signer: null, mldsaSigner: null on ALL frontend sendTransaction calls
[ ] No private keys anywhere in frontend code
[ ] ALWAYS simulate before send (check 'error' in sim)
[ ] No raw PSBT construction
[ ] No @btc-vision/transaction for contract calls
[ ] Wallet connection gated on isConnected + address (not signer object)
[ ] Address.fromString called with 2 params (not 1, not bc1p... string)
[ ] No Buffer usage anywhere
[ ] No static feeRate
[ ] getContract cached, not recreated per render
[ ] optimize: false in all getUTXOs calls
[ ] setTransactionDetails() called BEFORE simulate for payable functions
[ ] Output index 0 reserved -- extra outputs start at index 1
[ ] No getPublicKeyInfo when 0x address is already available
```

---

## Backend Security Checklist

```
[ ] signer: wallet.keypair AND mldsaSigner: wallet.mldsaKeypair on ALL backend sendTransaction calls
[ ] Private keys stored in environment variables, NEVER in code
[ ] ALWAYS simulate before send (check 'error' in sim)
[ ] No raw PSBT construction
[ ] No @btc-vision/transaction for contract calls (use opnet getContract)
[ ] Worker threads for CPU-bound operations
[ ] Rate limiting on all endpoints
[ ] Input validation on all user-provided data
[ ] MongoDB for persistence (not file-based storage)
[ ] Error handler registered FIRST on HyperExpress server
[ ] No Buffer usage anywhere (Uint8Array + BufferHelper)
[ ] optimize: false in all getUTXOs calls
[ ] deriveOPWallet() for wallet derivation (not derive())
```

---

## CEI Pattern (Checks-Effects-Interactions)

Always in this order:
1. **Checks**: Validate all conditions (permissions, balances, inputs)
2. **Effects**: Update all state
3. **Interactions**: Make external calls (cross-contract calls, transfers)

```typescript
public transfer(calldata: Calldata): BytesWriter {
    const to = calldata.readAddress();
    const amount = calldata.readU256();
    const sender = Blockchain.tx.sender;

    // 1. CHECKS
    const balance = this.balances.get(sender).get();
    if (u256.lt(balance, amount)) throw new Revert('Insufficient balance');

    // 2. EFFECTS -- update state FIRST
    this.balances.get(sender).set(SafeMath.sub(balance, amount));
    this.balances.get(to).set(SafeMath.add(this.balances.get(to).get(), amount));

    // 3. INTERACTIONS -- external calls LAST
    // (safe to call external contract now that state is updated)
}
```

---

## Critical Transaction Rules

### The Absolute Law

| NEVER | ALWAYS |
|-------|--------|
| `new Psbt()` | `getContract()` -> simulate -> `sendTransaction()` |
| `Psbt.fromBase64()` | Check `'error' in sim` before sending |
| `@btc-vision/transaction` for contract calls | `opnet` package `getContract()` for contract calls |
| Manual calldata encoding | ABI-typed method calls via `getContract()` |
| `signer: wallet.keypair` on frontend | `signer: null` on frontend |
| `signer: null` on backend | `signer: wallet.keypair` on backend |
| Skip simulation | ALWAYS simulate before sending |
| Static feeRate | `provider.gasParameters()` or undefined |
| `optimize: true` in getUTXOs | `optimize: false` ALWAYS |

### `@btc-vision/transaction` -- ONLY for TransactionFactory

The only valid use of `@btc-vision/transaction` for building transactions is `TransactionFactory` -- and only for:
- Plain BTC transfers (`createBTCTransfer`)
- Contract deployments

NOT for contract calls. Never.

---

## Signature Verification

### The ONLY Correct Approach (Contract-Side)

```typescript
// CONTRACT SIDE -- Blockchain.verifySignature() ONLY
const isValid: bool = Blockchain.verifySignature(
    Blockchain.tx.origin,   // ExtendedAddress
    signature,              // Uint8Array
    messageHash,            // 32-byte SHA256 hash
    false,                  // false = auto (Schnorr now, ML-DSA when enforced)
);
```

### DEPRECATED -- Never Use Directly

```typescript
// DEPRECATED -- will break when quantum consensus flag flips
Blockchain.verifyECDSASignature(...)          // DEPRECATED
Blockchain.verifyBitcoinECDSASignature(...)   // DEPRECATED
Blockchain.verifySchnorrSignature(...)        // DEPRECATED (but still works via verifySignature path)
```

### Client-Side Signing -- Always Use Auto Methods

```typescript
import { MessageSigner } from '@btc-vision/transaction';

// AUTO methods detect browser (OP_WALLET) vs backend (local keypair) automatically

// Schnorr
const signed = await MessageSigner.signMessageAuto(message);              // Browser: OP_WALLET
const signed = await MessageSigner.signMessageAuto(message, keypair);     // Backend: local

// Taproot-tweaked Schnorr
const signed = await MessageSigner.tweakAndSignMessageAuto(message);                    // Browser
const signed = await MessageSigner.tweakAndSignMessageAuto(message, keypair, network); // Backend

// ML-DSA (quantum-resistant)
const signed = await MessageSigner.signMLDSAMessageAuto(message);                    // Browser
const signed = await MessageSigner.signMLDSAMessageAuto(message, mldsaKeypair);      // Backend
```

### Non-Auto Methods -- Environment-Specific (Use with Caution)

```typescript
// ONLY in known backend environments
MessageSigner.signMessage(keypair, message);
MessageSigner.tweakAndSignMessage(keypair, message, network);
MessageSigner.signMLDSAMessage(mldsaKeypair, message);
```

---

## Common Agent Mistakes (Security-Critical)

These are real mistakes AI agents make repeatedly. Each one is a potential security vulnerability:

### 1. Timestamp Manipulation

```
VULNERABILITY: Using Blockchain.block.medianTimestamp for time-dependent logic
IMPACT: Bitcoin's MTP can be MANIPULATED BY MINERS within +/-2 hours
FIX: ALWAYS use Blockchain.block.number (block height). Strictly monotonic, tamper-proof.
     144 blocks = ~24h, 1008 blocks = ~1 week.
```

### 2. Private Key Exposure

```
VULNERABILITY: Passing signer: wallet.keypair on frontend
IMPACT: Private key exposed to browser, stolen by XSS or malicious extensions
FIX: Frontend ALWAYS uses signer: null, mldsaSigner: null. Wallet handles signing.
```

### 3. Missing Simulation

```
VULNERABILITY: Skipping simulation before sendTransaction()
IMPACT: Bitcoin transfers are irreversible. BTC sent to a reverted contract is GONE.
FIX: ALWAYS simulate first. Check 'error' in sim before sending.
```

### 4. Raw PSBT Construction

```
VULNERABILITY: Using new Psbt() or Psbt.fromBase64() for OPNet transactions
IMPACT: Bypasses OPNet transaction format, security checks, gas estimation
FIX: Use getContract() -> simulate -> sendTransaction() pattern.
```

### 5. Wrong Hashing Algorithm

```
VULNERABILITY: Using Keccak256 selectors (Ethereum-style)
IMPACT: Method selectors won't match, calls fail or hit wrong methods
FIX: OPNet uses SHA256 for all hashing and method selectors.
```

### 6. Missing SafeMath

```
VULNERABILITY: Raw u256 arithmetic (+, -, *, /) without SafeMath
IMPACT: Silent overflow/underflow, token minting from nothing, balance corruption
FIX: SafeMath.add(), SafeMath.sub(), SafeMath.mul(), SafeMath.div() for ALL u256 ops.
```

### 7. Constructor Initialization

```
VULNERABILITY: Putting initialization logic (minting, state writes) in constructor
IMPACT: Constructor runs on EVERY contract interaction, not just deployment.
        Tokens minted on every call, state reset on every call.
FIX: ALL initialization logic in onDeployment(), which runs only ONCE.
```

### 8. Bare @method() Decorator

```
VULNERABILITY: @method() with no params = zero ABI inputs declared
IMPACT: Callers must hand-roll calldata, SDK getContract() broken.
        Cannot be fixed without redeployment.
FIX: ALWAYS declare all method params: @method({ name: 'to', type: ABIDataTypes.ADDRESS }, ...)
```

### 9. Map Reference Equality

```
VULNERABILITY: Using native Map<Address, T> in contracts
IMPACT: AssemblyScript Map uses reference equality. Two Address instances with
        identical bytes are treated as different keys. Balances lost.
FIX: Use AddressMemoryMap, StoredMapU256, or Nested. For in-memory caches, key by string.
```

### 10. Deprecated Signature Methods

```
VULNERABILITY: Using verifyECDSASignature or verifySchnorrSignature directly
IMPACT: Will break when consensus disables UNSAFE_QUANTUM_SIGNATURES_ALLOWED
FIX: ALWAYS use Blockchain.verifySignature() -- consensus-aware, auto-selects algorithm.
```

### 11. Wrong Wallet Derivation

```
VULNERABILITY: Using mnemonic.derive() instead of mnemonic.deriveOPWallet()
IMPACT: Different derivation path. Keys don't match OPWallet.
        "Invalid ML-DSA legacy signature" errors.
FIX: ALWAYS use mnemonic.deriveOPWallet(AddressTypes.P2TR, 0)
```

### 12. Buffer Usage

```
VULNERABILITY: Using Buffer anywhere in the stack
IMPACT: Buffer is completely removed from OPNet. Runtime crashes.
FIX: Use Uint8Array everywhere. BufferHelper from @btc-vision/transaction for hex conversions.
```

### 13. Wrong assemblyscript Package

```
VULNERABILITY: Using upstream assemblyscript instead of @btc-vision/assemblyscript
IMPACT: No closure support, incompatible with OPNet runtime.
FIX: npm uninstall assemblyscript FIRST, then npm i @btc-vision/assemblyscript@^0.29.2
```

### 14. Unbounded Loops

```
VULNERABILITY: while loops or unbounded for loops in contracts
IMPACT: Gas explosion -- can consume all gas, effectively DOSing the contract.
FIX: ALL loops must be bounded. Cap iterations. Use pagination for large datasets.
```

### 15. Float Arithmetic

```
VULNERABILITY: Using f32/f64 in consensus code
IMPACT: Non-deterministic across CPUs. Different nodes compute different results.
        Consensus failure.
FIX: Use integer arithmetic only. SafeMath for u256.
```

### 16. Missing CSV Timelocks

```
VULNERABILITY: BTC-receiving swap addresses without CSV timelocks
IMPACT: Transaction pinning attacks. Attacker creates massive chains of unconfirmed
        transactions, preventing your transaction from confirming. Destroys DEXs.
FIX: ALL addresses receiving BTC in OPNet swaps MUST use CSV timelocks.
```

### 17. Address.fromString Misuse

```
VULNERABILITY: Passing bc1p... address or single param to Address.fromString()
IMPACT: Wrong address constructed, tokens sent to wrong/invalid address
FIX: Address.fromString(hashedMLDSAKey, publicKey) -- TWO hex params.
     hashedMLDSAKey = 32-byte SHA256 hash of ML-DSA key (NOT raw ML-DSA key)
     publicKey = Bitcoin tweaked pubkey (33 bytes compressed)
```

### 18. Static Fee Rate

```
VULNERABILITY: Hardcoded feeRate in sendTransaction
IMPACT: Overpay on low-fee periods, underpay and fail to confirm on high-fee periods
FIX: Use provider.gasParameters() for live rate, or omit for default.
```

### 19. Importing ABIDataTypes/Decorators

```
VULNERABILITY: Importing ABIDataTypes or @method from @btc-vision/btc-runtime/runtime
IMPACT: Build failure. These are compile-time globals injected by opnet-transform.
FIX: Do NOT import. Use ABIDataTypes.ADDRESS, @method(...) etc. directly.
```

---

## Real-Bug Vulnerability Patterns (27 Confirmed Bugs)

> Derived from real bugs found in btc-vision GitHub repos: btc-runtime, native-swap, opnet, opnet-node, op-vm, transaction.
> Each pattern has a PAT-XX ID, severity, detection rule, fix, and PR reference.

### SERIALIZATION / ENCODING

#### PAT-S1: Generic integer deserialization reads only first byte [CRITICAL]

When a generic `toValue<T>()` or read method uses `value[0] as T` instead of `BytesReader.read<T>()`, only the low byte of any integer is returned. A balance of 1,000,000 reads back as 64.

- **Detection:** grep `value[0] as T` or `arr[0] as T` in generic read methods
- **Fix:** Use `new BytesReader(value).read<T>()` — reads the correct byte width for the type
- **Real bug:** btc-runtime PR #137

```typescript
// BROKEN — only reads low byte regardless of type
toValue<T>(): T { return this.value[0] as T; } // 1,000,000 → 64

// FIXED — reads correct byte width
toValue<T>(): T { return new BytesReader(this.value).read<T>(); }
```

#### PAT-S2: BytesReader/BytesWriter off-by-one — reads at offset+N instead of offset [CRITICAL]

`readU8()` / `writeU8()` used `currentOffset + U8_BYTE_LENGTH` as the index instead of `currentOffset`, and failed to advance `currentOffset`. All u8 fields in serialized structs were corrupted.

- **Detection:** grep `getUint8(.*\+ U8_BYTE_LENGTH)` or `setUint8(.*\+ U8_BYTE_LENGTH)`
- **Fix:** Read/write at `currentOffset`, then `currentOffset += BYTE_LENGTH`
- **Real bug:** btc-runtime PR #57

```typescript
// BROKEN — reads at wrong offset, never advances
readU8(): u8 { return this.buffer.getUint8(this.currentOffset + U8_BYTE_LENGTH); }

// FIXED — reads at currentOffset, then advances
readU8(): u8 {
    const val = this.buffer.getUint8(this.currentOffset);
    this.currentOffset += U8_BYTE_LENGTH;
    return val;
}
```

#### PAT-S3: Write/read type mismatch in save/load — upper bytes silently truncated [HIGH]

`save()` writes a field as `writeU64()` but `load()` reads it as `readU32()`. The upper 4 bytes are discarded silently.

- **Detection:** Build a write/read type matrix for every `save()`/`load()` pair
- **Fix:** Use consistent types; prefer the smaller type that fits the data range
- **Real bug:** btc-runtime PR #88

#### PAT-S4: `.replace('0x', '')` corrupts hex strings [HIGH]

JavaScript's `String.replace(string, string)` replaces only the FIRST occurrence. If the hex data contains `0x`, this strips it from the wrong position.

- **Detection:** grep `.replace('0x', '')` — 100% of occurrences should be replaced
- **Fix:** `str.startsWith('0x') ? str.slice(2) : str`
- **Real bug:** opnet PR #135

```typescript
// BROKEN — replaces first '0x' occurrence anywhere in string
const clean = hex.replace('0x', '');

// FIXED — only strips leading prefix
const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
```

#### PAT-S5: Implicit integer narrowing in write calls [MEDIUM]

`writeU16(value.length)` where `value.length` is `i32` — AssemblyScript may silently truncate.

- **Detection:** grep all `writeU16(`, `writeU8(`, `writeU32(` and verify argument type exactly matches
- **Fix:** Explicit cast: `writeU16(u16(value.length))`
- **Real bug:** btc-runtime PR #52

---

### STORAGE / POINTER

#### PAT-P1: KeyMerger string key collision — no length prefix [CRITICAL]

Concatenating `parentKey + childKey` as plain strings is ambiguous: `("abc","def")` and `("ab","cdef")` both produce `"abcdef"`. Different logical entries write to the same storage slot.

- **Detection:** Template literals joining two keys: `` `${this.parentKey}${key}` `` with no separator
- **Fix:** Length-prefix both segments: `` `${a.length}:${a}${b.length}:${b}` ``
- **Real bug:** btc-runtime PR #61 (KeyMerger)

```typescript
// BROKEN — ("abc","def") collides with ("ab","cdef")
const storageKey = `${this.parentKey}${key}`;

// FIXED — length-prefixed, unambiguous
const storageKey = `${this.parentKey.length}:${this.parentKey}${key.length}:${key}`;
```

#### PAT-P2: encodePointer skips hashing for 32-byte inputs — pointer collision [HIGH]

The optimization `typed.length !== 32 ? sha256(typed) : typed` bypasses hashing when input is exactly 32 bytes, assuming it's "already a hash." Attackers can craft 32-byte inputs that collide with any existing pointer.

- **Detection:** Any conditional hash bypass based on input length
- **Fix:** Always hash — `Sha256.hash(typed)` unconditionally
- **Real bug:** btc-runtime PR #61 (encodePointer)

#### PAT-P3: verifyEnd() checks current offset instead of projected end position [HIGH]

`if (this.currentOffset > buffer.byteLength)` doesn't catch the read ABOUT TO happen.

- **Detection:** In `verifyEnd(size)` methods, the condition must use `size` (the requested end), not `this.currentOffset`
- **Fix:** `if (size > this.buffer.byteLength)`
- **Real bug:** btc-runtime PR #60

---

### ARITHMETIC / AMM

#### PAT-A1: Math functions silently return 0 on undefined inputs instead of reverting [HIGH]

`log(0)`, `ln(0)`, `logRatio(0, x)` returning 0 masks caller bugs. Downstream code relying on monotonicity receives a wrong result without any error signal.

- **Detection:** grep `if (x.isZero()) return u256.Zero` in math functions with mathematically undefined inputs
- **Fix:** `throw new Revert('SafeMath: log of zero')` — fail fast and loud
- **Real bug:** btc-runtime PR #129

#### PAT-A2: AMM pool update uses additive formula instead of constant-product [CRITICAL]

`T -= dT; B += dB` — the buy side BTC accumulation is independently added rather than derived from the k invariant. Over time, `k = B * T` drifts, allowing price manipulation.

- **Detection:** Any AMM reserve flush that does independent add/subtract on both sides
- **Fix:** After applying buys: `const k = B * T; T -= dT; B = k / T`
- **Real bug:** native-swap PR #63

```typescript
// BROKEN — independent updates, k drifts
virtualTokenReserve -= tokensOut;
virtualBtcReserve += btcIn; // NOT derived from k

// FIXED — k-invariant maintained
const k = virtualBtcReserve * virtualTokenReserve;
virtualTokenReserve -= tokensOut;
virtualBtcReserve = k / virtualTokenReserve;
```

#### PAT-A3: Provider purge/slash removes tokens but not proportional BTC — k-drift [CRITICAL]

Removing tokens from `virtualTokenReserve` without removing proportional BTC from `virtualSatoshisReserve` breaks the constant-product invariant after every purge.

- **Detection:** Any `subFromVirtualTokenReserve()` call without a corresponding `subFromVirtualSatoshisReserve()` in the same path
- **Fix:** Calculate `btcToRemove = (tokens * currentBTC) / currentTokens`, then remove both atomically
- **Real bug:** native-swap PR #51

#### PAT-L2: Trade accumulator allows pool exhaustion — no pre-condition check [HIGH]

`recordTradeVolumes()` accumulated `tokensOut` without checking that total projected buys would still leave tokens in the virtual pool.

- **Detection:** Any function that increments a batch trade accumulator without verifying `totalAccumulated + newAmount < projectedReserve`
- **Fix:** Before incrementing: simulate the pool-update and reject if reserves would be exhausted
- **Real bug:** native-swap PR #63

---

### ACCESS CONTROL / CRYPTO

#### PAT-C1: approveFrom() missing replay protection nonce [CRITICAL]

A signed off-chain approval that does not include a nonce can be replayed indefinitely. Attacker re-submits the old signature to re-set allowances even after the owner revoked them.

- **Detection:** Any `verifySignature` call where the signed payload does not include a monotonically-increasing per-address nonce
- **Fix:** Include `nonce` in the hash, verify `storedNonce == providedNonce`, then increment nonce atomically
- **Real bug:** btc-runtime PR #60

```typescript
// BROKEN — no nonce, signature can be replayed forever
const hash = sha256(encode(spender, amount, deadline));
Blockchain.verifySignature(owner, signature, hash, false);

// FIXED — nonce prevents replay
const nonce = this.nonces.get(owner);
const hash = sha256(encode(spender, amount, deadline, nonce));
Blockchain.verifySignature(owner, signature, hash, false);
this.nonces.set(owner, nonce + 1n);
```

#### PAT-C2: ABI selector computed from wrong type string [HIGH]

`encodeSelector('approveFrom(address,uint256,uint64,bytes)')` when the actual parameter is `u256`. The on-chain selector doesn't match any client-generated selector, making the function unreachable.

- **Detection:** Grep all `encodeSelector('...')` strings; cross-check every type against the actual AssemblyScript parameter types
- **Fix:** Type strings in selectors must exactly match the canonical ABI types of the parameters
- **Real bug:** btc-runtime PR #61, PR #60

#### PAT-C3: Decryption failure silently returns original ciphertext [CRITICAL]

A `decrypt()` function that returns the input bytes when decryption fails instead of `null`/error. The caller treats the ciphertext as valid plaintext — authentication bypass.

- **Detection:** Any decrypt function that returns the original `msg` variable; return type should be `T | null`
- **Fix:** Return `null` on decryption failure; callers must handle null explicitly
- **Real bug:** opnet-node PR #192

```typescript
// BROKEN — returns encrypted bytes as if decryption succeeded
public decrypt(msg: Uint8Array): Uint8Array {
    const decrypted = this.#decrypt(data, ...);
    if (decrypted !== null) { msg = decrypted; }
    return msg; // BUG: returns original ciphertext on failure
}

// FIXED — returns null on failure
public decrypt(msg: Uint8Array): Uint8Array | null {
    return this.#decrypt(data, ...); // null if failed
}
```

#### PAT-C4: Public key identified by length alone — scripts misidentified as keys [HIGH]

Checking `buffer.length === 33 || buffer.length === 65` to identify EC public keys misidentifies P2WSH witness scripts (commonly 65 bytes starting with `0x21`).

- **Detection:** Any code that treats a 33-byte or 65-byte buffer as a public key without checking the prefix byte
- **Fix:** Validate prefix: `buf[0] in {0x02, 0x03}` for compressed (33B), `buf[0] === 0x04` for uncompressed (65B)
- **Real bug:** opnet-node PR #225

```typescript
// BROKEN — length check only, misidentifies P2WSH scripts
if (witness.length === 2 && secondWitnessLength === 65) {
    return witness[1]; // Could be a script, not a pubkey!
}

// FIXED — validates EC prefix byte
function isValidPublicKeyBuffer(buffer: Buffer, length: number): boolean {
    if (length === 33) return buffer[0] === 0x02 || buffer[0] === 0x03;
    if (length === 65) return buffer[0] === 0x04;
    return false;
}
```

---

### BUSINESS LOGIC

#### PAT-L1: Provider activation uses post-sale (reduced) liquidity for reserve calculation [CRITICAL]

`activateProvider()` computes the "second 50%" of liquidity to add to virtual reserves, but was called AFTER `subtractFromLiquidityAmount()` — so it saw the already-reduced balance, producing a smaller reserve contribution.

- **Detection:** Any function that reads `provider.getLiquidityAmount()` for initialization/reserve purposes must be called BEFORE any `subtract` / `decrease` on the same provider's liquidity in that trade path
- **Fix:** Call activation before any liquidity subtraction
- **Real bug:** native-swap PR #67

#### PAT-L3: UTXO reported before trade state is committed [HIGH]

`reportUTXOUsed()` appeared outside the success branch of a conditional, executing even for providers that were sent to the purge queue.

- **Detection:** `reportUTXOUsed()` / `markUTXOSpent()` must only appear within confirmed-success code paths
- **Fix:** Call UTXO commitment immediately at the point of fill confirmation, before the failure path branches
- **Real bug:** native-swap PR #48

---

### MEMORY / BOUNDS

#### PAT-M1: Array push() allows off-by-one overflow [HIGH]

`if (this._length > this.MAX_LENGTH)` allows writing element at index `MAX_LENGTH` — one past the end. Adjacent storage is corrupted silently.

- **Detection:** All array `push()` bounds checks: `> MAX` should be `>= MAX` for 0-indexed arrays
- **Fix:** `if (this._length >= this.MAX_LENGTH) throw new Revert(...)`
- **Real bug:** btc-runtime PR #61

```typescript
// BROKEN — allows one extra element
if (this._length > this.MAX_LENGTH) throw new Revert('overflow');

// FIXED — correct bound
if (this._length >= this.MAX_LENGTH) throw new Revert('overflow');
```

#### PAT-M2: Memory padding written at wrong base pointer offset [HIGH]

In a write-data-then-pad-to-length operation, padding start was calculated from `result_data.len()` instead of `bytes_actually_written`.

- **Detection:** In "write slice + pad to length" functions, track `bytes_written = slice.len()`, use that as padding offset
- **Fix:** `pad_ptr = base + bytes_written`, not `base + source_buffer.len()`
- **Real bug:** op-vm PR #130

---

### GAS / RUNTIME

#### PAT-G1: Gas usage not captured at VM exit — ExitData carries 0 gas [HIGH]

`ExitData` was constructed without capturing gas before the exit handler ran. The gas field was stale/zero for failed executions.

- **Detection:** In any VM `env_exit` / abort handler, ensure `get_used_gas()` is called BEFORE constructing `ExitData`
- **Fix:** `let gas = instance.get_used_gas(&mut store); ExitData::new(status, gas, data)`
- **Real bug:** op-vm PR #109

```rust
// BROKEN — ExitData constructed without gas info
env.exit_data = ExitData::new(status, data.as_slice()); // gas unknown

// FIXED — gas captured at exit time
let gas_used = instance.get_used_gas(&mut store);
env.exit_data = ExitData::new(status, gas_used, data.as_slice());
```

#### PAT-G2: Double mutex lock on same instance causes deadlock [CRITICAL]

Acquiring `Mutex::lock()` twice on the same object within the same async task — once for execution, once for gas retrieval — deadlocks the runtime.

- **Detection:** In Rust async code, search for `mutex.lock()` ... `mutex.lock()` on the same mutex within the same scope
- **Fix:** Single lock; include gas in the execution return value
- **Real bug:** op-vm PR #77

```rust
// BROKEN — deadlock: first lock still held when second lock attempted
let mut contract = self.contract.lock().unwrap(); // lock #1
let result = contract.execute(...);
let gas_used = self.contract.lock().unwrap().get_used_gas(); // lock #2 DEADLOCK

// FIXED — single lock, gas embedded in result
let result = self.contract.lock().unwrap().execute(...); // includes gas_used
let gas_used = result.gas_used;
```

---

### NETWORKING / INDEXER

#### PAT-N1: `Buffer.from(undefined, 'hex') || fallback` — `||` doesn't catch exceptions [HIGH]

When `data.txid` is `undefined` (coinbase inputs), `Buffer.from(undefined, 'hex')` throws — `||` is not try/catch and the fallback is never evaluated.

- **Detection:** grep `Buffer.from(x) || fallback` where `x` may be null/undefined
- **Fix:** `x ? Buffer.from(x, 'hex') : Buffer.alloc(32)`
- **Real bug:** opnet-node PR #218

```typescript
// BROKEN — throws if txid is undefined/null; || never evaluated
this.originalTransactionId = Buffer.from(data.txid, 'hex') || Buffer.alloc(32);

// FIXED — explicit null check
this.originalTransactionId = data.txid ? Buffer.from(data.txid, 'hex') : Buffer.alloc(32);
```

#### PAT-N2: Promise resolve called after loop exits, not at the point of match [HIGH]

A `do...while` search resolves a Promise AFTER the loop using `if (found) resolve(found)`. If the loop completes a full round without finding, `found` may point to the last-checked busy item.

- **Detection:** Any `Promise` constructor where `resolve()` is called outside the loop that identifies the value
- **Fix:** `resolve(item); return;` immediately at the point of matching inside the loop
- **Real bug:** opnet-node PR #192

```typescript
// BROKEN — resolves after loop, may pick wrong vm
if (!vmManager.busy() && vmManager.initiated) { break; }
if (vmManager) { resolve(vmManager); } // could be wrong

// FIXED — resolve immediately at point of match
if (!vmManager.busy() && vmManager.initiated) {
    resolve(vmManager); return;
}
```

---

### TYPE SAFETY

#### PAT-T1: Abstract method return type mismatch breaks interface contract [MEDIUM]

`verify()` declared as returning `boolean` instead of `Buffer` — any implementing class fails at runtime when callers expect a Buffer.

- **Detection:** All `abstract` methods in classes that implement external library interfaces must have return types matching the interface exactly
- **Fix:** Match return type to the interface specification
- **Real bug:** transaction PR #86

#### PAT-T2: ECPair default RNG breaks in browser — Uint8Array vs Buffer type mismatch [MEDIUM]

`ECPair.makeRandom()` with default RNG returns a Web Crypto `Uint8Array`; the library expects a Node.js `Buffer`.

- **Detection:** Any `ECPair.makeRandom()` call without a custom `rng` option in code that runs in browsers
- **Fix:** Provide `rng: (size) => Buffer.from(randomBytes(size))` using `@noble/curves`
- **Real bug:** transaction PR #109

```typescript
// BROKEN — default rng returns Uint8Array, ecpair wants Buffer
const keyPair = this.ECPair.makeRandom({ network });

// FIXED — explicit Buffer conversion
const keyPair = this.ECPair.makeRandom({
    network,
    rng: (size: number): Buffer => Buffer.from(randomBytes(size)),
});
```

#### PAT-T3: Event decoding reassigns variable and loses original reference [MEDIUM]

`events = events[key]` then `events = events[p2tr]` — after the first assignment, `events` is no longer the original map. Fallback lookup indexes an already-overwritten value.

- **Detection:** Any function that reassigns an input map variable and later uses it for fallback lookups
- **Fix:** Preserve the original reference: `const orig = events; events = orig[key]; if (!ok) events = orig[fallbackKey]`
- **Real bug:** opnet PR #78

---

## Forbidden Patterns (Contract)

```
FORBIDDEN: while loops (unbounded gas consumption)
FORBIDDEN: Iterating all map keys (O(n) gas explosion)
FORBIDDEN: Unbounded arrays (cap size, use pagination)
FORBIDDEN: float (f32/f64) in consensus code (non-deterministic across CPUs)
FORBIDDEN: Raw u256 arithmetic (+, -, *, /) (use SafeMath)
FORBIDDEN: Native Map<T> with object keys (reference equality broken)
FORBIDDEN: Blockchain.block.medianTimestamp for logic (miner-manipulable +/-2h)
FORBIDDEN: ABIDataTypes import (it's a global, import causes build failure)
```

---

## Common Mistakes Quick Reference Table

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| `Blockchain.block.medianTimestamp` for time logic | Miner-manipulable +/-2h | `Blockchain.block.number` |
| Keccak256 selectors | OPNet uses SHA256 | SHA256 for all hashing |
| Calling `approve()` on OP-20 | Doesn't exist | `increaseAllowance()`/`decreaseAllowance()` |
| `Address.fromString(bc1p...)` | Takes TWO hex pubkey params | `Address.fromString(hashedMLDSAKey, tweakedPublicKey)` |
| `bitcoinjs-lib` | Wrong library | `@btc-vision/bitcoin` |
| Skip simulation | Bitcoin irreversible | Always simulate, check `'error' in sim` |
| Express/Fastify/Koa | Forbidden | `@btc-vision/hyper-express` |
| `verifyECDSASignature` directly | Deprecated, will break | `Blockchain.verifySignature()` |
| Non-Auto signing methods | Environment-specific crashes | `signMessageAuto()`, `tweakAndSignMessageAuto()` |
| `Buffer` anywhere | Removed from stack | `Uint8Array` + `BufferHelper` |
| `assemblyscript` (upstream) | Incompatible | `@btc-vision/assemblyscript` |
| Single-threaded backend | Can't handle concurrency | Worker threads |
| Old WalletConnect v1 API | Deprecated | `@btc-vision/walletconnect` v2 |
| Manual address prefix checks | Fragile, misses types | `AddressVerificator.detectAddressType()` |
| `mnemonic.derive()` | Wrong derivation path | `mnemonic.deriveOPWallet()` |
| Importing ABIDataTypes | Build failure | Use directly (it's a global) |
| `name()`/`symbol()` in tests | No such methods | `contract.metadata()` |
| `OP20_ABI` (wrong name) | Wrong export | `OP_20_ABI` |
| `getContract()` with 3-4 args | Requires 5 | `getContract<T>(addr, abi, provider, network, sender)` |
| `new JSONRpcProvider(url, net)` | Takes config object | `new JSONRpcProvider({ url, network })` |
| Missing crypto-browserify | Signing fails in browser | Add to nodePolyfills overrides AND undici alias |
| `transfer().properties.success` | Properties is `{}` | Check `result.revert === undefined` |
| 4 separate calls for metadata | 4x slower | `contract.metadata()` one call |
| Raw bigint for token amounts | Breaks with decimals | `BitcoinUtils.expandToDecimals()` |
| Constructor state initialization | Runs every call | Put in `onDeployment()` |
| Bare `@method()` | Zero ABI inputs | Declare all params |

---

## Buffer Replacement (MANDATORY -- All Domains)

`Buffer` does not exist in the OPNet stack. Use `Uint8Array` everywhere:

```typescript
import { BufferHelper } from '@btc-vision/transaction';

// WRONG
const data = Buffer.from('deadbeef', 'hex');
const hex = Buffer.from(bytes).toString('hex');

// CORRECT
const data: Uint8Array = BufferHelper.fromHex('deadbeef');
const hex: string = BufferHelper.toHex(bytes);
const bytes = new TextEncoder().encode('hello');
const str = new TextDecoder().decode(bytes);
```

---

## TypeScript Law (Non-Negotiable -- Audit Enforcement)

```
FORBIDDEN: any
FORBIDDEN: ! (non-null assertion)
FORBIDDEN: @ts-ignore
FORBIDDEN: eslint-disable
FORBIDDEN: object (lowercase)
FORBIDDEN: Function (uppercase)
FORBIDDEN: {} empty type
FORBIDDEN: number for satoshis (use bigint)
FORBIDDEN: float for financial values
FORBIDDEN: Section separator comments (// ===)
REQUIRED: bigint for satoshis, token amounts, block heights
REQUIRED: Explicit return types on all functions
REQUIRED: TSDoc for all public methods
REQUIRED: Strict null checks
REQUIRED: Interface definitions for all data shapes
```
