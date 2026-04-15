#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.build"
APP_NAME="Bitstraum Usage.app"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")}"
ASSET_NAME="BitstraumUsage-${VERSION}.zip"

zsh "$ROOT/Scripts/build.sh"
rm -f "$OUTPUT_DIR/$ASSET_NAME"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT_DIR/$APP_NAME" "$OUTPUT_DIR/$ASSET_NAME"

printf "Packaged %s\n" "$OUTPUT_DIR/$ASSET_NAME"
