# OPNet Frontend Development Reference

> **Role**: Frontend developers building React+Vite applications that interact with OPNet smart contracts
>
> **Self-contained**: All rules and patterns needed for frontend development are in this file.

---

## Architecture Context

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

- **NON-CUSTODIAL** -- Contracts NEVER hold BTC. They verify L1 tx outputs. "Verify-don't-custody."
- **Partial reverts** -- Only consensus layer execution reverts; Bitcoin transfers are ALWAYS final. BTC sent to a contract that reverts is GONE.
- **No gas token** -- Uses Bitcoin directly.
- **SHA-256, not Keccak-256** -- OPNet uses SHA-256 for all hashing and method selectors.
- **Buffer is GONE** -- The entire stack uses `Uint8Array` instead of Node.js `Buffer`.

### The Two Address Systems (Critical)

| System | Format | Used For |
|--------|--------|---------|
| Bitcoin Address | Taproot P2TR (`bc1p...`) | External identity, what you see in walletconnect |
| OPNet Address | ML-DSA public key hash (32 bytes, 0x hex) | Contract balances, internal state |

You CANNOT loop through Bitcoin addresses and transfer tokens. Contract storage uses ML-DSA addresses.

### Network Endpoints

| Network | RPC URL | `networks.*` value | Bech32 Prefix |
|---------|---------|-------------------|---------------|
| **Mainnet** | `https://mainnet.opnet.org` | `networks.bitcoin` | `bc` |
| **Testnet** | `https://testnet.opnet.org` | `networks.opnetTestnet` | `opt` |

**IMPORTANT**: ALWAYS use `networks.opnetTestnet` (NOT `networks.regtest`). The testnet is a Signet fork.

---

## Absolute Frontend Rules (Never Violate)

1. **Vite is MANDATORY** -- No webpack, no parcel, no rollup standalone.
2. **signer: null, mldsaSigner: null ALWAYS** -- The browser wallet (OP_WALLET) handles ALL signing. NEVER put private keys in frontend code.
3. **ALWAYS simulate before sendTransaction** -- Bitcoin transfers are irreversible.
4. **getContract() requires 5 params** -- `(address, abi, provider, network, senderAddress)`
5. **Address.fromString() requires 2 params** -- `(hashedMLDSAKey, publicKey)`. Never pass a raw Bitcoin address.
6. **Cache getContract instances** -- Never recreate on every render/call.
7. **Use @btc-vision/walletconnect v2 API** -- Not v1. `useWalletConnect()` is the hook.
8. **No raw PSBT** -- FORBIDDEN.
9. **No Buffer** -- Use `Uint8Array` + `BufferHelper`.
10. **No static feeRate** -- Use `provider.gasParameters()` or leave undefined.

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
| `@btc-vision/walletconnect` | `latest` |
| `eslint` | `^9.39.2` |
| `@eslint/js` | `^9.39.2` |

---

## Frontend Project Structure

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

---

## vite.config.ts -- COPY THIS EXACTLY

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
            // Browser shim for Node.js fetch -- REQUIRED for opnet
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

> `base: './'` is required for IPFS deployment (relative paths). If you use `base: '/'`, white page on IPFS.

---

## Frontend package.json

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

---

## Frontend tsconfig.json

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

---

## ESLint Config for React Frontend

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

---

## WalletConnect v2 -- Correct API

```typescript
import { useWalletConnect, SupportedWallets } from '@btc-vision/walletconnect';

const {
    isConnected,      // boolean -- check this, NOT signer
    address,          // "bc1p..." -- for display and refundTo only
    publicKey,        // "0x0203..." -- Bitcoin tweaked pubkey (33 bytes compressed)
    hashedMLDSAKey,   // "0xABCD..." -- 32-byte SHA256 hash of ML-DSA key
    mldsaPublicKey,   // "0x..." -- RAW ML-DSA pubkey (~2500 bytes) -- for signing ONLY
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

---

## getContract -- Full 5-Param Pattern

```typescript
import { getContract, IOP20Contract, OP_20_ABI, JSONRpcProvider } from 'opnet';
import { networks } from '@btc-vision/bitcoin';
import { Address } from 'opnet';

const provider = new JSONRpcProvider({ url: 'https://mainnet.opnet.org', network: networks.bitcoin });

// Build sender address from walletconnect
const { publicKey, hashedMLDSAKey } = useWalletConnect();
const senderAddress = Address.fromString(hashedMLDSAKey, publicKey);

// CORRECT -- all 5 params
const contract = getContract<IOP20Contract>(
    contractAddress,   // 1: address (op1... or 0x...)
    OP_20_ABI,         // 2: ABI
    provider,          // 3: provider
    networks.bitcoin,  // 4: network
    senderAddress,     // 5: sender address -- REQUIRED
);

// WRONG -- missing params
const contract = getContract(address, abi);                        // 2 params: BROKEN
const contract = getContract(address, abi, provider);              // 3 params: BROKEN
const contract = getContract(address, abi, provider, networks.bitcoin); // 4 params: missing sender
```

---

## Provider Singleton Pattern -- Cache It

```typescript
// WRONG -- creates a new provider on every render/call
function Component() {
    const provider = new JSONRpcProvider({ url, network }); // Bad!
}

// CORRECT -- singleton service
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

---

## Contract Cache Pattern -- Cache with setSender()

```typescript
// WRONG -- creates new contract instance every click
const handleClick = async () => {
    const contract = getContract(address, abi, provider, network, sender);  // New every time!
};

// CORRECT -- cache with setSender() for sender updates
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

---

## Transaction Pattern -- Simulate Always

```typescript
// FRONTEND pattern
const handleTransfer = async () => {
    // 1. Build simulation context
    const senderAddress = Address.fromString(hashedMLDSAKey, publicKey);
    const contract = contractService.getToken(tokenAddress, network, senderAddress);

    // 2. Simulate FIRST
    const sim = await contract.transfer(recipientPubKey, amount);
    if ('error' in sim) {
        setError(sim.error);
        return;
    }

    // 3. Send with null signers (ALWAYS on frontend)
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

---

## Dynamic feeRate -- Never Hardcode

```typescript
// WRONG -- static feeRate will overpay or underpay
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: 2,   // STATIC -- BAD
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});

// CORRECT -- leave undefined (opnet defaults) or use live rate
const gasParams = await provider.gasParameters();
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: gasParams.bitcoin.recommended.medium,  // Live rate
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

---

## Address Validation -- Always Use AddressVerificator

```typescript
import { AddressVerificator, AddressTypes } from '@btc-vision/transaction';

// WRONG -- manual prefix checks are fragile, miss P2MR, P2OP, etc.
if (address.startsWith('bc1p')) { /* P2TR */ }

// CORRECT -- use AddressVerificator
const type = AddressVerificator.detectAddressType(address, network);
const isValid = AddressVerificator.isValidAddress(address, network);
const isP2TR = AddressVerificator.isValidP2TRAddress(address, network);
const isP2MR = AddressVerificator.isValidP2MRAddress(address, network);   // quantum-resistant
const isContract = AddressVerificator.isValidP2OPAddress(address, network); // op1...
```

---

## Public Key Resolution

Bitcoin addresses (bc1p...) cannot be used directly in token operations. You need the hex public key (0x...).

```typescript
// If you only have a bc1p... address, resolve it
const info = await provider.getPublicKeyInfo('bc1p...');

if (!info || !info.publicKey) {
    // NOT FOUND -- force user to enter their public key manually
    setRequiresManualPubKey(true);
    return;
}

const pubKey = info.publicKey;  // "0x0203..."
```

**IMPORTANT**: `getPublicKeyInfo` with a contract address: use `getPublicKeyInfo(addr, true)` -- the second param `true` is required for contract addresses.

---

## metadata() -- Use Instead of Multiple Calls

```typescript
// WRONG -- 4 separate RPC calls (slow)
const name = await contract.name();
const symbol = await contract.symbol();
const decimals = await contract.decimals();
const totalSupply = await contract.totalSupply();

// CORRECT -- 1 RPC call
const metadataResult = await contract.metadata();
const { name, symbol, decimals, totalSupply } = metadataResult.properties;
```

---

## BitcoinUtils for Token Amounts

```typescript
import { BitcoinUtils } from 'opnet';

// WRONG -- raw bigint multiplication
const amount = BigInt(userInput) * 10n ** 18n;

// CORRECT -- BitcoinUtils handles decimals correctly
const amount = BitcoinUtils.expandToDecimals(userInput, tokenDecimals);

// Display (reverse)
const displayAmount = BitcoinUtils.formatUnits(amount, tokenDecimals);
```

---

## Plain BTC Transfer (Frontend)

```typescript
import { TransactionFactory } from '@btc-vision/transaction';
import { JSONRpcProvider } from 'opnet';
import { networks } from '@btc-vision/bitcoin';

const factory = new TransactionFactory();
const accounts = await window.opnet.requestAccounts();
const userAddress = accounts[0];

const utxos = await provider.utxoManager.getUTXOs({
    address: userAddress,
    optimize: false,   // ALWAYS false -- optimize: true filters UTXOs
});

const result = await factory.createBTCTransfer({
    signer: null,        // null -- OPWallet signs
    mldsaSigner: null,   // null -- OPWallet signs
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

---

## Extra Inputs/Outputs Pattern (setTransactionDetails)

Use when a contract needs to verify extra outputs during simulation:

```typescript
import { TransactionOutputFlags } from 'opnet';

// Step 1: Set BEFORE simulate
contract.setTransactionDetails({
    inputs: [],
    outputs: [{
        to: 'bc1p...recipient',
        value: 5000n,
        index: 1,   // index 0 is RESERVED -- start at 1
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

## WalletConnect CSS Fix (for modal at bottom of page)

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

## Key Imports Cheat Sheet

```typescript
import { getContract, IOP20Contract, OP_20_ABI, JSONRpcProvider, BitcoinUtils,
         Address, ABIDataTypes, TransactionOutputFlags } from 'opnet';
import { networks, Network } from '@btc-vision/bitcoin';
import { AddressVerificator, BufferHelper, MessageSigner,
         TransactionFactory } from '@btc-vision/transaction';
import { useWalletConnect, SupportedWallets } from '@btc-vision/walletconnect';
```

---

## All 19 Known Frontend Mistakes

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
// WRONG -- Address not in @btc-vision/bitcoin browser bundle
import { Address } from '@btc-vision/bitcoin'; // WILL FAIL IN BROWSER

// CORRECT
import { Address, ABIDataTypes, JSONRpcProvider } from 'opnet';
```

### 6. Passing raw Bitcoin address or 1 param to `Address.fromString()`

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
// Wrong -- bc1p... is NOT a public key
await contract.transfer(walletAddress, amount);

// Correct address format guide:
// walletAddress (bc1p/bc1q) -> ONLY for display and refundTo
// publicKey (0x hex, 33 bytes) -> Bitcoin tweaked pubkey, for Address.fromString 2nd param
// hashedMLDSAKey (0x hex, 32 bytes) -> SHA256 hash of ML-DSA key, for Address.fromString 1st param
// mldsaPublicKey (0x hex, ~2500 bytes) -> RAW ML-DSA key, for signing ONLY
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
// WRONG -- v1 API
const { connect, provider, signer } = useWalletConnect();
await connect();

// CORRECT -- v2 API
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
// WRONG -- ABSOLUTELY FORBIDDEN
import { Psbt } from '@btc-vision/bitcoin';
const psbt = new Psbt({ network });
psbt.addInput({ ... });

// CORRECT
const sim = await contract.transfer(to, amount);
const receipt = await sim.sendTransaction({ signer: null, mldsaSigner: null, ... });
```

### 12. Using @btc-vision/transaction directly for contract calls

```typescript
// WRONG -- TransactionFactory is NOT for contract calls
const factory = new TransactionFactory();
const tx = await factory.signInteraction({ contract, calldata, ... });

// CORRECT
const contract = getContract(address, abi, provider, network, sender);
const sim = await contract.transfer(to, amount);
const receipt = await sim.sendTransaction({ ... });
```

### 13. Passing signer on frontend / omitting signer on backend

```typescript
// WRONG -- Frontend with signer (LEAKS PRIVATE KEYS)
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,           // NEVER on frontend
    mldsaSigner: wallet.mldsaKeypair, // NEVER on frontend
    ...
});

// CORRECT -- Frontend (signer always null)
const receipt = await sim.sendTransaction({
    signer: null,
    mldsaSigner: null,
    refundTo: address,
    maximumAllowedSatToSpend: 10000n,
    network,
});
```

### 14. Skipping `setTransactionDetails` for payable functions with extra outputs

```typescript
// WRONG -- extra outputs without telling contract during simulation
const sim = await contract.somePayableMethod(args);
const receipt = await sim.sendTransaction({
    extraOutputs: [{ address: 'bc1p...', value: 5000 }], // Contract didn't see this!
});

// CORRECT -- set BEFORE simulate
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
// WRONG -- getContract is for contract calls, NOT BTC transfers
const contract = getContract(address, abi, provider, network, sender);
const sim = await contract.transfer(recipient, amount); // This is OP20, not BTC!

// CORRECT -- TransactionFactory for BTC transfers
import { TransactionFactory } from '@btc-vision/transaction';
const factory = new TransactionFactory();
const result = await factory.createBTCTransfer({
    signer: null, mldsaSigner: null,
    network, utxos, from: userAddress,
    to: 'bc1p...recipient', feeRate: 10, amount: 50000n,
});
await provider.sendRawTransaction(result.tx, false);
```

### 16. Raw bigint multiplication for token amounts

```typescript
// WRONG -- breaks with fractional amounts
const amount = BigInt(userInput) * 10n ** 18n;

// CORRECT
import { BitcoinUtils } from 'opnet';
const amount = BitcoinUtils.expandToDecimals(userInput, tokenDecimals);
const display = BitcoinUtils.formatUnits(amount, tokenDecimals);
```

### 17. Creating `getContract` inside event handlers (no caching)

```typescript
// WRONG -- new instance every click
const handleApprove = async () => {
    const contract = getContract(address, abi, provider, network, sender); // NEW every time!
};

// CORRECT -- cache and use setSender()
const cachedContract = getContract<IOP20Contract>(address, OP_20_ABI, provider, network, sender);
// Later in handler:
cachedContract.setSender(currentSender);
const sim = await cachedContract.increaseAllowance(spender, amount);
```

### 18. Static `feeRate` that will break on mainnet

```typescript
// WRONG -- hardcoded rate
await sim.sendTransaction({ signer: null, mldsaSigner: null, feeRate: 2, ... });

// CORRECT -- dynamic or undefined
const gasParams = await provider.gasParameters();
await sim.sendTransaction({
    signer: null, mldsaSigner: null,
    feeRate: gasParams.bitcoin.recommended.medium, // or just omit for default
    ...
});
```

### 19. Using `getPublicKeyInfo` RPC call when you have the 0x address

```typescript
// AVOIDABLE -- makes RPC call to resolve opr1 -> Address
const idoAddress = await provider.getPublicKeyInfo(CONTRACTS.BLOCK_IDO_OPR1, true);
const sim = await motoContract.increaseAllowance(idoAddress, amount);

// BETTER -- store and use 0x hex address directly
import { Address } from 'opnet';
const spenderAddress = Address.fromString(CONTRACTS.BLOCK_IDO_0X);
// Address.fromString with 1 param works for contract addresses (they are public key hashes)
const sim = await motoContract.increaseAllowance(spenderAddress, amount);
```

---

## Common Runtime Errors (Compilation Passes, Runtime Breaks)

These errors are invisible to `lint`, `typecheck`, and `build` — they only appear when the frontend runs in a browser. Learn them to avoid wasting fix cycles.

### RT-1: Missing Node.js Polyfills (White Page)
```
Uncaught ReferenceError: Buffer is not defined
Uncaught ReferenceError: process is not defined
Uncaught ReferenceError: global is not defined
```
**Cause:** OPNet packages depend on Node.js globals. Vite doesn't polyfill them by default.
**Prevention:** Use the exact `vite.config.ts` from this knowledge slice. The `vite-plugin-node-polyfills` plugin with `Buffer: true, global: true, process: true` is mandatory. Never remove or modify the polyfills config.

### RT-2: undici / fetch Shim Missing (RPC Calls Fail)
```
TypeError: Cannot read properties of undefined (reading 'Request')
Error: fetch is not defined
```
**Cause:** `opnet` uses Node.js `undici` for HTTP. In browser, it needs a shim.
**Prevention:** Add `undici: resolve(__dirname, 'node_modules/opnet/src/fetch/fetch-browser.js')` to `resolve.alias` in vite.config.ts. This is in the standard config — do not remove it.

### RT-3: Duplicate Package Instances (Subtle Crypto Failures)
```
Error: Invalid point on curve
Error: Expected Uint8Array of length 32
```
**Cause:** Multiple versions of `@noble/curves` or `@noble/hashes` loaded. Signing produces wrong output.
**Prevention:** Add `dedupe: ['@noble/curves', '@noble/hashes', '@scure/base']` to `resolve` in vite.config.ts. Add `"overrides": {"@noble/hashes": "2.0.1"}` to package.json.

### RT-4: CORS Errors on RPC (Blocked by Browser)
```
Access to fetch has been blocked by CORS policy
```
**Cause:** Direct RPC calls from browser to a node that doesn't set CORS headers.
**Prevention:** Use the official OPNet RPC URLs (`https://testnet.opnet.org`, `https://mainnet.opnet.org`) — they have CORS configured. Never use custom/local RPC URLs without a proxy.

### RT-5: React Hydration Mismatch (SSR or Strict Mode)
```
Warning: Text content did not match. Server: "..." Client: "..."
Uncaught Error: Hydration failed
```
**Cause:** Server-rendered HTML differs from client render. Common with wallet state (connected/disconnected) or dynamic values.
**Prevention:** For wallet-dependent UI, render a loading/skeleton state initially and update after `useEffect`. Never render wallet-specific content during initial render. Wrap dynamic content in `{typeof window !== 'undefined' && ...}` if needed.

### RT-6: BigInt Serialization Error (JSON.stringify fails)
```
TypeError: Do not know how to serialize a BigInt
```
**Cause:** `JSON.stringify()` cannot handle `bigint` values. Common when logging contract call results.
**Prevention:** Never pass raw contract results to `JSON.stringify()`. Convert bigint to string first: `value.toString()`. Or use a replacer: `JSON.stringify(obj, (_, v) => typeof v === 'bigint' ? v.toString() : v)`.

### RT-7: WalletConnect Modal Renders at Page Bottom (Not Centered)
```
[Visual bug — WC modal appears below page fold instead of centered overlay]
```
**Cause:** Default WalletConnect CSS doesn't work well with all layouts.
**Prevention:** Add the `wcm-modal` CSS fix from this knowledge slice (position: fixed, z-index: 9999, flex centering). Include it in your global CSS file.

### RT-8: Vite Dev Server Crashes on Node.js Module Import
```
[vite] Internal server error: Failed to resolve import "node:crypto"
[vite] Internal server error: "worker_threads" is not exported by "..."
```
**Cause:** OPNet packages import Node.js-only modules that Vite can't resolve.
**Prevention:** Add these to `build.rollupOptions.external`: `['worker_threads', 'node:sqlite', 'node:diagnostics_channel', 'node:async_hooks', 'node:perf_hooks', 'node:worker_threads']`. Also add `exclude: ['@btc-vision/transaction', 'crypto-browserify']` to `optimizeDeps`.

### RT-9: CSS Custom Properties Undefined (Variables Render as Empty)
```
[Visual bug — colors missing, transparent backgrounds, invisible text]
```
**Cause:** CSS custom properties referenced in components but never defined in `:root`.
**Prevention:** Always define all `--color-*`, `--spacing-*`, `--radius-*` variables in `:root` in your main CSS file BEFORE using them in components. Test by inspecting computed styles in DevTools.

### RT-10: Wallet Connect But No Contract Interaction (Silent Failure)
```
[Functional bug — wallet connects but contract calls return undefined/null]
```
**Cause:** `getContract()` called with wrong params (missing sender, wrong network, wrong ABI format).
**Prevention:** Always use all 5 params. Always build sender with `Address.fromString(hashedMLDSAKey, publicKey)` from WalletConnect. Always use `networks.opnetTestnet` (not `networks.testnet`). Always merge your ABI with `OP_NET_ABI` or `OP_20_ABI`.

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
