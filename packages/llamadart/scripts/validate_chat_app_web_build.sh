#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
BUILD_DIR="${1:-$ROOT_DIR/example/chat_app/build/web}"
BRIDGE_DIR="$BUILD_DIR/webgpu_bridge"

required_files=(
  "index.html"
  "flutter_bootstrap.js"
  "main.dart.js"
  "webgpu_bridge/llama_webgpu_bridge.js"
  "webgpu_bridge/llama_webgpu_bridge_worker.js"
  "webgpu_bridge/llama_webgpu_core.js"
  "webgpu_bridge/llama_webgpu_core.wasm"
  "webgpu_bridge/llama_webgpu_core_mem64.js"
  "webgpu_bridge/llama_webgpu_core_mem64.wasm"
  "webgpu_bridge/manifest.json"
  "webgpu_bridge/sha256sums.txt"
)

for relative_path in "${required_files[@]}"; do
  if [[ ! -s "$BUILD_DIR/$relative_path" ]]; then
    echo "[chat-app-web] error: missing or empty build asset: $relative_path" >&2
    exit 1
  fi
done

for wasm_file in \
  "$BRIDGE_DIR/llama_webgpu_core.wasm" \
  "$BRIDGE_DIR/llama_webgpu_core_mem64.wasm"; do
  magic="$(od -An -tx1 -N4 "$wasm_file" | tr -d '[:space:]')"
  if [[ "$magic" != "0061736d" ]]; then
    echo "[chat-app-web] error: invalid WebAssembly magic bytes: $wasm_file" >&2
    exit 1
  fi
done

(
  cd "$BRIDGE_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c sha256sums.txt
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -c sha256sums.txt
  else
    echo "[chat-app-web] error: sha256sum or shasum is required" >&2
    exit 1
  fi
)

echo "[chat-app-web] validated build artifact: $BUILD_DIR"
