# OPNet On-Chain E2E Testing Reference

> **Role**: Agents and developers writing real on-chain integration tests for deployed OPNet contracts
>
> **Self-contained**: All on-chain testing patterns, wallet setup, transaction waiting, and verification strategies are in this file.

---

## Why On-Chain E2E Testing Is Non-Negotiable

Simulation and on-chain execution differ in critical ways on OPNet:

| Aspect | Simulation | Real On-Chain |
|--------|-----------|---------------|
| `output.to` format | ML-DSA hex (whatever you pass) | **Bech32 address** (e.g., `opt1p...`) |
| `output.scriptPublicKey` | May be populated | **null** (`hasScriptPubKey=0`) |
| UTXO availability | Simulated against state snapshot | Must use real unspent UTXOs |
| Fee estimation | Estimated | Real BTC deducted from wallet |
| Wallet signing | Skipped (signer/mldsaSigner used directly) | Real signing with keypair + ML-DSA |
| Block confirmation | Instant | ~10 minutes per block |

A contract that passes simulation can fail on-chain. This is not theoretical — it happened with the Nexus marketplace `executeBTC` method (INC-mmfi7bj9-da60c9). The fix required adding bech32 decode logic to the contract's output verification.

**Rule: No contract is "done" until every method passes a real on-chain test.**

---

## Test Wallet Setup

### Required Wallet Configuration

E2E tests need at minimum ONE funded test wallet. Multi-party flows need TWO or more.

**Primary wallet (.env):**
```
WIF=<seller/owner wallet WIF>
QUANTUM_BASE58=<seller/owner ML-DSA keypair>
```

**Secondary wallet (.env.buyer):**
```
BUYER_MNEMONIC=<buyer/second-party mnemonic>
```

### Loading Wallets

```javascript
import { Wallet, Mnemonic, MLDSASecurityLevel, AddressTypes, Address } from '@btc-vision/transaction';
import { networks } from '@btc-vision/bitcoin';

const network = networks.opnetTestnet;

// Primary wallet (from WIF)
const primaryWallet = Wallet.fromWif(process.env.WIF, process.env.QUANTUM_BASE58, network);

// Secondary wallet (from mnemonic)
const secondaryMnemonic = new Mnemonic(process.env.BUYER_MNEMONIC, '', network, MLDSASecurityLevel.LEVEL2);
const secondaryWallet = secondaryMnemonic.deriveOPWallet(AddressTypes.P2TR, 0);
```

### Funding Test Wallets

If test wallets need BTC:
- OPNet testnet uses Signet BTC (free, no real value)
- Fund via faucet or existing test wallet
- Each state-changing tx costs ~10,000-50,000 sats in fees
- Budget: ~500,000 sats per full E2E suite

---

## Transaction Patterns

### Read-Only Method Test

```javascript
const contract = getContract(contractHex, abi, provider, network, wallet.address);

// Read methods are always simulated (no on-chain tx)
const result = await contract.readMethod(args);
if ('error' in result) {
    return { method: 'readMethod', status: 'fail', error: result.error };
}

// Verify returned value matches expected
const value = result.properties?.fieldName;
assert(value === expectedValue, `Expected ${expectedValue}, got ${value}`);
return { method: 'readMethod', status: 'pass', details: value?.toString() };
```

### State-Changing Method Test

```javascript
// 1. Simulate
const sim = await contract.writeMethod(arg1, arg2);
if ('error' in sim && sim.error) {
    return { method: 'writeMethod', status: 'fail', phase: 'simulation', error: sim.error };
}

// 2. Send real transaction
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,
    mldsaSigner: wallet.mldsaKeypair,
    network,
    maximumAllowedSatToSpend: 500_000n,
    refundTo: wallet.p2tr,
    feeRate: 10,
});

// 3. Wait for on-chain confirmation
const result = await waitForTx(provider, receipt.transactionId, 'writeMethod');
if (!result) return { method: 'writeMethod', status: 'fail', phase: 'timeout' };
if (result.reverted) return { method: 'writeMethod', status: 'fail', phase: 'on-chain', error: result.revert };

// 4. Verify state changed
const newState = await contract.readMethod();
assert(newState.properties?.field === expectedNewValue);

return { method: 'writeMethod', status: 'pass', txHash: receipt.transactionId, block: result.tx.blockNumber };
```

### Payable Method Test (HIGHEST RISK)

```javascript
import { TransactionOutputFlags } from 'opnet';

// 1. Set transaction details for simulation
// CRITICAL: Use ML-DSA hex WITHOUT 0x prefix for simulation
const recipientHex = recipientAddress.toHex().replace(/^0x/, '');

contract.setTransactionDetails({
    inputs: [],
    outputs: [{
        to: recipientHex,
        value: paymentAmount,
        index: 1,  // Output 0 is RESERVED by OPNet
        flags: TransactionOutputFlags.hasTo,
    }],
});

// 2. Simulate
const sim = await contract.payableMethod(reservationId);
if ('error' in sim && sim.error) {
    return { method: 'payableMethod', status: 'fail', phase: 'simulation', error: sim.error };
}

// 3. Send with real extraOutputs
// CRITICAL: Use bech32 address (not hex) for real transaction
// CRITICAL: value MUST be bigint (not Number)
const receipt = await sim.sendTransaction({
    signer: wallet.keypair,
    mldsaSigner: wallet.mldsaKeypair,
    network,
    maximumAllowedSatToSpend: 500_000n + paymentAmount,
    refundTo: wallet.p2tr,
    feeRate: 10,
    extraOutputs: [{ address: recipientBech32, value: paymentAmount }],
});

// 4. Wait for confirmation
const result = await waitForTx(provider, receipt.transactionId, 'payableMethod');
if (!result) return { method: 'payableMethod', status: 'fail', phase: 'timeout' };
if (result.reverted) return { method: 'payableMethod', status: 'fail', phase: 'on-chain', error: result.revert };

// 5. Verify payment AND state change
return { method: 'payableMethod', status: 'pass', txHash: receipt.transactionId, block: result.tx.blockNumber };
```

---

## UTXO Chaining (Approve + Action in Same Block)

When two TXs must run sequentially (e.g., approve then swap):

```javascript
// TX 1: Approve
const approveSim = await contract.increaseAllowance(spender, amount);
const approveReceipt = await approveSim.sendTransaction({ ...baseTx, refundTo: wallet.p2tr });

// TX 2: Action (uses UTXOs from TX 1)
const actionSim = await contract.doAction(args);
const actionReceipt = await actionSim.sendTransaction({
    ...baseTx,
    refundTo: wallet.p2tr,
    utxos: approveReceipt.newUTXOs,  // Chain the UTXOs
});

// Wait for both to confirm (they land in the same block)
await waitForTx(provider, approveReceipt.transactionId, 'approve');
await waitForTx(provider, actionReceipt.transactionId, 'action');
```

---

## Address Handling

### Hex to Address Object

SDK methods expecting `Address` parameters fail with `"Cannot use 'in' operator"` if passed strings.

```javascript
function hexToAddress(hex) {
    const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
    const bytes = new Uint8Array(clean.length / 2);
    for (let i = 0; i < bytes.length; i++) {
        bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    }
    return new Address(bytes);
}
```

### Resolving Bech32 to Hex

```javascript
async function resolveToHex(provider, addr) {
    if (addr.startsWith('0x') || /^[0-9a-fA-F]{64}$/.test(addr)) {
        return addr.startsWith('0x') ? addr : `0x${addr}`;
    }
    const rawInfo = await provider.getPublicKeysInfoRaw([addr]);
    const entry = rawInfo[addr];
    if (!entry || !entry.tweakedPubkey) throw new Error(`Cannot resolve: ${addr}`);
    return `0x${entry.tweakedPubkey}`;
}
```

---

## Waiting for Block Confirmation

```javascript
async function waitForTx(provider, txHash, label, maxWait = 900_000) {
    const start = Date.now();
    process.stdout.write(`  Waiting for ${label}...`);
    while (Date.now() - start < maxWait) {
        try {
            const tx = await provider.getTransaction(txHash);
            if (tx) {
                console.log(` confirmed block ${tx.blockNumber}`);
                try {
                    const r = await provider.getTransactionReceipt(txHash);
                    if (r?.revert) {
                        console.log(`  REVERTED: ${r.revert}`);
                        return { tx, reverted: true, revert: r.revert, receipt: r };
                    }
                    console.log(`  Gas: ${r?.gasUsed?.toString()}`);
                    return { tx, reverted: false, receipt: r };
                } catch {
                    return { tx, reverted: false, receipt: null };
                }
            }
        } catch {}
        await sleep(15_000);
        process.stdout.write('.');
    }
    console.log(' TIMEOUT');
    return null;
}
```

**Timing:**
- Poll every 15 seconds
- Max wait: 15 minutes (900 seconds) per transaction
- OPNet testnet blocks: ~10 minutes
- If timeout, report as failure (do not retry forever)

---

## Multi-Party Flow Testing

### Pattern: Marketplace (Seller + Buyer)

```
Step 1: [Seller] setApprovalForAll(marketplace, true)
  -> Wait for confirmation
Step 2: [Seller] listNFT(collection, tokenId, price, ...)
  -> Wait for confirmation, capture listingId
Step 3: [Buyer] reserveBTC(listingId)
  -> Wait for confirmation, capture reservationId
Step 4: [Buyer] executeBTC(reservationId) [PAYABLE]
  -> setTransactionDetails with seller payment output
  -> sendTransaction with extraOutputs to seller bech32 address
  -> Wait for confirmation
Step 5: [Verify] Check NFT ownership transferred, seller paid
```

### Pattern: Token Swap (User A + User B)

```
Step 1: [User A] increaseAllowance(swapContract, amount)
Step 2: [User A] addLiquidity(tokenA, tokenB, amountA, amountB)
  -> Wait, verify pool state
Step 3: [User B] increaseAllowance(swapContract, swapAmount)
Step 4: [User B] swap(tokenIn, tokenOut, amountIn, minAmountOut)
  -> Wait, verify balances changed correctly
```

### Pattern: Token with Staking

```
Step 1: [User] increaseAllowance(stakingContract, amount)
Step 2: [User] stake(amount)
  -> Wait, verify staked balance
Step 3: [Time passes — advance blocks or wait]
Step 4: [User] claimRewards()
  -> Wait, verify reward balance
Step 5: [User] unstake(amount)
  -> Wait, verify tokens returned
```

---

## Common On-Chain Test Failures

| Failure | Cause | Fix |
|---------|-------|-----|
| "Seller payment output not found" | Contract checks `output.to` as hex but node provides bech32 | Add `Bech32.decodeOrNull()` to contract output verification |
| "Error adding output" | `extraOutputs.value` is `Number` not `bigint` | Use `1_000_000n` not `Number(1_000_000n)` |
| "Cannot use 'in' operator to search for 'equals'" | Passed hex string where Address object expected | Use `new Address(Uint8Array.from(...))` |
| Simulation passes, on-chain reverts | Simulation uses different output format than real tx | Test on-chain — simulation alone is insufficient |
| Transaction timeout | Block not mined in 15 minutes | Increase maxWait, check testnet status |
| "UTXO already spent" | Using stale UTXOs after a previous tx | Use `receipt.newUTXOs` for UTXO chaining |

---

## Test Script Template

```javascript
#!/usr/bin/env node
/**
 * E2E Test: [Method/Flow Name]
 * Tests: [Brief description]
 * Wallets: [primary | primary + secondary]
 */
import { loadEnv, createProvider, waitForTx, resolveToHex, hexToAddress, network } from './harness.js';
import { Wallet } from '@btc-vision/transaction';
import { getContract, OP_NET_ABI } from 'opnet';

// Load wallet credentials
loadEnv('./deploy/.env');

const provider = createProvider();
const wallet = Wallet.fromWif(process.env.WIF, process.env.QUANTUM_BASE58, network);

const CONTRACT_ABI = [
    // ... method definitions
];

async function main() {
    console.log('\n=== E2E: [Test Name] ===\n');

    const contractHex = await resolveToHex(provider, 'opt1s...');
    const contract = getContract(contractHex, [...CONTRACT_ABI, ...OP_NET_ABI], provider, network, wallet.address);

    // ... test logic

    console.log('\n=== RESULT: PASS ===');
    return { status: 'pass' };
}

main()
    .then((result) => {
        if (result.status !== 'pass') {
            console.error('TEST FAILED:', result);
            process.exit(1);
        }
    })
    .catch((err) => {
        console.error('FATAL:', err);
        process.exit(1);
    });
```

---

## Results Format

```json
{
    "status": "pass|fail",
    "framework": "on-chain-e2e",
    "network": "opnetTestnet",
    "contractAddress": "opt1s...",
    "blockRange": { "start": 4100, "end": 4107 },
    "tests": {
        "read_methods": { "total": 5, "passed": 5, "failed": 0, "results": [] },
        "write_methods": { "total": 3, "passed": 3, "failed": 0, "results": [] },
        "payable_methods": { "total": 1, "passed": 1, "failed": 0, "results": [] },
        "full_flows": { "total": 1, "passed": 1, "failed": 0, "results": [] }
    },
    "finalState": {
        "verified": true,
        "checks": [
            { "check": "description", "passed": true }
        ]
    },
    "explorerLinks": {
        "contract": "https://opscan.org/accounts/{HEX}?network=op_testnet",
        "transactions": ["https://mempool.opnet.org/testnet4/tx/{TXID}"]
    }
}
```
