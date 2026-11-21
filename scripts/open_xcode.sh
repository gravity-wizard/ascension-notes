#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/swift"

echo "==> Opening Ascension Notes in Xcode..."
open "$SWIFT_DIR/Package.swift"

