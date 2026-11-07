#!/usr/bin/env python3
import json
import sys

from playwright.sync_api import sync_playwright


def main() -> int:
    url = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:7357"

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        page = browser.new_page()

        page.goto(url)
        page.wait_for_load_state("networkidle")

        result = page.evaluate(
            """
            async () => {
              const originalWorker = window.Worker;
              const calls = [];
              let workerId = 0;
              let firstModelLoadFails = false;

              class FakeWorker {
                constructor() {
                  this.id = ++workerId;
                  this.onmessage = null;
                  this.onerror = null;
                  queueMicrotask(() => {
                    this.onmessage?.({ data: { type: 'ready' } });
                  });
                }

                postMessage(message) {
                  if (!message || message.type !== 'call') {
                    return;
                  }

                  calls.push({ worker: this.id, method: message.method });

                  const ok = (value, state = {}) => {
                    queueMicrotask(() => {
                      this.onmessage?.({
                        data: {
                          type: 'result',
                          id: message.id,
                          value,
                          state,
                        },
                      });
                    });
                  };

                  const fail = (text, state = {}) => {
                    queueMicrotask(() => {
                      this.onmessage?.({
                        data: {
                          type: 'error',
                          id: message.id,
                          message: text,
                          state,
                        },
                      });
                    });
                  };

                  if (message.method === 'dispose') {
                    ok(null, {});
                    return;
                  }

                  if (message.method === 'loadModelFromUrl') {
                    if (!firstModelLoadFails) {
                      firstModelLoadFails = true;
                      fail('FS error');
                      return;
                    }

                    ok(1, {
                      metadata: {},
                      contextSize: 8192,
                      gpuActive: true,
                      backendName: 'WebGPU (Mock)',
                      supportsVision: false,
                      supportsAudio: false,
                    });
                    return;
                  }

                  if (message.method === 'loadMultimodalProjector') {
                    ok(1, {
                      metadata: {},
                      contextSize: 8192,
                      gpuActive: true,
                      backendName: 'WebGPU (Mock)',
                      supportsVision: true,
                      supportsAudio: false,
                    });
                    return;
                  }

                  if (message.method === 'createCompletion') {
                    queueMicrotask(() => {
                      this.onmessage?.({
                        data: {
                          type: 'event',
                          id: message.id,
                          event: 'token',
                          payload: {
                            piece: [79, 75],
                            currentText: 'OK',
                          },
                        },
                      });
                    });

                    ok('OK', {
                      metadata: {},
                      contextSize: 8192,
                      gpuActive: true,
                      backendName: 'WebGPU (Mock)',
                      supportsVision: true,
                      supportsAudio: false,
                    });
                    return;
                  }

                  ok(null, {});
                }

                terminate() {}
              }

              window.Worker = FakeWorker;

              try {
                const moduleUrl = `/webgpu_bridge/llama_webgpu_bridge.js?v=${Date.now()}`;
                const mod = await import(moduleUrl);
                const Bridge = mod.LlamaWebGpuBridge;
                const bridge = new Bridge({
                  workerUrl: 'https://example.com/llama_webgpu_bridge_worker.js',
                  logLevel: 2,
                });

                bridge._runtime = {
                  _modelBytes: 0,
                  _runtimeNotes: [],
                  async loadModelFromUrl() {
                    this._modelBytes = 1;
                    return 1;
                  },
                  async loadMultimodalProjector() {
                    return 1;
                  },
                  async createCompletion() {
                    return 'runtime';
                  },
                  supportsVision() {
                    return false;
                  },
                  supportsAudio() {
                    return false;
                  },
                  setLogLevel() {},
                  cancel() {},
                  async dispose() {},
                };

                const loadRc = await bridge.loadModelFromUrl(
                  'https://example.com/model.gguf',
                  { nCtx: 8192, nGpuLayers: 99 },
                );

                if (Number(loadRc) !== 1) {
                  throw new Error('loadModelFromUrl did not succeed');
                }

                const mmRc = await bridge.loadMultimodalProjector(
                  'https://example.com/mmproj.gguf',
                );

                if (Number(mmRc) !== 1) {
                  throw new Error('loadMultimodalProjector did not succeed');
                }

                const output = await bridge.createCompletion('describe', {
                  parts: [
                    {
                      type: 'image',
                      bytes: new Uint8Array([1, 2, 3]),
                    },
                  ],
                });

                if (output !== 'OK') {
                  throw new Error('createCompletion did not return expected output');
                }

                const workerCalls = calls.filter((entry) => entry.method === 'createCompletion');
                if (workerCalls.length < 1) {
                  throw new Error('worker createCompletion was not used');
                }

                return {
                  ok: true,
                  calls,
                };
              } catch (error) {
                return {
                  ok: false,
                  error: String(error),
                  calls,
                };
              } finally {
                window.Worker = originalWorker;
              }
            }
            """
        )

        browser.close()

    print(json.dumps(result, indent=2))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
