#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <app-url> <expected-commit-sha>" >&2
  exit 64
fi

APP_URL="${1%/}"
EXPECTED_SHA="$2"
BUILD_INFO_URL="$APP_URL/llamadart-build.json"
MAX_ATTEMPTS="${CHAT_APP_DEPLOY_VERIFY_ATTEMPTS:-30}"
RETRY_SECONDS="${CHAT_APP_DEPLOY_VERIFY_RETRY_SECONDS:-10}"

matched=0
for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
  build_info="$(curl -fsSL "$BUILD_INFO_URL?attempt=$attempt" 2>/dev/null || true)"
  if [[ "$build_info" == *"\"commit\":\"$EXPECTED_SHA\""* ]]; then
    matched=1
    break
  fi
  echo "[chat-app-web] waiting for deployed commit $EXPECTED_SHA ($attempt/$MAX_ATTEMPTS)"
  sleep "$RETRY_SECONDS"
done

if [[ "$matched" != "1" ]]; then
  echo "[chat-app-web] error: deployed build did not reach commit $EXPECTED_SHA" >&2
  exit 1
fi

required_urls=(
  "$APP_URL/"
  "$APP_URL/flutter_bootstrap.js"
  "$APP_URL/main.dart.js"
  "$APP_URL/webgpu_bridge/llama_webgpu_bridge.js"
  "$APP_URL/webgpu_bridge/llama_webgpu_bridge_worker.js"
  "$APP_URL/webgpu_bridge/llama_webgpu_core.js"
  "$APP_URL/webgpu_bridge/llama_webgpu_core.wasm"
  "$APP_URL/webgpu_bridge/llama_webgpu_core_mem64.js"
  "$APP_URL/webgpu_bridge/llama_webgpu_core_mem64.wasm"
)

for asset_url in "${required_urls[@]}"; do
  curl -fsSLI "$asset_url?commit=$EXPECTED_SHA" >/dev/null
done

headers="$(curl -fsSLI "$APP_URL/?commit=$EXPECTED_SHA")"
for expected_header in \
  'cross-origin-embedder-policy: require-corp' \
  'cross-origin-opener-policy: same-origin'; do
  if ! grep -qi "^$expected_header" <<<"$headers"; then
    echo "[chat-app-web] error: missing deployment header: $expected_header" >&2
    exit 1
  fi
done

echo "[chat-app-web] verified deployed commit and runtime assets: $EXPECTED_SHA"
