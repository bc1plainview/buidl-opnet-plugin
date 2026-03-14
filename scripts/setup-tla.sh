#!/bin/bash
# setup-tla.sh — One-time setup: downloads TLC model checker (tla2tools.jar)
# TLC is the official TLA+ model checker by Lamport's team at Microsoft Research
# It's a single JAR, no install required beyond Java
#
# Usage: bash scripts/setup-tla.sh
#
# Exit codes:
#   0 — Success
#   1 — Java not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TLA_DIR="$SCRIPT_DIR/tools/tla"
JAR_URL="https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar"

mkdir -p "$TLA_DIR"

if [[ ! -f "$TLA_DIR/tla2tools.jar" ]]; then
    echo "Downloading TLC model checker..."
    curl -L "$JAR_URL" -o "$TLA_DIR/tla2tools.jar"
    echo "TLC downloaded to $TLA_DIR/tla2tools.jar"
else
    echo "TLC already present at $TLA_DIR/tla2tools.jar"
fi

# Verify Java is available
if ! command -v java &>/dev/null; then
    echo "WARNING: Java not found. TLA+ verification requires Java 11+." >&2
    echo "Install with: apt-get install -y default-jre" >&2
    exit 1
fi

echo "TLA+ setup complete."
