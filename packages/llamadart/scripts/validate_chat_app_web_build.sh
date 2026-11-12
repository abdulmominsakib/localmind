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

manifest_json="$(tr -d '\r\n' < "$BRIDGE_DIR/manifest.json")"
manifest_tag="$(sed -nE \
  's/.*"bridge_assets_tag":[[:space:]]*"([^"]+)".*/\1/p' \
  <<<"$manifest_json")"
manifest_llama_cpp_tag="$(sed -nE \
  's/.*"llama_cpp_tag":[[:space:]]*"([^"]+)".*/\1/p' \
  <<<"$manifest_json")"
bootstrap_tag="$(sed -nE \
  "s/^[[:space:]]*const defaultBridgeAssetsTag = '([^']+)';.*$/\1/p" \
  "$BUILD_DIR/index.html")"
bootstrap_llama_cpp_tag="$(sed -nE \
  "s/^[[:space:]]*const defaultBridgeLlamaCppTag = '([^']+)';.*$/\1/p" \
  "$BUILD_DIR/index.html")"

if [[ -z "$manifest_tag" || -z "$manifest_llama_cpp_tag" ]]; then
  echo "[chat-app-web] error: bridge manifest is missing version provenance" >&2
  exit 1
fi

if [[ -z "$bootstrap_tag" || -z "$bootstrap_llama_cpp_tag" ]]; then
  echo "[chat-app-web] error: chat app bootstrap is missing bridge version provenance" >&2
  exit 1
fi

if [[ "$bootstrap_tag" != "$manifest_tag" ]]; then
  echo "[chat-app-web] error: bootstrap bridge tag '$bootstrap_tag' does not match manifest '$manifest_tag'" >&2
  exit 1
fi

if [[ "$bootstrap_llama_cpp_tag" != "$manifest_llama_cpp_tag" ]]; then
  echo "[chat-app-web] error: bootstrap llama.cpp tag '$bootstrap_llama_cpp_tag' does not match manifest '$manifest_llama_cpp_tag'" >&2
  exit 1
fi

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
