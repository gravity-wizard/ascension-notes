#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/swift"

echo "==> Running AscensionCore Swift tests..."
(cd "$SWIFT_DIR" && swift test)

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Generating Xcode project via XcodeGen..."
  (cd "$SWIFT_DIR" && xcodegen generate)
  echo "==> Opening AscensionNotes.xcodeproj in Xcode..."
  open "$SWIFT_DIR/AscensionNotes.xcodeproj"
else
  echo "==> xcodegen not found (install via 'brew install xcodegen' for iOS .xcodeproj)."
  echo "==> Opening Swift Package directly in Xcode..."
  open "$SWIFT_DIR/Package.swift"
fi
