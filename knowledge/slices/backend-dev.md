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

**Single-threaded API implementations are FORBIDDEN.** The main thread handles HTTP/WebSocket I/O only. All CPU-intensive work (contract simulation, signature verification, calldata encoding) runs in worker threads.

### Basic Worker Pool

```typescript
import { Worker, isMainThread, parentPort, workerData } from 'worker_threads';
import HyperExpress from '@btc-vision/hyper-express';
import os from 'os';

if (isMainThread) {
    const app = new HyperExpress.Server({
        max_body_length: 1024 * 1024 * 8,
        fast_abort: true,
        max_body_buffer: 1024 * 32,
        idle_timeout: 60,
        response_timeout: 120,
    });

    const workers: Worker[] = [];
    const WORKER_COUNT = Math.max(1, os.cpus().length - 1);

    for (let i = 0; i < WORKER_COUNT; i++) {
        workers.push(new Worker(__filename));
    }

    let workerIndex = 0;

    function getWorker(): Worker {
        const worker = workers[workerIndex];
        workerIndex = (workerIndex + 1) % workers.length;
        return worker;
    }

    app.post('/simulate', async (req, res) => {
        const body = await req.json();
        const worker = getWorker();
        worker.postMessage({ type: 'simulate', data: body });
        worker.once('message', (result) => {
            res.json(result);
        });
    });

    app.listen(3000);
} else {
    parentPort?.on('message', async (msg) => {
        if (msg.type === 'simulate') {
            const result = await simulateContract(msg.data);
            parentPort?.postMessage(result);
        }
    });
}
```

### Thread-Safe Service Pattern (Production)

For production backends, use a request-tracking service that maps responses back to callers:

```typescript
class SimulationService {
    private readonly workers: Worker[] = [];
    private readonly pendingRequests: Map<
        string,
        { resolve: (value: SimulationResult) => void; reject: (error: Error) => void }
    > = new Map();
    private workerIndex: number = 0;

    public constructor(workerCount: number = os.cpus().length - 1) {
        for (let i = 0; i < workerCount; i++) {
            const worker = new Worker('./simulation-worker.js');
            worker.on('message', (msg: WorkerResponse) => this.handleWorkerMessage(msg));
            worker.on('error', (err: Error) => this.handleWorkerError(err));
            this.workers.push(worker);
        }
    }

    public async simulate(request: SimulationRequest): Promise<SimulationResult> {
        const requestId = crypto.randomUUID();

        return new Promise((resolve, reject) => {
            this.pendingRequests.set(requestId, { resolve, reject });

            const worker = this.workers[this.workerIndex];
            this.workerIndex = (this.workerIndex + 1) % this.workers.length;

            worker.postMessage({ requestId, type: 'simulate', data: request });
        });
    }

    private handleWorkerMessage(msg: WorkerResponse): void {
        const pending = this.pendingRequests.get(msg.requestId);
        if (pending) {
            this.pendingRequests.delete(msg.requestId);
            if (msg.error) {
                pending.reject(new Error(msg.error));
            } else {
                pending.resolve(msg.result);
            }
        }
    }

    private handleWorkerError(error: Error): void {
        console.error('Worker error:', error.message);
    }
}
```

### What Goes in Workers vs Main Thread

| Main Thread (I/O only) | Worker Thread (CPU-bound) |
|------------------------|--------------------------|
| HTTP request handling | Contract simulation |
| WebSocket connections | Signature verification (ML-DSA) |
| MongoDB queries | Calldata encoding/decoding |
| Rate limiting | UTXO selection |
| Health checks | Transaction construction |

---

## Wallet Derivation (Backend-Specific)

Backend wallets require BOTH keypairs — the standard Taproot keypair AND the ML-DSA keypair. This is the single most common backend mistake.

### Correct Derivation Flow

```typescript
import { Mnemonic, MLDSASecurityLevel } from '@btc-vision/transaction';
import { networks, AddressTypes } from '@btc-vision/bitcoin';

// Step 1: Generate or restore mnemonic
const mnemonic = Mnemonic.generate(undefined, '', networks.bitcoin, MLDSASecurityLevel.LEVEL2);

// Step 2: Derive OPWallet-compatible wallet (MUST use deriveOPWallet, not derive)
const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);

// Step 3: Both keypairs are now available
const keypair = wallet.keypair;           // Taproot keypair (for BTC signing)
const mldsaKeypair = wallet.mldsaKeypair; // ML-DSA keypair (for quantum-resistant signing)

// Step 4: Use BOTH in sendTransaction
const receipt = await sim.sendTransaction({
    signer: keypair,           // REQUIRED
    mldsaSigner: mldsaKeypair, // REQUIRED
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### Key Storage Rules

```
NEVER: Mnemonic or private keys in source code
NEVER: Keys in config files committed to git
NEVER: Keys logged to console or error tracking
ALWAYS: Environment variables or secret managers
ALWAYS: .env in .gitignore
```

### Common Mistakes

| Mistake | Error You'll See | Fix |
|---------|-----------------|-----|
| `mnemonic.derive(0)` instead of `deriveOPWallet()` | "Invalid ML-DSA legacy signature" | Use `deriveOPWallet(AddressTypes.P2TR, 0)` |
| Missing `mldsaSigner` in sendTransaction | Transaction silently fails or reverts | Always pass both `signer` AND `mldsaSigner` |
| Using Level3 ML-DSA | Signature size too large | Use `MLDSASecurityLevel.LEVEL2` |

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

## RPC Provider Configuration (Backend-Specific)

Backend servers maintain long-lived provider connections. Configure for production reliability.

### Connection Pooling

JSONRpcProvider uses undici internally. Configure connection pooling for high throughput:

```typescript
// Standard configuration
const provider = new JSONRpcProvider({
    url: 'https://testnet.opnet.org',
    network: networks.opnetTestnet,
    timeout: 20_000,
    fetcherConfigurations: {
        keepAliveTimeout: 30_000,
        keepAliveTimeoutThreshold: 30_000,
        connections: 128,
        pipelining: 2,
    },
});

// High-throughput configuration (indexers, heavy API servers)
const highPerfProvider = new JSONRpcProvider({
    url: 'https://testnet.opnet.org',
    network: networks.opnetTestnet,
    timeout: 30_000,
    fetcherConfigurations: {
        keepAliveTimeout: 60_000,
        keepAliveTimeoutThreshold: 60_000,
        connections: 256,
        pipelining: 10,
    },
});
```

### Connection Pool Configuration Reference

| Option | Description | Default | High-Perf |
|--------|-------------|---------|-----------|
| `keepAliveTimeout` | Socket keep-alive duration | 30s | 60s |
| `keepAliveTimeoutThreshold` | Threshold before closing keep-alive | 30s | 60s |
| `connections` | Max concurrent connections per server | 128 | 256 |
| `pipelining` | Max pipelined requests per connection | 2 | 10 |

### Retry Logic with Exponential Backoff

All RPC calls from backend code MUST use retry logic. OPNet nodes can experience transient failures.

```typescript
async function withExponentialBackoff<T>(
    operation: () => Promise<T>,
    maxRetries: number = 5,
    baseDelayMs: number = 1000
): Promise<T> {
    let lastError: Error | undefined;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
        try {
            return await operation();
        } catch (error: unknown) {
            lastError = error instanceof Error ? error : new Error(String(error));
            const delay = baseDelayMs * Math.pow(2, attempt);
            console.warn(`RPC attempt ${attempt + 1} failed, waiting ${delay}ms: ${lastError.message}`);
            await new Promise((r) => setTimeout(r, delay));
        }
    }

    throw lastError;
}

// Usage with provider
const block = await withExponentialBackoff(() => provider.getBlock(height));
const balance = await withExponentialBackoff(() => provider.getBalance(address));
```

### Circuit Breaker Pattern

For long-running backend services, use a circuit breaker to prevent cascading failures when the RPC node goes down:

```typescript
class RpcCircuitBreaker {
    private failures: number = 0;
    private lastFailure: number = 0;
    private readonly threshold: number = 5;
    private readonly resetTimeMs: number = 30_000;

    public async execute<T>(operation: () => Promise<T>): Promise<T> {
        if (this.failures >= this.threshold) {
            if (Date.now() - this.lastFailure < this.resetTimeMs) {
                throw new Error('Circuit breaker open — RPC node unreachable');
            }
            this.failures = 0; // Half-open: try again after reset time
        }

        try {
            const result = await operation();
            this.failures = 0;
            return result;
        } catch (error: unknown) {
            this.failures++;
            this.lastFailure = Date.now();
            throw error;
        }
    }
}
```

---

## MongoDB Integration Patterns

MongoDB is the ONLY supported database for OPNet backend persistence. Use it for indexing blocks, transactions, UTXOs, and application-specific data.

### Schema Design for OPNet Data

```typescript
// Block index schema
interface IBlockDocument {
    readonly blockNumber: bigint;
    readonly blockHash: string;
    readonly timestamp: bigint;
    readonly transactionCount: number;
    readonly gasUsed: bigint;
    readonly indexedAt: Date;
}

// Transaction index schema
interface ITransactionDocument {
    readonly txHash: string;
    readonly blockNumber: bigint;
    readonly from: string;
    readonly to: string;
    readonly contractAddress: string;
    readonly method: string;
    readonly gasUsed: bigint;
    readonly status: 'success' | 'reverted';
    readonly indexedAt: Date;
}

// UTXO tracking schema
interface IUtxoDocument {
    readonly txid: string;
    readonly vout: number;
    readonly address: string;
    readonly value: bigint;
    readonly spent: boolean;
    readonly spentBy: string | null;
}
```

### Connection Pooling

```typescript
import { MongoClient, Db } from 'mongodb';

class DatabaseService {
    private static instance: DatabaseService;
    private client: MongoClient | null = null;
    private db: Db | null = null;

    public static getInstance(): DatabaseService {
        if (!DatabaseService.instance) {
            DatabaseService.instance = new DatabaseService();
        }
        return DatabaseService.instance;
    }

    public async connect(uri: string, dbName: string): Promise<void> {
        this.client = new MongoClient(uri, {
            maxPoolSize: 50,
            minPoolSize: 5,
            maxIdleTimeMS: 30_000,
            serverSelectionTimeoutMS: 5_000,
            connectTimeoutMS: 10_000,
        });

        await this.client.connect();
        this.db = this.client.db(dbName);

        // Create indexes on first connect
        await this.ensureIndexes();
    }

    public getDb(): Db {
        if (!this.db) {
            throw new Error('Database not connected — call connect() first');
        }
        return this.db;
    }

    private async ensureIndexes(): Promise<void> {
        const db = this.getDb();
        await db.collection('blocks').createIndex({ blockNumber: 1 }, { unique: true });
        await db.collection('transactions').createIndex({ txHash: 1 }, { unique: true });
        await db.collection('transactions').createIndex({ contractAddress: 1, blockNumber: -1 });
        await db.collection('utxos').createIndex({ address: 1, spent: 1 });
    }

    public async disconnect(): Promise<void> {
        await this.client?.close();
    }
}
```

### Important: bigint Serialization

MongoDB does not natively support JavaScript `bigint`. Use `Long` or string serialization:

```typescript
import { Long } from 'mongodb';

// Storing bigint
const doc = {
    blockNumber: Long.fromBigInt(blockNumber),
    gasUsed: gasUsed.toString(), // String for very large values
};

// Reading bigint
const stored = await collection.findOne({ txHash });
const blockNumber = BigInt(stored.blockNumber.toString());
```

---

## Structured Error Handling

Backend errors must be categorized, logged safely, and returned with consistent structure. NEVER leak private keys, mnemonics, or internal paths in error responses.

### OPNet Error Types

```typescript
import { OPNetError } from 'opnet';

async function handleRpcError(error: unknown): Promise<ErrorResponse> {
    if (error instanceof OPNetError) {
        return {
            type: 'rpc_error',
            code: error.code,
            message: error.message,
            retryable: isRetryable(error),
        };
    }

    if (error instanceof Error) {
        if (error.message.includes('timeout')) {
            return { type: 'timeout', code: 'TIMEOUT', message: 'RPC request timed out', retryable: true };
        }
        if (error.message.includes('not found')) {
            return { type: 'not_found', code: 'NOT_FOUND', message: error.message, retryable: false };
        }
    }

    return { type: 'unknown', code: 'INTERNAL', message: 'Internal server error', retryable: false };
}
```

### Structured API Response Format

```typescript
interface IApiResponse<T> {
    readonly success: boolean;
    readonly data: T | null;
    readonly error: IApiError | null;
}

interface IApiError {
    readonly code: string;
    readonly message: string;
    readonly retryable: boolean;
}

// Success response
function success<T>(data: T): IApiResponse<T> {
    return { success: true, data, error: null };
}

// Error response -- NEVER include stack traces or internal details
function fail(code: string, message: string, retryable: boolean = false): IApiResponse<never> {
    return { success: false, data: null, error: { code, message, retryable } };
}
```

### Safe Logging Rules

```
NEVER log: Private keys, mnemonics, wallet seeds, raw signatures
NEVER log: Full request bodies containing user credentials
ALWAYS log: Error codes, sanitized messages, request IDs, timestamps
ALWAYS log: RPC method names, contract addresses (public info)
```

---

## Rate Limiting Patterns

All public-facing backend endpoints MUST have rate limiting. OPNet RPC nodes also have limits — your backend must not overwhelm them.

### Per-Endpoint Rate Limiting with HyperExpress

```typescript
class EndpointRateLimiter {
    private readonly requests: Map<string, number[]> = new Map();
    private readonly maxRequests: number;
    private readonly windowMs: number;

    public constructor(maxRequests: number = 60, windowMs: number = 60_000) {
        this.maxRequests = maxRequests;
        this.windowMs = windowMs;
    }

    public isAllowed(clientIp: string): boolean {
        const now = Date.now();
        const timestamps = this.requests.get(clientIp) ?? [];

        // Remove expired entries
        const valid = timestamps.filter((t) => now - t < this.windowMs);

        if (valid.length >= this.maxRequests) {
            return false;
        }

        valid.push(now);
        this.requests.set(clientIp, valid);
        return true;
    }
}

// Middleware usage with HyperExpress
const limiter = new EndpointRateLimiter(60, 60_000); // 60 req/min

app.use((req, res, next) => {
    const ip = req.ip;
    if (!limiter.isAllowed(ip)) {
        res.status(429);
        res.json({ error: 'Rate limit exceeded', retryAfter: 60 });
        return;
    }
    next();
});
```

### RPC Request Concurrency Limiting

Limit concurrent outbound RPC requests to avoid overwhelming the OPNet node:

```typescript
import pLimit from 'p-limit';

// Max 10 concurrent RPC requests
const rpcLimit = pLimit(10);

async function batchGetBalances(addresses: string[]): Promise<Map<string, bigint>> {
    const results = new Map<string, bigint>();

    await Promise.all(
        addresses.map((addr) =>
            rpcLimit(async () => {
                const balance = await provider.getBalance(addr);
                results.set(addr, balance);
            })
        )
    );

    return results;
}
```

---

## Health Check / Monitoring Endpoints

Every OPNet backend MUST expose health check endpoints for deployment orchestration and monitoring.

### Liveness and Readiness Pattern

```typescript
app.get('/health/live', (req, res) => {
    // Liveness: is the process alive?
    res.status(200).json({ status: 'alive' });
});

app.get('/health/ready', async (req, res) => {
    // Readiness: can the service handle requests?
    const checks = {
        rpc: false,
        database: false,
        workers: false,
    };

    try {
        // Check RPC connectivity
        const blockNumber = await provider.getBlockNumber();
        checks.rpc = blockNumber > 0n;
    } catch {
        checks.rpc = false;
    }

    try {
        // Check database connectivity
        await DatabaseService.getInstance().getDb().command({ ping: 1 });
        checks.database = true;
    } catch {
        checks.database = false;
    }

    // Check worker pool
    checks.workers = workers.length > 0 && workers.every((w) => !w.threadId);

    const allReady = checks.rpc && checks.database && checks.workers;
    const status = allReady ? 200 : 503;

    res.status(status).json({ ready: allReady, checks });
});
```

### Startup Readiness Gate

Do NOT accept traffic until all subsystems are initialized:

```typescript
let isReady = false;

async function initialize(): Promise<void> {
    // 1. Connect to MongoDB
    await DatabaseService.getInstance().connect(process.env.MONGODB_URI, 'opnet-backend');

    // 2. Initialize RPC provider and verify connectivity
    const blockNumber = await provider.getBlockNumber();
    console.log(`Connected to OPNet — current block: ${blockNumber}`);

    // 3. Spawn worker pool
    for (let i = 0; i < WORKER_COUNT; i++) {
        workers.push(new Worker('./worker.js'));
    }

    // 4. Now accept traffic
    isReady = true;
}

// Gate all endpoints
app.use((req, res, next) => {
    if (!isReady && !req.path.startsWith('/health/live')) {
        res.status(503).json({ error: 'Service starting up' });
        return;
    }
    next();
});

initialize().then(() => {
    app.listen(3000);
    console.log('Backend ready on port 3000');
});
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
