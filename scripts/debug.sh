#!/usr/bin/env bash
set -euo pipefail

SONA_DIR="sona-live"

if [[ ! -d "$SONA_DIR" ]]; then
  echo "❌ Directory '$SONA_DIR' not found."
  exit 1
fi

echo "🚀 Running mkarchiso with debug options..."
sudo mkarchiso -v -w work -o out "$SONA_DIR"
