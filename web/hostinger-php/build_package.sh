#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$WEB_DIR/dist/FrmAnTsiTeam"

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/lib" "$OUT_DIR/data/uploads"

cp -R "$WEB_DIR/public/"* "$OUT_DIR/"
cp "$SCRIPT_DIR/config.php" "$OUT_DIR/config.php"
cp "$SCRIPT_DIR/api.php" "$OUT_DIR/api.php"
cp "$SCRIPT_DIR/image.php" "$OUT_DIR/image.php"
cp "$SCRIPT_DIR/.htaccess" "$OUT_DIR/.htaccess"
cp "$SCRIPT_DIR/lib/bootstrap.php" "$OUT_DIR/lib/bootstrap.php"
chmod 755 "$OUT_DIR/data" "$OUT_DIR/data/uploads"

if command -v zip >/dev/null 2>&1; then
  rm -f "$WEB_DIR/dist/FrmAnTsiTeam.zip"
  (cd "$OUT_DIR" && zip -qr "../FrmAnTsiTeam.zip" .)
fi

echo "Built Hostinger FrmAnTsiTeam bundle at: $OUT_DIR"
