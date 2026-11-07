#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAT_APP_DIR="$ROOT_DIR/example/chat_app"
LITERT_MODEL="${LITERT_MODEL:-$ROOT_DIR/.dart_tool/litert_lm_models/gemma-4-E2B-it.litertlm}"
LLAMADART_MODEL_NAME="${LLAMADART_MODEL_NAME:-gemma-4-E2B-it-Q4_K_S.gguf}"
DEFAULT_LLAMADART_MODEL="$ROOT_DIR/models/$LLAMADART_MODEL_NAME"
SIBLING_LLAMADART_MODEL="$(dirname "$ROOT_DIR")/llamadart/models/$LLAMADART_MODEL_NAME"
if [[ ! -f "$DEFAULT_LLAMADART_MODEL" && -f "$SIBLING_LLAMADART_MODEL" ]]; then
  DEFAULT_LLAMADART_MODEL="$SIBLING_LLAMADART_MODEL"
fi
LLAMADART_MODEL="${LLAMADART_MODEL:-$DEFAULT_LLAMADART_MODEL}"
DECODE_TOKENS="${DECODE_TOKENS:-256}"
SPECULATIVE="${SPECULATIVE:-false}"
PROMPT="${PROMPT:-Write a detailed practical guide for product engineers who want to use on-device language models in mobile and desktop apps. Cover privacy, latency, offline behavior, personalization, battery tradeoffs, model format choices, benchmarking methodology, rollout strategy, and failure modes. Use clear paragraphs and continue until the answer is complete.}"

APP="$CHAT_APP_DIR/build/macos/Build/Products/Debug/llamadart_chat_example.app"
MODEL_IN_APP="$APP/Contents/Resources/$(basename "$LITERT_MODEL")"

echo "== llamadart / llama.cpp Metal =="
(
  cd "$ROOT_DIR"
  dart run tool/macos_llamadart_benchmark.dart \
    "$LLAMADART_MODEL" \
    "$PROMPT" \
    "$DECODE_TOKENS"
)

echo
echo "== LiteRT-LM Metal =="
(
  cd "$CHAT_APP_DIR"
  rm -rf \
    "$CHAT_APP_DIR/.dart_tool/flutter_build" \
    "$CHAT_APP_DIR/build/native_assets/macos" \
    "$APP/Contents/Frameworks/LiteRtLmRuntime" \
    "$APP/Contents/Frameworks/LiteRtMetalAccelerator.framework" \
    "$APP/Contents/Frameworks/LiteRtTopKMetalSampler.framework" \
    "$APP/Contents/Frameworks/LiteRtTopKWebGpuSampler.framework" \
    "$APP/Contents/Frameworks/LiteRtWebGpuAccelerator.framework" \
    "$APP/Contents/Frameworks/LiteRt.framework" \
    "$APP/Contents/Frameworks/LiteRtLm.framework" \
    "$APP/Contents/Frameworks/GemmaModelConstraintProvider.framework"

  flutter build macos --debug \
    -t lib/litert_lm_benchmark_app.dart \
    --dart-define=BENCHMARK_AUTO_RUN=true \
    --dart-define="LITERT_LM_MODEL=$MODEL_IN_APP" \
    --dart-define=LLAMADART_MODEL= \
    --dart-define=LITERT_LM_BACKEND=gpu \
    --dart-define="LITERT_LM_SPECULATIVE=$SPECULATIVE" \
    --dart-define=LITERT_LM_RUNS=3 \
    --dart-define=LITERT_LM_WARMUPS=1 \
    --dart-define="LITERT_LM_OUTPUT_TOKENS=$DECODE_TOKENS" \
    --dart-define=LITERT_LM_MAX_TOKENS=4096 \
    --dart-define="LITERT_LM_PROMPT=$PROMPT"

  "$ROOT_DIR/tool/macos_litert_lm_prepare_app.sh" "$APP" >/dev/null
  cp "$LITERT_MODEL" "$MODEL_IN_APP"

  LOG_FILE="$(mktemp -t llamadart_litert_macos.XXXXXX.log)"
  "$APP/Contents/MacOS/llamadart_chat_example" >"$LOG_FILE" 2>&1 &
  APP_PID="$!"
  cleanup() {
    if kill -0 "$APP_PID" 2>/dev/null; then
      kill "$APP_PID" 2>/dev/null || true
    fi
    rm -f "$LOG_FILE"
  }
  trap cleanup EXIT

  NEXT_LINE=1
  DONE=0
  process_new_lines() {
    local chunk
    chunk="$(sed -n "${NEXT_LINE},\$p" "$LOG_FILE")"
    if [[ -n "$chunk" ]]; then
      grep -E 'BENCHMARK: RESULT|BENCHMARK: BENCHMARK_DONE|ERROR|Failed to create engine|RegisterAccelerator' <<<"$chunk" || true
      if grep -Eq 'BENCHMARK: (RESULT litert_lm|BENCHMARK_DONE)' <<<"$chunk"; then
        DONE=1
      fi
    fi
    NEXT_LINE="$(($(wc -l <"$LOG_FILE" | tr -d ' ') + 1))"
  }

  while kill -0 "$APP_PID" 2>/dev/null && [[ "$DONE" -eq 0 ]]; do
    process_new_lines
    sleep 0.2
  done
  process_new_lines
  cleanup
  trap - EXIT
  [[ "$DONE" -eq 1 ]]
)
