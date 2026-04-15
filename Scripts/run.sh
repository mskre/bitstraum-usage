#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build.sh"
open "$ROOT/.build/AI Usage Bar.app"
