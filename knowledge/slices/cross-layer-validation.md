# Cross-Layer Validation Knowledge

## Purpose

Cross-layer validation catches integration bugs between contract, frontend, and backend before the security audit runs. These bugs are the #1 cause of wasted audit and E2E testing cycles — an ABI mismatch that could be caught in 30 seconds wastes an entire auditor dispatch.

## Common Mismatch Types

### 1. ABI Method Not Found
**Symptom**: Frontend calls `contract.stake()` but the ABI has no `stake` method.
**Cause**: Contract-dev renamed the method, or frontend-dev assumed a method exists.
**Detection**: Parse ABI JSON, extract all method names, grep frontend for `contract.` calls.
**Fix**: Either add the method to the contract or fix the frontend call.

### 2. Parameter Count Mismatch
**Symptom**: Frontend calls `contract.transfer(to, amount)` but ABI expects `transfer(to, amount, memo)`.
**Cause**: Contract added a parameter that frontend doesn't know about.
**Detection**: Compare parameter count in ABI definition vs frontend call.
**Fix**: Update the frontend call to match the ABI.

### 3. Parameter Type Mismatch
**Symptom**: Frontend passes `number` for a `uint256` parameter.
**Cause**: Frontend-dev used `number` instead of `bigint`.
**Detection**: Check that uint256/u256 params use BigInt in frontend code.
**Fix**: Convert to BigInt (`BigInt(amount)` or `amount as bigint`).

### 4. Contract Address Inconsistency
**Symptom**: Frontend uses address `0xabc...` but deployment receipt shows `0xdef...`.
**Cause**: Address was hardcoded before deployment, never updated.
**Detection**: Compare address in frontend config with deployment receipt.
**Fix**: Use environment variable or config file that gets updated post-deployment.

### 5. Network Mismatch
**Symptom**: Frontend uses `networks.testnet` but contract deployed to `networks.opnetTestnet`.
**Cause**: Common OPNet mistake — `networks.testnet` is Testnet4, not OPNet testnet.
**Detection**: Grep for `networks.testnet` in frontend/backend, flag if not `opnetTestnet`.
**Fix**: Change to `networks.opnetTestnet`.

### 6. Signer Configuration
**Symptom**: Frontend passes `signer: wallet.keypair` (leaks private key).
**Cause**: Frontend-dev copied backend pattern.
**Detection**: Grep frontend for `signer:` not followed by `null`.
**Fix**: Frontend must always use `signer: null, mldsaSigner: null`.

### 7. Event Name Mismatch
**Symptom**: Frontend listens for `Transfer` event but contract emits `TokenTransfer`.
**Cause**: Contract-dev changed event name.
**Detection**: Compare event names in ABI with frontend event listeners.
**Fix**: Align event names.

### 8. Return Type Mismatch
**Symptom**: Frontend expects `transfer()` to return `boolean` but OP-20 returns empty BytesWriter.
**Cause**: Frontend-dev assumed Ethereum-style return values.
**Detection**: Check ABI return types vs frontend handling.
**Fix**: Handle the actual return type from the ABI.

## How to Read an OPNet ABI

OPNet ABIs are `BitcoinInterfaceAbi` arrays — each element is either a `FunctionBaseData` or `EventBaseData`:

```typescript
// Function entry
{
  "name": "transfer",
  "type": "function",
  "inputs": [
    { "name": "to", "type": "ADDRESS" },
    { "name": "amount", "type": "UINT256" }
  ],
  "outputs": [
    { "name": "success", "type": "BOOL" }
  ],
  "modifier": "nonpayable"
}

// Event entry
{
  "name": "Transfer",
  "type": "event",
  "values": [
    { "name": "from", "type": "ADDRESS" },
    { "name": "to", "type": "ADDRESS" },
    { "name": "amount", "type": "UINT256" }
  ]
}
```

## Validation Checklist

For each frontend/backend file that imports contract interaction code:

- [ ] Every `contract.methodName()` call exists in the ABI
- [ ] Parameter count matches ABI definition
- [ ] uint256 params use BigInt (not number)
- [ ] Address params use Address type or valid string format
- [ ] Contract address comes from config/env (not hardcoded)
- [ ] Network is `networks.opnetTestnet` for testnet (not `networks.testnet`)
- [ ] Frontend uses `signer: null, mldsaSigner: null`
- [ ] Backend uses `signer: wallet.keypair, mldsaSigner: wallet.mldsaKeypair`
- [ ] Event listeners match ABI event names
- [ ] Return value handling matches ABI output types

## Routing Decisions

When a mismatch is found, determine which agent should fix it:

| Mismatch | Route to | Reasoning |
|----------|----------|-----------|
| Method missing from ABI | contract-dev | Contract needs the method |
| Frontend calls wrong method name | frontend-dev | Frontend has a typo |
| Parameter type mismatch | frontend-dev | Frontend should match ABI |
| Contract address hardcoded | frontend-dev | Frontend config issue |
| Network mismatch | frontend-dev or backend-dev | Whoever has the wrong network |
| Signer leak in frontend | frontend-dev | Security fix |
| Event name mismatch | Depends | Check which side changed |
| Return type handling | frontend-dev | Frontend should adapt to ABI |
