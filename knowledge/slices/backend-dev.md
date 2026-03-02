# OPNet Backend Development Reference

> **Role**: Backend developers building server-side services that interact with OPNet smart contracts
>
> **Self-contained**: All rules and patterns needed for backend development are in this file.

---

## Architecture Context

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

- **NON-CUSTODIAL** -- Contracts NEVER hold BTC. They verify L1 tx outputs. "Verify-don't-custody."
- **Partial reverts** -- Only consensus layer execution reverts; Bitcoin transfers are ALWAYS final. BTC sent to a contract that reverts is GONE.
- **No gas token** -- Uses Bitcoin directly.
- **SHA-256, not Keccak-256** -- OPNet uses SHA-256 for all hashing and method selectors.
- **Buffer is GONE** -- The entire stack uses `Uint8Array` instead of Node.js `Buffer`.
- **ML-DSA only** -- ECDSA/Schnorr are deprecated. Use `Blockchain.verifySignature()`.

### Network Endpoints

| Network | RPC URL | `networks.*` value |
|---------|---------|-------------------|
| **Mainnet** | `https://mainnet.opnet.org` | `networks.bitcoin` |
| **Testnet** | `https://testnet.opnet.org` | `networks.opnetTestnet` |

---

## Package Installation

```bash
rm -rf node_modules package-lock.json
npx npm-check-updates -u && npm i @btc-vision/bitcoin@rc @btc-vision/bip32@latest @btc-vision/ecpair@latest @btc-vision/transaction@rc opnet@rc --prefer-online
npm i -D eslint@^10.0.0 @eslint/js@^10.0.1 typescript-eslint@^8.56.0
```

### Package Version Reference

| Package | Version Tag |
|---------|------------|
| `@btc-vision/bitcoin` | `@rc` |
| `@btc-vision/transaction` | `@rc` |
| `opnet` | `@rc` |
| `@btc-vision/bip32` | `latest` |
| `@btc-vision/ecpair` | `latest` |
| `@btc-vision/hyper-express` | `latest` |
| `@btc-vision/uwebsocket.js` | `latest` |
| `eslint` | `^9.39.2` |
| `@eslint/js` | `^9.39.2` |

---

## Backend package.json

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

---

## ESLint Config for Backend

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

---

## Required Frameworks

| Use | Never Use |
|-----|-----------|
| `@btc-vision/hyper-express` | Express, Fastify, Koa, Hapi |
| `@btc-vision/uwebsocket.js` | Socket.io, ws |
| MongoDB | SQLite, PostgreSQL (for OPNet indexing) |
| Worker threads | Single-threaded implementations |

---

## HyperExpress Server Pattern

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

---

## Backend Transaction Pattern

On the backend, you MUST specify both signers. This is the opposite of the frontend pattern.

```typescript
// BACKEND -- MUST specify both signers
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,           // REQUIRED on backend
    mldsaSigner: wallet.mldsaKeypair, // REQUIRED on backend
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### Signer Rules Summary

```
FRONTEND: signer: null, mldsaSigner: null        (wallet handles signing)
BACKEND:  signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair  (server signs)
```

There are NO exceptions. Mixing these up = private key leak or broken transaction.

---

## Provider + Contract Management (Server-Side)

```typescript
import { JSONRpcProvider, getContract, IOP20Contract, OP_20_ABI } from 'opnet';
import { networks } from '@btc-vision/bitcoin';

// Provider singleton -- same pattern as frontend
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

// Contract caching -- same setSender() pattern
class ContractService {
    private readonly cache = new Map<string, IOP20Contract>();

    public getToken(address: string, network: Network, sender: Address): IOP20Contract {
        if (!this.cache.has(address)) {
            const provider = ProviderService.getInstance().getProvider(network);
            const contract = getContract<IOP20Contract>(address, OP_20_ABI, provider, network, sender);
            this.cache.set(address, contract);
        }
        const cached = this.cache.get(address)!;
        cached.setSender(sender);
        return cached;
    }
}
```

---

## Threading Pattern (Mandatory)

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

---

## Wallet Derivation -- Use deriveOPWallet()

```typescript
import { Mnemonic, MLDSASecurityLevel } from '@btc-vision/transaction';
import { networks, AddressTypes } from '@btc-vision/bitcoin';

const mnemonic = Mnemonic.generate(undefined, '', networks.bitcoin, MLDSASecurityLevel.LEVEL2);

// CORRECT -- OPWallet-compatible derivation
const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);

// WRONG -- uses different derivation path, keys won't match OPWallet
const wallet = mnemonic.derive(0);
```

---

## Client-Side Signing -- Always Use Auto Methods

```typescript
import { MessageSigner } from '@btc-vision/transaction';

// AUTO methods detect browser (OP_WALLET) vs backend (local keypair) automatically

// Schnorr (works in both environments)
const signed = await MessageSigner.signMessageAuto(message, keypair);     // Backend: local

// Taproot-tweaked Schnorr
const signed = await MessageSigner.tweakAndSignMessageAuto(message, keypair, network); // Backend

// ML-DSA (quantum-resistant)
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

## Backend Error Handling

```typescript
// Wrap all RPC/contract interactions
async function safeContractCall<T>(fn: () => Promise<T>): Promise<T | null> {
    try {
        return await fn();
    } catch (error: unknown) {
        if (error instanceof Error) {
            console.error(`Contract call failed: ${error.message}`);
        }
        return null;
    }
}

// Always check simulation results before sending
const sim = await contract.transfer(to, amount);
if ('error' in sim) {
    console.error('Simulation failed:', sim.error);
    return; // DO NOT proceed to sendTransaction
}
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

## Key Imports Cheat Sheet

```typescript
import { JSONRpcProvider, getContract, IOP20Contract, OP_20_ABI } from 'opnet';
import { networks } from '@btc-vision/bitcoin';
import { AddressVerificator, BufferHelper, MessageSigner, Mnemonic,
         MLDSASecurityLevel } from '@btc-vision/transaction';
import HyperExpress from '@btc-vision/hyper-express';
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
