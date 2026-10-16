#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export XDG_DATA_HOME="${XDG_DATA_HOME:-$PWD/.local/data}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$PWD/.local/config}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$PWD/.local/cache}"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
exec "${GODOT_BIN:-godot4}" --path "$PWD" "$@"
