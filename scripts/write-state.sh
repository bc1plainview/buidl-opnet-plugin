#!/bin/bash
# write-state.sh — Atomic state writer for The Loop
#
# Two modes:
#   1. Full write (stdin):  echo "yaml content" | bash write-state.sh
#   2. Partial update:      bash write-state.sh key=value [key=value ...]
#
# Targets .claude/loop/state.yaml (or override via STATE_FILE env var).
# Writes to a temp file, then atomically renames into place.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
STATE_FILE="${STATE_FILE:-$PROJECT_DIR/.claude/loop/state.yaml}"

# Ensure parent directory exists
mkdir -p "$(dirname "$STATE_FILE")"

TMP_FILE="${STATE_FILE}.tmp.$$"

# Cleanup on any exit
trap 'rm -f "$TMP_FILE"' EXIT

# Cross-platform sed -i
sedi() {
  if [[ "$OSTYPE" == darwin* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

if [[ $# -eq 0 ]]; then
  # ── Full write mode: read YAML from stdin ──
  cat > "$TMP_FILE"
  mv "$TMP_FILE" "$STATE_FILE"
elif [[ "$1" == "--nested" ]]; then
  # ── Nested YAML update mode: uses Python for safe nested key writes ──
  # Usage: write-state.sh --nested key.path=value [key.path=value ...]
  shift
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: State file does not exist: $STATE_FILE" >&2
    echo "Cannot do nested update on a missing file. Use full-write mode first." >&2
    exit 1
  fi

  cp "$STATE_FILE" "$TMP_FILE"

  # Build Python script for all updates
  PYTHON_SCRIPT='
import sys, os

def load_yaml_simple(path):
    """Simple YAML loader for flat and one-level nested structures."""
    result = {}
    current_parent = None
    with open(path, "r") as f:
        for line in f:
            stripped = line.rstrip("\n")
            if not stripped or stripped.startswith("#"):
                continue
            # Nested key (2-space indented)
            if stripped.startswith("  ") and current_parent is not None:
                key_val = stripped.strip()
                if ": " in key_val:
                    k, v = key_val.split(": ", 1)
                elif key_val.endswith(":"):
                    k, v = key_val[:-1], ""
                else:
                    continue
                if current_parent not in result or not isinstance(result[current_parent], dict):
                    result[current_parent] = {}
                result[current_parent][k] = v
            else:
                # Top-level key
                if ": " in stripped:
                    k, v = stripped.split(": ", 1)
                    result[k] = v
                    current_parent = k
                elif stripped.endswith(":"):
                    k = stripped[:-1]
                    result[k] = {}
                    current_parent = k
                else:
                    current_parent = None
    return result

def dump_yaml_simple(data, path):
    """Simple YAML dumper preserving flat and one-level nested structures."""
    with open(path, "w") as f:
        for k, v in data.items():
            if isinstance(v, dict):
                f.write(f"{k}:\n")
                for nk, nv in v.items():
                    f.write(f"  {nk}: {nv}\n")
            else:
                f.write(f"{k}: {v}\n")

tmp = sys.argv[1]
updates = sys.argv[2:]

data = load_yaml_simple(tmp)

for update in updates:
    eq_pos = update.index("=")
    key_path = update[:eq_pos]
    value = update[eq_pos+1:]
    parts = key_path.split(".")
    if len(parts) == 1:
        data[parts[0]] = value
    elif len(parts) == 2:
        parent, child = parts
        if parent not in data or not isinstance(data[parent], dict):
            data[parent] = {}
        data[parent][child] = value
    else:
        print(f"ERROR: Nesting deeper than 2 levels not supported: {key_path}", file=sys.stderr)
        sys.exit(1)

dump_yaml_simple(data, tmp)
'

  python3 -c "$PYTHON_SCRIPT" "$TMP_FILE" "$@"
  mv "$TMP_FILE" "$STATE_FILE"
else
  # ── Partial update mode: key=value pairs (flat keys only) ──
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "ERROR: State file does not exist: $STATE_FILE" >&2
    echo "Cannot do partial update on a missing file. Use full-write mode first." >&2
    exit 1
  fi

  cp "$STATE_FILE" "$TMP_FILE"

  for arg in "$@"; do
    KEY="${arg%%=*}"
    VALUE="${arg#*=}"
    if [[ "$KEY" == "$arg" ]]; then
      echo "ERROR: Invalid argument '$arg'. Use key=value format." >&2
      exit 1
    fi
    # Replace the line matching ^key: with new value
    # Handles YAML scalars (top-level keys only)
    if grep -q "^${KEY}:" "$TMP_FILE"; then
      sedi "s|^${KEY}:.*|${KEY}: ${VALUE}|" "$TMP_FILE"
    else
      # Key doesn't exist — append it
      echo "${KEY}: ${VALUE}" >> "$TMP_FILE"
    fi
  done

  mv "$TMP_FILE" "$STATE_FILE"
fi
