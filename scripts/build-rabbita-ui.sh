#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
ui_dir="$repo_root/ui/rabbita-job"

echo "[rabbita] formatting MoonBit UI package"
moon -C "$ui_dir" fmt

echo "[rabbita] checking MoonBit UI package"
moon -C "$ui_dir" check

echo "[rabbita] updating package interface"
moon -C "$ui_dir" info

echo "[rabbita] building Vite bundle"
npm --prefix "$ui_dir" run build

echo "[rabbita] build complete"
