# OPNet Troubleshooting Guide

Common errors, their exact causes, and copy-paste fixes.

---

## Deployment Errors

### "Constructor gas limit exceeded" / Deployment reverts consuming ALL gas

**Symptom**: Transaction is sent, costs gas, but the contract address doesn't appear. RPC returns success but contract not found.

**Cause**: The OPNet protocol hardcodes a **20M gas limit** for the deployment (constructor) call. If your `onDeployment()` exceeds this, the entire deployment reverts — consuming all gas.

**Fix**:
1. Move complex initialization OUT of `onDeployment()` into separate admin methods called post-deployment
2. Remove any cross-contract calls from `onDeployment()`
3. Simplify minting/state initialization
4. Ensure correct calldata encoding matches expected types

```typescript
// WRONG — too much in onDeployment
public override onDeployment(calldata: Calldata): void {
    this._mint(Blockchain.tx.sender, HUGE_SUPPLY);
    this.callOtherContract();    // Cross-contract call — expensive!
    for (let i = 0; i < 1000; i++) {  // Loop — gas killer!
        this.state.set(...);
    }
}

// CORRECT — keep it minimal
public override onDeployment(calldata: Calldata): void {
    // Read minimal calldata
    const initialOwner = calldata.readAddress();
    this.owner.set(initialOwner);
    // That's it. Save complex setup for a separate init() call.
}
```

---

### "Cannot find module @btc-vision/btc-runtime" / "Cannot find module assemblyscript"

**Cause**: Both `assemblyscript` (upstream) and `@btc-vision/assemblyscript` (fork) are installed, causing conflicts. OR only upstream `assemblyscript` is installed.

**Fix**:
```bash
npm uninstall assemblyscript
npx npm-check-updates -u && npm i @btc-vision/btc-runtime@rc @btc-vision/as-bignum@latest @btc-vision/assemblyscript @btc-vision/opnet-transform@latest @assemblyscript/loader@latest --prefer-online
```

The custom fork `@btc-vision/assemblyscript` is REQUIRED. The upstream package does not support closures needed by btc-runtime.

---

### "Transaction reverted consuming all gas" (runtime, not deployment)

**Cause** (check in this order):
1. **Cross-contract calls in `onDeployment()`** — remove them
2. **Calldata encoding mismatch** — the deployed ABI expects different params than what was sent
3. **Insufficient gas limit** — increase `gasLimit` on the transaction
4. **Missing WASM features** — check `asconfig.json` has all `enable` entries

**Diagnostic**:
```bash
# Check if WASM compiles correctly
asc --config asconfig.json --target my-contract 2>&1

# Verify WASM exists and has content
ls -la build/
wasm-objdump -x build/MyContract.wasm | head -50  # if wasm-tools available
```

---

### WASM compilation produces 0 bytes / WASM execution failed

**Cause**: Incorrect `asconfig.json` — missing feature flags, wrong settings.

**Fix**: Your `asconfig.json` options MUST include ALL of these:
```json
{
    "options": {
        "enable": [
            "sign-extension",
            "mutable-globals",
            "nontrapping-f2i",
            "bulk-memory",
            "simd",
            "reference-types",
            "multi-value"
        ],
        "noAssert": false,
        "shrinkLevel": 1,
        "memoryBase": 0,
        "initialMemory": 1,
        "runtime": "stub",
        "exportStart": "start",
        "transform": "@btc-vision/opnet-transform"
    }
}
```

Missing ANY of the `enable` features = runtime trap = burns all gas.

---

## Runtime Errors

### "Buffer is not defined" / "Cannot find name 'Buffer'" / "Buffer.from is not a function"

**Cause**: Buffer has been completely removed from the OPNet stack.

**Fix**:
```typescript
import { BufferHelper } from '@btc-vision/transaction';

// Replace all Buffer.from(hex, 'hex') with:
const data: Uint8Array = BufferHelper.fromHex(hexString);

// Replace all Buffer.from(bytes).toString('hex') with:
const hex: string = BufferHelper.toHex(bytes);

// Replace Buffer.from(str) with:
const bytes: Uint8Array = new TextEncoder().encode(str);

// Replace Buffer.from(str).toString('utf8') reverse:
const str: string = new TextDecoder().decode(bytes);
```

---

### "getPublicKeyInfo returned undefined" / "Public key not found"

**Cause**: The address hasn't made any transactions on-chain yet (no public key registered in OPNet state).

**Fix**:
```typescript
// For wallet addresses that haven't transacted:
const info = await provider.getPublicKeyInfo(address);
if (!info || !info.publicKey) {
    // Force user to enter their public key manually
    setRequiresManualInput(true);
    return;
}

// For CONTRACT addresses (second param `true` is required):
const info = await provider.getPublicKeyInfo(contractAddress, true);
```

---

### "signInteraction is not a function" / "TransactionFactory.signInteraction is not a function"

**Cause**: Using `@btc-vision/transaction`'s `TransactionFactory` directly for contract calls. It is ONLY for deployments and BTC transfers.

**Fix**:
```typescript
// WRONG — TransactionFactory is not for contract calls
import { TransactionFactory } from '@btc-vision/transaction';
const factory = new TransactionFactory();
await factory.signInteraction(...); // This doesn't exist for contract calls

// CORRECT — use getContract from opnet
import { getContract, IOP20Contract, OP_20_ABI } from 'opnet';
const contract = getContract<IOP20Contract>(address, OP_20_ABI, provider, network, sender);
const sim = await contract.transfer(to, amount);
const receipt = await sim.sendTransaction({ signer: null, mldsaSigner: null, ... });
```

---

### "Invalid ML-DSA legacy signature" / "Signature verification failed"

**Cause**: Using `mnemonic.derive()` instead of `mnemonic.deriveOPWallet()`. These use different derivation paths — the ML-DSA keypair will be different, so signatures won't verify against the registered address.

**Fix**:
```typescript
import { Mnemonic, MLDSASecurityLevel } from '@btc-vision/transaction';
import { networks, AddressTypes } from '@btc-vision/bitcoin';

const mnemonic = Mnemonic.generate(undefined, '', networks.bitcoin, MLDSASecurityLevel.LEVEL2);

// CORRECT — OPWallet-compatible derivation
const wallet = mnemonic.deriveOPWallet(AddressTypes.P2TR, 0);

// WRONG — different derivation path
const wallet = mnemonic.derive(0);
```

---

### "Property 'approve' does not exist" / "contract.approve is not a function"

**Cause**: OP20 does NOT have `approve()`. It uses `increaseAllowance`/`decreaseAllowance` to prevent the well-known approve race condition.

**Fix**:
```typescript
// WRONG
await contract.approve(spender, amount);

// CORRECT
await contract.increaseAllowance(spender, amount);
await contract.decreaseAllowance(spender, amount);
```

---

### "setTransactionDetails not found" / "contract.setTransactionDetails is not a function"

**Cause**: Calling `setTransactionDetails` in the wrong place, or on an uncached contract instance.

**Fix**: Call `setTransactionDetails` on the contract INSTANCE, BEFORE simulate, EVERY time:
```typescript
import { TransactionOutputFlags } from 'opnet';

// Must be called on the contract object, before simulate
contract.setTransactionDetails({
    inputs: [],
    outputs: [{
        to: 'bc1p...recipient',
        value: 5000n,
        index: 1,  // 0 is RESERVED
        flags: TransactionOutputFlags.hasTo,
    }],
});

// Simulate immediately after
const sim = await contract.somePayableMethod(args);
```

Note: `setTransactionDetails()` clears after each call. Set it right before EVERY simulate that needs it.

---

### Deployment works but contract not found

**Cause**: The deployment transaction was accepted by the network but the contract execution consumed all gas = reverted. The deployment tx is on-chain but the contract state was not written.

**Diagnosis**:
```typescript
// Check if the transaction was actually successful
const tx = await provider.getTransaction(txId);
console.log('status:', tx.status); // Look for gas consumption
```

**Fix**: See "Constructor gas limit exceeded" section above.

---

### "2048 byte receipt limit" / Receipt too large

**Cause**: OPNet limits receipts to 2048 bytes. Contracts that try to return large amounts of data hit this limit.

**Fix**: Use chunked reading pattern:
```typescript
// Contract side — paginate responses
@method({ name: 'offset', type: ABIDataTypes.UINT32 }, { name: 'limit', type: ABIDataTypes.UINT32 })
@returns({ name: 'items', type: ABIDataTypes.ARRAY })
public getItems(calldata: Calldata): BytesWriter {
    const offset = calldata.readU32();
    const limit = calldata.readU32();
    // Return only items[offset..offset+limit]
}

// Client side — multiple calls
const PAGE_SIZE = 10;
let offset = 0;
let allItems: Item[] = [];

while (true) {
    const result = await contract.getItems(offset, PAGE_SIZE);
    const items = result.properties.items;
    allItems = [...allItems, ...items];
    if (items.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
}
```

---

## Frontend Errors

### White page on IPFS

**Cause**: `base: '/'` in vite.config.ts — absolute paths don't work on IPFS.

**Fix**: Set `base: './'` in vite.config.ts:
```typescript
export default defineConfig({
    base: './',   // REQUIRED for IPFS
    // ...
});
```

---

### WalletConnect modal at bottom of page

**Cause**: Default CSS positioning of `wcm-modal` renders at document bottom.

**Fix**: Add to your global CSS:
```css
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

### "Address.fromString() crashes" / "Invalid address" on Address.fromString

**Cause**: Passing a bech32 address (`bc1q...`/`bc1p...`) or only one parameter. `Address.fromString()` requires TWO hex pubkey parameters.

**Fix**:
```typescript
import { useWalletConnect } from '@btc-vision/walletconnect';
import { Address } from 'opnet';

const { publicKey, hashedMLDSAKey } = useWalletConnect();
// publicKey = "0x0203..." (33-byte compressed Bitcoin tweaked pubkey)
// hashedMLDSAKey = "0xABCD..." (32-byte SHA256 hash of ML-DSA key)

// CORRECT — 2 params, both hex
const sender = Address.fromString(hashedMLDSAKey, publicKey);

// WRONG variants:
// Address.fromString('bc1p...')                   — bc1p address, not a pubkey
// Address.fromString(publicKey)                   — missing second param
// Address.fromString(mldsaPublicKey, publicKey)   — mldsaPublicKey is RAW (~2500 bytes), need HASH
```

---

### "Wallet not connected" even when wallet IS connected

**Cause**: Gating on `signer` object which starts as `null` on frontend.

**Fix**:
```typescript
// WRONG — signer is null on frontend
if (!signer) throw new Error('Wallet not connected');

// CORRECT — check isConnected and address
const { isConnected, address } = useWalletConnect();
if (!isConnected || !address) throw new Error('Wallet not connected');
```

---

### Crypto operations fail / "crypto.subtle is not available"

**Cause**: Missing `crypto-browserify` override in Vite config.

**Fix**: Ensure vite.config.ts includes:
```typescript
nodePolyfills({
    globals: {
        Buffer: true,
        global: true,
        process: true
    },
    overrides: {
        crypto: 'crypto-browserify'  // REQUIRED
    }
}),
```

AND:
```typescript
resolve: {
    alias: {
        global: 'global',
        undici: resolve(__dirname, 'node_modules/opnet/src/fetch/fetch-browser.js')
    },
    dedupe: ['@noble/curves', '@noble/hashes', '@scure/base', 'buffer', 'react', 'react-dom']
},
optimizeDeps: {
    exclude: ['crypto-browserify']  // Cannot be pre-bundled (circular deps)
}
```

---

### "import { Address } from '@btc-vision/bitcoin'" fails in browser

**Cause**: `Address` is not in the browser bundle of `@btc-vision/bitcoin`.

**Fix**:
```typescript
// WRONG
import { Address } from '@btc-vision/bitcoin';

// CORRECT
import { Address, ABIDataTypes, JSONRpcProvider } from 'opnet';
```

---

### Simulation succeeds but sendTransaction fails

**Cause**: Simulation doesn't check BTC availability. Actual send needs funded UTXOs.

**Fix**: Ensure sender has sufficient BTC UTXOs:
```typescript
const utxos = await provider.utxoManager.getUTXOs({
    address: userAddress,
    optimize: false,  // ALWAYS false
});
console.log('Available UTXOs:', utxos.length);
// If empty/insufficient, user needs to fund their wallet
```

---

## Contract Interaction Errors

### `increaseAllowance` not found / `approve` doesn't work

```typescript
// WRONG — approve doesn't exist on OP20
await contract.approve(spender, amount);

// CORRECT
await contract.increaseAllowance(spender, amount);
```

---

### Contract deploy calldata is 0 bytes (regtest)

**Cause**: Known regtest node bug — node passes 0 bytes to `onDeploy()`.

**Workaround**: Don't rely on constructor calldata in `onDeployment()` on regtest. Use a separate `initialize()` method call post-deployment.

---

### getContract returns undefined / wrong contract

**Cause**: Missing parameters. `getContract` requires exactly 5 params.

**Fix**:
```typescript
const contract = getContract<IMyContract>(
    address,          // 1: contract address
    MY_ABI,           // 2: ABI array
    provider,         // 3: provider instance
    networks.bitcoin, // 4: network — REQUIRED
    senderAddress,    // 5: sender — REQUIRED
);
```

---

### `contract.name()` / `contract.symbol()` not found in tests

**Cause**: The unit-test-framework's built-in `OP20` class does NOT have `name()` or `symbol()` as direct methods.

**Fix**:
```typescript
// WRONG — in tests
const name = await token.name();
const symbol = await token.symbol();

// CORRECT — in tests
const { metadata } = await token.metadata();
const name = metadata.name;
const symbol = metadata.symbol;
```

---

## AssemblyScript Fork Issues

### "Duplicate asc binary" / Build conflicts

```bash
# Check what's installed
npm list assemblyscript
npm list @btc-vision/assemblyscript

# Fix: uninstall upstream, keep fork
npm uninstall assemblyscript
npm i @btc-vision/assemblyscript@^0.29.2
```

### "Closures are not supported"

**Cause**: Using upstream `assemblyscript` instead of the custom fork.

**Fix**: Same as above — uninstall upstream, install `@btc-vision/assemblyscript`.

---

## WalletConnect v2 Issues

### "openConnectModal is not a function" / "connectToWallet undefined"

**Cause**: Using old WalletConnect v1 API.

**Fix**: Update `@btc-vision/walletconnect` to latest and use v2 API:
```typescript
// OLD v1
const { connect, provider, signer } = useWalletConnect();
await connect();

// NEW v2
const { connectToWallet, isConnected, address } = useWalletConnect();
await connectToWallet(SupportedWallets.OP_WALLET);
```

---

## Unit Test Issues

### "Cannot find module '@btc-vision/unit-test-framework'" or wrong version

**Fix**:
```bash
rm -rf node_modules package-lock.json
npm uninstall assemblyscript 2>/dev/null
npx npm-check-updates -u && npm i @btc-vision/bitcoin@rc @btc-vision/bip32@latest @btc-vision/ecpair@latest @btc-vision/transaction@rc opnet@rc @btc-vision/op-vm@rc @btc-vision/unit-test-framework@beta --prefer-online
```

### "Cannot use import statement outside a module"

```bash
# WRONG
npx ts-node tests/MyContract.test.ts

# CORRECT — must use --esm flag
npx ts-node --esm tests/MyContract.test.ts
```

### Blockchain.setSender() not found

```typescript
// WRONG — method doesn't exist
Blockchain.setSender(userAddress);

// CORRECT — use property setter
Blockchain.msgSender = userAddress;
```

---

## General Tips

```
✓ Always use optimize: false in getUTXOs() — optimize: true filters UTXOs
✓ Never use number for satoshi amounts — always bigint
✓ Never use while loops in contracts — bounded for loops only
✓ Always simulate before sending — never skip
✓ Check guidelines/setup-guidelines.md for package versions — never guess
✓ Never use Buffer — Uint8Array everywhere (Buffer is removed from the stack)
✓ Always npm uninstall assemblyscript before installing @btc-vision/assemblyscript
✓ Use MongoDB for backend persistence, not file-based storage
✓ Use @btc-vision/hyper-express for backends, never Express/Fastify/Koa
✓ Use block.number for time logic, never medianTimestamp
✓ Use increaseAllowance/decreaseAllowance, never approve
✓ Use Blockchain.verifySignature, never the deprecated ECDSA/Schnorr methods
```
