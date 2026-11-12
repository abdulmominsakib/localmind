#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
OUT_DIR="${WEBGPU_BRIDGE_OUT_DIR:-$ROOT_DIR/example/chat_app/web/webgpu_bridge}"
ASSETS_REPO="${WEBGPU_BRIDGE_ASSETS_REPO:-leehack/llama-web-bridge-assets}"
ASSETS_TAG="${WEBGPU_BRIDGE_ASSETS_TAG:-v0.1.83}"
CDN_BASE="${WEBGPU_BRIDGE_CDN_BASE:-https://cdn.jsdelivr.net/gh/${ASSETS_REPO}@${ASSETS_TAG}}"
CURL_DOWNLOAD_ARGS=(
  --connect-timeout 15
  --max-time 300
  --retry 3
  --retry-delay 1
  --retry-max-time 600
)

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Downloads prebuilt WebGPU bridge assets into the chat_app web directory.

Default source:
  https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@v0.1.83

Environment variables:
  WEBGPU_BRIDGE_ASSETS_REPO   Asset repo in owner/repo format
  WEBGPU_BRIDGE_ASSETS_TAG    Asset version/tag (recommended: pinned release tag)
  WEBGPU_BRIDGE_CDN_BASE      Full base URL override (advanced)
  WEBGPU_BRIDGE_OUT_DIR       Destination directory

Usage:
  ./scripts/fetch_webgpu_bridge_assets.sh

Examples:
  WEBGPU_BRIDGE_ASSETS_TAG=v0.1.83 ./scripts/fetch_webgpu_bridge_assets.sh
  WEBGPU_BRIDGE_ASSETS_REPO=acme/llama-web-bridge-assets WEBGPU_BRIDGE_ASSETS_TAG=v2 ./scripts/fetch_webgpu_bridge_assets.sh
USAGE
  exit 0
fi

mkdir -p "$OUT_DIR"
downloaded_files=()

mark_downloaded() {
  downloaded_files+=("$1")
}

was_downloaded() {
  local expected="$1"
  local downloaded
  for downloaded in "${downloaded_files[@]}"; do
    if [[ "$downloaded" == "$expected" ]]; then
      return 0
    fi
  done
  return 1
}

download_required() {
  local file_name="$1"
  local source_url="$CDN_BASE/$file_name"
  local target_path="$OUT_DIR/$file_name"

  echo "[webgpu-assets] downloading $source_url"
  curl -fL "${CURL_DOWNLOAD_ARGS[@]}" "$source_url" -o "$target_path"
  mark_downloaded "$file_name"
}

download_optional() {
  local file_name="$1"
  local source_url="$CDN_BASE/$file_name"
  local target_path="$OUT_DIR/$file_name"

  rm -f "$target_path"
  if curl -fsI --connect-timeout 15 --max-time 30 "$source_url" >/dev/null; then
    echo "[webgpu-assets] downloading optional $source_url"
    curl -fL "${CURL_DOWNLOAD_ARGS[@]}" "$source_url" -o "$target_path"
    mark_downloaded "$file_name"
  fi
}

download_required "llama_webgpu_bridge.js"
download_optional "llama_webgpu_bridge_worker.js"
download_optional "llama_webgpu_bridge.d.ts"
download_required "llama_webgpu_core.js"
download_required "llama_webgpu_core.wasm"
download_optional "llama_webgpu_core_mem64.js"
download_optional "llama_webgpu_core_mem64.wasm"
download_optional "manifest.json"
download_optional "sha256sums.txt"

if [[ -f "$OUT_DIR/sha256sums.txt" ]]; then
  echo "[webgpu-assets] verifying checksums"
  (
    cd "$OUT_DIR"

    is_required_checksum_file() {
      case "$1" in
        llama_webgpu_bridge.js|llama_webgpu_core.js|llama_webgpu_core.wasm)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    }

    filtered_sums="$(mktemp)"
    missing_required=0
    while read -r checksum file_name; do
      if [[ -z "${checksum:-}" || -z "${file_name:-}" ]]; then
        continue
      fi

      file_name="${file_name#\*}"

      if was_downloaded "$file_name" && [[ -f "$file_name" ]]; then
        printf '%s  %s\n' "$checksum" "$file_name" >> "$filtered_sums"
      elif is_required_checksum_file "$file_name"; then
        echo "[webgpu-assets] error: checksum lists required asset that was not downloaded: $file_name"
        missing_required=1
      else
        echo "[webgpu-assets] warning: checksum lists optional asset that was not downloaded: $file_name; skipping"
      fi
    done < sha256sums.txt

    if [[ "$missing_required" == "1" ]]; then
      rm -f "$filtered_sums"
      exit 1
    fi

    if [[ ! -s "$filtered_sums" ]]; then
      echo "[webgpu-assets] warning: checksum file did not include any downloaded assets; skipping checksum verification"
    elif command -v sha256sum >/dev/null 2>&1; then
      sha256sum -c "$filtered_sums"
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 -c "$filtered_sums"
    else
      echo "[webgpu-assets] warning: no sha256 tool found; skipping checksum verification"
    fi
    rm -f "$filtered_sums"
  )
fi

if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$OUT_DIR"
    files=(
      "llama_webgpu_bridge.js"
      "llama_webgpu_core.js"
      "llama_webgpu_core.wasm"
    )
    if [[ -f "llama_webgpu_bridge_worker.js" ]]; then
      files+=("llama_webgpu_bridge_worker.js")
    fi
    if [[ -f "llama_webgpu_bridge.d.ts" ]]; then
      files+=("llama_webgpu_bridge.d.ts")
    fi
    if [[ -f "llama_webgpu_core_mem64.js" ]]; then
      files+=("llama_webgpu_core_mem64.js")
    fi
    if [[ -f "llama_webgpu_core_mem64.wasm" ]]; then
      files+=("llama_webgpu_core_mem64.wasm")
    fi

    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "${files[@]}" > sha256sums.txt
    else
      sha256sum "${files[@]}" > sha256sums.txt
    fi
  )
fi

echo "[webgpu-assets] done"
echo "  repo: $ASSETS_REPO"
echo "  tag : $ASSETS_TAG"
echo "  out : $OUT_DIR"
