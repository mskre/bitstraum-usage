#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="$HOME/Applications"
APP_NAME="AI Usage Bar.app"

"$ROOT/Scripts/build.sh"
rm -rf "$TARGET_DIR/$APP_NAME"
cp -R "$ROOT/.build/$APP_NAME" "$TARGET_DIR/$APP_NAME"

printf "Installed %s/%s\n" "$TARGET_DIR" "$APP_NAME"
