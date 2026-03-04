# OPNet Transaction Simulation Reference

> **Role**: Developers testing contract interactions without waiting for testnet block confirmations
>
> **Self-contained**: All simulation patterns, local testing strategies, and mock setups are in this file.

---

## Why Simulate

On-chain transactions on OPNet testnet take ~10 minutes per block. Simulation lets you:
- Validate calldata encoding before spending BTC
- Catch gas limit issues before they burn funds
- Test contract logic changes instantly during development
- Verify expected return values from contract methods
- Debug revert reasons without waiting for block confirmation

---

## Simulation via `getContract` (Primary Method)

Every contract call through the `opnet` npm package supports simulation. This is the standard approach.

### Read-Only Calls (Always Simulated)

Read-only calls never touch the blockchain. They execute against current state:

```typescript
import { getContract } from 'opnet';
import { JSONRpcProvider } from 'opnet';
import { networks } from '@btc-vision/bitcoin';

const provider = new JSONRpcProvider({
    url: 'https://testnet.opnet.org',
    network: networks.opnetTestnet,
});

const contract = getContract<MyTokenABI>(
    contractAddress,
    abi,
    provider,
    networks.opnetTestnet,
);

// Read-only — always simulated, never broadcasts
const balance = await contract.balanceOf(walletAddress);
if ('error' in balance) {
    console.error('Simulation failed:', balance.error);
} else {
    console.log('Balance:', balance.decoded);
}
```

### Write Calls with Simulation

For state-changing calls, always simulate BEFORE sending:

```typescript
// Step 1: Simulate the call (dry run)
const simulation = await contract.transfer(recipientAddress, amount);

if ('error' in simulation) {
    // Simulation failed — DO NOT send the transaction
    console.error('Would revert:', simulation.error);
    return;
}

// Step 2: Check simulation results
console.log('Estimated gas:', simulation.estimatedGas);
console.log('Return value:', simulation.decoded);

// Step 3: Only after successful simulation, send for real
// (Frontend: signer=null, mldsaSigner=null — wallet handles signing)
// (Backend: signer=wallet.keypair, mldsaSigner=wallet.mldsaKeypair)
```

---

## Deployment Simulation

Use `TransactionFactory` to simulate contract deployments:

```typescript
import { TransactionFactory } from '@btc-vision/transaction';
import { readFileSync } from 'fs';

const wasmBytes = new Uint8Array(readFileSync('./build/contract.wasm'));
const factory = new TransactionFactory();

// Simulate deployment — catches WASM errors, gas issues, encoding problems
const simResult = await factory.simulateDeployment({
    wasm: wasmBytes,
    network: networks.opnetTestnet,
});

if ('error' in simResult) {
    console.error('Deployment would fail:', simResult.error);
    // Common errors:
    // - "Constructor gas limit exceeded" → move logic to onDeployment()
    // - "WASM execution failed" → check asconfig.json
    // - "Invalid bytecode" → rebuild the contract
} else {
    console.log('Deployment simulation passed');
    console.log('Estimated gas:', simResult.estimatedGas);
    console.log('Contract address:', simResult.contractAddress);
    // Now safe to actually deploy
}
```

---

## Local Development Loop (No Testnet Required)

For rapid iteration, use regtest with a local OPNet node:

### 1. Regtest Setup

```typescript
import { networks } from '@btc-vision/bitcoin';

const provider = new JSONRpcProvider({
    url: 'http://localhost:9001',  // Local regtest RPC
    network: networks.regtest,
});
```

### 2. Instant Block Mining (Regtest Only)

On regtest, you control block production:

```bash
# Mine a single block (confirms pending transactions instantly)
bitcoin-cli -regtest generatetoaddress 1 <your-address>
```

### 3. Full Local Flow

```
1. Deploy contract to regtest (instant confirmation)
2. Simulate calls against regtest state
3. Test edge cases by manipulating regtest state
4. Only move to testnet once all local tests pass
```

---

## Gas Estimation Patterns

### Query Live Gas Parameters

```typescript
// NEVER hardcode gas values — always query from RPC
const gasParams = await provider.gasParameters();
console.log('Base fee:', gasParams.baseFee);
console.log('Priority fee:', gasParams.priorityFee);
console.log('Gas limit:', gasParams.gasLimit);
```

### Estimate Before Sending

```typescript
const simulation = await contract.myMethod(arg1, arg2);
if (!('error' in simulation)) {
    const gasEstimate = simulation.estimatedGas;
    // Add 20% buffer for safety
    const gasWithBuffer = BigInt(Math.ceil(Number(gasEstimate) * 1.2));
    console.log(`Gas estimate: ${gasEstimate} (with buffer: ${gasWithBuffer})`);
}
```

---

## Common Simulation Errors

| Error | Cause | Fix |
|-------|-------|-----|
| "Transaction reverted" | Contract logic rejected the call | Check require/assert conditions, verify inputs |
| "Gas limit exceeded" | Call uses more gas than allowed | Optimize contract logic, split into smaller calls |
| "Constructor gas limit exceeded" | Too much logic in constructor | Move to `onDeployment()` (20M gas limit for constructor) |
| "Invalid calldata" | ABI mismatch or wrong encoding | Verify ABI matches deployed contract version |
| "Contract not found" | Wrong address or not deployed | Verify contract address and network |
| "Insufficient balance" | Wallet can't cover gas | Fund wallet or use regtest with mined coins |

---

## Frontend Simulation Pattern

On frontend, simulation happens automatically before wallet signing:

```typescript
// The opnet package simulates internally before prompting the wallet
const result = await contract.transfer(recipient, amount);

if ('error' in result) {
    // Show error to user — no wallet prompt happened
    showError(`Transaction would fail: ${result.error}`);
    return;
}

// Simulation passed — now send (wallet will prompt user)
await sendTransaction({
    calldata: result.calldata,
    to: contractAddress,
    signer: null,        // Frontend: wallet handles signing
    mldsaSigner: null,   // Frontend: wallet handles ML-DSA signing
});
```

---

## Testing Strategy Summary

| Phase | Method | Latency | Use Case |
|-------|--------|---------|----------|
| Development | Regtest simulation | Instant | Rapid iteration, logic testing |
| Integration | Testnet simulation (dry run) | ~1-2s | Verify against real state |
| Pre-deploy | Deployment simulation | ~1-2s | Catch WASM/gas issues |
| Production | Full testnet tx | ~10 min | Final verification before mainnet |

**Rule**: Never skip simulation. BTC transactions are irreversible. Always simulate first.
