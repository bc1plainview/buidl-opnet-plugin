# OPNet Contract Development Reference

> **Role**: Smart contract developers writing AssemblyScript contracts for OPNet
>
> **Self-contained**: All rules and patterns needed for contract development are in this file.

---

## Architecture Context

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

- **Contracts are WebAssembly** -- Compiled from AssemblyScript using `@btc-vision/assemblyscript` (custom fork with closure support)
- **NON-CUSTODIAL** -- Contracts NEVER hold BTC. They verify L1 tx outputs. "Verify-don't-custody."
- **Partial reverts** -- Only consensus layer execution reverts; Bitcoin transfers are ALWAYS final. BTC sent to a contract that reverts is GONE.
- **No gas token** -- Uses Bitcoin directly.
- **SHA-256, not Keccak-256** -- OPNet uses SHA-256 for all hashing and method selectors. This is Bitcoin, not Ethereum.
- **Constructor call gas limit**: 20M gas hardcoded by the protocol
- **Regular call gas limit**: configurable, defaults to 300M
- **Buffer is GONE** -- The entire stack uses `Uint8Array` instead of Node.js `Buffer`.

---

## Package Installation

```bash
rm -rf node_modules package-lock.json
npm uninstall assemblyscript 2>/dev/null   # MANDATORY -- must uninstall upstream first
npx npm-check-updates -u && npm i @btc-vision/btc-runtime@rc @btc-vision/as-bignum@latest @btc-vision/assemblyscript @btc-vision/opnet-transform@latest @assemblyscript/loader@latest --prefer-online
npm i -D eslint@^10.0.0 @eslint/js@^10.0.1 typescript-eslint@^8.56.0
```

### Package Version Reference

| Package | Version Tag |
|---------|------------|
| `@btc-vision/btc-runtime` | `@rc` |
| `@btc-vision/opnet-transform` | `1.1.0` |
| `@btc-vision/assemblyscript` | `^0.29.2` |
| `@btc-vision/as-bignum` | `0.1.2` |
| `eslint` | `^9.39.2` |
| `@eslint/js` | `^9.39.2` |

---

## Project Structure

```
my-contract/
├── src/
│   ├── index.ts           # Entry point (factory + abort)
│   └── MyContract.ts      # Contract implementation
├── build/                 # Compiled WASM output
├── package.json
├── asconfig.json          # AssemblyScript config
└── tsconfig.json
```

---

## asconfig.json -- COPY THIS EXACTLY

```json
{
    "targets": {
        "my-contract": {
            "outFile": "build/MyContract.wasm",
            "use": ["abort=src/index/abort"]
        }
    },
    "options": {
        "sourceMap": false,
        "optimizeLevel": 3,
        "shrinkLevel": 1,
        "converge": true,
        "noAssert": false,
        "enable": [
            "sign-extension",
            "mutable-globals",
            "nontrapping-f2i",
            "bulk-memory",
            "simd",
            "reference-types",
            "multi-value"
        ],
        "runtime": "stub",
        "memoryBase": 0,
        "initialMemory": 1,
        "exportStart": "start",
        "transform": "@btc-vision/opnet-transform"
    }
}
```

**Critical asconfig.json rules:**
- `shrinkLevel`: MUST be `1` (NOT `2`)
- `noAssert`: MUST be `false` (NOT `true`)
- `enable`: ALL listed features required. Missing any = runtime trap
- `transform`: MUST be `"@btc-vision/opnet-transform"` (NOT a subpath, NOT in targets)
- `runtime`: MUST be `"stub"`
- `exportStart`: MUST be `"start"`
- Each target's `use` points to ITS abort handler

### Multi-Contract asconfig.json

```json
{
    "targets": {
        "token": {
            "outFile": "build/MyToken.wasm",
            "use": ["abort=src/token/index/abort"]
        },
        "nft": {
            "outFile": "build/MyNFT.wasm",
            "use": ["abort=src/nft/index/abort"]
        }
    },
    "options": {
        "sourceMap": false,
        "optimizeLevel": 3,
        "shrinkLevel": 1,
        "converge": true,
        "noAssert": false,
        "enable": [
            "sign-extension",
            "mutable-globals",
            "nontrapping-f2i",
            "bulk-memory",
            "simd",
            "reference-types",
            "multi-value"
        ],
        "runtime": "stub",
        "memoryBase": 0,
        "initialMemory": 1,
        "exportStart": "start",
        "transform": "@btc-vision/opnet-transform"
    }
}
```

---

## Contract package.json

```json
{
    "scripts": {
        "build": "asc --config asconfig.json --target my-contract",
        "lint": "eslint src --ext .ts",
        "typecheck": "tsc --noEmit",
        "clean": "rm -rf build/*"
    },
    "dependencies": {
        "@btc-vision/as-bignum": "0.1.2",
        "@btc-vision/btc-runtime": "rc"
    },
    "devDependencies": {
        "@btc-vision/assemblyscript": "^0.29.2",
        "@btc-vision/opnet-transform": "1.1.0",
        "eslint": "^9.39.2",
        "@eslint/js": "^9.39.2"
    },
    "overrides": {
        "@noble/hashes": "2.0.1"
    }
}
```

---

## ESLint Config for Contracts (AssemblyScript)

```javascript
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
    js.configs.recommended,
    ...tseslint.configs.recommended,
    {
        rules: {
            '@typescript-eslint/no-explicit-any': 'error',
            '@typescript-eslint/explicit-function-return-type': 'error',
            '@typescript-eslint/no-unused-vars': 'error',
            '@typescript-eslint/no-non-null-assertion': 'error',
            'no-console': 'warn',
        },
    }
);
```

---

## Contract Entry Point -- Required Structure

```typescript
import { Blockchain } from '@btc-vision/btc-runtime/runtime';
import { MyContract } from './MyContract';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';

// 1. Factory function -- REQUIRED. Must return NEW instance, not assign instance.
Blockchain.contract = (): MyContract => {
    return new MyContract();
};

// 2. Runtime exports -- REQUIRED
export * from '@btc-vision/btc-runtime/runtime/exports';

// 3. Abort handler -- REQUIRED
export function abort(message: string, fileName: string, line: u32, column: u32): void {
    revertOnError(message, fileName, line, column);
}
```

---

## The Constructor vs onDeployment Trap (CRITICAL)

```
constructor() runs on EVERY contract interaction (every single call)
onDeployment() runs ONLY ONCE on the first deployment
```

**NEVER put initialization logic in the constructor.** This is one of the most common critical bugs.

```typescript
export class MyContract extends OP_NET {
    public constructor() {
        super();
        // ONLY: set up selectors, declare storage fields
        // DO NOT: mint tokens, write storage, set initial state
    }

    public override onDeployment(_calldata: Calldata): void {
        // CORRECT: ALL initialization goes here
        // This runs ONCE
        const currentBlock = Blockchain.block.number;
        this.deploymentBlock.set(currentBlock);
        this._mint(Blockchain.tx.sender, INITIAL_SUPPLY);
    }
}
```

---

## @method() MUST Declare ALL Parameters

`@method()` with no arguments = zero ABI inputs declared. This is a CRITICAL bug:
- Callers must hand-roll calldata -- no type safety
- SDK `getContract()` doesn't work
- Cannot be fixed without redeployment

```typescript
// WRONG -- bare @method(), zero ABI inputs. FORBIDDEN.
@method()
@returns({ name: 'success', type: ABIDataTypes.BOOL })
public airdrop(calldata: Calldata): BytesWriter { ... }

// CORRECT -- declare every input; tuples work
@method({ name: 'entries', type: ABIDataTypes.TUPLE, components: [
    { name: 'recipient', type: ABIDataTypes.ADDRESS },
    { name: 'amountPill', type: ABIDataTypes.UINT64 },
    { name: 'amountMoto', type: ABIDataTypes.UINT64 },
]})
@returns({ name: 'success', type: ABIDataTypes.BOOL })
public airdrop(calldata: Calldata): BytesWriter { ... }

// CORRECT -- method with params
@method({ name: 'to', type: ABIDataTypes.ADDRESS }, { name: 'amount', type: ABIDataTypes.UINT256 })
@returns({ type: ABIDataTypes.BOOL })
public transfer(calldata: Calldata): BytesWriter { ... }
```

---

## Decorator Globals (Do NOT Import These)

`@method`, `@returns`, `@emit`, `@final`, and `ABIDataTypes` are **compile-time globals** injected by `@btc-vision/opnet-transform`. They are NOT exports from `@btc-vision/btc-runtime/runtime`. Importing them causes build failures.

```typescript
// WRONG -- causes build failure
import { ABIDataTypes } from '@btc-vision/btc-runtime/runtime';
import { method } from '@btc-vision/btc-runtime/runtime';

// CORRECT -- just use them directly, no import needed
@method({ name: 'to', type: ABIDataTypes.ADDRESS })
@returns({ type: ABIDataTypes.BOOL })
public transfer(calldata: Calldata): BytesWriter { ... }
```

(`@final` is a standard AssemblyScript decorator from the language itself -- it IS available.)

---

## Common Imports

```typescript
import {
    Blockchain,
    OP_NET,
    OP20,
    OP721,
    Address,
    Calldata,
    BytesWriter,
    Selector,
    StoredU256,
    StoredBoolean,
    StoredString,
    StoredU64,
    AddressMemoryMap,
    StoredMapU256,
    encodeSelector,
    SafeMath,
    Revert,
} from '@btc-vision/btc-runtime/runtime';

import { u256, u128 } from '@btc-vision/as-bignum/assembly';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';

// NOTE: @method, @returns, @emit, @final, ABIDataTypes -- DO NOT IMPORT, they are globals
```

---

## SafeMath -- MANDATORY for ALL u256 Operations

```typescript
import { SafeMath } from '@btc-vision/btc-runtime/runtime';

// WRONG -- can overflow/underflow silently
const result = a + b;
const result = a - b;
const result = a * b;

// CORRECT -- SafeMath reverts on overflow/underflow
const result = SafeMath.add(a, b);
const result = SafeMath.sub(a, b);
const result = SafeMath.mul(a, b);
const result = SafeMath.div(a, b);
```

---

## Creating u256 Values

```typescript
// WRONG -- pow() may not exist, can fail
const amount = u256.fromU64(1000).mul(u256.fromU64(10).pow(18));

// CORRECT -- calculate offline, use string for large values
const TOKENS_PER_MINT: u256 = u256.fromString('1000000000000000000000');      // 1000 * 10^18
const MAX_SUPPLY: u256 = u256.fromString('100000000000000000000000000');       // 100M * 10^18

// For small values, fromU32/fromU64 is fine
const MAX_MINTS: u256 = u256.fromU32(5);
const ONE: u256 = u256.One;
const ZERO: u256 = u256.Zero;
```

---

## Storage and Pointers

```typescript
export class MyContract extends OP_NET {
    // Automatic pointer allocation (recommended)
    private readonly myValuePointer: u16 = Blockchain.nextPointer;
    private readonly myMapPointer: u16 = Blockchain.nextPointer;

    // Storage instances using those pointers
    private readonly myValue: StoredU256 = new StoredU256(this.myValuePointer, u256.Zero);
    private readonly balances: AddressMemoryMap<Address, StoredU256> = new AddressMemoryMap(
        this.myMapPointer,
        Address.dead()
    );
}
```

**CRITICAL: NEVER use bare `Map<Address, T>` in contracts.** AssemblyScript's `Map` uses reference equality -- two `Address` instances with identical bytes are different references. Use `AddressMemoryMap`, `StoredMapU256`, or `Nested` instead. For in-memory caches, key by `string` (`.toHexString()`).

### Storage Types

| Type | Use Case |
|------|----------|
| `StoredU256` | Single u256 value (total supply, deployment block) |
| `StoredBoolean` | Boolean flag (mint closed, paused) |
| `StoredString` | String value (name, symbol) |
| `StoredU64` | Single u64 value (block numbers, timestamps) |
| `AddressMemoryMap` | Address -> value mapping (balances) |
| `StoredMapU256` | u256 -> u256 mapping (generic key-value) |

---

## Forbidden Contract Patterns

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

## Use Block Number, Not Timestamp

```typescript
// WRONG -- medianTimestamp can be manipulated by miners (+/-2 hours)
if (Blockchain.block.medianTimestamp > deadline) { ... }

// CORRECT -- block.number is strictly monotonic and tamper-proof
// 144 blocks = ~24 hours, 1008 blocks = ~1 week
if (Blockchain.block.number >= deploymentBlock + 1008n) { ... }
```

---

## callMethod Pattern -- Must Include super

```typescript
public callMethod(calldata: Calldata): BytesWriter {
    const selector = calldata.readSelector();
    switch (selector) {
        case this.mySelector:
            return this.myMethod(calldata);
        default:
            return super.callMethod(calldata);  // REQUIRED -- handles inherited methods
    }
}
```

---

## BytesWriter Size Must Match Content

```typescript
// WRONG -- size mismatch
const writer = new BytesWriter(1);
writer.writeU256(value);  // Needs 32 bytes!

// CORRECT -- calculate exact size
const writer = new BytesWriter(32);           // u256
const writer = new BytesWriter(1);            // bool
const writer = new BytesWriter(8);            // u64
const writer = new BytesWriter(1 + 32 + 8);  // bool + u256 + u64
```

---

## OP20 Token Pattern

```typescript
import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Address,
    Blockchain,
    BytesWriter,
    Calldata,
    OP20,
    OP20InitParameters,
    SafeMath,
} from '@btc-vision/btc-runtime/runtime';

@final
export class MyToken extends OP20 {
    public constructor() {
        const params: OP20InitParameters = {
            name: 'My Token',
            symbol: 'MTK',
            decimals: 18,
            maxSupply: u256.fromString('100000000000000000000000000'), // 100M tokens
        };
        super(params);
    }

    public override onDeployment(_calldata: Calldata): void {
        // Initialization goes HERE, not in constructor
        this._mint(Blockchain.tx.sender, this.maxSupply);
    }

    public override callMethod(calldata: Calldata): BytesWriter {
        const selector = calldata.readSelector();
        switch (selector) {
            // Add custom methods here
            default:
                return super.callMethod(calldata);
        }
    }
}
```

**OP20 uses `increaseAllowance()`/`decreaseAllowance()`, NOT `approve()`.** The `approve()` function does not exist on OPNet's OP20.

---

## Signature Verification in Contracts

```typescript
// ONLY correct approach -- consensus-aware, auto-selects algorithm
const isValid: bool = Blockchain.verifySignature(
    Blockchain.tx.origin,   // ExtendedAddress (has both key types)
    signature,              // Signature bytes
    messageHash,            // 32-byte SHA256 hash
    false,                  // false = auto-select, true = force ML-DSA
);

// DEPRECATED -- will break when quantum consensus flag flips
// DO NOT USE: verifyECDSASignature, verifyBitcoinECDSASignature, verifySchnorrSignature
```

---

## Upgradeable Contracts

```typescript
import { Upgradeable, Calldata } from '@btc-vision/btc-runtime/runtime';

export class MyContract extends Upgradeable {
    public constructor() {
        super();
    }

    public override onUpdate(_oldVersion: u256, calldata: Calldata): void {
        // Migration logic -- runs ONCE on upgrade
        // CRITICAL: Storage pointers MUST remain in same order across versions
        // New pointers should be APPENDED, never inserted between existing ones
    }
}
```

---

## Selector Computation

OPNet method selectors are computed using SHA-256 (not Keccak-256):

```typescript
// In contract (AssemblyScript):
const selector: Selector = encodeSelector('transfer(address,uint256)');

// In tests (TypeScript):
private getSelector(signature: string): number {
    return Number(`0x${this.abiCoder.encodeSelector(signature)}`);
}
```

---

## Buffer Replacement (MANDATORY)

`Buffer` does not exist in the OPNet stack. Use `Uint8Array` everywhere:

```typescript
import { BufferHelper } from '@btc-vision/transaction';

// WRONG
const data = Buffer.from('deadbeef', 'hex');
const hex = Buffer.from(bytes).toString('hex');

// CORRECT
const data: Uint8Array = BufferHelper.fromHex('deadbeef');
const hex: string = BufferHelper.toHex(bytes);
// Or for strings:
const bytes = new TextEncoder().encode('hello');
const str = new TextDecoder().decode(bytes);
```

---

## Code Verification Order (MANDATORY)

```bash
# 1. Lint (MUST pass with zero errors)
npm run lint

# 2. TypeScript check (MUST pass with zero errors)
npm run typecheck   # or: npx tsc --noEmit

# 3. Build (only after lint + types pass)
npm run build

# 4. Test (run on clean build)
npm run test
```

Never skip lint. Never ship code with lint errors.

---

## Common Contract Mistakes at a Glance

| Problem | Fix |
|---------|-----|
| Deployment reverts consuming all gas | Check: asconfig.json features, cross-contract calls in onDeployment, calldata encoding |
| `Cannot find module assemblyscript` | `npm uninstall assemblyscript` first, then install `@btc-vision/assemblyscript` |
| `Buffer is not defined` | Replace all Buffer with Uint8Array + BufferHelper |
| WASM execution failed | Check asconfig.json has ALL enable features, abort handler exists |
| Contract not found after deployment | Consumed all gas = reverted. Check onDeployment() complexity. |
| `@method()` bare -- broken ABI | Always declare params: `@method({ name, type }, ...)` |
| State not persisting | Check: are you using save() after StoredArray mutations? |
| Null comparison broken in AS | AssemblyScript null checks work differently -- use explicit checks |
| Constructor trap | OPNet constructor runs on EVERY interaction. Put init in onDeployment(). |

---

## TypeScript Law (Non-Negotiable)

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
