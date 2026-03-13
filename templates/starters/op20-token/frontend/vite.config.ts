// OPNet-Ready Vite Config Template
// Includes all required polyfills, shims, and deduplication

import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

export default defineConfig({
    plugins: [
        react(),
        nodePolyfills({
            include: ['buffer', 'crypto', 'stream', 'util', 'process', 'events'],
            globals: { Buffer: true, global: true, process: true },
        }),
    ],
    resolve: {
        alias: {
            // undici shim — required for OPNet RPC calls
            undici: 'node_modules/undici/lib/web/fetch/index.js',
        },
        dedupe: [
            '@btc-vision/bitcoin',
            '@btc-vision/transaction',
            '@noble/hashes',
            '@noble/curves',
            'opnet',
        ],
    },
    build: {
        target: 'esnext',
        rollupOptions: {
            output: {
                manualChunks: {
                    vendor: ['react', 'react-dom'],
                    opnet: ['opnet', '@btc-vision/transaction'],
                    crypto: ['@noble/hashes', '@noble/curves'],
                },
            },
        },
    },
    define: {
        global: 'globalThis',
    },
});
