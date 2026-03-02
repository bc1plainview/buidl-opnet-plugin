# OPNet Integration Review Reference

> **Role**: Reviewers verifying cross-layer integration between contracts, frontends, and backends
>
> **Self-contained**: All integration patterns, consistency requirements, and known failure modes are in this file.

---

## Overview

OPNet applications span three layers: smart contracts (AssemblyScript/WASM), frontends (React+Vite), and backends (hyper-express). Each layer has its own address formats, encoding patterns, and configuration. Integration bugs happen when these layers disagree.

This document covers the critical connection points and the known ways they fail.

---

## Contract ABI to Frontend getContract() Connection

The contract defines methods with `@method()` decorators. The frontend accesses those methods via `getContract()` with an ABI.

### How It Connects

1. **Contract side**: `@method({ name: 'to', type: ABIDataTypes.ADDRESS }, { name: 'amount', type: ABIDataTypes.UINT256 })`
2. **ABI definition**: The ABI must declare the same method name with matching parameter types
3. **Frontend side**: `const contract = getContract<IMyContract>(address, myABI, provider, network, sender)`
4. **Frontend call**: `await contract.transfer(recipientAddress, amount)` -- parameter order and types must match

### Common Failure: ABI Mismatch

```
SYMPTOM: contract.transfer() returns simulation error or unexpected behavior
ROOT CAUSE: ABI declared in frontend doesn't match contract's @method() decorators
FIX: Verify that every @method() parameter name, type, and order exactly matches the ABI definition
```

### Common Failure: Bare @method()

```
SYMPTOM: getContract() can't find method, or method requires manual calldata
ROOT CAUSE: Contract uses @method() with no params -- zero ABI inputs declared
FIX: Contract must declare ALL params: @method({ name: 'to', type: ABIDataTypes.ADDRESS }, ...)
     This requires redeployment to fix.
```

---

## Selector Encoding Consistency

OPNet uses SHA-256 (not Keccak-256) for method selectors. The selector must be computed identically in contracts and frontends/tests.

### Contract Side (AssemblyScript)

```typescript
const selector: Selector = encodeSelector('transfer(address,uint256)');
```

### Test Side (TypeScript)

```typescript
private getSelector(signature: string): number {
    return Number(`0x${this.abiCoder.encodeSelector(signature)}`);
}
```

### Common Failure: Selector Mismatch

```
SYMPTOM: Contract receives wrong method call, or callMethod falls through to super (unknown selector)
ROOT CAUSE: Method signature string doesn't match between contract and caller
FIX:
  - Use the FULL method signature with param types: 'transfer(address,uint256)'
  - NOT just the method name: 'transfer'
  - NOT with param names: 'transfer(address to, uint256 amount)'
  - Param types must match ABIDataTypes exactly:
    ABIDataTypes.ADDRESS -> 'address'
    ABIDataTypes.UINT256 -> 'uint256'
    ABIDataTypes.BOOL -> 'bool'
    ABIDataTypes.BYTES32 -> 'bytes32'
    ABIDataTypes.TUPLE -> use component types
```

---

## Address Format Consistency Across Layers

OPNet has two address systems. Using the wrong format in the wrong place is the most common integration failure.

### Address Format Quick Reference

| Format | Where Used | Example |
|--------|-----------|---------|
| Bitcoin address (`bc1p...`) | WalletConnect display, refundTo param, explorer links | `bc1pxyz...` |
| Hashed ML-DSA key (0x, 32 bytes) | First param of Address.fromString | `0xABCD...` (32 bytes) |
| Bitcoin tweaked pubkey (0x, 33 bytes) | Second param of Address.fromString | `0x0203...` (33 bytes) |
| Raw ML-DSA pubkey (0x, ~2500 bytes) | Signing operations ONLY | `0x...` (~2500 bytes) |
| Contract address (`op1...`) | Contract deployment output, getContract first param | `op1abc...` |
| Contract address (0x hex) | Internal state, storage keys | `0x1234...` |

### Address.fromString -- The TWO-Param Rule

```typescript
// For USER addresses (wallets):
const sender = Address.fromString(hashedMLDSAKey, publicKey);
//                                  ^^^              ^^^
//                                  32-byte hash     33-byte tweaked pubkey

// For CONTRACT addresses (already public key hashes):
const contractAddr = Address.fromString(contractHexAddress);
// 1 param works because contract addresses ARE the hash
```

### Common Failure: Address.fromString with Wrong Params

```
SYMPTOM: Wrong address constructed, tokens sent to nonexistent address, balance shows zero
ROOT CAUSE (1): Passing bc1p... to Address.fromString -- Bech32 is NOT a pubkey
ROOT CAUSE (2): Passing only publicKey (1 param) -- missing hashedMLDSAKey
ROOT CAUSE (3): Passing raw mldsaPublicKey (~2500 bytes) instead of hashedMLDSAKey (32 bytes)
FIX: Always use both params from walletconnect: Address.fromString(hashedMLDSAKey, publicKey)
```

### Common Failure: Using bc1p... for Token Operations

```
SYMPTOM: Transfer fails or sends to wrong address
ROOT CAUSE: Passing Bitcoin address (bc1p...) to contract method that expects OPNet address
FIX: Bitcoin addresses are for display and refundTo ONLY. Use the hex pubkey for contract calls.
     Get it from walletconnect's publicKey field or resolve via provider.getPublicKeyInfo()
```

---

## Network Configuration Consistency

All three layers MUST use the same network configuration.

### What Must Match

| Config Item | Contract | Frontend | Backend |
|-------------|----------|----------|---------|
| Network object | (deployed to target) | `networks.opnetTestnet` or `networks.bitcoin` | Same |
| RPC URL | N/A | `https://testnet.opnet.org` or `https://mainnet.opnet.org` | Same |
| Contract addresses | (output of deployment) | Config file with deployed addresses | Same |

### Common Failure: Network Mismatch

```
SYMPTOM: Contract not found, transactions fail, balances show zero
ROOT CAUSE: Frontend points to testnet RPC but uses mainnet network object (or vice versa)
FIX: Verify all three match:
  - JSONRpcProvider url matches the network
  - networks.* value matches the target chain
  - Contract addresses are from the correct deployment
```

### Common Failure: Wrong networks.* Value

```
SYMPTOM: Address encoding fails, Bech32 prefix wrong
ROOT CAUSE: Using networks.testnet or networks.regtest instead of networks.opnetTestnet
FIX: OPNet testnet = networks.opnetTestnet (Signet fork). NEVER networks.testnet or networks.regtest.
```

---

## Deployed Contract Address Updates

When a contract is redeployed, the frontend and backend must be updated with the new address.

### Recommended Pattern

```typescript
// src/config/contracts.ts -- single source of truth
export const CONTRACTS = {
    TOKEN: {
        address: 'op1...deployedaddress',
        hex: '0x...hexaddress',
    },
    DEX_ROUTER: {
        address: 'op1...routeraddress',
        hex: '0x...hexaddress',
    },
} as const;
```

### Common Failure: Stale Contract Address

```
SYMPTOM: Calls succeed but return unexpected data, or contract not found
ROOT CAUSE: Frontend still references old contract address after redeployment
FIX: Update CONTRACTS config file. Verify with provider.getCode(newAddress) that the new contract exists.
```

---

## getContract Parameter Consistency

`getContract` requires exactly 5 parameters, and each must be correct.

```typescript
const contract = getContract<IOP20Contract>(
    contractAddress,   // 1: from CONTRACTS config (op1... or 0x...)
    OP_20_ABI,         // 2: must match contract's @method() declarations
    provider,          // 3: singleton JSONRpcProvider for correct network
    networks.bitcoin,  // 4: must match provider's network
    senderAddress,     // 5: Address.fromString(hashedMLDSAKey, publicKey)
);
```

### Common Failure: Missing Sender Address

```
SYMPTOM: Simulation works but sendTransaction fails, or sender-dependent logic breaks
ROOT CAUSE: getContract called with 4 params (missing senderAddress)
FIX: Always pass all 5 params. The 5th param (sender) is required for simulation context.
```

### Common Failure: JSONRpcProvider Positional Args

```
SYMPTOM: Provider construction fails or connects to wrong endpoint
ROOT CAUSE: new JSONRpcProvider(url, network) -- positional args
FIX: Constructor takes config OBJECT: new JSONRpcProvider({ url: '...', network: networks.bitcoin })
```

---

## Signer Consistency Between Frontend and Backend

```
FRONTEND: signer: null, mldsaSigner: null        (wallet handles signing)
BACKEND:  signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair  (server signs)
```

### Common Failure: Signer on Frontend

```
SYMPTOM: Private key exposure, or "invalid signer" error
ROOT CAUSE: Passing wallet.keypair to sendTransaction on frontend
FIX: Frontend ALWAYS uses signer: null, mldsaSigner: null. The OP_WALLET extension handles signing.
```

### Common Failure: Null Signer on Backend

```
SYMPTOM: Transaction not signed, broadcast fails
ROOT CAUSE: Using signer: null on backend (no wallet extension to handle signing)
FIX: Backend MUST provide signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair
```

---

## Buffer/Uint8Array Consistency

`Buffer` does not exist in the OPNet stack. ALL layers must use `Uint8Array`.

```typescript
import { BufferHelper } from '@btc-vision/transaction';

// WRONG (any layer)
const data = Buffer.from('deadbeef', 'hex');
const hex = Buffer.from(bytes).toString('hex');

// CORRECT (any layer)
const data: Uint8Array = BufferHelper.fromHex('deadbeef');
const hex: string = BufferHelper.toHex(bytes);
```

If Buffer appears anywhere in the stack (contract, frontend, or backend), it is a bug.

---

## Package Version Consistency

All layers sharing OPNet packages must use the same version tags.

| Package | Tag | Layers |
|---------|-----|--------|
| `@btc-vision/bitcoin` | `@rc` | Frontend, Backend |
| `@btc-vision/transaction` | `@rc` | Frontend, Backend |
| `opnet` | `@rc` | Frontend, Backend |

Every `package.json` that includes OPNet packages MUST have:

```json
{
    "overrides": {
        "@noble/hashes": "2.0.1"
    }
}
```

### Common Failure: Missing @noble/hashes Override

```
SYMPTOM: Cryptographic operations fail, hash mismatches, signature verification fails
ROOT CAUSE: Different @noble/hashes versions between layers or within node_modules
FIX: Add "overrides": { "@noble/hashes": "2.0.1" } to every package.json
```

---

## Integration Review Checklist

Use this checklist when reviewing cross-layer integration:

### Contract <-> Frontend
```
[ ] Every contract @method() has matching ABI definition in frontend
[ ] ABI parameter names and types match @method() decorators exactly
[ ] No bare @method() decorators (zero ABI inputs)
[ ] Selector encoding uses full method signature (not just name)
[ ] Contract address in frontend config matches actual deployment
[ ] getContract called with all 5 params
[ ] Address.fromString uses 2 params (hashedMLDSAKey, publicKey) for user addresses
[ ] Frontend uses signer: null, mldsaSigner: null
[ ] Simulation result checked for error before sendTransaction
```

### Contract <-> Backend
```
[ ] Same ABI definitions as frontend
[ ] Same contract addresses as frontend
[ ] Backend uses signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair
[ ] Wallet derived with deriveOPWallet() (not derive())
[ ] Same network configuration as frontend
```

### Frontend <-> Backend
```
[ ] Same network endpoints (RPC URL)
[ ] Same network object (networks.opnetTestnet or networks.bitcoin)
[ ] Same contract addresses
[ ] Same @noble/hashes override version
[ ] No Buffer usage in either layer
```

### Cross-Cutting
```
[ ] No networks.testnet or networks.regtest (use networks.opnetTestnet)
[ ] No Buffer anywhere (Uint8Array + BufferHelper)
[ ] overrides: { "@noble/hashes": "2.0.1" } in all package.json files
[ ] Explorer links (mempool + OPScan) shown for all transactions
[ ] optimize: false in all getUTXOs calls
[ ] OP20 uses increaseAllowance/decreaseAllowance (not approve)
```

---

## Known Integration Incident Patterns

These are patterns that have caused real failures in production:

### 1. Address.fromString 2-Param Bug
**Frequency**: Very common. AI agents consistently get this wrong.
**Symptom**: Tokens appear to transfer but recipient balance is zero.
**Root cause**: Address constructed from wrong params (1 param, or wrong 2 params).
**Prevention**: Always destructure `{ hashedMLDSAKey, publicKey }` from walletconnect.

### 2. Selector Mismatch
**Frequency**: Common when contracts are updated without updating tests/frontend.
**Symptom**: Contract call falls through to super.callMethod(), returns unexpected error.
**Root cause**: Method signature string in encodeSelector doesn't match ABI.
**Prevention**: Use the exact same method signature string everywhere.

### 3. Stale Contract Address After Redeployment
**Frequency**: Happens on every redeployment cycle.
**Symptom**: Contract not found, or old contract responds with outdated logic.
**Root cause**: Frontend/backend config not updated after redeployment.
**Prevention**: Single CONTRACTS config file, update immediately after deployment, verify with getCode().

### 4. Network Configuration Drift
**Frequency**: Common during testnet-to-mainnet migration.
**Symptom**: Everything works on testnet, breaks on mainnet (or vice versa).
**Root cause**: One layer points to testnet, another to mainnet.
**Prevention**: Single network config consumed by all layers.

### 5. Missing Simulation Check
**Frequency**: Common in "happy path only" implementations.
**Symptom**: BTC sent to contract that reverts, BTC is GONE (partial revert).
**Root cause**: sendTransaction called without checking simulation result for errors.
**Prevention**: ALWAYS check `'error' in sim` before calling sendTransaction.

### 6. OP_20_ABI vs OP20_ABI Naming
**Frequency**: Common typo.
**Symptom**: Import error, undefined ABI.
**Root cause**: The export is `OP_20_ABI` (with underscore), not `OP20_ABI`.
**Prevention**: Use autocomplete, grep for the correct export name.

### 7. JSONRpcProvider Constructor Misuse
**Frequency**: Common -- developers assume positional args.
**Symptom**: Provider connects to wrong endpoint or fails to construct.
**Root cause**: `new JSONRpcProvider(url, network)` instead of `new JSONRpcProvider({ url, network })`.
**Prevention**: Always use config object pattern.
