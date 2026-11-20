#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/swift"

# Prefer full Xcode over CommandLineTools so XCTest & SwiftUI frameworks resolve
if [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  CURRENT_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$CURRENT_DEV_DIR" != "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    echo "==> Using Xcode toolchain ($DEVELOPER_DIR)"
  fi
fi

echo "==> Running AscensionCore Swift tests..."
if ! (cd "$SWIFT_DIR" && swift test); then
  echo "⚠️  CLI 'swift test' failed (if xcode-select points to CommandLineTools, run:"
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer)"
  echo "==> Continuing to open Xcode anyway (run Cmd+U inside Xcode to test)..."
fi

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Generating Xcode project via XcodeGen..."
  (cd "$SWIFT_DIR" && xcodegen generate)
  echo "==> Opening AscensionNotes.xcodeproj in Xcode..."
  open "$SWIFT_DIR/AscensionNotes.xcodeproj"
else
  echo "==> Opening Swift Package directly in Xcode..."
  open "$SWIFT_DIR/Package.swift"
fi
