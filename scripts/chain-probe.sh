#!/bin/bash
# chain-probe.sh — Query OPNet RPC for chain state before spec generation
#
# Writes gas parameters, block height, and network info to artifacts/chain-state.json.
# Handles RPC failure gracefully (writes probe_status: "failed", continues).
#
# Usage: bash chain-probe.sh [artifacts-dir] [rpc-url]
#   artifacts-dir: directory to write chain-state.json (default: current dir)
#   rpc-url: OPNet RPC endpoint (default: https://testnet.opnet.org)
#
# Exit codes:
#   0 — Always (graceful failure by design)

set -euo pipefail

ARTIFACTS_DIR="${1:-.}"
RPC_URL="${2:-https://testnet.opnet.org}"

OUTPUT_FILE="$ARTIFACTS_DIR/chain-state.json"

# Ensure output directory exists
mkdir -p "$ARTIFACTS_DIR"

# Helper: write a failed probe result and exit cleanly
write_failed() {
  local reason="${1:-unknown}"
  cat > "$OUTPUT_FILE" << EOF
{
  "probe_status": "failed",
  "reason": "$reason",
  "rpc_url": "$RPC_URL",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  exit 0
}

# Check if curl is available
if ! command -v curl >/dev/null 2>&1; then
  write_failed "curl not available"
fi

# Query block height
BLOCK_RESPONSE=$(curl -s --max-time 10 -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"btc_blockNumber","params":[],"id":1}' 2>/dev/null || true)

if [[ -z "$BLOCK_RESPONSE" ]]; then
  write_failed "rpc_unreachable"
fi

# Parse block height
BLOCK_HEIGHT=$(echo "$BLOCK_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    result = data.get('result', '')
    if isinstance(result, str) and result.startswith('0x'):
        print(int(result, 16))
    elif isinstance(result, (int, float)):
        print(int(result))
    else:
        print(result)
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")

# Query gas parameters
GAS_RESPONSE=$(curl -s --max-time 10 -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"btc_gasParameters","params":[],"id":2}' 2>/dev/null || true)

GAS_INFO=$(echo "$GAS_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    result = data.get('result', {})
    if isinstance(result, dict):
        print(json.dumps(result))
    else:
        print('{}')
except Exception:
    print('{}')
" 2>/dev/null || echo "{}")

# Determine network from RPC URL
NETWORK="unknown"
case "$RPC_URL" in
  *testnet*) NETWORK="testnet" ;;
  *regtest*) NETWORK="regtest" ;;
  *mainnet*) NETWORK="mainnet" ;;
esac

# Format block_height as proper JSON type (number if valid, string if unknown)
if [[ "$BLOCK_HEIGHT" =~ ^[0-9]+$ ]]; then
  BLOCK_HEIGHT_JSON="$BLOCK_HEIGHT"
else
  BLOCK_HEIGHT_JSON="\"$BLOCK_HEIGHT\""
fi

# Write successful probe result
# max_contract_size_bytes: 400KB known OPNet constant
cat > "$OUTPUT_FILE" << EOF
{
  "probe_status": "success",
  "rpc_url": "$RPC_URL",
  "network": "$NETWORK",
  "block_height": $BLOCK_HEIGHT_JSON,
  "max_contract_size_bytes": 400000,
  "gas_parameters": $GAS_INFO,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

exit 0
