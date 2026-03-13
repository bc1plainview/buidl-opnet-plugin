// OP-20 Token Frontend Template
// CUSTOMIZE: Replace MyToken references, contract address, and ABI import
//
// This template follows all OPNet frontend conventions:
// - useWalletConnect() (NOT useWallet())
// - signer: null, mldsaSigner: null (wallet handles signing)
// - Dark mode, glass-morphism, CSS custom properties
// - Skeleton loaders (NOT spinners)
// - Explorer links for every transaction (mempool + OPScan)

import { useState, useEffect, useCallback } from 'react';
// import { useWalletConnect } from './hooks/useWalletConnect';
// import { useToken } from './hooks/useToken';

function App(): JSX.Element {
    // CUSTOMIZE: Uncomment and configure wallet + token hooks
    // const { address, isConnected, connect, disconnect } = useWalletConnect();
    // const { metadata, balance, transfer, isLoading } = useToken(address);

    return (
        <div
            style={{
                minHeight: '100vh',
                background: 'var(--bg-primary)',
                color: 'var(--text-primary)',
                fontFamily: 'var(--font-display)',
            }}
        >
            {/* Header */}
            <header
                style={{
                    padding: 'var(--space-6) var(--space-8)',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    borderBottom: '1px solid var(--border-subtle)',
                }}
            >
                <h1 style={{ fontSize: '1.5rem', fontWeight: 600 }}>
                    {/* CUSTOMIZE: Token name */}
                    MyToken
                </h1>
                <button
                    // onClick={isConnected ? disconnect : connect}
                    style={{
                        padding: 'var(--space-3) var(--space-6)',
                        borderRadius: 'var(--radius-md)',
                        border: '1px solid var(--border-accent)',
                        background: 'var(--bg-card)',
                        color: 'var(--text-primary)',
                        cursor: 'pointer',
                        backdropFilter: 'blur(12px)',
                    }}
                >
                    {/* {isConnected ? 'Disconnect' : 'Connect Wallet'} */}
                    Connect Wallet
                </button>
            </header>

            {/* Main Content */}
            <main style={{ maxWidth: '600px', margin: '0 auto', padding: 'var(--space-8)' }}>
                {/* Token Info Card */}
                <div
                    style={{
                        background: 'var(--bg-card)',
                        borderRadius: 'var(--radius-lg)',
                        padding: 'var(--space-6)',
                        border: '1px solid var(--border-subtle)',
                        backdropFilter: 'blur(16px)',
                        marginBottom: 'var(--space-6)',
                    }}
                >
                    <h2 style={{ marginBottom: 'var(--space-4)' }}>Token Info</h2>
                    {/* CUSTOMIZE: Replace with actual token data from useToken hook */}
                    <div style={{ fontVariantNumeric: 'tabular-nums' }}>
                        <p>Name: MyToken</p>
                        <p>Symbol: MTK</p>
                        <p>Balance: --</p>
                    </div>
                </div>

                {/* Transfer Card */}
                <div
                    style={{
                        background: 'var(--bg-card)',
                        borderRadius: 'var(--radius-lg)',
                        padding: 'var(--space-6)',
                        border: '1px solid var(--border-subtle)',
                        backdropFilter: 'blur(16px)',
                    }}
                >
                    <h2 style={{ marginBottom: 'var(--space-4)' }}>Transfer</h2>
                    {/* CUSTOMIZE: Wire up transfer form with useToken hook */}
                    <form>
                        <input
                            type="text"
                            placeholder="Recipient address"
                            style={{
                                width: '100%',
                                padding: 'var(--space-3)',
                                marginBottom: 'var(--space-3)',
                                background: 'var(--bg-input)',
                                border: '1px solid var(--border-subtle)',
                                borderRadius: 'var(--radius-sm)',
                                color: 'var(--text-primary)',
                            }}
                        />
                        <input
                            type="text"
                            placeholder="Amount"
                            style={{
                                width: '100%',
                                padding: 'var(--space-3)',
                                marginBottom: 'var(--space-4)',
                                background: 'var(--bg-input)',
                                border: '1px solid var(--border-subtle)',
                                borderRadius: 'var(--radius-sm)',
                                color: 'var(--text-primary)',
                            }}
                        />
                        <button
                            type="submit"
                            style={{
                                width: '100%',
                                padding: 'var(--space-3)',
                                borderRadius: 'var(--radius-md)',
                                border: 'none',
                                background: 'var(--accent-primary)',
                                color: 'var(--text-on-accent)',
                                cursor: 'pointer',
                                fontWeight: 600,
                            }}
                        >
                            Send
                        </button>
                    </form>
                </div>
            </main>
        </div>
    );
}

export default App;
