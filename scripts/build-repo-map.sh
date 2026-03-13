#!/bin/bash
# build-repo-map.sh — Hierarchical cross-layer repository map generator
#
# Usage: bash scripts/build-repo-map.sh [abi-json-path] [frontend-dir] [backend-dir]
#
# Generates artifacts/repo-map.md with sections:
#   - Contract Layer (from abi.json): class, methods with signatures, storage slots, events
#   - Frontend Layer (populated after frontend-dev)
#   - Backend Layer (populated after backend-dev)
#   - Cross-Layer Integrity Checks (auto-generated: missing methods, extra calls)
#
# Target: < 300 lines
#
# Exit codes:
#   0 — Success
#   1 — Error during generation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ABI_PATH="${1:-}"
FRONTEND_DIR="${2:-}"
BACKEND_DIR="${3:-}"

OUTPUT_DIR="${SCRIPT_DIR}/artifacts"
mkdir -p "$OUTPUT_DIR"

export _REPOMAP_ABI="$ABI_PATH"
export _REPOMAP_FRONTEND="$FRONTEND_DIR"
export _REPOMAP_BACKEND="$BACKEND_DIR"
export _REPOMAP_OUTPUT="$OUTPUT_DIR/repo-map.md"
python3 << 'PYEOF'
import sys
import json
import os
import re
import glob

abi_path = os.environ.get('_REPOMAP_ABI', '')
frontend_dir = os.environ.get('_REPOMAP_FRONTEND', '')
backend_dir = os.environ.get('_REPOMAP_BACKEND', '')
output_path = os.environ['_REPOMAP_OUTPUT']

lines = []
contract_methods = []
frontend_calls = []
backend_calls = []

# --- Contract Layer ---
lines.append("# Repository Map")
lines.append("")
lines.append("## Contract Layer")
lines.append("")

if abi_path and os.path.exists(abi_path):
    try:
        with open(abi_path, 'r') as f:
            abi_data = json.load(f)

        # Handle both array format and object format
        abi_entries = abi_data if isinstance(abi_data, list) else abi_data.get('abi', abi_data.get('methods', []))

        methods_section = []
        events_section = []
        storage_section = []

        if isinstance(abi_entries, list):
            for entry in abi_entries:
                if not isinstance(entry, dict):
                    continue

                entry_type = entry.get('type', 'function')
                name = entry.get('name', 'unknown')

                if entry_type in ('function', 'method'):
                    inputs = entry.get('inputs', [])
                    outputs = entry.get('outputs', [])
                    input_sig = ", ".join(
                        "{}: {}".format(inp.get('name', 'arg'), inp.get('type', 'unknown'))
                        for inp in inputs
                    ) if isinstance(inputs, list) else ""
                    output_sig = ", ".join(
                        "{}".format(out.get('type', 'unknown'))
                        for out in outputs
                    ) if isinstance(outputs, list) else ""

                    method_line = "- `{}({})` -> `{}`".format(name, input_sig, output_sig if output_sig else "void")
                    methods_section.append(method_line)
                    contract_methods.append(name)

                elif entry_type == 'event':
                    params = entry.get('inputs', entry.get('params', []))
                    param_sig = ", ".join(
                        "{}: {}".format(p.get('name', 'arg'), p.get('type', 'unknown'))
                        for p in params
                    ) if isinstance(params, list) else ""
                    events_section.append("- `{}`({})".format(name, param_sig))

                elif entry_type == 'storage':
                    slot = entry.get('slot', 'unknown')
                    storage_section.append("- `{}` (slot: {})".format(name, slot))

            if methods_section:
                lines.append("### Methods")
                lines.append("")
                lines.extend(methods_section)
                lines.append("")

            if events_section:
                lines.append("### Events")
                lines.append("")
                lines.extend(events_section)
                lines.append("")

            if storage_section:
                lines.append("### Storage Slots")
                lines.append("")
                lines.extend(storage_section)
                lines.append("")

        if not methods_section and not events_section and not storage_section:
            lines.append("*ABI parsed but no recognized entries found.*")
            lines.append("")

    except (json.JSONDecodeError, IOError):
        lines.append("*ABI file exists but could not be parsed.*")
        lines.append("")
else:
    lines.append("*No ABI file available. Run contract-dev first.*")
    lines.append("")

# --- Frontend Layer ---
lines.append("## Frontend Layer")
lines.append("")

if frontend_dir and os.path.isdir(frontend_dir):
    # Scan for contract method calls
    src_dir = os.path.join(frontend_dir, "src")
    search_dir = src_dir if os.path.isdir(src_dir) else frontend_dir

    ts_files = []
    for root, dirs, files in os.walk(search_dir):
        for f in files:
            if f.endswith(('.ts', '.tsx', '.js', '.jsx')):
                ts_files.append(os.path.join(root, f))

    components = []
    hooks = []
    services = []

    for fpath in ts_files:
        fname = os.path.basename(fpath)
        rel_path = os.path.relpath(fpath, frontend_dir)

        if 'component' in rel_path.lower() or fname.endswith(('.tsx', '.jsx')):
            components.append(rel_path)
        elif 'hook' in rel_path.lower() or fname.startswith('use'):
            hooks.append(rel_path)
        elif 'service' in rel_path.lower() or 'api' in rel_path.lower():
            services.append(rel_path)

        # Scan for contract method calls
        try:
            with open(fpath, 'r') as f:
                content = f.read()
            # Match patterns like contract.methodName( or .methodName(
            for match in re.finditer(r'\.(\w+)\s*\(', content):
                call_name = match.group(1)
                if call_name in contract_methods:
                    frontend_calls.append(call_name)
        except (IOError, UnicodeDecodeError):
            pass

    if components:
        lines.append("### Components")
        for c in components[:20]:
            lines.append("- `{}`".format(c))
        lines.append("")

    if hooks:
        lines.append("### Hooks")
        for h in hooks[:10]:
            lines.append("- `{}`".format(h))
        lines.append("")

    if services:
        lines.append("### Services")
        for s in services[:10]:
            lines.append("- `{}`".format(s))
        lines.append("")

    if frontend_calls:
        lines.append("### Contract Calls")
        for call in sorted(set(frontend_calls)):
            lines.append("- `{}`".format(call))
        lines.append("")

    if not components and not hooks and not services:
        lines.append("*Frontend directory exists but no recognized source files found.*")
        lines.append("")
else:
    lines.append("*Not yet populated. Run frontend-dev first.*")
    lines.append("")

# --- Backend Layer ---
lines.append("## Backend Layer")
lines.append("")

if backend_dir and os.path.isdir(backend_dir):
    src_dir = os.path.join(backend_dir, "src")
    search_dir = src_dir if os.path.isdir(src_dir) else backend_dir

    ts_files = []
    for root, dirs, files in os.walk(search_dir):
        for f in files:
            if f.endswith(('.ts', '.js')):
                ts_files.append(os.path.join(root, f))

    routes = []
    services = []

    for fpath in ts_files:
        fname = os.path.basename(fpath)
        rel_path = os.path.relpath(fpath, backend_dir)

        if 'route' in rel_path.lower():
            routes.append(rel_path)
        elif 'service' in rel_path.lower():
            services.append(rel_path)

        # Scan for contract method calls
        try:
            with open(fpath, 'r') as f:
                content = f.read()
            for match in re.finditer(r'\.(\w+)\s*\(', content):
                call_name = match.group(1)
                if call_name in contract_methods:
                    backend_calls.append(call_name)
        except (IOError, UnicodeDecodeError):
            pass

    if routes:
        lines.append("### Routes")
        for r in routes[:20]:
            lines.append("- `{}`".format(r))
        lines.append("")

    if services:
        lines.append("### Services")
        for s in services[:10]:
            lines.append("- `{}`".format(s))
        lines.append("")

    if backend_calls:
        lines.append("### Contract Calls")
        for call in sorted(set(backend_calls)):
            lines.append("- `{}`".format(call))
        lines.append("")

    if not routes and not services:
        lines.append("*Backend directory exists but no recognized source files found.*")
        lines.append("")
else:
    lines.append("*Not yet populated. Run backend-dev first.*")
    lines.append("")

# --- Cross-Layer Integrity Checks ---
lines.append("## Cross-Layer Integrity Checks")
lines.append("")

all_calls = set(frontend_calls + backend_calls)
contract_set = set(contract_methods)

if contract_methods:
    # Missing methods: called but not in ABI
    missing = sorted(all_calls - contract_set)
    if missing:
        lines.append("### Missing Methods (called but not in ABI)")
        for m in missing:
            callers = []
            if m in frontend_calls:
                callers.append("frontend")
            if m in backend_calls:
                callers.append("backend")
            lines.append("- `{}` (called by: {})".format(m, ", ".join(callers)))
        lines.append("")

    # Uncalled methods: in ABI but never called
    uncalled = sorted(contract_set - all_calls)
    if uncalled and (frontend_dir or backend_dir):
        lines.append("### Uncalled Methods (in ABI but never called)")
        for m in uncalled:
            lines.append("- `{}`".format(m))
        lines.append("")

    if not missing and not uncalled:
        lines.append("*All contract methods are called. No missing or extra calls detected.*")
        lines.append("")
else:
    lines.append("*No contract ABI available for integrity checks.*")
    lines.append("")

# Truncate to 300 lines
if len(lines) > 300:
    lines = lines[:297]
    lines.append("")
    lines.append("*... truncated to 300 lines ...*")
    lines.append("")

with open(output_path, 'w') as f:
    f.write('\n'.join(lines))
    f.write('\n')

print("Repo map written to {} ({} lines)".format(output_path, len(lines)))
PYEOF
