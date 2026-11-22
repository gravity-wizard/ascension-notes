#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_DIR="$ROOT_DIR/swift"
APP_BUNDLE="$SWIFT_DIR/.build/AscensionNotes.app"
BIN_PATH="$SWIFT_DIR/.build/debug/AscensionNotesApp"

echo "==> Building Ascension Notes App (no Xcode needed)..."
cd "$SWIFT_DIR"
swift build --product AscensionNotesApp

echo "==> Bundling & bringing Ascension Notes to foreground..."
killall AscensionNotesApp 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/AscensionNotesApp"
chmod +x "$APP_BUNDLE/Contents/MacOS/AscensionNotesApp"

# Copy SwiftPM resource bundles if present
for bundle in "$SWIFT_DIR/.build/debug/"*.bundle; do
  if [[ -d "$bundle" ]]; then
    cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
  fi
done

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>AscensionNotesApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.gravitywizard.AscensionNotes</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Ascension Notes</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open -n "$APP_BUNDLE"
