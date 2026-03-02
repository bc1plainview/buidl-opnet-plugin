# OPNet Development Bible — The Definitive Reference

> **Version 2.0.0-opnet** | **MANDATORY READING for ALL OPNet projects**
>
> Danny's Claude: **Read this entire document before writing a single line of OPNet code.**
> If you skip this, you will repeat the same mistakes. Every rule here came from a real bug.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Package Versions & Setup](#2-package-versions--setup)
3. [Contract Development Rules](#3-contract-development-rules)
4. [Frontend Development Rules](#4-frontend-development-rules)
5. [Backend Development Rules](#5-backend-development-rules)
6. [Transaction Rules](#6-transaction-rules)
7. [Common Agent Mistakes](#7-common-agent-mistakes)
8. [Known Frontend Mistakes (All 19)](#8-known-frontend-mistakes-all-19)
9. [Security Checklist](#9-security-checklist)
10. [Signature Verification](#10-signature-verification)
11. [Deployment](#11-deployment)
12. [Quick Reference](#12-quick-reference)

---

## 1. Architecture Overview

### What OPNet Is

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

| What OPNet IS | What OPNet is NOT |
|--------------|-------------------|
| Bitcoin L1 consensus layer | A sidechain |
| Fully trustless | An L2 |
| Permissionless | A metaprotocol |
| Decentralized (Bitcoin PoW + OPNet epoch SHA1 mining) | Indexer-dependent |

OPNet's **checksum root** is a cryptographic fingerprint of the entire state. After 20 blocks, changing it requires rewriting Bitcoin history at millions of dollars per hour — making OPNet state more final than Bitcoin's 6-confirmation security.

### Key Principles

1. **Contracts are WebAssembly** — Compiled from AssemblyScript using `@btc-vision/assemblyscript` (custom fork with closure support)
2. **NON-CUSTODIAL** — Contracts NEVER hold BTC. They verify L1 tx outputs, they don't hold funds. "Verify-don't-custody."
3. **Partial reverts** — Only consensus layer execution reverts; Bitcoin transfers are ALWAYS final. BTC sent to a contract that reverts is GONE.
4. **No gas token** — Uses Bitcoin directly. No ETH equivalent.
5. **CSV timelocks MANDATORY** — All addresses receiving BTC in swaps MUST use CSV (CheckSequenceVerify) to prevent transaction pinning attacks.
6. **Quantum resistance** — ML-DSA (FIPS 204) signature support via P2MR addresses (BIP-360).
7. **Buffer is GONE** — The entire stack uses `Uint8Array` instead of Node.js `Buffer`.
8. **SHA-256, not Keccak-256** — OPNet uses SHA-256 for all hashing and method selectors. This is Bitcoin, not Ethereum.

### Network Endpoints

| Network | RPC URL | `networks.*` value | Bech32 Prefix |
|---------|---------|-------------------|---------------|
| **Mainnet** | `https://mainnet.opnet.org` | `networks.bitcoin` | `bc` |
| **Testnet** | `https://testnet.opnet.org` | `networks.opnetTestnet` | `opt` |

> **IMPORTANT**: For OPNet development, ALWAYS use `networks.opnetTestnet` (NOT `networks.regtest`). The testnet is a Signet fork with OPNet-specific network parameters.

### The Two Address Systems (Critical for Transfers/Airdrops)

On Ethereum, there's one address format. On OPNet, there are TWO completely different systems:

| System | Format | Used For |
|--------|--------|---------|
| Bitcoin Address | Taproot P2TR (`bc1p...`) | External identity, what you see in walletconnect |
| OPNet Address | ML-DSA public key hash (32 bytes, 0x hex) | Contract balances, internal state |

**You CANNOT loop through Bitcoin addresses and transfer tokens.** Contract storage uses ML-DSA addresses. The link between them only exists once the user proves ownership of both keys (via a claim/signature pattern).

### CSV: The Critical Anti-Pinning Mechanism

Transaction pinning is a catastrophic attack where an attacker creates massive chains of unconfirmed transactions, preventing your transaction from confirming. This destroys DEXs.

**Without CSV**: Maximum unconfirmed chain length = UNLIMITED (pinning possible forever)  
**With CSV**: Maximum unconfirmed chain length = ZERO (must wait for confirmation)

ALL addresses receiving BTC in OPNet swaps MUST use CSV timelocks.

---

## 2. Package Versions & Setup

### NEVER GUESS PACKAGE VERSIONS

OPNet packages use `@rc` release tags. Wrong versions = build failures.

### Install Commands (Run THESE, not just `npm install`)

#### For Backend / Frontend / Plugins:
```bash
rm -rf node_modules package-lock.json
npx npm-check-updates -u && npm i @btc-vision/bitcoin@rc @btc-vision/bip32@latest @btc-vision/ecpair@latest @btc-vision/transaction@rc opnet@rc --prefer-online
npm i -D eslint@^10.0.0 @eslint/js@^10.0.1 typescript-eslint@^8.56.0
```

#### For Contract Projects (AssemblyScript):
```bash
rm -rf node_modules package-lock.json
npm uninstall assemblyscript 2>/dev/null   # MANDATORY — must uninstall upstream first
npx npm-check-updates -u && npm i @btc-vision/btc-runtime@rc @btc-vision/as-bignum@latest @btc-vision/assemblyscript @btc-vision/opnet-transform@latest @assemblyscript/loader@latest --prefer-online
npm i -D eslint@^10.0.0 @eslint/js@^10.0.1 typescript-eslint@^8.56.0
```

#### For Unit Test Projects:
```bash
rm -rf node_modules package-lock.json
npm uninstall assemblyscript 2>/dev/null
npx npm-check-updates -u && npm i @btc-vision/bitcoin@rc @btc-vision/bip32@latest @btc-vision/ecpair@latest @btc-vision/transaction@rc opnet@rc @btc-vision/op-vm@rc @btc-vision/unit-test-framework@beta --prefer-online
npm i -D eslint@^10.0.0 @eslint/js@^10.0.1 typescript-eslint@^8.56.0
```

### Package Version Reference

| Package | Version Tag | Used In |
|---------|------------|---------|
| `@btc-vision/bitcoin` | `@rc` | Frontend, Backend, Plugins, Tests |
| `@btc-vision/transaction` | `@rc` | Frontend, Backend, Plugins, Tests |
| `opnet` | `@rc` | Frontend, Backend, Plugins, Tests |
| `@btc-vision/bip32` | `latest` | Frontend, Backend |
| `@btc-vision/ecpair` | `latest` | Frontend, Backend |
| `@btc-vision/btc-runtime` | `@rc` | Contracts |
| `@btc-vision/opnet-transform` | `1.1.0` | Contracts |
| `@btc-vision/assemblyscript` | `^0.29.2` | Contracts |
| `@btc-vision/as-bignum` | `0.1.2` | Contracts |
| `@btc-vision/unit-test-framework` | `@beta` | Tests |
| `@btc-vision/op-vm` | `@rc` | Tests |
| `eslint` | `^9.39.2` | All |
| `@eslint/js` | `^9.39.2` | All |

### Buffer is COMPLETELY REMOVED

**`Buffer` does not exist in the OPNet stack.** Use `Uint8Array` everywhere:

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

### Contract Project Structure

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

### asconfig.json — COPY THIS EXACTLY

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

#### Multi-Contract asconfig.json:
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

### Contract package.json

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

### Frontend Project Structure

```
my-frontend/
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── components/
│   ├── hooks/
│   ├── services/
│   ├── utils/
│   ├── types/
│   └── abi/
├── public/
├── index.html
├── package.json
├── vite.config.ts
└── tsconfig.json
```

### vite.config.ts — COPY THIS EXACTLY

```typescript
import { resolve } from 'path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import eslint from 'vite-plugin-eslint2';

export default defineConfig({
    base: './',   // REQUIRED for IPFS: must be './' not '/'
    plugins: [
        // Node.js polyfills MUST come FIRST
        nodePolyfills({
            globals: {
                Buffer: true,
                global: true,
                process: true
            },
            overrides: {
                crypto: 'crypto-browserify'   // REQUIRED for signing
            }
        }),
        react(),
        eslint({ cache: false })
    ],
    resolve: {
        alias: {
            global: 'global',
            // Browser shim for Node.js fetch — REQUIRED for opnet
            undici: resolve(__dirname, 'node_modules/opnet/src/fetch/fetch-browser.js')
        },
        mainFields: ['module', 'main', 'browser'],
        dedupe: ['@noble/curves', '@noble/hashes', '@scure/base', 'buffer', 'react', 'react-dom']
    },
    build: {
        commonjsOptions: {
            strictRequires: true,
            transformMixedEsModules: true
        },
        rollupOptions: {
            output: {
                entryFileNames: '[name].js',
                chunkFileNames: 'js/[name]-[hash].js',
                assetFileNames: (assetInfo) => {
                    const name = assetInfo.names?.[0] ?? '';
                    const info = name.split('.');
                    const ext = info[info.length - 1];
                    if (/png|jpe?g|svg|gif|tiff|bmp|ico/i.test(ext || '')) return `images/[name][extname]`;
                    if (/woff|woff2|eot|ttf|otf/i.test(ext || '')) return `fonts/[name][extname]`;
                    if (/css/i.test(ext || '')) return `css/[name][extname]`;
                    return `assets/[name][extname]`;
                },
                manualChunks(id) {
                    if (id.includes('crypto-browserify') || id.includes('randombytes')) return undefined;
                    if (id.includes('node_modules')) {
                        if (id.includes('@noble/curves')) return 'noble-curves';
                        if (id.includes('@noble/hashes')) return 'noble-hashes';
                        if (id.includes('@scure/')) return 'scure';
                        if (id.includes('@btc-vision/transaction')) return 'btc-transaction';
                        if (id.includes('@btc-vision/bitcoin')) return 'btc-bitcoin';
                        if (id.includes('@btc-vision/bip32')) return 'btc-bip32';
                        if (id.includes('@btc-vision/post-quantum')) return 'btc-post-quantum';
                        if (id.includes('@btc-vision/wallet-sdk')) return 'btc-wallet-sdk';
                        if (id.includes('@btc-vision/logger')) return 'btc-logger';
                        if (id.includes('node_modules/opnet')) return 'opnet';
                        if (id.includes('bip39')) return 'bip39';
                        if (id.includes('ecpair') || id.includes('tiny-secp256k1')) return 'bitcoin-utils';
                        if (
                            id.includes('node_modules/react-dom') ||
                            id.includes('node_modules/react/') ||
                            id.includes('node_modules/scheduler')
                        ) return 'react-ui';
                        if (id.includes('ethers')) return 'ethers';
                        if (id.includes('protobufjs') || id.includes('@protobufjs')) return 'protobuf';
                    }
                }
            },
            external: [
                'worker_threads',
                'node:sqlite',
                'node:diagnostics_channel',
                'node:async_hooks',
                'node:perf_hooks',
                'node:worker_threads'
            ]
        },
        target: 'esnext',
        modulePreload: false,
        cssCodeSplit: false,
        assetsInlineLimit: 10000,
        chunkSizeWarningLimit: 3000
    },
    optimizeDeps: {
        include: ['react', 'react-dom', 'buffer', 'process', 'stream-browserify'],
        exclude: ['@btc-vision/transaction', 'crypto-browserify']
    }
});
```

> **NOTE**: `base: './'` is required for IPFS deployment (relative paths). If you use `base: '/'`, white page on IPFS.

### Frontend package.json

```json
{
    "dependencies": {
        "react": "latest",
        "react-dom": "latest",
        "opnet": "rc",
        "@btc-vision/transaction": "rc",
        "@btc-vision/bitcoin": "rc",
        "@btc-vision/ecpair": "latest",
        "@btc-vision/bip32": "latest",
        "@btc-vision/walletconnect": "latest"
    },
    "devDependencies": {
        "vite": "latest",
        "@vitejs/plugin-react": "latest",
        "vite-plugin-node-polyfills": "latest",
        "vite-plugin-eslint2": "latest",
        "typescript": "latest",
        "@types/react": "latest",
        "@types/react-dom": "latest",
        "@types/node": "latest",
        "eslint": "^9.39.2",
        "@eslint/js": "^9.39.2",
        "@typescript-eslint/eslint-plugin": "latest",
        "@typescript-eslint/parser": "latest",
        "eslint-plugin-react": "latest",
        "eslint-plugin-react-hooks": "latest",
        "crypto-browserify": "latest",
        "stream-browserify": "latest"
    },
    "overrides": {
        "@noble/hashes": "2.0.1"
    }
}
```

### Frontend tsconfig.json

```json
{
    "compilerOptions": {
        "target": "ESNext",
        "module": "ESNext",
        "moduleResolution": "bundler",
        "strict": true,
        "noImplicitAny": true,
        "strictNullChecks": true,
        "noUnusedLocals": true,
        "noUnusedParameters": true,
        "noImplicitReturns": true,
        "esModuleInterop": true,
        "skipLibCheck": true,
        "jsx": "react-jsx",
        "lib": ["ESNext", "DOM", "DOM.Iterable"]
    },
    "include": ["src"]
}
```

### Backend package.json

```json
{
    "type": "module",
    "dependencies": {
        "@btc-vision/hyper-express": "latest",
        "@btc-vision/uwebsocket.js": "latest",
        "opnet": "rc",
        "@btc-vision/transaction": "rc",
        "@btc-vision/bitcoin": "rc"
    },
    "devDependencies": {
        "typescript": "latest",
        "@types/node": "latest",
        "eslint": "^9.39.2",
        "@eslint/js": "^9.39.2"
    },
    "overrides": {
        "@noble/hashes": "2.0.1"
    }
}
```

### ESLint Configs

#### For Contract (AssemblyScript) — `eslint.config.js`:
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

#### For Backend / Unit Tests / Plugins — `eslint.config.js`:
```javascript
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
    js.configs.recommended,
    ...tseslint.configs.strictTypeChecked,
    {
        languageOptions: {
            parserOptions: {
                project: true,
                tsconfigRootDir: import.meta.dirname,
            },
        },
        rules: {
            '@typescript-eslint/no-explicit-any': 'error',
            '@typescript-eslint/explicit-function-return-type': 'error',
            '@typescript-eslint/no-unused-vars': 'error',
            '@typescript-eslint/no-non-null-assertion': 'error',
        },
    }
);
```

#### For React Frontend — `eslint.config.js`:
```javascript
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactHooks from 'eslint-plugin-react-hooks';
import reactRefresh from 'eslint-plugin-react-refresh';

export default tseslint.config(
    js.configs.recommended,
    ...tseslint.configs.recommended,
    {
        plugins: {
            'react-hooks': reactHooks,
            'react-refresh': reactRefresh,
        },
        rules: {
            ...reactHooks.configs.recommended.rules,
            'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
            '@typescript-eslint/no-explicit-any': 'error',
            '@typescript-eslint/explicit-function-return-type': 'error',
            '@typescript-eslint/no-non-null-assertion': 'error',
        },
    }
);
```

### Code Verification Order (MANDATORY — Run ALL of These)

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

**Never skip lint. Never ship code with lint errors. Never say "run npm run lint" — ACTUALLY RUN IT.**

### WalletConnect CSS Fix (for modal at bottom of page)

```css
/* Add to your global CSS if WalletConnect modal renders at bottom */
wcm-modal {
    position: fixed !important;
    top: 0 !important;
    left: 0 !important;
    right: 0 !important;
    bottom: 0 !important;
    z-index: 9999 !important;
    display: flex !important;
    align-items: center !important;
    justify-content: center !important;
    background: rgba(0, 0, 0, 0.5) !important;
}

wcm-modal::part(container) {
    position: relative !important;
    margin: auto !important;
}
```

---

## 3. Contract Development Rules

### Contract Entry Point — Required Structure

```typescript
import { Blockchain } from '@btc-vision/btc-runtime/runtime';
import { MyContract } from './MyContract';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';

// 1. Factory function — REQUIRED. Must return NEW instance, not assign instance.
Blockchain.contract = (): MyContract => {
    return new MyContract();
};

// 2. Runtime exports — REQUIRED
export * from '@btc-vision/btc-runtime/runtime/exports';

// 3. Abort handler — REQUIRED
export function abort(message: string, fileName: string, line: u32, column: u32): void {
    revertOnError(message, fileName, line, column);
}
```

### The Constructor vs onDeployment Trap (CRITICAL)

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

### @method() MUST Declare ALL Parameters (Critical Bug Prevention)

`@method()` with no arguments = zero ABI inputs declared. This is a CRITICAL bug:
- Callers must hand-roll calldata — no type safety
- SDK `getContract()` doesn't work
- Cannot be fixed without redeployment

```typescript
// WRONG — bare @method(), zero ABI inputs. FORBIDDEN.
@method()
@returns({ name: 'success', type: ABIDataTypes.BOOL })
public airdrop(calldata: Calldata): BytesWriter { ... }

// CORRECT — declare every input; tuples work
@method({ name: 'entries', type: ABIDataTypes.TUPLE, components: [
    { name: 'recipient', type: ABIDataTypes.ADDRESS },
    { name: 'amountPill', type: ABIDataTypes.UINT64 },
    { name: 'amountMoto', type: ABIDataTypes.UINT64 },
]})
@returns({ name: 'success', type: ABIDataTypes.BOOL })
public airdrop(calldata: Calldata): BytesWriter { ... }

// CORRECT — method with params
@method({ name: 'to', type: ABIDataTypes.ADDRESS }, { name: 'amount', type: ABIDataTypes.UINT256 })
@returns({ type: ABIDataTypes.BOOL })
public transfer(calldata: Calldata): BytesWriter { ... }
```

### Decorator Globals (Do NOT Import These)

`@method`, `@returns`, `@emit`, `@final`, and `ABIDataTypes` are **compile-time globals** injected by `@btc-vision/opnet-transform`. They are NOT exports from `@btc-vision/btc-runtime/runtime`. Importing them causes build failures.

```typescript
// WRONG — causes build failure
import { ABIDataTypes } from '@btc-vision/btc-runtime/runtime';
import { method } from '@btc-vision/btc-runtime/runtime';

// CORRECT — just use them directly, no import needed
@method({ name: 'to', type: ABIDataTypes.ADDRESS })
@returns({ type: ABIDataTypes.BOOL })
public transfer(calldata: Calldata): BytesWriter { ... }
```

(`@final` is a standard AssemblyScript decorator from the language itself — it IS available.)

### Common Imports

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

// NOTE: @method, @returns, @emit, @final, ABIDataTypes — DO NOT IMPORT, they are globals
```

### SafeMath — MANDATORY for ALL u256 Operations

```typescript
import { SafeMath } from '@btc-vision/btc-runtime/runtime';

// WRONG — can overflow/underflow silently
const result = a + b;
const result = a - b;
const result = a * b;

// CORRECT — SafeMath reverts on overflow/underflow
const result = SafeMath.add(a, b);
const result = SafeMath.sub(a, b);
const result = SafeMath.mul(a, b);
const result = SafeMath.div(a, b);
```

### Creating u256 Values

```typescript
// WRONG — pow() may not exist, can fail
const amount = u256.fromU64(1000).mul(u256.fromU64(10).pow(18));

// CORRECT — calculate offline, use string for large values
const TOKENS_PER_MINT: u256 = u256.fromString('1000000000000000000000');      // 1000 * 10^18
const MAX_SUPPLY: u256 = u256.fromString('100000000000000000000000000');       // 100M * 10^18

// For small values, fromU32/fromU64 is fine
const MAX_MINTS: u256 = u256.fromU32(5);
const ONE: u256 = u256.One;
const ZERO: u256 = u256.Zero;
```

### Storage and Pointers

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

**CRITICAL: NEVER use bare `Map<Address, T>` in contracts.** AssemblyScript's `Map` uses reference equality — two `Address` instances with identical bytes are different references. Use `AddressMemoryMap`, `StoredMapU256`, or `Nested` instead. For in-memory caches, key by `string` (`.toHexString()`).

### Storage Types

| Type | Use Case |
|------|----------|
| `StoredU256` | Single u256 value (total supply, deployment block) |
| `StoredBoolean` | Boolean flag (mint closed, paused) |
| `StoredString` | String value (name, symbol) |
| `StoredU64` | Single u64 value (block numbers, timestamps) |
| `AddressMemoryMap` | Address → value mapping (balances) |
| `StoredMapU256` | u256 → u256 mapping (generic key-value) |

### Forbidden Contract Patterns

```
✗ while loops — FORBIDDEN (unbounded gas consumption)
✗ Iterating all map keys — FORBIDDEN (O(n) gas explosion)
✗ Unbounded arrays — FORBIDDEN (cap size, use pagination)
✗ float (f32/f64) — FORBIDDEN in consensus code (non-deterministic across CPUs)
✗ Raw u256 arithmetic (+, -, *, /) — FORBIDDEN (use SafeMath)
✗ Native Map<T> with object keys — FORBIDDEN (reference equality broken)
✗ Blockchain.block.medianTimestamp for logic — FORBIDDEN (miner-manipulable ±2h)
✗ ABIDataTypes import — FORBIDDEN (it's a global, import causes build failure)
```

### Use Block Number, Not Timestamp

```typescript
// WRONG — medianTimestamp can be manipulated by miners (±2 hours)
if (Blockchain.block.medianTimestamp > deadline) { ... }

// CORRECT — block.number is strictly monotonic and tamper-proof
// 144 blocks ≈ 24 hours, 1008 blocks ≈ 1 week
if (Blockchain.block.number >= deploymentBlock + 1008n) { ... }
```

### callMethod Pattern — Must Include super

```typescript
public callMethod(calldata: Calldata): BytesWriter {
    const selector = calldata.readSelector();
    switch (selector) {
        case this.mySelector:
            return this.myMethod(calldata);
        default:
            return super.callMethod(calldata);  // REQUIRED — handles inherited methods
    }
}
```

### BytesWriter Size Must Match Content

```typescript
// WRONG — size mismatch
const writer = new BytesWriter(1);
writer.writeU256(value);  // Needs 32 bytes!

// CORRECT — calculate exact size
const writer = new BytesWriter(32);           // u256
const writer = new BytesWriter(1);            // bool
const writer = new BytesWriter(8);            // u64
const writer = new BytesWriter(1 + 32 + 8);  // bool + u256 + u64
```

### OP20 Token Pattern

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

### Signature Verification in Contracts

```typescript
// ONLY correct approach — consensus-aware, auto-selects algorithm
const isValid: bool = Blockchain.verifySignature(
    Blockchain.tx.origin,   // ExtendedAddress (has both key types)
    signature,              // Signature bytes
    messageHash,            // 32-byte SHA256 hash
    false,                  // false = auto-select, true = force ML-DSA
);

// DEPRECATED — will break when quantum consensus flag flips
// DO NOT USE: verifyECDSASignature, verifyBitcoinECDSASignature, verifySchnorrSignature
```

### Upgradeable Contracts

```typescript
import { Upgradeable, Calldata } from '@btc-vision/btc-runtime/runtime';

export class MyContract extends Upgradeable {
    public constructor() {
        super();
    }

    public override onUpdate(_oldVersion: u256, calldata: Calldata): void {
        // Migration logic — runs ONCE on upgrade
        // CRITICAL: Storage pointers MUST remain in same order across versions
        // New pointers should be APPENDED, never inserted between existing ones
    }
}
```

---

## 4. Frontend Development Rules

### ABSOLUTE RULES (Never Violate)

1. **Vite is MANDATORY** — No webpack, no parcel, no rollup standalone. Vite only.
2. **signer: null, mldsaSigner: null ALWAYS** — The browser wallet (OP_WALLET) handles ALL signing. NEVER put private keys in frontend code.
3. **ALWAYS simulate before sendTransaction** — Bitcoin transfers are irreversible.
4. **getContract() requires 5 params** — `(address, abi, provider, network, senderAddress)`
5. **Address.fromString() requires 2 params** — `(hashedMLDSAKey, publicKey)`. Never pass a raw Bitcoin address.
6. **Cache getContract instances** — Never recreate on every render/call.
7. **Use @btc-vision/walletconnect v2 API** — Not v1. `useWalletConnect()` is the hook.
8. **No raw PSBT** — FORBIDDEN.
9. **No Buffer** — Use `Uint8Array` + `BufferHelper`.
10. **No static feeRate** — Use `provider.gasParameters()` or leave undefined.

### Walletconnect v2 — Correct API

```typescript
import { useWalletConnect, SupportedWallets } from '@btc-vision/walletconnect';

const {
    isConnected,      // boolean — check this, NOT signer
    address,          // "bc1p..." — for display and refundTo only
    publicKey,        // "0x0203..." — Bitcoin tweaked pubkey (33 bytes compressed)
    hashedMLDSAKey,   // "0xABCD..." — 32-byte SHA256 hash of ML-DSA key
    mldsaPublicKey,   // "0x..." — RAW ML-DSA pubkey (~2500 bytes) — for signing ONLY
    network,          // network object
    connectToWallet,  // function
    disconnect,       // function
} = useWalletConnect();

// Connect
await connectToWallet(SupportedWallets.OP_WALLET);

// Build OPNet Address from walletconnect data
const senderAddress = Address.fromString(hashedMLDSAKey, publicKey);
//                                        ^^^              ^^^
//                                        1st param        2nd param
//                                        (32-byte hash)   (Bitcoin tweaked pubkey)
```

### getContract — Full 5-Param Pattern

```typescript
import { getContract, IOP20Contract, OP_20_ABI, JSONRpcProvider } from 'opnet';
import { networks } from '@btc-vision/bitcoin';
import { Address } from 'opnet';

const provider = new JSONRpcProvider({ url: 'https://mainnet.opnet.org', network: networks.bitcoin });

// Build sender address from walletconnect
const { publicKey, hashedMLDSAKey } = useWalletConnect();
const senderAddress = Address.fromString(hashedMLDSAKey, publicKey);

// CORRECT — all 5 params
const contract = getContract<IOP20Contract>(
    contractAddress,   // 1: address (op1... or 0x...)
    OP_20_ABI,         // 2: ABI
    provider,          // 3: provider
    networks.bitcoin,  // 4: network
    senderAddress,     // 5: sender address — REQUIRED
);

// WRONG — missing params
const contract = getContract(address, abi);                        // 2 params: BROKEN
const contract = getContract(address, abi, provider);              // 3 params: BROKEN
const contract = getContract(address, abi, provider, networks.bitcoin); // 4 params: missing sender
```

### Provider Singleton Pattern — Cache It

```typescript
// WRONG — creates a new provider on every render/call
function Component() {
    const provider = new JSONRpcProvider({ url, network }); // Bad!
}

// CORRECT — singleton service
class ProviderService {
    private static instance: ProviderService;
    private providers: Map<string, JSONRpcProvider> = new Map();

    public static getInstance(): ProviderService {
        if (!ProviderService.instance) {
            ProviderService.instance = new ProviderService();
        }
        return ProviderService.instance;
    }

    public getProvider(network: Network): JSONRpcProvider {
        const key = network === networks.bitcoin ? 'mainnet' : 'testnet';
        if (!this.providers.has(key)) {
            const url = network === networks.bitcoin ? 'https://mainnet.opnet.org' : 'https://testnet.opnet.org';
            this.providers.set(key, new JSONRpcProvider({ url, network }));
        }
        return this.providers.get(key)!;
    }
}
```

### Contract Cache Pattern — Cache with setSender()

```typescript
// WRONG — creates new contract instance every click
const handleClick = async () => {
    const contract = getContract(address, abi, provider, network, sender);  // New every time!
};

// CORRECT — cache with setSender() for sender updates
class ContractService {
    private readonly cache = new Map<string, IOP20Contract>();

    public getToken(address: string, network: Network, sender: Address): IOP20Contract {
        if (!this.cache.has(address)) {
            const contract = getContract<IOP20Contract>(address, OP_20_ABI, provider, network, sender);
            this.cache.set(address, contract);
        }
        const cached = this.cache.get(address)!;
        cached.setSender(sender);  // Update sender without recreating
        return cached;
    }
}
```

### Transaction Pattern — Simulate Always

```typescript
// FRONTEND pattern
const handleTransfer = async () => {
    // 1. Build simulation context
    const senderAddress = Address.fromString(hashedMLDSAKey, publicKey);
    const contract = contractService.getToken(tokenAddress, network, senderAddress);

    // 2. OPTIONAL: Set extra I/O before simulate if payable
    // contract.setTransactionDetails({ inputs: [], outputs: [{ to: '...', value: 5000n, index: 1, flags: TransactionOutputFlags.hasTo }] });

    // 3. Simulate FIRST
    const sim = await contract.transfer(recipientPubKey, amount);
    if ('error' in sim) {
        setError(sim.error);
        return;
    }

    // 4. Send with null signers (ALWAYS on frontend)
    const receipt = await sim.sendTransaction({
        signer: null,           // ALWAYS null on frontend
        mldsaSigner: null,      // ALWAYS null on frontend
        refundTo: address,      // bc1p... wallet address
        maximumAllowedSatToSpend: 100000n,
        network,
    });

    console.log('tx:', receipt);
};
```

### Dynamic feeRate — Never Hardcode

```typescript
// WRONG — static feeRate will overpay or underpay
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: 2,   // STATIC — BAD
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});

// CORRECT — leave undefined (opnet defaults) or use live rate
const gasParams = await provider.gasParameters();
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: gasParams.bitcoin.recommended.medium,  // Live rate
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### Address Validation — Always Use AddressVerificator

```typescript
import { AddressVerificator, AddressTypes } from '@btc-vision/transaction';

// WRONG — manual prefix checks are fragile, miss P2MR, P2OP, etc.
if (address.startsWith('bc1p')) { /* P2TR */ }

// CORRECT — use AddressVerificator
const type = AddressVerificator.detectAddressType(address, network);
const isValid = AddressVerificator.isValidAddress(address, network);
const isP2TR = AddressVerificator.isValidP2TRAddress(address, network);
const isP2MR = AddressVerificator.isValidP2MRAddress(address, network);   // quantum-resistant
const isContract = AddressVerificator.isValidP2OPAddress(address, network); // op1...
```

### Public Key Resolution

Bitcoin addresses (bc1p...) cannot be used directly in token operations. You need the hex public key (0x...).

```typescript
// If you only have a bc1p... address, resolve it
const info = await provider.getPublicKeyInfo('bc1p...');

if (!info || !info.publicKey) {
    // NOT FOUND — force user to enter their public key manually
    setRequiresManualPubKey(true);
    return;
}

const pubKey = info.publicKey;  // "0x0203..."
```

**IMPORTANT**: `getPublicKeyInfo` with a contract address: use `getPublicKeyInfo(addr, true)` — the second param `true` is required for contract addresses.

### BitcoinUtils for Token Amounts

```typescript
import { BitcoinUtils } from 'opnet';

// WRONG — raw bigint multiplication
const amount = BigInt(userInput) * 10n ** 18n;

// CORRECT — BitcoinUtils handles decimals correctly
const amount = BitcoinUtils.expandToDecimals(userInput, tokenDecimals);

// Display (reverse)
const displayAmount = BitcoinUtils.formatUnits(amount, tokenDecimals);
```

### metadata() — Use Instead of Multiple Calls

```typescript
// WRONG — 4 separate RPC calls (slow)
const name = await contract.name();
const symbol = await contract.symbol();
const decimals = await contract.decimals();
const totalSupply = await contract.totalSupply();

// CORRECT — 1 RPC call
const metadataResult = await contract.metadata();
const { name, symbol, decimals, totalSupply } = metadataResult.properties;
```

### Plain BTC Transfer (Frontend)

```typescript
import { TransactionFactory } from '@btc-vision/transaction';
import { JSONRpcProvider } from 'opnet';
import { networks } from '@btc-vision/bitcoin';

const factory = new TransactionFactory();
const accounts = await window.opnet.requestAccounts();
const userAddress = accounts[0];

const utxos = await provider.utxoManager.getUTXOs({
    address: userAddress,
    optimize: false,   // ALWAYS false — optimize: true filters UTXOs
});

const result = await factory.createBTCTransfer({
    signer: null,        // null — OPWallet signs
    mldsaSigner: null,   // null — OPWallet signs
    network,
    utxos,
    from: userAddress,
    to: 'bc1p...recipient',
    feeRate: 10,
    amount: 50000n,
    // NO gasSatFee, NO priorityFee for plain BTC transfers
});

await provider.sendRawTransaction(result.tx, false);
```

### Extra Inputs/Outputs Pattern (setTransactionDetails)

Use when a contract needs to verify extra outputs during simulation:

```typescript
import { TransactionOutputFlags } from 'opnet';

// Step 1: Set BEFORE simulate
contract.setTransactionDetails({
    inputs: [],
    outputs: [{
        to: 'bc1p...recipient',
        value: 5000n,
        index: 1,   // index 0 is RESERVED — start at 1
        flags: TransactionOutputFlags.hasTo,
    }],
});

// Step 2: Simulate
const sim = await contract.somePayableMethod(args);
if ('error' in sim) throw new Error(sim.error);

// Step 3: Send with matching extras
const receipt = await sim.sendTransaction({
    signer: null,
    mldsaSigner: null,
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
    extraOutputs: [{
        address: 'bc1p...recipient',
        value: 5000,   // Must match what was set above
    }],
});
```

**setTransactionDetails() clears after each call. Call it right before every simulate that needs it.**

---

## 5. Backend Development Rules

### Required Frameworks

| Use | Never Use |
|-----|-----------|
| `@btc-vision/hyper-express` | Express, Fastify, Koa, Hapi |
| `@btc-vision/uwebsocket.js` | Socket.io, ws |
| MongoDB | SQLite, PostgreSQL (for OPNet indexing) |
| Worker threads | Single-threaded implementations |

### Backend Transaction Pattern

```typescript
// BACKEND — MUST specify both signers
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,           // REQUIRED on backend
    mldsaSigner: wallet.mldsaKeypair, // REQUIRED on backend
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### HyperExpress Server Pattern

```typescript
import HyperExpress from '@btc-vision/hyper-express';

const app = new HyperExpress.Server({
    max_body_length: 1024 * 1024 * 8,   // 8mb
    fast_abort: true,
    max_body_buffer: 1024 * 32,          // 32kb
    idle_timeout: 60,
    response_timeout: 120,
});

// CRITICAL: Always register global error handler FIRST
app.set_error_handler((req, res, error) => {
    if (res.closed) return;
    res.atomic(() => {
        res.status(500);
        res.json({ error: 'Something went wrong.' });
    });
});
```

### Threading Pattern (Mandatory)

```typescript
import { Worker, isMainThread, parentPort } from 'worker_threads';
import os from 'os';

if (isMainThread) {
    // Main thread: HTTP server only
    const WORKER_COUNT = Math.max(1, os.cpus().length - 1);
    const workers: Worker[] = [];
    for (let i = 0; i < WORKER_COUNT; i++) {
        workers.push(new Worker(__filename));
    }
    // Round-robin dispatch to workers
} else {
    // Worker thread: CPU-intensive operations
    parentPort?.on('message', async (msg) => {
        // Handle simulation, signing, etc.
    });
}
```

### Wallet Derivation — Use deriveOPWallet()

```typescript
import { Mnemonic, MLDSASecurityLevel } from '@btc-vision/transaction';
import { networks, AddressTypes } from '@btc-vision/bitcoin';

const mnemonic = Mnemonic.generate(undefined, '', networks.bitcoin, MLDSASecurityLevel.LEVEL2);

// CORRECT — OPWallet-compatible derivation
const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);

// WRONG — uses different derivation path, keys won't match OPWallet
const wallet = mnemonic.derive(0);
```

---

## 6. Transaction Rules

### The Absolute Law

| NEVER | ALWAYS |
|-------|--------|
| `new Psbt()` | `getContract()` → simulate → `sendTransaction()` |
| `Psbt.fromBase64()` | Check `'error' in sim` before sending |
| `@btc-vision/transaction` for contract calls | `opnet` package `getContract()` for contract calls |
| Manual calldata encoding | ABI-typed method calls via `getContract()` |
| `signer: wallet.keypair` on frontend | `signer: null` on frontend |
| `signer: null` on backend | `signer: wallet.keypair` on backend |
| Skip simulation | ALWAYS simulate before sending |
| Static feeRate | `provider.gasParameters()` or undefined |
| `optimize: true` in getUTXOs | `optimize: false` ALWAYS |

### `@btc-vision/transaction` — ONLY for TransactionFactory

The only valid use of `@btc-vision/transaction` for building transactions is `TransactionFactory` — and only for:
- Plain BTC transfers (`createBTCTransfer`)
- Contract deployments

NOT for contract calls. Never.

### Signer Rules Summary

```
FRONTEND: signer: null, mldsaSigner: null
BACKEND:  signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair
```

There are NO exceptions. Mixing these up = private key leak or broken transaction.

---

## 7. Common Agent Mistakes

**These are real mistakes AI agents make repeatedly. If you catch yourself doing any of these, STOP.**

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Using `Blockchain.block.medianTimestamp` for time-dependent logic | Bitcoin's MTP can be MANIPULATED BY MINERS within ±2 hours. Critical security vulnerability. | **ALWAYS use `Blockchain.block.number`** (block height). Strictly monotonic, tamper-proof. 144 blocks ≈ 24h. |
| Using Keccak256 selectors | OPNet uses **SHA256**, not Keccak256. This is Bitcoin, not Ethereum. | Use SHA256 for all hashing and method selectors |
| Calling `approve()` on OP-20 tokens | OP-20 does NOT have `approve()`. Doesn't exist. | Use `increaseAllowance(spender, amount)` and `decreaseAllowance(spender, amount)` |
| Passing `bc1p...` address to `Address.fromString()` | `Address.fromString()` takes TWO hex pubkey parameters, not a Bech32 address string. | `Address.fromString(hashedMLDSAKey, tweakedPublicKey)` — both are hex strings |
| Using `bitcoinjs-lib` | OPNet has its own Bitcoin library with critical patches, 145x faster PSBT creation. | Use `@btc-vision/bitcoin` — never `bitcoinjs-lib` |
| Skipping simulation before `sendTransaction()` | Bitcoin transfers are irreversible. If contract reverts, your BTC is gone. | ALWAYS simulate first. Check `'error' in sim` before sending. |
| Using Express/Fastify/Koa for backends | Forbidden. Significantly slower. | Use `@btc-vision/hyper-express` and `@btc-vision/uwebsockets.js` |
| Not running `npm-check-updates` after setup | Stale versions = build failures | Run `npx npm-check-updates -u && npm i ...` |
| Using `verifyECDSASignature` or `verifySchnorrSignature` without deprecation warning | Both ECDSA and Schnorr are DEPRECATED. ECDSA will break when consensus disables `UNSAFE_QUANTUM_SIGNATURES_ALLOWED`. | **ALWAYS use** `Blockchain.verifySignature(address, signature, hash)` — consensus-aware, auto-selects algorithm |
| Using non-Auto signing methods (`signMessage()`, `signMLDSAMessage()`) | Environment-specific — wrong one = runtime crash | **ALWAYS use Auto methods**: `signMessageAuto()`, `tweakAndSignMessageAuto()`, `signMLDSAMessageAuto()` |
| Using `Buffer` anywhere | `Buffer` is REMOVED from entire OPNet stack | Use `Uint8Array` everywhere. `BufferHelper` from `@btc-vision/transaction` for hex conversions. |
| Using `assemblyscript` instead of `@btc-vision/assemblyscript` | Upstream `assemblyscript` incompatible with OPNet — no closure support. | `npm uninstall assemblyscript && npm i @btc-vision/assemblyscript@^0.29.2` |
| Not uninstalling `assemblyscript` before installing fork | Both provide `asc` binary — version conflicts, build failures | Always `npm uninstall assemblyscript` FIRST |
| Single-threaded backend APIs | Cannot handle concurrent OPNet requests. Hard requirement. | Use Worker threads for CPU-bound work. `@btc-vision/hyper-express` supports threading natively. |
| Not using MongoDB for persistence | File-based storage doesn't scale for OPNet indexing | Use MongoDB for all backend persistence |
| Using old WalletConnect v1 API | v1 is deprecated. API changed significantly. | Use `@btc-vision/walletconnect` v2 API. `useWalletConnect()` hook. |
| Manually checking address prefixes (startsWith) | Fragile, misses P2MR, P2OP, P2WSH, P2WDA types. | Use `AddressVerificator.detectAddressType()` from `@btc-vision/transaction` |
| Using `mnemonic.derive()` instead of `mnemonic.deriveOPWallet()` | Different derivation path. Keys won't match OPWallet. "Invalid ML-DSA legacy signature" errors. | **ALWAYS use `mnemonic.deriveOPWallet(AddressTypes.P2TR, 0)`** for OPWallet-compatible derivation |
| Importing `ABIDataTypes` or decorators in contract code | These are compile-time globals from `@btc-vision/opnet-transform`. Importing = build failure. | Do NOT import. Use `ABIDataTypes.ADDRESS`, `@method(...)` etc. directly — transform provides them. |
| Calling `name()` or `symbol()` on OP20 test class | Unit-test-framework's `OP20` has no `name()` or `symbol()` methods directly. | Use `const { metadata } = await token.metadata()` then `metadata.name`, `metadata.symbol`. |
| Using `Blockchain.setSender()` in tests | This method does NOT exist. | Use `Blockchain.msgSender = address` (property setter) |
| Using `Networks` enum from `@btc-vision/bitcoin` | No `Networks` enum exists in `@btc-vision/bitcoin`. | Use `networks` (lowercase namespace): `networks.bitcoin`, `networks.opnetTestnet`, `networks.testnet`, `networks.regtest` |
| Using `OP20_ABI` (missing underscore) | Wrong export name. | Use `OP_20_ABI` from `opnet` |
| Calling `getContract()` with 3-4 args | Requires 5 params. 4th (network) and 5th (senderAddress) are needed. | `getContract<T>(address, abi, provider, network, senderAddress)` — always 5 args |
| `new JSONRpcProvider(url, network)` positional args | Constructor takes config OBJECT, not positional args. | `new JSONRpcProvider({ url: '...', network: networks.bitcoin })` |
| Missing `crypto-browserify` override in Vite | Without it, signing operations fail in browser. | Add `overrides: { crypto: 'crypto-browserify' }` to nodePolyfills AND `undici` alias |
| Checking `transfer().properties.success` | OP-20 `Transfer` type returns `CallResult<{}>` — properties is `{}`. No `success` boolean. | Check `result.revert === undefined` to determine if transfer succeeded |
| Using `this.getSelector()` as if inherited from ContractRuntime | ContractRuntime does NOT provide `getSelector()`. Not inherited. | Define your own: `private getSelector(sig: string): number { return Number(\`0x\${this.abiCoder.encodeSelector(sig)}\`); }` |
| 4 separate RPC calls for name/symbol/decimals/totalSupply | 4 network round-trips instead of 1. 4x-10x slower. | Use `contract.metadata()` which returns ALL token info in one call |
| Raw bigint multiplication for token amounts | Breaks with fractional amounts, different decimals. | Use `BitcoinUtils.expandToDecimals(value, decimals)` from `opnet` |
| Constructor trap in contracts | OPNet constructor runs on EVERY interaction. Minting/state changes in constructor runs every call! | Put ALL initialization logic in `onDeployment()`, which runs only ONCE. |
| `@method()` with no params | Zero ABI inputs declared. Callers must hand-roll calldata. Breaks SDK. Requires redeployment. | ALWAYS declare all method params: `@method({ name: 'to', type: ABIDataTypes.ADDRESS }, ...)` |

---

## 8. Known Frontend Mistakes (All 19)

### 1. Using `contract.execute()` with raw selector bytes

```typescript
// WRONG
const selector = new Uint8Array([0x01, 0x02, 0x03, 0x04]);
const result = await contract.execute(selector, calldata);

// CORRECT
const result = await contract.claim(signature, messageHash);
```

### 2. Missing `getContract` parameters (must be 5)

```typescript
// WRONG
const contract = getContract(address, abi);
const contract = getContract(address, abi, provider);

// CORRECT
const contract = getContract(address, abi, provider, network, senderAddress);
```

### 3. Gating frontend actions on `signer` from walletconnect

On frontend, the `signer` from walletconnect may be `null` initially. Don't gate on it.

```typescript
// WRONG
if (!signer) throw new Error('Wallet not connected');
await contract.claim(signer, ...);

// CORRECT
const { isConnected, address } = useWalletConnect();
if (!isConnected || !address) throw new Error('Wallet not connected');
```

### 4. Using walletconnect's provider for read calls

```typescript
// WRONG
const { provider } = useWalletConnect();
const data = await provider.call(...);

// CORRECT
const readProvider = new JSONRpcProvider({ url: 'https://mainnet.opnet.org', network: networks.bitcoin });
const contract = getContract(address, abi, readProvider, network, sender);
```

### 5. Importing from wrong packages

| Symbol | Correct Package |
|--------|----------------|
| `Address` | `@btc-vision/transaction` or re-exported from `opnet` |
| `ABIDataTypes` | `@btc-vision/transaction` or re-exported from `opnet` |
| `JSONRpcProvider` | `opnet` |
| `networks` | `@btc-vision/bitcoin` |

```typescript
// WRONG — Address not in @btc-vision/bitcoin browser bundle
import { Address } from '@btc-vision/bitcoin'; // WILL FAIL IN BROWSER

// CORRECT
import { Address, ABIDataTypes, JSONRpcProvider } from 'opnet';
```

### 6. Passing raw Bitcoin address or 1 param to `Address.fromString()`

`Address.fromString()` requires TWO params:
- First: `hashedMLDSAKey` (32-byte SHA256 hash of ML-DSA key — NOT the raw ML-DSA public key)
- Second: `publicKey` (Bitcoin tweaked public key, 33 bytes compressed)

```typescript
// WRONG
const sender = Address.fromString(walletAddress);      // bc1p... is NOT a pubkey
const sender = Address.fromString(publicKey);          // Missing second param
const sender = Address.fromString(mldsaPublicKey, publicKey); // mldsaPublicKey is RAW (~2500 bytes), need HASH

// CORRECT
const { publicKey, hashedMLDSAKey } = useWalletConnect();
const sender = Address.fromString(hashedMLDSAKey, publicKey);
//                                  ^^^              ^^^
//                                  32-byte hash     33-byte tweaked pubkey
```

### 7. Using `walletAddress` (bc1p...) where public key hex is needed

```typescript
// Wrong — bc1p... is NOT a public key
await contract.transfer(walletAddress, amount);

// Correct address format guide:
// walletAddress (bc1p/bc1q) → ONLY for display and refundTo
// publicKey (0x hex, 33 bytes) → Bitcoin tweaked pubkey, for Address.fromString 2nd param
// hashedMLDSAKey (0x hex, 32 bytes) → SHA256 hash of ML-DSA key, for Address.fromString 1st param
// mldsaPublicKey (0x hex, ~2500 bytes) → RAW ML-DSA key, for signing ONLY
```

### 8. Using `Buffer` anywhere

```typescript
// WRONG
const data = Buffer.from(hexString, 'hex');

// CORRECT
import { BufferHelper } from '@btc-vision/transaction';
const data = BufferHelper.hexToUint8Array(hexString);
const hex = BufferHelper.uint8ArrayToHex(bytes);
```

### 9. Using old WalletConnect v1 API

```typescript
// WRONG — v1 API
const { connect, provider, signer } = useWalletConnect();
await connect();

// CORRECT — v2 API
const { connectToWallet, isConnected, address } = useWalletConnect();
await connectToWallet(SupportedWallets.OP_WALLET);
```

### 10. Manual address prefix checking instead of AddressVerificator

```typescript
// WRONG
if (address.startsWith('bc1p')) { /* P2TR */ }

// CORRECT
import { AddressVerificator } from '@btc-vision/transaction';
const type = AddressVerificator.detectAddressType(address, network);
```

### 11. Using raw PSBT for OPNet transactions

```typescript
// WRONG — ABSOLUTELY FORBIDDEN
import { Psbt } from '@btc-vision/bitcoin';
const psbt = new Psbt({ network });
psbt.addInput({ ... });

// CORRECT
const sim = await contract.transfer(to, amount);
const receipt = await sim.sendTransaction({ signer: null, mldsaSigner: null, ... });
```

### 12. Using @btc-vision/transaction directly for contract calls

```typescript
// WRONG — TransactionFactory is NOT for contract calls
const factory = new TransactionFactory();
const tx = await factory.signInteraction({ contract, calldata, ... });

// CORRECT
const contract = getContract(address, abi, provider, network, sender);
const sim = await contract.transfer(to, amount);
const receipt = await sim.sendTransaction({ ... });
```

### 13. Passing signer on frontend / omitting signer on backend

```typescript
// WRONG — Frontend with signer (LEAKS PRIVATE KEYS)
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,           // NEVER on frontend
    mldsaSigner: wallet.mldsaKeypair, // NEVER on frontend
    ...
});

// CORRECT — Frontend (signer always null)
const receipt = await sim.sendTransaction({
    signer: null,
    mldsaSigner: null,
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});

// CORRECT — Backend (signers required)
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,
    mldsaSigner: wallet.mldsaKeypair,
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### 14. Skipping `setTransactionDetails` for payable functions with extra outputs

```typescript
// WRONG — extra outputs without telling contract during simulation
const sim = await contract.somePayableMethod(args);
const receipt = await sim.sendTransaction({
    extraOutputs: [{ address: 'bc1p...', value: 5000 }], // Contract didn't see this!
});

// CORRECT — set BEFORE simulate
import { TransactionOutputFlags } from 'opnet';
contract.setTransactionDetails({
    inputs: [],
    outputs: [{
        to: 'bc1p...recipient',
        value: 5000n,
        index: 1,   // 0 is RESERVED
        flags: TransactionOutputFlags.hasTo,
    }],
});
const sim = await contract.somePayableMethod(args);
const receipt = await sim.sendTransaction({
    extraOutputs: [{ address: 'bc1p...recipient', value: 5000 }],
    ...
});
```

### 15. Using `getContract()` for plain BTC transfers

```typescript
// WRONG — getContract is for contract calls, NOT BTC transfers
const contract = getContract(address, abi, provider, network, sender);
const sim = await contract.transfer(recipient, amount); // This is OP20, not BTC!

// CORRECT — TransactionFactory for BTC transfers
import { TransactionFactory } from '@btc-vision/transaction';
const factory = new TransactionFactory();
const result = await factory.createBTCTransfer({
    signer: null,
    mldsaSigner: null,
    network, utxos, from: userAddress,
    to: 'bc1p...recipient', feeRate: 10, amount: 50000n,
});
await provider.sendRawTransaction(result.tx, false);
```

### 16. Raw bigint multiplication for token amounts

```typescript
// WRONG — breaks with fractional amounts
const amount = BigInt(userInput) * 10n ** 18n;

// CORRECT
import { BitcoinUtils } from 'opnet';
const amount = BitcoinUtils.expandToDecimals(userInput, tokenDecimals);
const display = BitcoinUtils.formatUnits(amount, tokenDecimals);
```

### 17. Creating `getContract` inside event handlers (no caching)

```typescript
// WRONG — new instance every click
const handleApprove = async () => {
    const contract = getContract(address, abi, provider, network, sender); // NEW every time!
};

// CORRECT — cache and use setSender()
const cachedContract = getContract<IOP20Contract>(address, OP_20_ABI, provider, network, sender);
// Later in handler:
cachedContract.setSender(currentSender);
const sim = await cachedContract.increaseAllowance(spender, amount);
```

### 18. Static `feeRate` that will break on mainnet

```typescript
// WRONG — hardcoded rate
await sim.sendTransaction({ signer: null, mldsaSigner: null, feeRate: 2, ... });

// CORRECT — dynamic or undefined
const gasParams = await provider.gasParameters();
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: gasParams.bitcoin.recommended.medium, // or just omit for default
    ...
});
```

### 19. Using `getPublicKeyInfo` RPC call when you have the 0x address

```typescript
// AVOIDABLE — makes RPC call to resolve opr1 → Address
const idoAddress = await provider.getPublicKeyInfo(CONTRACTS.BLOCK_IDO_OPR1, true);
const sim = await motoContract.increaseAllowance(idoAddress, amount);

// BETTER — store and use 0x hex address directly
import { Address } from 'opnet';
const spenderAddress = Address.fromString(CONTRACTS.BLOCK_IDO_0X);
// Address.fromString with 1 param works for contract addresses (they are public key hashes)
const sim = await motoContract.increaseAllowance(spenderAddress, amount);
```

---

## 9. Security Checklist

### Contract Security

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
[ ] Not initialize state in constructor (use onDeployment)
[ ] @method() declares ALL params (no bare @method())
[ ] No ABIDataTypes import (it's a global)
[ ] CSV timelocks on all BTC-receiving swap addresses
[ ] No iterating all token holders for airdrops (use claim pattern)
[ ] No approve() — use increaseAllowance()/decreaseAllowance()
[ ] save() called after mutations on StoredU256Array/StoredAddressArray
```

### Frontend Security

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
```

### CEI Pattern (Checks-Effects-Interactions)

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

    // 2. EFFECTS — update state FIRST
    this.balances.get(sender).set(SafeMath.sub(balance, amount));
    this.balances.get(to).set(SafeMath.add(this.balances.get(to).get(), amount));

    // 3. INTERACTIONS — external calls LAST
    // (safe to call external contract now that state is updated)
}
```

---

## 10. Signature Verification

### The ONLY Correct Approach

```typescript
// CONTRACT SIDE — Blockchain.verifySignature() ONLY
const isValid: bool = Blockchain.verifySignature(
    Blockchain.tx.origin,   // ExtendedAddress
    signature,              // Uint8Array
    messageHash,            // 32-byte SHA256 hash
    false,                  // false = auto (Schnorr now, ML-DSA when enforced)
);
```

### DEPRECATED — Never Use Directly

```typescript
// DEPRECATED — will break when quantum consensus flag flips
Blockchain.verifyECDSASignature(...)          // DEPRECATED
Blockchain.verifyBitcoinECDSASignature(...)   // DEPRECATED
Blockchain.verifySchnorrSignature(...)        // DEPRECATED (but still works via verifySignature path)
```

### Client-Side Signing — Always Use Auto Methods

```typescript
import { MessageSigner } from '@btc-vision/transaction';

// AUTO methods detect browser (OP_WALLET) vs backend (local keypair) automatically
// ALWAYS use these

// Schnorr (works in both environments)
const signed = await MessageSigner.signMessageAuto(message);              // Browser: OP_WALLET
const signed = await MessageSigner.signMessageAuto(message, keypair);     // Backend: local

// Taproot-tweaked Schnorr
const signed = await MessageSigner.tweakAndSignMessageAuto(message);                    // Browser
const signed = await MessageSigner.tweakAndSignMessageAuto(message, keypair, network); // Backend

// ML-DSA (quantum-resistant)
const signed = await MessageSigner.signMLDSAMessageAuto(message);                    // Browser
const signed = await MessageSigner.signMLDSAMessageAuto(message, mldsaKeypair);      // Backend
```

### Non-Auto Methods — Environment-Specific (Use with Caution)

```typescript
// ONLY in known backend environments
MessageSigner.signMessage(keypair, message);
MessageSigner.tweakAndSignMessage(keypair, message, network);
MessageSigner.signMLDSAMessage(mldsaKeypair, message);
```

---

## 11. Deployment

### Gas Limits

- **Constructor call on deployment**: 20M gas hardcoded by the protocol
- **Regular calls**: configurable, defaults to 300M
- **CRITICAL**: If your `onDeployment()` method is complex or makes cross-contract calls, it can exceed the 20M gas limit and the deployment will revert consuming all gas

### Why Deployment Reverts Consuming All Gas

If you see "deployment works but contract not found" or "transaction reverted consuming all gas":
1. **Cross-contract calls in `onDeployment()`** — avoid these
2. **Calldata encoding mismatch** — verify the ABI encoding of deployment params
3. **Insufficient gas limit** — 20M is the cap; complex init logic must be simplified
4. **Missing/wrong asconfig.json features** — ensure ALL `enable` features are present

### Deployment Pattern

```typescript
// CORRECT deployment calldata encoding
import { BinaryWriter } from '@btc-vision/transaction';

const calldata = new BinaryWriter();
calldata.writeAddress(ownerAddress);      // write expected param types
calldata.writeU256(initialSupply);

const deploymentCalldata = calldata.getBuffer();
```

### IPFS Deployment — opnet-cli ONLY

```bash
# Build first
npm run build   # produces dist/ folder

# Upload to IPFS (no domain)
bash /path/to/opnet-cli/scripts/ipfs-upload.sh ./dist

# Upload + publish to .btc domain
bash /path/to/opnet-cli/scripts/ipfs-upload.sh ./dist mysite

# Dry run
bash /path/to/opnet-cli/scripts/ipfs-upload.sh ./dist mysite --dry-run
```

**FORBIDDEN IPFS methods:**
- Local IPFS daemon (Kubo) — do NOT run `ipfs add`
- Direct HTTP calls to IPFS API
- Any method other than the opnet-cli script

**REQUIRED for IPFS**: `base: './'` in vite.config.ts (NOT `base: '/'`)

---

## 12. Quick Reference

### Network Endpoints

```typescript
import { networks } from '@btc-vision/bitcoin';

const NETWORKS = {
    mainnet: {
        network: networks.bitcoin,
        rpc: 'https://mainnet.opnet.org',
    },
    testnet: {
        network: networks.opnetTestnet,
        rpc: 'https://testnet.opnet.org',
    },
};
```

### Selector Computation

OPNet method selectors are computed using SHA-256 (not Keccak-256):

```typescript
// In contract (AssemblyScript):
const selector: Selector = encodeSelector('transfer(address,uint256)');

// In tests (TypeScript):
private getSelector(signature: string): number {
    return Number(`0x${this.abiCoder.encodeSelector(signature)}`);
}
```

### Key Imports Cheat Sheet

```typescript
// For contracts (AssemblyScript):
import { Blockchain, OP_NET, OP20, OP721, Address, Calldata, BytesWriter,
         Selector, StoredU256, StoredBoolean, StoredString, StoredU64,
         AddressMemoryMap, StoredMapU256, encodeSelector, SafeMath, Revert,
         Upgradeable } from '@btc-vision/btc-runtime/runtime';
import { u256, u128 } from '@btc-vision/as-bignum/assembly';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';
// NOTE: @method, @returns, @emit, @final, ABIDataTypes — DO NOT IMPORT (they are globals)

// For frontend:
import { getContract, IOP20Contract, OP_20_ABI, JSONRpcProvider, BitcoinUtils,
         Address, ABIDataTypes, TransactionOutputFlags } from 'opnet';
import { networks, Network } from '@btc-vision/bitcoin';
import { AddressVerificator, BufferHelper, MessageSigner,
         TransactionFactory } from '@btc-vision/transaction';
import { useWalletConnect, SupportedWallets } from '@btc-vision/walletconnect';

// For backend:
import { JSONRpcProvider, getContract, IOP20Contract, OP_20_ABI } from 'opnet';
import { networks } from '@btc-vision/bitcoin';
import { AddressVerificator, BufferHelper, MessageSigner, Mnemonic,
         MLDSASecurityLevel } from '@btc-vision/transaction';
import HyperExpress from '@btc-vision/hyper-express';

// For tests:
import { opnet, OPNetUnit, Assert, Blockchain, ContractRuntime } from '@btc-vision/unit-test-framework';
import { Address, BinaryWriter, BinaryReader } from '@btc-vision/transaction';
```

### Common Contract Mistakes at a Glance

| Problem | Fix |
|---------|-----|
| Deployment reverts consuming all gas | Check: asconfig.json features, cross-contract calls in onDeployment, calldata encoding |
| `Cannot find module assemblyscript` | `npm uninstall assemblyscript` first, then install `@btc-vision/assemblyscript` |
| `Buffer is not defined` | Replace all Buffer with Uint8Array + BufferHelper |
| `getPublicKeyInfo returned undefined` | Address hasn't transacted yet. For contracts: use `getPublicKeyInfo(addr, true)` |
| `signInteraction is not a function` | Use `getContract()` + simulate + `sendTransaction()` — NOT TransactionFactory for contract calls |
| `Invalid ML-DSA legacy signature` | Using `derive()` instead of `deriveOPWallet()` — keys don't match |
| `Property 'approve' does not exist` | OP20 uses `increaseAllowance`/`decreaseAllowance`, not `approve` |
| `setTransactionDetails not found` | Call on contract instance BEFORE simulate |
| WASM execution failed | Check asconfig.json has ALL enable features, abort handler exists |
| Contract not found after deployment | Consumed all gas = reverted. Check onDeployment() complexity. |
| 2048 byte receipt limit | Use chunked reading pattern for large data |
| White page on IPFS | Set `base: './'` in vite.config.ts |
| WalletConnect modal at bottom | Add the CSS fix (see Section 2) |
| `@method()` bare — broken ABI | Always declare params: `@method({ name, type }, ...)` |
| State not persisting | Check: are you using save() after StoredArray mutations? |
| Null comparison broken in AS | AssemblyScript null checks work differently — use explicit checks |

### TypeScript Law (Non-Negotiable)

```
✗ any              — FORBIDDEN
✗ !                — FORBIDDEN (non-null assertion)
✗ @ts-ignore       — FORBIDDEN
✗ eslint-disable   — FORBIDDEN
✗ object (lowercase) — FORBIDDEN
✗ Function (uppercase) — FORBIDDEN
✗ {} empty type    — FORBIDDEN
✗ number for satoshis — FORBIDDEN (use bigint)
✗ float for financial values — FORBIDDEN
✗ Section separator comments (// ===) — FORBIDDEN
✓ bigint for satoshis, token amounts, block heights
✓ Explicit return types on all functions
✓ TSDoc for all public methods
✓ Strict null checks
✓ Interface definitions for all data shapes
```

---

*This bible was synthesized from all OPNet development documentation, guidelines, known mistakes, and real-world debugging sessions. Keep it updated as the ecosystem evolves.*
