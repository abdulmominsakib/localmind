#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAT_APP_DIR="$ROOT_DIR/example/chat_app"
PORT="${PORT:-7358}"
DEFAULT_PLAYWRIGHT_PYTHON="$ROOT_DIR/.dart_tool/playwright-python/bin/python"
if [[ -n "${PYTHON_BIN:-}" ]]; then
  PYTHON_BIN="$PYTHON_BIN"
elif [[ -x "$DEFAULT_PLAYWRIGHT_PYTHON" ]]; then
  PYTHON_BIN="$DEFAULT_PLAYWRIGHT_PYTHON"
else
  PYTHON_BIN="python3"
fi
DECODE_TOKENS="${DECODE_TOKENS:-256}"
CONTEXT_SIZE="${CONTEXT_SIZE:-4096}"
WARMUPS="${WARMUPS:-1}"
RUNS="${RUNS:-3}"
TARGETS="${TARGETS:-llamadart,litert_lm}"
THREADS="${THREADS:-2}"
THREAD_POOL_SIZE="${THREAD_POOL_SIZE:-2}"
LLAMADART_GPU_LAYERS="${LLAMADART_GPU_LAYERS:-99}"
LITERT_GPU_LAYERS="${LITERT_GPU_LAYERS:-999}"
LOAD_TIMEOUT_MS="${LOAD_TIMEOUT_MS:-2400000}"
RESPONSE_TIMEOUT_MS="${RESPONSE_TIMEOUT_MS:-1200000}"
PROMPT="${PROMPT:-Write a detailed practical guide for product engineers who want to use on-device language models in mobile and desktop apps. Cover privacy, latency, offline behavior, personalization, battery tradeoffs, model format choices, benchmarking methodology, rollout strategy, and failure modes. Use clear paragraphs and continue until the answer is complete.}"

target_enabled() {
  case ",$TARGETS," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

LLAMADART_MODEL_NAME="${LLAMADART_MODEL_NAME:-gemma-4-E2B-it-Q4_K_S.gguf}"
DEFAULT_LLAMADART_MODEL="$ROOT_DIR/models/$LLAMADART_MODEL_NAME"
SIBLING_LLAMADART_MODEL="$(dirname "$ROOT_DIR")/llamadart/models/$LLAMADART_MODEL_NAME"
if [[ ! -f "$DEFAULT_LLAMADART_MODEL" && -f "$SIBLING_LLAMADART_MODEL" ]]; then
  DEFAULT_LLAMADART_MODEL="$SIBLING_LLAMADART_MODEL"
fi
LLAMADART_MODEL="${LLAMADART_MODEL:-$DEFAULT_LLAMADART_MODEL}"

LITERT_WEB_MODEL_URL="${LITERT_WEB_MODEL_URL:-https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it-web.litertlm?download=true}"
LITERT_WEB_MODEL="${LITERT_WEB_MODEL:-$ROOT_DIR/.dart_tool/litert_lm_models/gemma-4-E2B-it-web.litertlm}"
DOWNLOAD_LITERT_WEB_MODEL="${DOWNLOAD_LITERT_WEB_MODEL:-0}"

if target_enabled llamadart && [[ ! -f "$LLAMADART_MODEL" ]]; then
  echo "GGUF model not found: $LLAMADART_MODEL" >&2
  exit 2
fi

if ! "$PYTHON_BIN" -c "import playwright" >/dev/null 2>&1; then
  echo "Python Playwright package not found for PYTHON_BIN=$PYTHON_BIN" >&2
  echo "Run the local web smoke setup first, or set PYTHON_BIN to a Python with Playwright installed." >&2
  exit 2
fi

if [[ "$DOWNLOAD_LITERT_WEB_MODEL" == "1" && ! -f "$LITERT_WEB_MODEL" ]]; then
  mkdir -p "$(dirname "$LITERT_WEB_MODEL")"
  curl -L --fail --retry 5 --retry-all-errors --retry-delay 3 \
    --continue-at - "$LITERT_WEB_MODEL_URL" -o "$LITERT_WEB_MODEL"
fi

echo "== Preparing web benchmark =="
if target_enabled llamadart; then
  echo "  GGUF: $LLAMADART_MODEL"
else
  echo "  GGUF: skipped"
fi
if [[ -f "$LITERT_WEB_MODEL" ]]; then
  echo "  LiteRT-LM web: $LITERT_WEB_MODEL"
else
  echo "  LiteRT-LM web: $LITERT_WEB_MODEL_URL"
fi
echo "  runs/warmups: $RUNS/$WARMUPS"
echo "  output/context tokens: $DECODE_TOKENS/$CONTEXT_SIZE"
echo "  GGUF/LiteRT GPU layers: $LLAMADART_GPU_LAYERS/$LITERT_GPU_LAYERS"
echo "  targets: $TARGETS"

(
  cd "$ROOT_DIR"
  ./scripts/fetch_webgpu_bridge_assets.sh >/dev/null
)

(
  cd "$CHAT_APP_DIR"
  flutter build web --base-href=/example/chat_app/build/web/
)

MODEL_DIR="$ROOT_DIR/.dart_tool/web_benchmark_models"
mkdir -p "$MODEL_DIR"
if target_enabled llamadart; then
  ln -sf "$LLAMADART_MODEL" "$MODEL_DIR/$(basename "$LLAMADART_MODEL")"
  LLAMADART_MODEL_URL="http://127.0.0.1:$PORT/.dart_tool/web_benchmark_models/$(basename "$LLAMADART_MODEL")"
fi

if [[ -f "$LITERT_WEB_MODEL" ]]; then
  ln -sf "$LITERT_WEB_MODEL" "$MODEL_DIR/$(basename "$LITERT_WEB_MODEL")"
  LITERT_WEB_BENCHMARK_URL="http://127.0.0.1:$PORT/.dart_tool/web_benchmark_models/$(basename "$LITERT_WEB_MODEL")"
else
  LITERT_WEB_BENCHMARK_URL="$LITERT_WEB_MODEL_URL"
fi

SERVER_LOG="$(mktemp -t llamadart_web_benchmark_server.XXXXXX.log)"
"$PYTHON_BIN" "$ROOT_DIR/tool/testing/serve_static_with_headers.py" \
  --directory "$ROOT_DIR" \
  --port "$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"
cleanup() {
  if kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -f "$SERVER_LOG"
}
trap cleanup EXIT

for _ in $(seq 1 150); do
  if "$PYTHON_BIN" - "$PORT" <<'PY' >/dev/null 2>&1
import socket
import sys

with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.2):
    pass
PY
  then
    break
  fi
  sleep 0.2
done

APP_URL="http://127.0.0.1:$PORT/example/chat_app/build/web/"

echo
if target_enabled llamadart; then
  echo "== Web llama.cpp / GGUF WebGPU =="
  "$PYTHON_BIN" "$ROOT_DIR/tool/testing/playwright_chat_app_benchmark.py" \
    "$APP_URL" \
    --label "web_llamacpp_gguf_webgpu" \
    --model-url "$LLAMADART_MODEL_URL" \
    --response-source bridge \
    --backend-index 0 \
    --gpu-layers "$LLAMADART_GPU_LAYERS" \
    --context-size "$CONTEXT_SIZE" \
    --max-tokens "$DECODE_TOKENS" \
    --warmups "$WARMUPS" \
    --runs "$RUNS" \
    --threads "$THREADS" \
    --thread-pool-size "$THREAD_POOL_SIZE" \
    --load-timeout-ms "$LOAD_TIMEOUT_MS" \
    --response-timeout-ms "$RESPONSE_TIMEOUT_MS" \
    --mem64 \
    --prompt "$PROMPT"
else
  echo "== Skipping web llama.cpp / GGUF WebGPU =="
fi

echo
if target_enabled litert_lm; then
  echo "== Web LiteRT-LM / WebGPU =="
  "$PYTHON_BIN" "$ROOT_DIR/tool/testing/playwright_chat_app_benchmark.py" \
    "$APP_URL" \
    --label "web_litert_lm_webgpu" \
    --model-url "$LITERT_WEB_BENCHMARK_URL" \
    --response-source litert \
    --backend-index 2 \
    --gpu-layers "$LITERT_GPU_LAYERS" \
    --context-size "$CONTEXT_SIZE" \
    --max-tokens "$DECODE_TOKENS" \
    --warmups "$WARMUPS" \
    --runs "$RUNS" \
    --threads "$THREADS" \
    --thread-pool-size "$THREAD_POOL_SIZE" \
    --load-timeout-ms "$LOAD_TIMEOUT_MS" \
    --response-timeout-ms "$RESPONSE_TIMEOUT_MS" \
    --prompt "$PROMPT"
else
  echo "== Skipping web LiteRT-LM / WebGPU =="
fi

cleanup
trap - EXIT
