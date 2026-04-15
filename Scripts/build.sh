#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT/.build"
OUTPUT_BIN="$OUTPUT_DIR/AIUsageBar"
APP_NAME="Bitstraum Usage.app"
APP_DIR="$OUTPUT_DIR/$APP_NAME"
APP_CONTENTS="$APP_DIR/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

mkdir -p "$OUTPUT_DIR"

swiftc \
  -framework AppKit \
  -framework SwiftUI \
  -framework WebKit \
  "$ROOT"/Sources/AIUsageBar/*.swift \
  -o "$OUTPUT_BIN"

printf "Built %s\n" "$OUTPUT_BIN"

mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$ROOT/Resources/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$OUTPUT_BIN" "$APP_MACOS/AIUsageBar"
chmod +x "$APP_MACOS/AIUsageBar"

printf "Bundled %s\n" "$APP_DIR"

# Ad-hoc code sign
codesign --force --deep --sign - "$APP_DIR"
printf "Signed %s\n" "$APP_DIR"
