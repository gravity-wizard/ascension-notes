#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/swift"

echo "==> Building and launching Ascension Notes App..."
cd "$SWIFT_DIR"
swift run AscensionNotesApp
