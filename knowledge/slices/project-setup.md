# OPNet Project Setup Knowledge Slice

> **For: orchestrator and all agents** | Extracted from opnet-bible.md sections 1, 2

---

## Architecture Overview

OPNet is a **Bitcoin L1 consensus layer** enabling smart contracts directly on Bitcoin.

| What OPNet IS | What OPNet is NOT |
|--------------|-------------------|
| Bitcoin L1 consensus layer | A sidechain |
| Fully trustless | An L2 |
| Permissionless | A metaprotocol |
| Decentralized (Bitcoin PoW + OPNet epoch SHA1 mining) | Indexer-dependent |

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

**IMPORTANT**: ALWAYS use `networks.opnetTestnet` (NOT `networks.testnet`). The testnet is a Signet fork with OPNet-specific network parameters.

### The Two Address Systems

| System | Format | Used For |
|--------|--------|---------|
| Bitcoin Address | Taproot P2TR (`bc1p...`) | External identity, what you see in walletconnect |
| OPNet Address | ML-DSA public key hash (32 bytes, 0x hex) | Contract balances, internal state |

**You CANNOT loop through Bitcoin addresses and transfer tokens.** Contract storage uses ML-DSA addresses.

## Package Versions & Setup

### NEVER GUESS PACKAGE VERSIONS

OPNet packages use `@rc` release tags. Wrong versions = build failures.

### Install Commands

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

### Buffer is COMPLETELY REMOVED

```typescript
import { BufferHelper } from '@btc-vision/transaction';

// WRONG
const data = Buffer.from('deadbeef', 'hex');
const hex = Buffer.from(bytes).toString('hex');

// CORRECT
const data: Uint8Array = BufferHelper.fromHex('deadbeef');
const hex: string = BufferHelper.toHex(bytes);
const bytes = new TextEncoder().encode('hello');
const str = new TextDecoder().decode(bytes);
```

### MANDATORY package.json override

ALL projects MUST include:
```json
{
    "overrides": {
        "@noble/hashes": "2.0.1"
    }
}
```

## Project Structures

### Contract Project

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

### Frontend Project

```
my-frontend/
├── src/
│   ├── main.tsx
│   ├── App.tsx
│   ├── components/
│   ├── hooks/
│   ├── services/
│   └── config/
├── public/
├── package.json
├── vite.config.ts
└── tsconfig.json
```

### Backend Project

```
my-backend/
├── src/
│   ├── index.ts           # HyperExpress entry
│   ├── routes/
│   ├── services/
│   └── config/
├── package.json
└── tsconfig.json
```

## Code Verification Order (MANDATORY)

```bash
# 1. Lint (MUST pass with zero errors)
npm run lint

# 2. TypeScript check (MUST pass with zero errors)
npm run typecheck

# 3. Build (only after lint + types pass)
npm run build

# 4. Test (run on clean build)
npm test
```

## TypeScript Law (Non-Negotiable)

```
FORBIDDEN: any, !, @ts-ignore, eslint-disable, object, Function, {}, number for satoshis, float for financial values
REQUIRED: bigint for satoshis/token amounts/block heights, explicit return types, TSDoc for public methods, strict null checks, interface definitions for all data shapes
```

## Key Imports Cheat Sheet

```typescript
// For contracts (AssemblyScript):
import { Blockchain, OP_NET, OP20, OP721, Address, Calldata, BytesWriter,
         Selector, StoredU256, StoredBoolean, StoredString, StoredU64,
         AddressMemoryMap, StoredMapU256, encodeSelector, SafeMath, Revert,
         Upgradeable } from '@btc-vision/btc-runtime/runtime';
import { u256, u128 } from '@btc-vision/as-bignum/assembly';
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
```
