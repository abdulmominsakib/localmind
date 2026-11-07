#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${ROOT_DIR}/example/chat_app"
WEB_BUILD_DIR="${APP_DIR}/build/web"

PORT="${PLAYWRIGHT_GATE_PORT:-7357}"
PYTHON_BIN="${PLAYWRIGHT_PYTHON:-python3}"
CHANNEL="${PLAYWRIGHT_CHANNEL:-chrome}"

CPU_FIRST_TOKEN_MAX_MS="${CPU_MM_FIRST_TOKEN_MAX_MS:-120000}"
CPU_INFER_MAX_MS="${CPU_MM_INFER_MAX_MS:-240000}"
WEBGPU_FIRST_TOKEN_MAX_MS="${WEBGPU_MM_FIRST_TOKEN_MAX_MS:-30000}"
WEBGPU_INFER_MAX_MS="${WEBGPU_MM_INFER_MAX_MS:-180000}"
MIN_TOKENS="${MM_MIN_TOKENS:-0}"

if [[ "${LLAMADART_SKIP_WEB_BUILD:-0}" != "1" ]]; then
  echo "[gate] building chat_app web bundle"
  (
    cd "${APP_DIR}"
    flutter build web
  )
fi

if [[ ! -f "${WEB_BUILD_DIR}/index.html" ]]; then
  echo "[gate] missing built web bundle at ${WEB_BUILD_DIR}" >&2
  exit 1
fi

SERVER_LOG="$(mktemp -t llamadart-mm-gate-server.XXXXXX.log)"
"${PYTHON_BIN}" \
  "${ROOT_DIR}/tool/testing/serve_static_with_headers.py" \
  --port "${PORT}" \
  --directory "${WEB_BUILD_DIR}" >"${SERVER_LOG}" 2>&1 &
SERVER_PID=$!

cleanup() {
  if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -f "${SERVER_LOG}"
}
trap cleanup EXIT

"${PYTHON_BIN}" - "${PORT}" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
deadline = time.time() + 30.0
while time.time() < deadline:
    with socket.socket() as sock:
        sock.settimeout(0.5)
        try:
            sock.connect(("127.0.0.1", port))
            raise SystemExit(0)
        except OSError:
            time.sleep(0.2)

sys.stderr.write(f"Timed out waiting for local server on port {port}\n")
raise SystemExit(1)
PY

common_args=(
  "http://127.0.0.1:${PORT}"
  --channel "${CHANNEL}"
  --model-timeout-ms 600000
  --mmproj-timeout-ms 360000
  --infer-timeout-ms 420000
  --n-predict 192
)

if [[ "${MIN_TOKENS}" =~ ^[0-9]+$ ]] && [[ "${MIN_TOKENS}" -gt 0 ]]; then
  common_args+=(--min-token-count "${MIN_TOKENS}")
fi

if [[ -n "${QWEN_MM_IMAGE_PATH:-}" ]]; then
  common_args+=(--image-path "${QWEN_MM_IMAGE_PATH}")
else
  common_args+=(--expect-text "HELLO")
fi

echo "[gate] running CPU multimodal regression check"
"${PYTHON_BIN}" "${ROOT_DIR}/tool/testing/playwright_qwen_cpu_multimodal_smoke.py" \
  "${common_args[@]}" \
  --n-gpu-layers 0 \
  --media-max-image-pixels 307200 \
  --media-max-image-edge 768 \
  --expect-n-gpu-layers 0 \
  --max-first-token-latency-ms "${CPU_FIRST_TOKEN_MAX_MS}" \
  --max-inference-ms "${CPU_INFER_MAX_MS}"

echo "[gate] running WebGPU multimodal regression check"
"${PYTHON_BIN}" "${ROOT_DIR}/tool/testing/playwright_qwen_cpu_multimodal_smoke.py" \
  "${common_args[@]}" \
  --n-gpu-layers 99 \
  --expect-n-gpu-layers 99 \
  --max-first-token-latency-ms "${WEBGPU_FIRST_TOKEN_MAX_MS}" \
  --max-inference-ms "${WEBGPU_INFER_MAX_MS}"

echo "[gate] multimodal regression checks passed"
