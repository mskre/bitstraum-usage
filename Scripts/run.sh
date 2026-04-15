#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Bitstraum Usage.app"

zsh "$ROOT/Scripts/build.sh"
open "$ROOT/.build/$APP_NAME"
