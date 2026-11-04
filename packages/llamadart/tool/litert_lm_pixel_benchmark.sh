#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/example/chat_app"
BENCHMARK_TARGET="$APP_DIR/lib/litert_lm_benchmark_app.dart"
APP_ID="com.example.llamadart_chat_example"
MODEL_NAME="${MODEL_NAME:-gemma-4-E2B-it.litertlm}"
MODEL_URL="${MODEL_URL:-https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/$MODEL_NAME}"
LOCAL_MODEL="${LOCAL_MODEL:-$ROOT_DIR/.dart_tool/litert_lm_models/$MODEL_NAME}"
DEVICE_APP_FILES_DIR="${DEVICE_APP_FILES_DIR:-/data/user/0/$APP_ID/files}"
DEVICE_MODEL="${DEVICE_MODEL:-$DEVICE_APP_FILES_DIR/$MODEL_NAME}"
LLAMADART_MODEL_NAME="${LLAMADART_MODEL_NAME:-gemma-4-E2B-it-Q4_K_S.gguf}"
DEFAULT_LLAMADART_MODEL="$ROOT_DIR/models/$LLAMADART_MODEL_NAME"
SIBLING_LLAMADART_MODEL="$(dirname "$ROOT_DIR")/llamadart/models/$LLAMADART_MODEL_NAME"
if [[ ! -f "$DEFAULT_LLAMADART_MODEL" && -f "$SIBLING_LLAMADART_MODEL" ]]; then
  DEFAULT_LLAMADART_MODEL="$SIBLING_LLAMADART_MODEL"
fi
LOCAL_LLAMADART_MODEL="${LOCAL_LLAMADART_MODEL:-$DEFAULT_LLAMADART_MODEL}"
DEVICE_LLAMADART_MODEL="${DEVICE_LLAMADART_MODEL:-$DEVICE_APP_FILES_DIR/$LLAMADART_MODEL_NAME}"
LLAMADART_DRAFT_MODEL_NAME="${LLAMADART_DRAFT_MODEL_NAME:-mtp-gemma-4-E2B-it.gguf}"
DEFAULT_LLAMADART_DRAFT_MODEL="$ROOT_DIR/models/$LLAMADART_DRAFT_MODEL_NAME"
SIBLING_LLAMADART_DRAFT_MODEL="$(dirname "$ROOT_DIR")/llamadart/models/$LLAMADART_DRAFT_MODEL_NAME"
if [[ ! -f "$DEFAULT_LLAMADART_DRAFT_MODEL" && -f "$SIBLING_LLAMADART_DRAFT_MODEL" ]]; then
  DEFAULT_LLAMADART_DRAFT_MODEL="$SIBLING_LLAMADART_DRAFT_MODEL"
fi
LOCAL_LLAMADART_DRAFT_MODEL="${LOCAL_LLAMADART_DRAFT_MODEL:-$DEFAULT_LLAMADART_DRAFT_MODEL}"
DEVICE_LLAMADART_DRAFT_MODEL="${DEVICE_LLAMADART_DRAFT_MODEL:-$DEVICE_APP_FILES_DIR/$LLAMADART_DRAFT_MODEL_NAME}"
BACKEND="${BACKEND:-gpu}"
LLAMADART_BACKEND="${LLAMADART_BACKEND:-auto}"
TARGETS="${TARGETS:-litert_lm,llamadart}"
RUNS="${RUNS:-3}"
WARMUPS="${WARMUPS:-1}"
OUTPUT_TOKENS="${OUTPUT_TOKENS:-256}"
MAX_TOKENS="${MAX_TOKENS:-4096}"
SPECULATIVE="${SPECULATIVE:-false}"
PROMPT="${PROMPT:-Write a detailed practical guide for product engineers who want to use on-device language models in mobile and desktop apps. Cover privacy, latency, offline behavior, personalization, battery tradeoffs, model format choices, benchmarking methodology, rollout strategy, and failure modes. Use clear paragraphs and continue until the answer is complete.}"
if [[ -n "${LOG_TIMEOUT:-}" ]]; then
  LITERT_LM_LOG_TIMEOUT="${LITERT_LM_LOG_TIMEOUT:-$LOG_TIMEOUT}"
  LLAMADART_LOG_TIMEOUT="${LLAMADART_LOG_TIMEOUT:-$LOG_TIMEOUT}"
  BOTH_LOG_TIMEOUT="${BOTH_LOG_TIMEOUT:-$LOG_TIMEOUT}"
else
  LITERT_LM_LOG_TIMEOUT="${LITERT_LM_LOG_TIMEOUT:-1200}"
  LLAMADART_LOG_TIMEOUT="${LLAMADART_LOG_TIMEOUT:-3600}"
  BOTH_LOG_TIMEOUT="${BOTH_LOG_TIMEOUT:-4800}"
fi
FAIL_IF_GGUF_MISSING="${FAIL_IF_GGUF_MISSING:-0}"

ADB="${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"
if [[ ! -x "$ADB" ]]; then
  echo "adb not found. Set ADB=/path/to/adb or ANDROID_HOME." >&2
  exit 2
fi

DEVICE="${DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$("$ADB" devices -l | awk '$2 == "device" { print $1; exit }')"
fi
if [[ -z "$DEVICE" ]]; then
  echo "No Android device found. Set DEVICE=<adb serial> if needed." >&2
  "$ADB" devices -l
  exit 2
fi

if [[ ! -f "$BENCHMARK_TARGET" ]]; then
  echo "Benchmark app target not found: $BENCHMARK_TARGET" >&2
  exit 2
fi

mkdir -p "$(dirname "$LOCAL_MODEL")"
if [[ ! -f "$LOCAL_MODEL" ]]; then
  echo "Downloading $MODEL_URL"
  curl -L --fail --retry 5 --retry-all-errors --retry-delay 3 --continue-at - "$MODEL_URL" -o "$LOCAL_MODEL"
fi

LLAMADART_MODEL_DEFINE=""
if [[ -f "$LOCAL_LLAMADART_MODEL" ]]; then
  LLAMADART_MODEL_DEFINE="$DEVICE_LLAMADART_MODEL"
else
  echo "Skipping GGUF benchmark; file not found: $LOCAL_LLAMADART_MODEL" >&2
  if [[ "$FAIL_IF_GGUF_MISSING" == "1" ]]; then
    exit 2
  fi
fi
LLAMADART_DRAFT_MODEL_DEFINE=""
if [[ "$SPECULATIVE" == "true" && -f "$LOCAL_LLAMADART_DRAFT_MODEL" ]]; then
  LLAMADART_DRAFT_MODEL_DEFINE="$DEVICE_LLAMADART_DRAFT_MODEL"
elif [[ "$SPECULATIVE" == "true" ]]; then
  echo "No GGUF draft model found for speculative llama.cpp: $LOCAL_LLAMADART_DRAFT_MODEL" >&2
fi

echo "Benchmark configuration:"
echo "  device: $DEVICE"
echo "  targets: $TARGETS"
echo "  backend: $BACKEND"
echo "  llama.cpp backend: $LLAMADART_BACKEND"
echo "  speculative: $SPECULATIVE"
echo "  runs/warmups: $RUNS/$WARMUPS"
echo "  output/max tokens: $OUTPUT_TOKENS/$MAX_TOKENS"
echo "  log timeouts: LiteRT-LM=${LITERT_LM_LOG_TIMEOUT}s llamadart=${LLAMADART_LOG_TIMEOUT}s both=${BOTH_LOG_TIMEOUT}s"
echo "  LiteRT-LM model: $LOCAL_MODEL -> $DEVICE_MODEL"
if [[ -n "$LLAMADART_MODEL_DEFINE" ]]; then
  echo "  GGUF model: $LOCAL_LLAMADART_MODEL -> $DEVICE_LLAMADART_MODEL"
  if [[ -n "$LLAMADART_DRAFT_MODEL_DEFINE" ]]; then
    echo "  GGUF draft model: $LOCAL_LLAMADART_DRAFT_MODEL -> $DEVICE_LLAMADART_DRAFT_MODEL"
  fi
else
  echo "  GGUF model: unavailable"
fi

push_app_file() {
  local local_path="$1"
  local file_name="$2"
  local local_bytes
  local device_bytes
  local_bytes="$(wc -c <"$local_path" | tr -d ' ')"
  device_bytes="$("$ADB" -s "$DEVICE" shell "run-as '$APP_ID' stat -c%s 'files/$file_name' 2>/dev/null" | tr -d '\r' || true)"
  if [[ "$device_bytes" == "$local_bytes" ]]; then
    echo "$file_name already present in app files; skipping push."
    return
  fi
  "$ADB" -s "$DEVICE" shell "run-as '$APP_ID' rm -f 'files/$file_name'"
  "$ADB" -s "$DEVICE" shell "run-as '$APP_ID' sh -c 'cat > files/$file_name'" <"$local_path"
}

build_install_and_push() {
  local target="$1"
  local litert_model_define=""
  local llamadart_model_define=""
  local llamadart_draft_model_define=""

  case "$target" in
    litert_lm)
      litert_model_define="$DEVICE_MODEL"
      ;;
    llamadart)
      if [[ -z "$LLAMADART_MODEL_DEFINE" ]]; then
        echo "Skipping llamadart target; no GGUF model is available." >&2
        return 1
      fi
      llamadart_model_define="$DEVICE_LLAMADART_MODEL"
      llamadart_draft_model_define="$LLAMADART_DRAFT_MODEL_DEFINE"
      ;;
    both)
      litert_model_define="$DEVICE_MODEL"
      llamadart_model_define="$LLAMADART_MODEL_DEFINE"
      llamadart_draft_model_define="$LLAMADART_DRAFT_MODEL_DEFINE"
      ;;
    *)
      echo "Unknown TARGETS entry: $target" >&2
      return 1
      ;;
  esac

  echo "Building benchmark APK target=$target backend=$BACKEND"
  (
    cd "$APP_DIR"
    flutter build apk --debug \
      -t lib/litert_lm_benchmark_app.dart \
      --dart-define=BENCHMARK_AUTO_RUN=true \
      --dart-define="LITERT_LM_MODEL=$litert_model_define" \
      --dart-define="LLAMADART_MODEL=$llamadart_model_define" \
      --dart-define="LLAMADART_DRAFT_MODEL=$llamadart_draft_model_define" \
      --dart-define="LITERT_LM_BACKEND=$BACKEND" \
      --dart-define="LLAMADART_BACKEND=$LLAMADART_BACKEND" \
      --dart-define="LITERT_LM_SPECULATIVE=$SPECULATIVE" \
      --dart-define="LITERT_LM_RUNS=$RUNS" \
      --dart-define="LITERT_LM_WARMUPS=$WARMUPS" \
      --dart-define="LITERT_LM_OUTPUT_TOKENS=$OUTPUT_TOKENS" \
      --dart-define="LITERT_LM_MAX_TOKENS=$MAX_TOKENS" \
      --dart-define="LITERT_LM_PROMPT=$PROMPT"
  )

  echo "Installing APK on $DEVICE"
  "$ADB" -s "$DEVICE" install -r "$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"

  "$ADB" -s "$DEVICE" shell "run-as '$APP_ID' mkdir -p files"
  if [[ -n "$litert_model_define" ]]; then
    echo "Pushing model to $DEVICE_MODEL"
    push_app_file "$LOCAL_MODEL" "$MODEL_NAME"
  fi
  if [[ -n "$llamadart_model_define" ]]; then
    echo "Pushing GGUF model to $DEVICE_LLAMADART_MODEL"
    push_app_file "$LOCAL_LLAMADART_MODEL" "$LLAMADART_MODEL_NAME"
  fi
  if [[ -n "$llamadart_draft_model_define" ]]; then
    echo "Pushing GGUF draft model to $DEVICE_LLAMADART_DRAFT_MODEL"
    push_app_file "$LOCAL_LLAMADART_DRAFT_MODEL" "$LLAMADART_DRAFT_MODEL_NAME"
  fi
}

run_installed_benchmark() {
  local target="$1"
  local timeout="$BOTH_LOG_TIMEOUT"
  local log_file
  local logcat_pid
  log_file="$(mktemp -t llamadart_litert_pixel.XXXXXX.log)"

  case "$target" in
    litert_lm)
      timeout="$LITERT_LM_LOG_TIMEOUT"
      ;;
    llamadart)
      timeout="$LLAMADART_LOG_TIMEOUT"
      ;;
  esac

  "$ADB" -s "$DEVICE" shell am force-stop "$APP_ID" || true
  "$ADB" -s "$DEVICE" logcat -c
  "$ADB" -s "$DEVICE" logcat -s flutter:I '*:S' >"$log_file" &
  logcat_pid="$!"
  cleanup_logcat() {
    if kill -0 "$logcat_pid" 2>/dev/null; then
      kill "$logcat_pid" 2>/dev/null || true
      wait "$logcat_pid" 2>/dev/null || true
    fi
    rm -f "$log_file"
  }

  echo "Launching benchmark app target=$target"
  "$ADB" -s "$DEVICE" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1

  echo "Capturing benchmark logs until BENCHMARK_DONE"
  local next_line=1
  local done=0
  local failed=0
  local start_seconds
  start_seconds="$(date +%s)"
  process_new_lines() {
    local chunk
    chunk="$(sed -n "${next_line},\$p" "$log_file")"
    if [[ -n "$chunk" ]]; then
      grep -E 'BENCHMARK: RESULT|BENCHMARK: BENCHMARK_DONE|ERROR|Failed to create engine|RegisterAccelerator' <<<"$chunk" || true
      if grep -q 'BENCHMARK: ERROR' <<<"$chunk"; then
        failed=1
      fi
      if grep -q 'BENCHMARK: BENCHMARK_DONE' <<<"$chunk"; then
        done=1
      fi
    fi
    next_line="$(($(wc -l <"$log_file" | tr -d ' ') + 1))"
  }

  while [[ "$done" -eq 0 ]]; do
    process_new_lines
    local now_seconds
    now_seconds="$(date +%s)"
    if ((now_seconds - start_seconds >= timeout)); then
      echo "Timed out waiting for BENCHMARK_DONE after ${timeout}s" >&2
      cleanup_logcat
      return 1
    fi
    if ((now_seconds - start_seconds > 5)); then
      local app_pid
      app_pid="$("$ADB" -s "$DEVICE" shell pidof "$APP_ID" | tr -d '\r' || true)"
      if [[ -z "$app_pid" ]]; then
        echo "Benchmark app process exited before BENCHMARK_DONE." >&2
        cleanup_logcat
        return 1
      fi
    fi
    sleep 1
  done
  process_new_lines
  cleanup_logcat
  if [[ "$failed" -ne 0 ]]; then
    echo "Benchmark app reported an error." >&2
    return 1
  fi
  return 0
}

status=0
IFS=',' read -r -a target_array <<<"$TARGETS"
for target in "${target_array[@]}"; do
  target="${target//[[:space:]]/}"
  if [[ -z "$target" ]]; then
    continue
  fi
  if ! build_install_and_push "$target"; then
    status=1
    continue
  fi
  if ! run_installed_benchmark "$target"; then
    status=1
  fi
done
exit "$status"
