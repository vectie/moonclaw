#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:-"$repo_root/dist"}
version=${MOONCLAW_RELEASE_VERSION:-$(sed -n 's/^version = "\([^"]*\)"/\1/p' "$repo_root/moon.mod" | head -n 1)}
release_base_url=${MOONCLAW_RELEASE_BASE_URL:-"https://github.com/vectie/moonclaw/releases/download/v$version"}
system_name=$(uname -s)
machine_name=$(uname -m)

case "$system_name" in
  Darwin) platform=macos ;;
  Linux) platform=linux ;;
  *)
    echo "unsupported release platform: $system_name" >&2
    exit 1
    ;;
esac

case "$machine_name" in
  arm64|aarch64) architecture=arm64 ;;
  x86_64|amd64) architecture=x86_64 ;;
  *)
    echo "unsupported release architecture: $machine_name" >&2
    exit 1
    ;;
esac

asset_name="moonclaw-$version-$platform-$architecture.tar.gz"
stage_dir="$out_dir/.moonclaw-$version-$platform-$architecture"
archive_path="$out_dir/$asset_name"
manifest_path="$out_dir/release-manifest.json"
checksums_path="$out_dir/checksums.txt"

mkdir -p "$out_dir"
rm -rf "$stage_dir"
mkdir -p "$stage_dir"

python3 "$repo_root/scripts/buildinfo.py"
moon -C "$repo_root" build cmd/main --target native --release
binary_path="$repo_root/_build/native/release/build/vectie/moonclaw/cmd/main/main.exe"
if [ ! -x "$binary_path" ]; then
  echo "MoonClaw release binary was not produced at $binary_path" >&2
  exit 1
fi

install -m 0755 "$binary_path" "$stage_dir/moonclaw"
if [ -n "${MOONCLAW_CODESIGN_IDENTITY:-}" ] && [ "$platform" = macos ]; then
  codesign --force --options runtime --timestamp --sign "$MOONCLAW_CODESIGN_IDENTITY" "$stage_dir/moonclaw"
fi

tar -C "$stage_dir" -czf "$archive_path" moonclaw
checksum=$(shasum -a 256 "$archive_path" | awk '{print $1}')
printf '%s  %s\n' "$checksum" "$asset_name" > "$checksums_path"

python3 - "$manifest_path" "$version" "$platform" "$architecture" "$asset_name" "$checksum" "$release_base_url" <<'PY'
import json
import sys

path, version, platform, architecture, name, sha256, base_url = sys.argv[1:]
payload = {
    "schema": "moonclaw-release-manifest.v1",
    "version": version,
    "assets": [
        {
            "platform": platform,
            "architecture": architecture,
            "name": name,
            "url": f"{base_url}/{name}",
            "sha256": sha256,
            "binary": "moonclaw",
        }
    ],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY

rm -rf "$stage_dir"
printf '%s\n' "$archive_path" "$manifest_path" "$checksums_path"
