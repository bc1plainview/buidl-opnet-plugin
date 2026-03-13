// useToken — Hook for OP-20 token interactions
// CUSTOMIZE: Replace CONTRACT_ADDRESS with your deployed contract address
// CUSTOMIZE: Import your token's ABI
//
// This hook follows all OPNet frontend conventions:
// - getContract from opnet package (NOT @btc-vision/transaction)
// - signer: null, mldsaSigner: null (wallet handles signing)
// - BigInt for all amounts
// - Simulate before send

import { useState, useEffect, useCallback } from 'react';
// import { getContract, JSONRpcProvider } from 'opnet';
// import { networks } from '@btc-vision/bitcoin';
// import type { OP20Contract } from 'opnet';

// CUSTOMIZE: Replace with your deployed contract address
// const CONTRACT_ADDRESS = 'bcrt1p...your-contract-address';

// CUSTOMIZE: Set your network
// const NETWORK = networks.opnetTestnet;
// const PROVIDER_URL = 'https://testnet.opnet.org';

interface TokenMetadata {
    name: string;
    symbol: string;
    decimals: number;
    totalSupply: bigint;
}

interface UseTokenReturn {
    metadata: TokenMetadata | null;
    balance: bigint;
    transfer: (to: string, amount: bigint) => Promise<string | null>;
    isLoading: boolean;
    error: string | null;
}

// CUSTOMIZE: Uncomment and configure this hook after deploying your contract
export function useToken(_address: string | null): UseTokenReturn {
    const [metadata, setMetadata] = useState<TokenMetadata | null>(null);
    const [balance, setBalance] = useState<bigint>(0n);
    const [isLoading, setIsLoading] = useState<boolean>(false);
    const [error, setError] = useState<string | null>(null);

    // CUSTOMIZE: Uncomment to fetch token metadata on mount
    useEffect(() => {
        if (!_address) return;

        // Example metadata fetch (uncomment and configure):
        // const fetchMetadata = async () => {
        //     setIsLoading(true);
        //     try {
        //         const provider = new JSONRpcProvider(PROVIDER_URL, NETWORK);
        //         const contract = getContract<OP20Contract>(CONTRACT_ADDRESS, provider);
        //         const name = await contract.name();
        //         const symbol = await contract.symbol();
        //         const decimals = await contract.decimals();
        //         const totalSupply = await contract.totalSupply();
        //         setMetadata({ name, symbol, decimals: Number(decimals), totalSupply });
        //     } catch (err) {
        //         setError(err instanceof Error ? err.message : 'Failed to fetch metadata');
        //     } finally {
        //         setIsLoading(false);
        //     }
        // };
        // void fetchMetadata();
    }, [_address]);

    // CUSTOMIZE: Uncomment to fetch balance when address changes
    useEffect(() => {
        if (!_address) return;

        // Example balance fetch (uncomment and configure):
        // const fetchBalance = async () => {
        //     try {
        //         const provider = new JSONRpcProvider(PROVIDER_URL, NETWORK);
        //         const contract = getContract<OP20Contract>(CONTRACT_ADDRESS, provider);
        //         const bal = await contract.balanceOf(_address);
        //         setBalance(bal);
        //     } catch (err) {
        //         setError(err instanceof Error ? err.message : 'Failed to fetch balance');
        //     }
        // };
        // void fetchBalance();
    }, [_address]);

    // CUSTOMIZE: Uncomment and wire up transfer
    const transfer = useCallback(async (_to: string, _amount: bigint): Promise<string | null> => {
        setError(null);

        // Example transfer (uncomment and configure):
        // try {
        //     setIsLoading(true);
        //     const provider = new JSONRpcProvider(PROVIDER_URL, NETWORK);
        //     const contract = getContract<OP20Contract>(CONTRACT_ADDRESS, provider);
        //
        //     // Simulate first
        //     const sim = await contract.transfer(to, amount);
        //     if (!sim.result) {
        //         setError('Transfer simulation failed');
        //         return null;
        //     }
        //
        //     // Send with wallet signing (signer: null on frontend)
        //     const tx = await contract.sendTransaction(sim, {
        //         signer: null,
        //         mldsaSigner: null,
        //     });
        //
        //     return tx.result;
        // } catch (err) {
        //     setError(err instanceof Error ? err.message : 'Transfer failed');
        //     return null;
        // } finally {
        //     setIsLoading(false);
        // }

        return null;
    }, []);

    return { metadata, balance, transfer, isLoading, error };
}
