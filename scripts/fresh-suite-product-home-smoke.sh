#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
moon_bin="${MOON_BIN:-/Users/kq/.moon/bin/moon}"
root="$(mktemp -d "${TMPDIR:-/tmp}/moonclaw-fresh-suite-product-home.XXXXXX")"

cleanup() {
  rm -rf "$root"
}
trap cleanup EXIT

suite_home="$root"
project="$root/books/smoke-project"
product_home="$root/.moonsuite/products/moonclaw"
workspace="$product_home/workspace"
config="$product_home/moonclaw.json"

mkdir -p "$root/.moonsuite" "$root/.tmp" "$project"

run_moonclaw() {
  "$moon_bin" run cmd/main --target native -- "$@"
}

assert_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "expected file missing: $path" >&2
    exit 1
  fi
}

assert_dir() {
  local path="$1"
  if [[ ! -d "$path" ]]; then
    echo "expected directory missing: $path" >&2
    exit 1
  fi
}

assert_absent() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "legacy path should not exist: $path" >&2
    exit 1
  fi
}

assert_contains() {
  local path="$1"
  local needle="$2"
  if ! /usr/bin/grep -Fq "$needle" "$path"; then
    echo "expected $path to contain: $needle" >&2
    exit 1
  fi
}

cd "$repo_root"

run_moonclaw onboard init \
  --home "$suite_home" \
  --cwd "$project" \
  --model "codex/gpt-5.4" \
  --gateway-port 19123 \
  --gateway-token "fresh-suite-smoke-token" >/dev/null

run_moonclaw acp add codex \
  --home "$suite_home" \
  --cwd "$project" \
  --id "codex-smoke" \
  --label "Codex Smoke" \
  --workspace "$workspace" \
  --target-cwd "$project" \
  --model "gpt-5.4" \
  --command "codex" >/dev/null

assert_file "$config"
assert_dir "$workspace"
assert_file "$workspace/IDENTITY.md"
assert_file "$workspace/AGENTS.md"
assert_file "$workspace/USER.md"
assert_file "$workspace/ROUTINES.md"
assert_file "$workspace/MEMORY.md"

assert_contains "$config" "\"primary\": \"codex/gpt-5.4\""
assert_contains "$config" "\"port\": 19123"
assert_contains "$config" "\"token\": \"fresh-suite-smoke-token\""
assert_contains "$config" "\"codex-smoke\""
assert_contains "$config" "\"backend\": \"codex\""
assert_contains "$config" "\"workspace\": \"$workspace\""
assert_contains "$config" "\"cwd\": \"$project\""
assert_contains "$config" "\"command\": \"codex\""
assert_contains "$config" "\"model\": \"gpt-5.4\""

assert_absent "$root/.moonclaw"
assert_absent "$root/moonclaw.json"
assert_absent "$root/moonclaw-jobs"
assert_absent "$root/.moonclaw-worktrees"
assert_absent "$root/.moonclaw-tool-journal"
assert_absent "$project/.moonclaw"
assert_absent "$project/moonclaw.json"

echo "MoonClaw fresh-suite product-home smoke passed on $root"
