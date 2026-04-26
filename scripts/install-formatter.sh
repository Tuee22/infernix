#!/usr/bin/env sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
build_root=${INFERNIX_BUILD_ROOT:-"$repo_root/.build"}
tools_root="$build_root/haskell-style-tools"
cache_root="$tools_root/cache"
bin_root="$tools_root/bin"

mkdir -p "$cache_root" "$bin_root"

system_name=$(uname -s)
machine_name=$(uname -m)

case "$machine_name" in
  aarch64) machine_name=arm64 ;;
  amd64) machine_name=x86_64 ;;
esac

case "$system_name:$machine_name" in
  Darwin:arm64)
    ormolu_url="https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-aarch64-darwin.zip"
    ormolu_archive="$cache_root/ormolu-aarch64-darwin.zip"
    hlint_url="https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-osx.tar.gz"
    hlint_archive="$cache_root/hlint-3.10-x86_64-osx.tar.gz"
    ;;
  Darwin:x86_64)
    ormolu_url="https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-x86_64-darwin.zip"
    ormolu_archive="$cache_root/ormolu-x86_64-darwin.zip"
    hlint_url="https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-osx.tar.gz"
    hlint_archive="$cache_root/hlint-3.10-x86_64-osx.tar.gz"
    ;;
  Linux:x86_64)
    ormolu_url="https://github.com/tweag/ormolu/releases/download/0.8.0.2/ormolu-x86_64-linux.zip"
    ormolu_archive="$cache_root/ormolu-x86_64-linux.zip"
    hlint_url="https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-linux.tar.gz"
    hlint_archive="$cache_root/hlint-3.10-x86_64-linux.tar.gz"
    ;;
  *)
    echo "install-formatter: no repo-owned formatter bootstrap is configured for $system_name $machine_name" >&2
    exit 1
    ;;
esac

download_if_missing() {
  url=$1
  target=$2
  if [ ! -f "$target" ]; then
    curl -fsSL "$url" -o "$target"
  fi
}

download_if_missing "$ormolu_url" "$ormolu_archive"
download_if_missing "$hlint_url" "$hlint_archive"

if [ ! -x "$bin_root/ormolu" ]; then
  if ! command -v unzip >/dev/null 2>&1; then
    echo "install-formatter: unzip is required to extract ormolu" >&2
    exit 1
  fi
  unzip -o "$ormolu_archive" ormolu '*.dylib' -d "$bin_root" >/dev/null
  chmod +x "$bin_root/ormolu"
fi

if [ ! -x "$bin_root/hlint" ]; then
  temp_dir=$(mktemp -d)
  trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM
  tar -xzf "$hlint_archive" -C "$temp_dir"
  hlint_path=$(find "$temp_dir" -type f -name hlint | head -n 1)
  if [ -z "$hlint_path" ]; then
    echo "install-formatter: $hlint_archive did not contain an hlint executable" >&2
    exit 1
  fi
  install "$hlint_path" "$bin_root/hlint"
  chmod +x "$bin_root/hlint"
  rm -rf "$temp_dir"
  trap - EXIT HUP INT TERM
fi
