#!/usr/bin/env python3
import argparse
import base64
from pathlib import Path
from typing import Any

from playwright_qwen_harness import (
    DEFAULT_APP_URL,
    DEFAULT_MODEL_URL,
    DEFAULT_MMPROJ_URL,
    print_json_result,
    run_bridge_evaluation,
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_url", nargs="?", default=DEFAULT_APP_URL)
    parser.add_argument("model_url", nargs="?", default=DEFAULT_MODEL_URL)
    parser.add_argument("mmproj_url", nargs="?", default=DEFAULT_MMPROJ_URL)
    parser.add_argument("--model-timeout-ms", type=int, default=8 * 60 * 1000)
    parser.add_argument("--mmproj-timeout-ms", type=int, default=5 * 60 * 1000)
    parser.add_argument("--infer-timeout-ms", type=int, default=5 * 60 * 1000)
    parser.add_argument("--n-predict", type=int, default=192)
    parser.add_argument("--n-gpu-layers", type=int, default=0)
    parser.add_argument("--n-threads", type=int, default=4)
    parser.add_argument("--image-path", type=str, default="")
    parser.add_argument("--media-max-image-pixels", type=int, default=0)
    parser.add_argument("--media-max-image-edge", type=int, default=0)
    parser.add_argument("--max-first-token-latency-ms", type=int, default=0)
    parser.add_argument("--max-inference-ms", type=int, default=0)
    parser.add_argument("--min-token-count", type=int, default=0)
    parser.add_argument("--expect-text", type=str, default="")
    parser.add_argument("--expect-n-gpu-layers", type=int, default=-1)
    parser.add_argument("--channel", type=str, default="chromium")
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()

    app_url = args.app_url
    model_url = args.model_url
    mmproj_url = args.mmproj_url
    image_path = args.image_path.strip()

    image_bytes_base64: str | None = None
    image_file_name: str | None = None
    if image_path:
        image_file = Path(image_path).expanduser()
        if not image_file.exists() or not image_file.is_file():
            raise FileNotFoundError(f"Image file not found: {image_file}")

        image_bytes = image_file.read_bytes()
        if not image_bytes:
            raise ValueError(f"Image file is empty: {image_file}")

        image_bytes_base64 = base64.b64encode(image_bytes).decode("ascii")
        image_file_name = image_file.name

    print("[e2e] opening app", flush=True)
    payload = run_bridge_evaluation(
        app_url=app_url,
        channel=args.channel,
        headed=args.headed,
        default_timeout_ms=0,
        echo_console=True,
        evaluate_script=
            """
            async ({ modelUrl, mmprojUrl, modelTimeoutMs, mmprojTimeoutMs, inferTimeoutMs, nPredict, nGpuLayers, nThreads, imageBytesBase64, imageFileName, mediaMaxImagePixels, mediaMaxImageEdge }) => {
              const withTimeout = (promise, ms, label) =>
                Promise.race([
                  promise,
                  new Promise((_, reject) =>
                    setTimeout(() => reject(new Error(`${label} timeout (${ms}ms)`)), ms),
                  ),
                ]);

              const bridge = new window.LlamaWebGpuBridge({
                workerUrl:
                  typeof window.__llamadartBridgeWorkerUrl === 'string'
                    ? window.__llamadartBridgeWorkerUrl
                    : undefined,
                coreModuleUrl:
                  typeof window.__llamadartBridgeCoreModuleUrl === 'string'
                    ? window.__llamadartBridgeCoreModuleUrl
                    : undefined,
                coreModuleUrlMem64:
                  typeof window.__llamadartBridgeCoreModuleUrlMem64 === 'string'
                    ? window.__llamadartBridgeCoreModuleUrlMem64
                    : undefined,
                wasmUrl:
                  typeof window.__llamadartBridgeWasmUrl === 'string'
                    ? window.__llamadartBridgeWasmUrl
                    : undefined,
                wasmUrlMem64:
                  typeof window.__llamadartBridgeWasmUrlMem64 === 'string'
                    ? window.__llamadartBridgeWasmUrlMem64
                    : undefined,
                preferMemory64: window.__llamadartBridgePreferMemory64 === true,
                threadPoolSize:
                  Number.isFinite(Number(window.__llamadartBridgeThreadPoolSize))
                    ? Number(window.__llamadartBridgeThreadPoolSize)
                    : undefined,
                logLevel: 3,
              });

              const timings = {};
              try {
                const loadStart = performance.now();
                await withTimeout(
                  bridge.loadModelFromUrl(modelUrl, {
                    nCtx: 4096,
                    nGpuLayers,
                    nThreads,
                    useCache: true,
                    remoteFetchThresholdBytes: 9000000000000,
                  }),
                  modelTimeoutMs,
                  'loadModelFromUrl',
                );
                timings.modelLoadMs = Math.round(performance.now() - loadStart);

                const mmprojStart = performance.now();
                await withTimeout(
                  bridge.loadMultimodalProjector(mmprojUrl),
                  mmprojTimeoutMs,
                  'loadMultimodalProjector',
                );
                timings.mmprojLoadMs = Math.round(performance.now() - mmprojStart);

                const decodeBase64ToUint8Array = (value) => {
                  const binary = atob(value);
                  const out = new Uint8Array(binary.length);
                  for (let i = 0; i < binary.length; i += 1) {
                    out[i] = binary.charCodeAt(i);
                  }
                  return out;
                };

                let imageBytes = null;
                let imageSource = 'synthetic';
                if (typeof imageBytesBase64 === 'string' && imageBytesBase64.length > 0) {
                  imageBytes = decodeBase64ToUint8Array(imageBytesBase64);
                  imageSource = imageFileName || 'provided';
                }

                if (!imageBytes) {
                  const canvas = document.createElement('canvas');
                  canvas.width = 320;
                  canvas.height = 180;
                  const ctx = canvas.getContext('2d');
                  ctx.fillStyle = '#0f172a';
                  ctx.fillRect(0, 0, canvas.width, canvas.height);
                  ctx.fillStyle = '#22d3ee';
                  ctx.fillRect(16, 16, 288, 148);
                  ctx.fillStyle = '#111827';
                  ctx.font = 'bold 42px sans-serif';
                  ctx.fillText('HELLO', 80, 108);

                  const blob = await new Promise((resolve, reject) => {
                    canvas.toBlob((value) => {
                      if (value) {
                        resolve(value);
                        return;
                      }
                      reject(new Error('toBlob failed'));
                    }, 'image/png');
                  });
                  imageBytes = new Uint8Array(await blob.arrayBuffer());
                }

                const inferStart = performance.now();
                let tokenCount = 0;
                let firstTokenAtMs = null;
                const output = await withTimeout(
                  bridge.createCompletion(
                    'what do you see?',
                    {
                      nPredict,
                      temp: 0.0,
                      topK: 1,
                      topP: 1.0,
                      penalty: 1.0,
                      seed: 42,
                      onToken: () => {
                        if (firstTokenAtMs === null) {
                          firstTokenAtMs = performance.now() - inferStart;
                        }
                        tokenCount += 1;
                      },
                      parts: [{ type: 'image', bytes: imageBytes }],
                      mediaMaxImagePixels:
                        Number.isFinite(Number(mediaMaxImagePixels)) && Number(mediaMaxImagePixels) > 0
                          ? Number(mediaMaxImagePixels)
                          : undefined,
                      mediaMaxImageEdge:
                        Number.isFinite(Number(mediaMaxImageEdge)) && Number(mediaMaxImageEdge) > 0
                          ? Number(mediaMaxImageEdge)
                          : undefined,
                    },
                  ),
                  inferTimeoutMs,
                  'createCompletion',
                );
                timings.inferenceMs = Math.round(performance.now() - inferStart);
                const outputText = String(output || '');
                const trimmedOutput = outputText.trim();

                const metadata =
                  typeof bridge.getModelMetadata === 'function'
                    ? bridge.getModelMetadata() || {}
                    : {};

                if (tokenCount <= 0 || trimmedOutput.length == 0) {
                  return {
                    ok: false,
                    error: 'CPU multimodal returned no visible tokens.',
                    version: window.__llamadartBridgeLocalVersion || null,
                    coi: window.crossOriginIsolated,
                    timings,
                    metadata: {
                      execution: metadata['llamadart.webgpu.execution'] || null,
                      fallbackReason: metadata['llamadart.webgpu.worker_fallback_reason'] || null,
                      mmprojLoaded: metadata['llamadart.webgpu.mmproj_loaded'] || null,
                      supportsVision: metadata['llamadart.webgpu.supports_vision'] || null,
                      nGpuLayers: metadata['llamadart.webgpu.n_gpu_layers'] || null,
                      runtimeNotes: metadata['llamadart.webgpu.runtime_notes'] || null,
                    },
                    debug: {
                      tokenCount,
                      firstTokenLatencyMs:
                        firstTokenAtMs === null ? null : Math.round(firstTokenAtMs),
                      nGpuLayers,
                      nThreads,
                      imageBytes: imageBytes.length,
                      imageSource,
                      mediaMaxImagePixels,
                      mediaMaxImageEdge,
                      rawOutput: outputText.slice(0, 120),
                    },
                  };
                }

                return {
                  ok: true,
                  version: window.__llamadartBridgeLocalVersion || null,
                  coi: window.crossOriginIsolated,
                  output: outputText.slice(0, 280),
                  outputFull: outputText,
                  tokenCount,
                  timings,
                  debug: {
                    firstTokenLatencyMs:
                      firstTokenAtMs === null ? null : Math.round(firstTokenAtMs),
                    nGpuLayers,
                    nThreads,
                    imageBytes: imageBytes.length,
                    imageSource,
                    mediaMaxImagePixels,
                    mediaMaxImageEdge,
                  },
                  metadata: {
                    execution: metadata['llamadart.webgpu.execution'] || null,
                    fallbackReason: metadata['llamadart.webgpu.worker_fallback_reason'] || null,
                    mmprojLoaded: metadata['llamadart.webgpu.mmproj_loaded'] || null,
                    supportsVision: metadata['llamadart.webgpu.supports_vision'] || null,
                    nGpuLayers: metadata['llamadart.webgpu.n_gpu_layers'] || null,
                    runtimeNotes: metadata['llamadart.webgpu.runtime_notes'] || null,
                  },
                };
              } catch (error) {
                const metadata =
                  typeof bridge.getModelMetadata === 'function'
                    ? bridge.getModelMetadata() || {}
                    : {};
                return {
                  ok: false,
                  error: String(error),
                  version: window.__llamadartBridgeLocalVersion || null,
                  coi: window.crossOriginIsolated,
                  timings,
                  metadata: {
                    execution: metadata['llamadart.webgpu.execution'] || null,
                    fallbackReason: metadata['llamadart.webgpu.worker_fallback_reason'] || null,
                    mmprojLoaded: metadata['llamadart.webgpu.mmproj_loaded'] || null,
                    supportsVision: metadata['llamadart.webgpu.supports_vision'] || null,
                    runtimeNotes: metadata['llamadart.webgpu.runtime_notes'] || null,
                  },
                };
              } finally {
                try {
                  await bridge.dispose();
                } catch (_) {
                  // best-effort cleanup only
                }
              }
            }
            """,
        payload={
            "modelUrl": model_url,
            "mmprojUrl": mmproj_url,
            "modelTimeoutMs": args.model_timeout_ms,
            "mmprojTimeoutMs": args.mmproj_timeout_ms,
            "inferTimeoutMs": args.infer_timeout_ms,
            "nPredict": args.n_predict,
            "nGpuLayers": args.n_gpu_layers,
            "nThreads": args.n_threads,
            "imageBytesBase64": image_bytes_base64,
            "imageFileName": image_file_name,
            "mediaMaxImagePixels": args.media_max_image_pixels,
            "mediaMaxImageEdge": args.media_max_image_edge,
        },
    )
    print("[e2e] evaluation finished", flush=True)

    result: dict[str, Any] = payload.get("result", {})
    full_output_text = result.pop("outputFull", None)
    gate_errors: list[str] = []

    debug = result.get("debug")
    timings = result.get("timings")
    metadata = result.get("metadata")

    first_token_latency_ms = None
    if isinstance(debug, dict):
        raw_first_token = debug.get("firstTokenLatencyMs")
        if isinstance(raw_first_token, (int, float)):
            first_token_latency_ms = int(raw_first_token)

    inference_ms = None
    if isinstance(timings, dict):
        raw_inference_ms = timings.get("inferenceMs")
        if isinstance(raw_inference_ms, (int, float)):
            inference_ms = int(raw_inference_ms)

    token_count = result.get("tokenCount")
    if not isinstance(token_count, int):
        token_count = 0

    if args.max_first_token_latency_ms > 0:
        if first_token_latency_ms is None:
            gate_errors.append(
                "Missing first token latency metric for gate validation.",
            )
        elif first_token_latency_ms > args.max_first_token_latency_ms:
            gate_errors.append(
                "First token latency "
                f"{first_token_latency_ms}ms exceeds threshold "
                f"{args.max_first_token_latency_ms}ms.",
            )

    if args.max_inference_ms > 0:
        if inference_ms is None:
            gate_errors.append("Missing inference timing metric for gate validation.")
        elif inference_ms > args.max_inference_ms:
            gate_errors.append(
                f"Inference time {inference_ms}ms exceeds threshold "
                f"{args.max_inference_ms}ms.",
            )

    if args.min_token_count > 0 and token_count < args.min_token_count:
        gate_errors.append(
            f"Token count {token_count} is below required minimum "
            f"{args.min_token_count}.",
        )

    expected_text = args.expect_text.strip()
    if result.get("ok") is True and expected_text:
        if not isinstance(full_output_text, str) or (
            expected_text.casefold() not in full_output_text.casefold()
        ):
            gate_errors.append(
                f"Multimodal output did not contain expected text: {expected_text!r}.",
            )

    if args.expect_n_gpu_layers >= 0:
        resolved_gpu_layers = None
        if isinstance(metadata, dict):
            raw_layers = metadata.get("nGpuLayers")
            if raw_layers is not None:
                try:
                    resolved_gpu_layers = int(str(raw_layers).strip())
                except ValueError:
                    resolved_gpu_layers = None

        if resolved_gpu_layers is None:
            gate_errors.append("Missing resolved GPU layer metadata for gate validation.")
        elif resolved_gpu_layers != args.expect_n_gpu_layers:
            gate_errors.append(
                "Resolved GPU layers "
                f"{resolved_gpu_layers} did not match expected "
                f"{args.expect_n_gpu_layers}.",
            )

    if gate_errors:
        result["ok"] = False
        result["gateErrors"] = gate_errors

    print_json_result(payload)
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
