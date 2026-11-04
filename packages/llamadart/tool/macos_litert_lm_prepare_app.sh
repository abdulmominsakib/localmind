#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:?usage: $0 /path/to/App.app}"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
RUNTIME_DIR="$FRAMEWORKS_DIR/LiteRtLmRuntime"

resolve_litert_arch() {
  local arch="${LLAMADART_LITERT_LM_ARCH:-$(uname -m)}"
  case "$arch" in
    arm64 | aarch64)
      echo "arm64"
      ;;
    x64 | x86_64 | amd64)
      echo "x64"
      ;;
    *)
      echo "Unsupported LiteRT-LM macOS architecture: $arch" >&2
      exit 2
      ;;
  esac
}

LITERT_ARCH="$(resolve_litert_arch)"

required_libraries() {
  printf '%s\n' \
    "libCLiteRTLM_mac.dylib" \
    "libLiteRtLm.dylib"
}

validate_litert_dir() {
  local candidate="$1"
  local mode="${2:-candidate}"
  local missing=()
  local library

  [[ -d "$candidate" ]] || return 1
  while IFS= read -r library; do
    if [[ ! -f "$candidate/$library" ]]; then
      missing+=("$library")
    fi
  done < <(required_libraries)

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "$mode" == "explicit" ]]; then
    echo "LiteRT-LM macOS $LITERT_ARCH library directory is incomplete: $candidate" >&2
    echo "Missing required runtime libraries:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 2
  fi
  return 1
}

required_native_spm_files() {
  printf '%s\n' \
    "LiteRtLm.framework/Versions/A/LiteRtLm" \
    "libCLiteRTLM_mac.dylib"
}

has_complete_native_spm_runtime() {
  local file

  [[ -d "$FRAMEWORKS_DIR" ]] || return 1
  while IFS= read -r file; do
    [[ -f "$FRAMEWORKS_DIR/$file" ]] || return 1
  done < <(required_native_spm_files)
}

has_complete_embedded_runtime() {
  validate_litert_dir "$RUNTIME_DIR" && return 0
  has_complete_native_spm_runtime
}

resolve_litert_dir() {
  if [[ -n "${LLAMADART_LITERT_LM_LIB_DIR:-}" ]]; then
    validate_litert_dir "$LLAMADART_LITERT_LM_LIB_DIR" "explicit"
    echo "$LLAMADART_LITERT_LM_LIB_DIR"
    return
  fi

  local candidates=(
    "$ROOT_DIR/.dart_tool/llamadart/litert_lm/0.15.0-native.3/macos_$LITERT_ARCH"
    "$ROOT_DIR/.dart_tool/llamadart/litert_lm/0.15.0-native.3/macos/$LITERT_ARCH"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if validate_litert_dir "$candidate"; then
      echo "$candidate"
      return
    fi
  done

  echo "No complete LiteRT-LM macOS $LITERT_ARCH library directory found." >&2
  exit 2
}

sign_if_needed() {
  local target="$1"
  if ! file "$target" | grep -q "Mach-O"; then
    return
  fi

  local identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
  if [[ -z "$identity" ]]; then
    identity="-"
  fi
  codesign --force --sign "$identity" --timestamp=none "$target" >/dev/null
}

install_library() {
  local library="$1"
  local target="$RUNTIME_DIR/$library"

  cp "$LITERT_DIR/$library" "$target"
  chmod +x "$target"
  sign_if_needed "$target"
}

if [[ "${LLAMADART_FORCE_LITERT_LM_PREPARE:-}" != "1" ]] && \
   has_complete_embedded_runtime; then
  echo "Complete LiteRT-LM runtime detected; skipping legacy macOS runtime copy."
  exit 0
fi

LITERT_DIR="$(resolve_litert_dir)"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

while IFS= read -r library; do
  install_library "$library"
done < <(required_libraries)

echo "Prepared LiteRT-LM macOS runtime libraries in $RUNTIME_DIR"
