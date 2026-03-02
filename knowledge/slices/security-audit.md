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
