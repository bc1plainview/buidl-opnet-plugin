# OPNet Deployment Reference

> **Role**: Developers deploying OPNet smart contracts and frontends to testnet/mainnet
>
> **Self-contained**: All deployment rules, gas limits, explorer links, and network endpoints are in this file.

---

## Network Endpoints

| Network | RPC URL | `networks.*` value | Bech32 Prefix |
|---------|---------|-------------------|---------------|
| **Mainnet** | `https://mainnet.opnet.org` | `networks.bitcoin` | `bc` |
| **Testnet** | `https://testnet.opnet.org` | `networks.opnetTestnet` | `opt` |

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

**IMPORTANT**: For OPNet development, ALWAYS use `networks.opnetTestnet` (NOT `networks.regtest`). The testnet is a Signet fork with OPNet-specific network parameters.

---

## Gas Limits

- **Constructor call on deployment**: 20M gas hardcoded by the protocol
- **Regular calls**: configurable, defaults to 300M
- **CRITICAL**: If your `onDeployment()` method is complex or makes cross-contract calls, it can exceed the 20M gas limit and the deployment will revert consuming all gas

### Why Deployment Reverts Consuming All Gas

If you see "deployment works but contract not found" or "transaction reverted consuming all gas":
1. **Cross-contract calls in `onDeployment()`** -- avoid these
2. **Calldata encoding mismatch** -- verify the ABI encoding of deployment params
3. **Insufficient gas limit** -- 20M is the cap; complex init logic must be simplified
4. **Missing/wrong asconfig.json features** -- ensure ALL `enable` features are present

---

## Deployment Pattern

```typescript
// CORRECT deployment calldata encoding
import { BinaryWriter } from '@btc-vision/transaction';

const calldata = new BinaryWriter();
calldata.writeAddress(ownerAddress);      // write expected param types
calldata.writeU256(initialSupply);

const deploymentCalldata = calldata.getBuffer();
```

### TransactionFactory -- ONLY for Deployments and BTC Transfers

`TransactionFactory` from `@btc-vision/transaction` is the ONLY valid way to build deployment transactions. It is also valid for plain BTC transfers (`createBTCTransfer`).

**TransactionFactory is NOT for contract calls.** Contract calls must use `getContract()` -> simulate -> `sendTransaction()` from the `opnet` package.

---

## Contract Verification After Deployment

After deploying, verify the contract exists and responds:

```typescript
import { JSONRpcProvider } from 'opnet';

const provider = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

// Check contract code exists at address
const code = await provider.getCode(contractAddress);
if (!code || code.length === 0) {
    console.error('Contract not found -- deployment likely reverted');
}

// For token contracts, verify metadata
const contract = getContract<IOP20Contract>(contractAddress, OP_20_ABI, provider, network, sender);
const metadata = await contract.metadata();
console.log('Token:', metadata.properties.name, metadata.properties.symbol);
```

---

## Explorer Links (MANDATORY on All Frontends)

Every transaction sent from a frontend MUST display both explorer links. No exceptions.

### Mempool Explorer

```
Mainnet:  https://mempool.opnet.org/tx/{TXID}
Testnet:  https://mempool.opnet.org/testnet4/tx/{TXID}
```

### OPScan Explorer

```
Mainnet:  https://opscan.org/accounts/{HEX_ADDRESS}?network=op_mainnet
Testnet:  https://opscan.org/accounts/{HEX_ADDRESS}?network=op_testnet
```

### Implementation Pattern

```typescript
function getExplorerLinks(txid: string, address: string, isMainnet: boolean): { mempool: string; opscan: string } {
    const mempoolBase = isMainnet ? 'https://mempool.opnet.org' : 'https://mempool.opnet.org/testnet4';
    const opscanNetwork = isMainnet ? 'op_mainnet' : 'op_testnet';

    return {
        mempool: `${mempoolBase}/tx/${txid}`,
        opscan: `https://opscan.org/accounts/${address}?network=${opscanNetwork}`,
    };
}
```

---

## IPFS Deployment -- opnet-cli ONLY

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
- Local IPFS daemon (Kubo) -- do NOT run `ipfs add`
- Direct HTTP calls to IPFS API
- Any method other than the opnet-cli script

**REQUIRED for IPFS**: `base: './'` in vite.config.ts (NOT `base: '/'`). Using `base: '/'` causes white page on IPFS.

---

## Testnet vs Mainnet Differences

| Aspect | Testnet | Mainnet |
|--------|---------|---------|
| Network object | `networks.opnetTestnet` | `networks.bitcoin` |
| RPC URL | `https://testnet.opnet.org` | `https://mainnet.opnet.org` |
| Bech32 prefix | `opt` | `bc` |
| Mempool URL | `/testnet4/tx/{TXID}` | `/tx/{TXID}` |
| OPScan network param | `op_testnet` | `op_mainnet` |
| BTC value | Testnet BTC (free) | Real BTC |
| Gas costs | Same gas model | Same gas model |
| Constructor gas limit | 20M | 20M |

---

## Pre-Deployment Checklist

```
[ ] All code passes: lint -> typecheck -> build -> test
[ ] asconfig.json has ALL required enable features
[ ] shrinkLevel: 1 (not 2), noAssert: false (not true)
[ ] No cross-contract calls in onDeployment()
[ ] Deployment calldata encoding matches expected params
[ ] Constructor only contains pointer setup + super()
[ ] All initialization logic in onDeployment()
[ ] @method() decorators declare ALL params
[ ] Contract tested with unit-test-framework
[ ] Security checklist reviewed
[ ] Explorer links implemented in frontend
[ ] base: './' in vite.config.ts (if deploying to IPFS)
```

---

## Common Deployment Problems

| Problem | Fix |
|---------|-----|
| Deployment reverts consuming all gas | Check: asconfig.json features, cross-contract calls in onDeployment, calldata encoding |
| Contract not found after deployment | Consumed all gas = reverted. Check onDeployment() complexity. |
| `Cannot find module assemblyscript` | `npm uninstall assemblyscript` first, then install `@btc-vision/assemblyscript` |
| WASM execution failed | Check asconfig.json has ALL enable features, abort handler exists |
| White page on IPFS | Set `base: './'` in vite.config.ts |
| 2048 byte receipt limit | Use chunked reading pattern for large data |
