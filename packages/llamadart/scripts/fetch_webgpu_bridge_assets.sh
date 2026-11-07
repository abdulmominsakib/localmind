#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
OUT_DIR="${WEBGPU_BRIDGE_OUT_DIR:-$ROOT_DIR/example/chat_app/web/webgpu_bridge}"
ASSETS_REPO="${WEBGPU_BRIDGE_ASSETS_REPO:-leehack/llama-web-bridge-assets}"
ASSETS_TAG="${WEBGPU_BRIDGE_ASSETS_TAG:-v0.1.26}"
CDN_BASE="${WEBGPU_BRIDGE_CDN_BASE:-https://cdn.jsdelivr.net/gh/${ASSETS_REPO}@${ASSETS_TAG}}"
PATCH_SAFARI_COMPAT="${WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT:-1}"
MIN_SAFARI_VERSION="${WEBGPU_BRIDGE_MIN_SAFARI_VERSION:-170400}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'USAGE'
Downloads prebuilt WebGPU bridge assets into the chat_app web directory.

Default source:
  https://cdn.jsdelivr.net/gh/leehack/llama-web-bridge-assets@v0.1.26

Environment variables:
  WEBGPU_BRIDGE_ASSETS_REPO   Asset repo in owner/repo format
  WEBGPU_BRIDGE_ASSETS_TAG    Asset version/tag (recommended: pinned release tag)
  WEBGPU_BRIDGE_CDN_BASE      Full base URL override (advanced)
  WEBGPU_BRIDGE_OUT_DIR       Destination directory
  WEBGPU_BRIDGE_PATCH_SAFARI_COMPAT  Patch legacy core for Safari support (1/0)
  WEBGPU_BRIDGE_MIN_SAFARI_VERSION   Packed minimum Safari version (default: 170400)

Usage:
  ./scripts/fetch_webgpu_bridge_assets.sh

Examples:
  WEBGPU_BRIDGE_ASSETS_TAG=v0.1.26 ./scripts/fetch_webgpu_bridge_assets.sh
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
  curl -fL --retry 3 --retry-delay 1 "$source_url" -o "$target_path"
  mark_downloaded "$file_name"
}

download_optional() {
  local file_name="$1"
  local source_url="$CDN_BASE/$file_name"
  local target_path="$OUT_DIR/$file_name"

  rm -f "$target_path"
  if curl -fsI "$source_url" >/dev/null; then
    echo "[webgpu-assets] downloading optional $source_url"
    curl -fL --retry 3 --retry-delay 1 "$source_url" -o "$target_path"
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

if [[ "$PATCH_SAFARI_COMPAT" == "1" ]]; then
  CORE_JS="$OUT_DIR/llama_webgpu_core.js"
  BRIDGE_JS="$OUT_DIR/llama_webgpu_bridge.js"
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[webgpu-assets] warning: python3 not found; skipping Safari compatibility patch"
  elif [[ -f "$CORE_JS" ]]; then
    echo "[webgpu-assets] applying Safari compatibility patch (min=$MIN_SAFARI_VERSION)"
    python3 - "$CORE_JS" "$MIN_SAFARI_VERSION" <<'PY'
from pathlib import Path
import re
import sys

core_path = Path(sys.argv[1])
min_safari = int(sys.argv[2])
text = core_path.read_text(errors='ignore')
original = text

unsupported_guard = (
    'if(currentSafariVersion<TARGET_NOT_SUPPORTED){throw new Error(`This page was '
    'compiled without support for Safari browser. Pass -sMIN_SAFARI_VERSION='
    '${currentSafariVersion} or lower to enable support for this browser.`)}'
)
if unsupported_guard in text:
    text = text.replace(unsupported_guard, '', 1)

pattern = re.compile(
    r'if\(currentSafariVersion<\d+\)\{throw new Error\(`This emscripten-generated '
    r'code requires Safari v\$\{packedVersionToHumanReadable\(\d+\)\} '
    r'\(detected v\$\{currentSafariVersion\}\)`\)\}'
)
replacement = (
    f'if(currentSafariVersion<{min_safari}){{throw new Error(`This emscripten-generated '
    f'code requires Safari v${{packedVersionToHumanReadable({min_safari})}} '
    f'(detected v${{currentSafariVersion}})`)}}'
)
text, _ = pattern.subn(replacement, text, count=1)

if text != original:
    core_path.write_text(text)
PY
  fi

  if [[ -f "$BRIDGE_JS" ]]; then
    echo "[webgpu-assets] applying stream chunk copy compatibility patch"
    python3 - "$BRIDGE_JS" <<'PY'
from pathlib import Path
import re
import sys

bridge_path = Path(sys.argv[1])
text = bridge_path.read_text(errors='ignore')
original = text

pattern = re.compile(r'chunks\.push\(value\);\s*loaded \+= value\.length;')
replacement = (
    'const chunk = value.slice ? value.slice() : new Uint8Array(value);\n'
    '    chunks.push(chunk);\n'
    '    loaded += chunk.length;'
)
text, _ = pattern.subn(replacement, text, count=1)

if text != original:
    bridge_path.write_text(text)
PY
  fi
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
