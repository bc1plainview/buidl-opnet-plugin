#!/bin/bash
# fuzz-contract.sh — Property-based fuzz case generator for OPNet contracts
#
# Usage: bash scripts/fuzz-contract.sh <abi-path> [contract-address] [rpc-url]
#
# Reads an ABI JSON file, extracts @method signatures and param types,
# generates boundary test cases for each method, and outputs them as
# artifacts/testing/fuzz-cases.json.
#
# This script does NOT send transactions. It only generates test cases.
#
# Boundary values by type:
#   u256:    [0, 1, 2^128, 2^256-1, 2^256-2]
#   address: [zero, contract, caller]
#   bool:    [true, false]
#
# For each method: generates all single-param boundary combinations
# plus 10 random valid-type combinations.
#
# Exit codes:
#   0 — Success
#   1 — Missing arguments or file not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ABI_PATH="${1:-}"
CONTRACT_ADDRESS="${2:-bc1p_placeholder}"
RPC_URL="${3:-https://testnet.opnet.org}"

if [[ -z "$ABI_PATH" || ! -f "$ABI_PATH" ]]; then
  echo "Usage: bash scripts/fuzz-contract.sh <abi-path> [contract-address] [rpc-url]" >&2
  echo "  abi-path: path to the ABI JSON file" >&2
  echo "  contract-address: optional deployed contract address" >&2
  echo "  rpc-url: optional RPC endpoint URL" >&2
  exit 1
fi

# Determine output directory
OUTPUT_DIR="${FUZZ_OUTPUT_DIR:-artifacts/testing}"
mkdir -p "$OUTPUT_DIR"

# Generate fuzz cases using Python
python3 -c "
import json, sys, random

abi_path = sys.argv[1]
contract_address = sys.argv[2]
output_dir = sys.argv[3]

with open(abi_path) as f:
    abi = json.load(f)

# Extract methods from ABI
# ABI format: array of { name, inputs: [{name, type}], type: 'function' }
methods = []
if isinstance(abi, list):
    for entry in abi:
        if entry.get('type') in ('function', 'method', None):
            name = entry.get('name', '')
            inputs = entry.get('inputs', [])
            if name and inputs:  # Skip methods with no params
                methods.append({
                    'name': name,
                    'inputs': [{'name': inp.get('name', f'param{i}'), 'type': inp.get('type', 'unknown')} for i, inp in enumerate(inputs)]
                })
elif isinstance(abi, dict):
    # Handle object-style ABI
    for name, spec in abi.items():
        if isinstance(spec, dict):
            inputs = spec.get('inputs', [])
            if inputs:
                methods.append({
                    'name': name,
                    'inputs': [{'name': inp.get('name', f'param{i}'), 'type': inp.get('type', 'unknown')} for i, inp in enumerate(inputs)]
                })

# Boundary values by type
BOUNDARIES = {
    'u256': ['0', '1', '340282366920938463463374607431768211456', '115792089237316195423570985008687907853269984665640564039457584007913129639935', '115792089237316195423570985008687907853269984665640564039457584007913129639934'],
    'uint256': ['0', '1', '340282366920938463463374607431768211456', '115792089237316195423570985008687907853269984665640564039457584007913129639935', '115792089237316195423570985008687907853269984665640564039457584007913129639934'],
    'u128': ['0', '1', '170141183460469231731687303715884105727', '340282366920938463463374607431768211455', '340282366920938463463374607431768211454'],
    'u64': ['0', '1', '9223372036854775807', '18446744073709551615', '18446744073709551614'],
    'u32': ['0', '1', '2147483647', '4294967295', '4294967294'],
    'u16': ['0', '1', '32767', '65535', '65534'],
    'u8': ['0', '1', '127', '255', '254'],
    'address': ['0x0000000000000000000000000000000000000000000000000000000000000000', contract_address, '0xcaller_placeholder'],
    'Address': ['0x0000000000000000000000000000000000000000000000000000000000000000', contract_address, '0xcaller_placeholder'],
    'bool': ['true', 'false'],
    'boolean': ['true', 'false'],
    'string': ['', 'a', 'A' * 256],
    'bytes': ['0x', '0x00', '0x' + 'ff' * 32],
    'Uint8Array': ['0x', '0x00', '0x' + 'ff' * 32],
}

# Default boundary for unknown types
DEFAULT_BOUNDARY = ['0', '1', '0x' + 'ff' * 32]

fuzz_cases = []

for method in methods:
    method_name = method['name']
    inputs = method['inputs']

    # Generate all single-param boundary combinations
    for param_idx, param in enumerate(inputs):
        param_type = param['type']
        boundaries = BOUNDARIES.get(param_type, DEFAULT_BOUNDARY)

        for boundary_val in boundaries:
            # Create a test case where this param gets the boundary value
            # and other params get a safe default
            params = {}
            for j, p in enumerate(inputs):
                if j == param_idx:
                    params[p['name']] = boundary_val
                else:
                    # Use first boundary value (0/zero/false) as safe default
                    p_type = p['type']
                    p_boundaries = BOUNDARIES.get(p_type, DEFAULT_BOUNDARY)
                    params[p['name']] = p_boundaries[0]

            fuzz_cases.append({
                'method': method_name,
                'params': params,
                'expected_revert': False,
                'boundary_param': param['name'],
                'boundary_type': param_type,
                'boundary_value': boundary_val
            })

    # Generate 10 random valid-type combinations
    for _ in range(10):
        params = {}
        for p in inputs:
            p_type = p['type']
            p_boundaries = BOUNDARIES.get(p_type, DEFAULT_BOUNDARY)
            params[p['name']] = random.choice(p_boundaries)

        fuzz_cases.append({
            'method': method_name,
            'params': params,
            'expected_revert': False,
            'boundary_param': 'random',
            'boundary_type': 'random',
            'boundary_value': 'random'
        })

output_path = f'{output_dir}/fuzz-cases.json'
with open(output_path, 'w') as f:
    json.dump(fuzz_cases, f, indent=2)

print(f'Generated {len(fuzz_cases)} fuzz cases for {len(methods)} methods')
print(f'Output: {output_path}')
for m in methods:
    param_types = ', '.join(p['type'] for p in m['inputs'])
    print(f'  {m[\"name\"]}({param_types})')
" "$ABI_PATH" "$CONTRACT_ADDRESS" "$OUTPUT_DIR"
