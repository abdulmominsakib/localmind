#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <native-lib-dir> <lib-name> [<lib-name> ...]" >&2
  echo "Example: $0 .dart_tool/lib libggml-cuda.so libggml-hip.so" >&2
  exit 2
fi

lib_dir="$1"
shift

if [[ ! -d "$lib_dir" ]]; then
  echo "Library directory not found: $lib_dir" >&2
  exit 2
fi

if ! command -v ldd >/dev/null 2>&1; then
  echo "Required tool not found: ldd" >&2
  exit 2
fi

status=0
for lib_name in "$@"; do
  lib_path="$lib_dir/$lib_name"
  if [[ ! -f "$lib_path" ]]; then
    echo "[skip] $lib_name (not present)"
    continue
  fi

  echo "## $lib_name"
  missing="$(
    LD_LIBRARY_PATH="$lib_dir:${LD_LIBRARY_PATH:-}" \
      ldd "$lib_path" | grep 'not found' || true
  )"
  if [[ -n "$missing" ]]; then
    echo "$missing"
    status=1
  else
    echo "OK"
  fi
done

exit "$status"
