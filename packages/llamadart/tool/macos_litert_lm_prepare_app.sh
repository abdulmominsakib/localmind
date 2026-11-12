#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:?usage: $0 /path/to/App.app}"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
RUNTIME_DIR="$FRAMEWORKS_DIR/LiteRtLmRuntime"

# The arm64 slice of a universal build needs the runtime even on an Intel
# build Mac, so Xcode's ARCHS decides before the host does.
resolve_litert_arch() {
  local arch="${LLAMADART_LITERT_LM_ARCH:-}"
  if [[ -z "$arch" && -n "${ARCHS:-}" ]]; then
    case " $ARCHS " in
      *" arm64 "*) arch="arm64" ;;
      *) arch="$ARCHS" ;;
    esac
  fi
  arch="${arch:-$(uname -m)}"
  case "$arch" in
    arm64 | aarch64)
      echo "arm64"
      ;;
    x64 | x86_64 | amd64)
      echo "x86_64"
      ;;
    *)
      echo "Unsupported LiteRT-LM macOS architecture: $arch" >&2
      exit 2
      ;;
  esac
}

LITERT_ARCH="$(resolve_litert_arch)"

if [[ "$LITERT_ARCH" == x86_64 ]]; then
  echo "warning: LiteRT-LM is not available on macOS x86_64: litert-lm-native publishes arm64-only macOS runtimes (leehack/litert-lm-native#72). This x86_64-only build gets no LiteRT-LM runtime." >&2
  exit 0
fi

required_libraries() {
  case "$LITERT_ARCH" in
    arm64)
      printf '%s
' \
        "libCLiteRTLM_mac.dylib" \
        "libGemmaModelConstraintProvider.dylib" \
        "libLiteRtLm.dylib" \
        "libwebgpu_dawn.dylib"
      ;;
  esac
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
  case "$LITERT_ARCH" in
    arm64)
      printf '%s
' \
        "LiteRtLm.framework/Versions/A/LiteRtLm" \
        "libCLiteRTLM_mac.dylib" \
        "LiteRtLm.framework/Versions/A/Dependencies/libGemmaModelConstraintProvider.dylib" \
        "libwebgpu_dawn.dylib"
      ;;
  esac
}

has_complete_native_spm_runtime() {
  local file

  [[ -d "$FRAMEWORKS_DIR" ]] || return 1
  while IFS= read -r file; do
    [[ -f "$FRAMEWORKS_DIR/$file" ]] || return 1
  done < <(required_native_spm_files)
}

resolve_litert_dir() {
  if [[ -n "${LLAMADART_LITERT_LM_LIB_DIR:-}" ]]; then
    validate_litert_dir "$LLAMADART_LITERT_LM_LIB_DIR" "explicit"
    echo "$LLAMADART_LITERT_LM_LIB_DIR"
    return
  fi

  local candidates=(
    "$ROOT_DIR/.dart_tool/llamadart/litert_lm/0.19.1-4/macos_$LITERT_ARCH"
    "$ROOT_DIR/.dart_tool/llamadart/litert_lm/0.19.1-4/macos/$LITERT_ARCH"
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

# Signing rewrites the embedded bytes, so freshness is tracked by a digest of
# the prepared sources. The stamp lives beside the bundle to stay outside its
# code signature.
RUNTIME_STAMP="$APP_PATH.litert_lm_runtime.sha256"

source_digest() {
  local source_dir="$1"
  local library

  while IFS= read -r library; do
    shasum -a 256 "$source_dir/$library"
  done < <(required_libraries) | awk '{ print $1 }'
}

embedded_runtime_matches() {
  local source_dir="$1"

  [[ -f "$RUNTIME_STAMP" ]] || return 1
  [[ "$(source_digest "$source_dir")" == "$(cat "$RUNTIME_STAMP")" ]]
}

if [[ "${LLAMADART_FORCE_LITERT_LM_PREPARE:-}" != "1" ]]; then
  if validate_litert_dir "$RUNTIME_DIR"; then
    # An incremental build after a core upgrade must not keep the old runtime.
    if ! PREPARED_DIR="$(resolve_litert_dir 2>/dev/null)" ||
       embedded_runtime_matches "$PREPARED_DIR"; then
      echo "Complete LiteRT-LM runtime detected; skipping legacy macOS runtime copy."
      exit 0
    fi
    echo "Embedded LiteRT-LM runtime is not from $PREPARED_DIR; replacing it."
  elif has_complete_native_spm_runtime; then
    echo "Complete LiteRT-LM runtime detected; skipping legacy macOS runtime copy."
    exit 0
  fi
fi

LITERT_DIR="$(resolve_litert_dir)"

rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"

while IFS= read -r library; do
  install_library "$library"
done < <(required_libraries)

source_digest "$LITERT_DIR" >"$RUNTIME_STAMP"

echo "Prepared LiteRT-LM macOS runtime libraries in $RUNTIME_DIR"
