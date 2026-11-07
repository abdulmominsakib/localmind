#!/usr/bin/env python3
import argparse
import json
import re
import statistics
import time
from typing import Any

from playwright.sync_api import TimeoutError as PlaywrightTimeoutError
from playwright.sync_api import sync_playwright

from playwright_chat_app_utils import (
    append_console_log,
    browser_args,
    emit,
    enable_flutter_semantics,
    enter_chat_prompt,
    local_storage_init_script,
    safe_body_text,
)


def wait_for_text(page, needle: str, timeout_ms: int, label: str) -> str:
    deadline = time.monotonic() + (timeout_ms / 1000)
    lower_needle = needle.lower()
    last_status = 0.0
    while time.monotonic() < deadline:
        text = safe_body_text(page)
        if lower_needle in text.lower():
            return text
        if "Something went wrong" in text and "Retry" in text:
            state = page.evaluate(
                """() => ({
                  bridgeError: window.__llamadartRealBridgeLastError,
                  liteRtLmError: window.__llamadartRealLiteRtLmLastError,
                  bridgeLoadError: window.__llamadartBridgeLoadError,
                })"""
            )
            raise RuntimeError(
                f"App entered error state while waiting for {label}: "
                f"{json.dumps(state, ensure_ascii=False)}\n{text[-1200:]}"
            )
        now = time.monotonic()
        if now - last_status >= 30:
            last_status = now
            emit(
                "waiting",
                label=label,
                elapsed_seconds=round(now - (deadline - timeout_ms / 1000), 1),
                body_tail=text[-700:],
            )
        time.sleep(2)
    raise TimeoutError(f"Timed out waiting for {label}: {needle}")


def extract_response_state(page) -> dict[str, Any]:
    return page.evaluate(
        """() => ({
          bridgeResponse: window.__llamadartRealBridgeLastResponse,
          bridgeError: window.__llamadartRealBridgeLastError,
          liteRtLmResponse: window.__llamadartRealLiteRtLmLastResponse,
          liteRtLmError: window.__llamadartRealLiteRtLmLastError,
          liteRtLmPrompt: window.__llamadartRealLiteRtLmLastPrompt,
          liteRtLmSettings: window.__llamadartRealLiteRtLmLastSettings,
          liteRtLmConversationConfig:
            window.__llamadartRealLiteRtLmLastConversationConfig,
          liteRtLmChunks: window.__llamadartRealLiteRtLmLastChunks,
        })"""
    )


def collect_bridge_globals(page) -> dict[str, Any]:
    return page.evaluate(
        """() => ({
          crossOriginIsolated: window.crossOriginIsolated,
          assetSource: window.__llamadartBridgeAssetSource ?? null,
          moduleUrl: window.__llamadartBridgeModuleUrl ?? null,
          coreModuleUrl: window.__llamadartBridgeCoreModuleUrl ?? null,
          coreModuleUrlMem64: window.__llamadartBridgeCoreModuleUrlMem64 ?? null,
          wasmUrl: window.__llamadartBridgeWasmUrl ?? null,
          wasmUrlMem64: window.__llamadartBridgeWasmUrlMem64 ?? null,
          workerUrl: window.__llamadartBridgeWorkerUrl ?? null,
          preferMemory64: window.__llamadartBridgePreferMemory64 ?? null,
          enableMemory64: window.__llamadartBridgeEnableMem64 ?? null,
          workerFallbackReason: window.__llamadartBridgeWorkerFallbackReason ?? null,
          loadError: window.__llamadartBridgeLoadError ?? null,
          threadPoolSize: window.__llamadartBridgeThreadPoolSize ?? null,
          liteRtLmModuleUrl: window.__llamadartLiteRtLmModuleUrl ?? null,
        })"""
    )


def response_for_source(state: dict[str, Any], response_source: str) -> str:
    if response_source == "bridge":
        return str(state.get("bridgeResponse") or "")
    if response_source == "litert":
        return str(state.get("liteRtLmResponse") or "")
    bridge_response = str(state.get("bridgeResponse") or "")
    if bridge_response.strip():
        return bridge_response
    return str(state.get("liteRtLmResponse") or "")


def wait_for_generation_complete(
    page,
    response_source: str,
    timeout_ms: int,
) -> tuple[dict[str, Any], str, int]:
    deadline = time.monotonic() + (timeout_ms / 1000)
    last_status = 0.0
    while time.monotonic() < deadline:
        state = extract_response_state(page)
        if response_source in ("bridge", "auto") and state.get("bridgeError"):
            raise RuntimeError(f"Bridge generation failed: {state['bridgeError']}")
        if response_source in ("litert", "auto") and state.get("liteRtLmError"):
            raise RuntimeError(f"LiteRT-LM generation failed: {state['liteRtLmError']}")

        response = response_for_source(state, response_source)
        body = safe_body_text(page)
        running = "Stop generation" in body
        if response.strip() and not running:
            return state, body, len(response)

        now = time.monotonic()
        if now - last_status >= 30:
            last_status = now
            emit(
                "waiting",
                label="generation",
                elapsed_seconds=round(now - (deadline - timeout_ms / 1000), 1),
                response_source=response_source,
                response_chars=len(response),
                body_tail=body[-700:],
                liteRtLmPrompt=str(state.get("liteRtLmPrompt") or "")[-300:],
                liteRtLmChunks=state.get("liteRtLmChunks"),
            )
        time.sleep(1)
    raise TimeoutError("Timed out waiting for generation to finish")


def parse_ui_metrics(body: str) -> dict[str, Any]:
    metrics: dict[str, Any] = {}
    context_matches = re.findall(r"(\d+)/(\d+)\s+tok", body)
    if context_matches:
        used, total = context_matches[-1]
        metrics["contextUsedTokens"] = int(used)
        metrics["contextSize"] = int(total)

    patterns = {
        "averageTokensPerSecond": r"avg\s+([0-9]+(?:\.[0-9]+)?)\s+tok/s",
        "decodeTokensPerSecond": r"decode\s+([0-9]+(?:\.[0-9]+)?)\s+tok/s",
        "timeToFirstTokenMilliseconds": r"first\s+([0-9]+(?:\.[0-9]+)?)ms",
        "totalMilliseconds": r"total\s+([0-9]+(?:\.[0-9]+)?)ms",
    }
    for key, pattern in patterns.items():
        matches = re.findall(pattern, body)
        if matches:
            metrics[key] = float(matches[-1])
    return metrics


def summarize(values: list[float]) -> dict[str, float | None]:
    if not values:
        return {"median": None, "min": None, "max": None}
    return {
        "median": statistics.median(values),
        "min": min(values),
        "max": max(values),
    }


def run_chat_benchmark(
    page,
    args: argparse.Namespace,
    response_source: str,
    started_at: float,
) -> tuple[int, list[dict[str, Any]]]:
    emit("goto", app_url=args.app_url, label=args.label)
    page.goto(args.app_url, wait_until="domcontentloaded")
    enable_flutter_semantics(page)

    button = page.get_by_role("button", name=re.compile(r"Load Model"))
    button.wait_for(timeout=120000)
    emit("load_click", model_url=args.model_url)
    button.click()
    body_after_load = wait_for_text(
        page,
        "Model loaded successfully! Ready to chat.",
        args.load_timeout_ms,
        "model load",
    )
    load_elapsed_ms = int((time.monotonic() - started_at) * 1000)
    emit(
        "loaded",
        loadMilliseconds=load_elapsed_ms,
        body_tail=body_after_load[-700:],
    )

    runs: list[dict[str, Any]] = []
    total_runs = args.warmups + args.runs
    for index in range(total_runs):
        measured = index >= args.warmups
        page.evaluate(
            """() => {
              window.__llamadartRealBridgeLastResponse = null;
              window.__llamadartRealBridgeLastError = null;
              window.__llamadartRealLiteRtLmLastResponse = null;
              window.__llamadartRealLiteRtLmLastError = null;
              window.__llamadartRealLiteRtLmLastChunks = [];
            }"""
        )
        enter_chat_prompt(page, args.prompt)
        generation_started = time.monotonic()
        page.get_by_role("button", name="Send message").click()
        try:
            page.get_by_role("button", name="Stop generation").wait_for(
                timeout=10000,
            )
        except PlaywrightTimeoutError:
            pass
        _state, body, response_chars = wait_for_generation_complete(
            page,
            response_source,
            args.response_timeout_ms,
        )
        elapsed_ms = int((time.monotonic() - generation_started) * 1000)
        ui_metrics = parse_ui_metrics(body)
        run = {
            "index": index,
            "measured": measured,
            "elapsedMilliseconds": elapsed_ms,
            "responseChars": response_chars,
            **ui_metrics,
        }
        runs.append(run)
        emit("run", **run)

    return load_elapsed_ms, runs


def build_success_result(
    page,
    args: argparse.Namespace,
    response_source: str,
    load_elapsed_ms: int,
    runs: list[dict[str, Any]],
    page_errors: list[str],
    request_failures: list[str],
    console_logs: list[dict[str, str]],
) -> dict[str, Any]:
    measured_runs = [run for run in runs if run["measured"]]
    return {
        "label": args.label,
        "modelUrl": args.model_url,
        "responseSource": response_source,
        "loadMilliseconds": load_elapsed_ms,
        "warmups": args.warmups,
        "runs": args.runs,
        "contextSize": args.context_size,
        "targetDecodeTokens": args.max_tokens,
        "browser": "chromium",
        "browserAngle": args.browser_angle,
        "mem64Requested": args.mem64,
        "measured": {
            "averageTokensPerSecond": summarize(
                [
                    float(run["averageTokensPerSecond"])
                    for run in measured_runs
                    if "averageTokensPerSecond" in run
                ]
            ),
            "decodeTokensPerSecond": summarize(
                [
                    float(run["decodeTokensPerSecond"])
                    for run in measured_runs
                    if "decodeTokensPerSecond" in run
                ]
            ),
            "totalMilliseconds": summarize(
                [
                    float(run["totalMilliseconds"])
                    for run in measured_runs
                    if "totalMilliseconds" in run
                ]
            ),
            "elapsedMilliseconds": summarize(
                [float(run["elapsedMilliseconds"]) for run in measured_runs]
            ),
        },
        "runsDetail": runs,
        "bridgeGlobals": collect_bridge_globals(page),
        "pageErrors": page_errors[-10:],
        "requestFailures": request_failures[-10:],
        "consoleTail": console_logs[-25:],
    }


def build_failure_result(
    page,
    args: argparse.Namespace,
    response_source: str,
    error: Exception,
    started_at: float,
    page_errors: list[str],
    request_failures: list[str],
    console_logs: list[dict[str, str]],
) -> dict[str, Any]:
    try:
        body_tail = safe_body_text(page)[-1200:]
    except Exception as body_error:
        body_tail = f"<body unavailable: {body_error}>"
    try:
        response_state: dict[str, Any] = extract_response_state(page)
    except Exception as state_error:
        response_state = {"error": str(state_error)}
    try:
        bridge_globals: dict[str, Any] = collect_bridge_globals(page)
    except Exception as globals_error:
        bridge_globals = {"error": str(globals_error)}

    return {
        "label": args.label,
        "modelUrl": args.model_url,
        "responseSource": response_source,
        "error": str(error),
        "exceptionType": type(error).__name__,
        "elapsedMilliseconds": int((time.monotonic() - started_at) * 1000),
        "body_tail": body_tail,
        "responseState": response_state,
        "bridgeGlobals": bridge_globals,
        "pageErrors": page_errors[-10:],
        "requestFailures": request_failures[-10:],
        "consoleTail": console_logs[-25:],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_url")
    parser.add_argument("--label", required=True)
    parser.add_argument("--model-url", required=True)
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--response-source", choices=["auto", "bridge", "litert"])
    parser.add_argument("--backend-index", type=int, required=True)
    parser.add_argument("--gpu-layers", type=int, default=999)
    parser.add_argument("--context-size", type=int, default=4096)
    parser.add_argument("--max-tokens", type=int, default=256)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--thread-pool-size", type=int, default=2)
    parser.add_argument("--load-timeout-ms", type=int, default=40 * 60 * 1000)
    parser.add_argument("--response-timeout-ms", type=int, default=20 * 60 * 1000)
    parser.add_argument("--browser-angle", choices=["auto", "default", "metal", "vulkan"], default="auto")
    parser.add_argument("--mem64", action="store_true")
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()

    response_source = args.response_source
    if response_source is None:
        response_source = "litert" if args.model_url.lower().split("?")[0].endswith(".litertlm") else "bridge"

    seeded_settings = {
        "flutter.model_path": json.dumps(args.model_url),
        "flutter.preferred_backend": json.dumps(args.backend_index),
        "flutter.context_size": json.dumps(args.context_size),
        "flutter.max_tokens": json.dumps(args.max_tokens),
        "flutter.gpu_layers": json.dumps(args.gpu_layers),
        "flutter.threads": json.dumps(args.threads),
        "flutter.threads_batch": json.dumps(args.threads),
        "flutter.temperature": json.dumps(0.0),
        "flutter.top_k": json.dumps(1),
        "flutter.top_p": json.dumps(1.0),
        "flutter.min_p": json.dumps(0.0),
        "flutter.penalty": json.dumps(1.1),
        "flutter.tools_enabled": json.dumps(False),
        "flutter.tool_declarations": json.dumps("[]"),
        "flutter.thinking_enabled": json.dumps(False),
        "flutter.thinking_budget_tokens": json.dumps(0),
        "flutter.single_turn_mode": json.dumps(True),
        "flutter.log_level": json.dumps(0),
        "flutter.native_log_level": json.dumps(2),
    }

    init_script = f"""
      window.__llamadartPreferLocalBridgeRuntime = true;
      window.__llamadartBridgeBootstrapVerbose = true;
      window.__llamadartBridgeThreadPoolSize = {args.thread_pool_size};
      window.__llamadartBridgeEnableMem64 = {str(args.mem64).lower()};
      window.__llamadartBridgePreferMemory64 = {str(args.mem64).lower()};
      window.__llamadartBridgeAllowAutoRemoteFetchBackend = true;
      window.__llamadartRealBridgeLastResponse = null;
      window.__llamadartRealBridgeLastError = null;
      window.__llamadartRealLiteRtLmLastResponse = null;
      window.__llamadartRealLiteRtLmLastError = null;
      window.__llamadartRealLiteRtLmLastSettings = null;
      window.__llamadartRealLiteRtLmLastConversationConfig = null;
      window.__llamadartRealLiteRtLmLastPrompt = null;
      window.__llamadartRealLiteRtLmLastChunks = [];

      window.__llamadartRealBridgePatchTimer = setInterval(() => {{
        const BridgeClass = window.LlamaWebGpuBridge;
        if (typeof BridgeClass !== 'function') return;
        if (BridgeClass.__llamadartBenchmarkPatched === true) {{
          clearInterval(window.__llamadartRealBridgePatchTimer);
          return;
        }}
        const original = BridgeClass.prototype?.createCompletion;
        if (typeof original !== 'function') return;
        BridgeClass.prototype.createCompletion = async function(prompt, options) {{
          window.__llamadartRealBridgeLastResponse = null;
          window.__llamadartRealBridgeLastError = null;
          try {{
            const result = await original.call(this, prompt, options);
            window.__llamadartRealBridgeLastResponse = String(result ?? '');
            return result;
          }} catch (error) {{
            window.__llamadartRealBridgeLastError = String(error);
            throw error;
          }}
        }};
        BridgeClass.__llamadartBenchmarkPatched = true;
        clearInterval(window.__llamadartRealBridgePatchTimer);
      }}, 20);

      window.__llamadartRealLiteRtLmExtractText = function(value) {{
        if (value == null) return '';
        if (typeof value === 'string') return value;
        if (typeof value.text === 'string') return value.text;
        if (Array.isArray(value.content)) {{
          return value.content
            .map(item => item && typeof item.text === 'string' ? item.text : '')
            .join('');
        }}
        return '';
      }};
      window.__llamadartRealLiteRtLmCapture = async function(stream) {{
        try {{
          const reader = stream.getReader();
          let text = '';
          let chunks = [];
          while (true) {{
            const result = await reader.read();
            if (result.done) break;
            chunks.push(result.value);
            window.__llamadartRealLiteRtLmLastChunks = chunks.slice(-8);
            text += window.__llamadartRealLiteRtLmExtractText(result.value);
            window.__llamadartRealLiteRtLmLastResponse = text;
          }}
          if (typeof reader.releaseLock === 'function') reader.releaseLock();
        }} catch (error) {{
          window.__llamadartRealLiteRtLmLastError = String(error);
        }}
      }};
      window.__llamadartRealLiteRtLmInstallModuleWrapper = function() {{
        const originalModuleUrl =
          typeof window.__llamadartLiteRtLmModuleUrl === 'string' &&
          window.__llamadartLiteRtLmModuleUrl.length > 0
            ? window.__llamadartLiteRtLmModuleUrl
            : 'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.15.0/+esm';
        const moduleSource = [
          'import * as mod from ' + JSON.stringify(originalModuleUrl) + ';',
          'const summarizeSettings = (settings) => {{',
          '  const mainExecutorSettings = settings?.mainExecutorSettings;',
          '  return {{',
          '    model: settings?.model,',
          '    backend: settings?.backend,',
          '    mainExecutorSettings: mainExecutorSettings ? {{',
          '      maxNumTokens: mainExecutorSettings.maxNumTokens,',
          '      samplerBackend: mainExecutorSettings.samplerBackend,',
          '      backendConfig: mainExecutorSettings.backendConfig,',
          '      advancedSettings: mainExecutorSettings.advancedSettings,',
          '    }} : null,',
          '  }};',
          '}};',
          'const wrapConversation = (conversation) => new Proxy(conversation, {{',
          '  get(target, prop, receiver) {{',
          '    if (prop === "sendMessageStreaming") {{',
          '      return function(prompt) {{',
          '        globalThis.__llamadartRealLiteRtLmLastResponse = null;',
          '        globalThis.__llamadartRealLiteRtLmLastError = null;',
          '        globalThis.__llamadartRealLiteRtLmLastPrompt = String(prompt ?? "");',
          '        globalThis.__llamadartRealLiteRtLmLastChunks = [];',
          '        const stream = target.sendMessageStreaming(prompt);',
          '        if (stream && typeof stream.tee === "function") {{',
          '          const branches = stream.tee();',
          '          globalThis.__llamadartRealLiteRtLmCapture(branches[1]);',
          '          return branches[0];',
          '        }}',
          '        return stream;',
          '      }};',
          '    }}',
          '    const value = Reflect.get(target, prop, receiver);',
          '    return typeof value === "function" ? value.bind(target) : value;',
          '  }}',
          '}});',
          'const wrapEngine = (engine) => new Proxy(engine, {{',
          '  get(target, prop, receiver) {{',
          '    if (prop === "createConversation") {{',
          '      return async function(config) {{',
          '        globalThis.__llamadartRealLiteRtLmLastConversationConfig = config;',
          '        const conversation = await target.createConversation(config);',
          '        return wrapConversation(conversation);',
          '      }};',
          '    }}',
          '    const value = Reflect.get(target, prop, receiver);',
          '    return typeof value === "function" ? value.bind(target) : value;',
          '  }}',
          '}});',
          'export const Backend = mod.Backend;',
          'export const Engine = new Proxy(mod.Engine, {{',
          '  get(target, prop, receiver) {{',
          '    if (prop === "create") {{',
          '      return async function(settings) {{',
          '        globalThis.__llamadartRealLiteRtLmLastSettings = summarizeSettings(settings);',
          '        const engine = await target.create(settings);',
          '        return wrapEngine(engine);',
          '      }};',
          '    }}',
          '    const value = Reflect.get(target, prop, receiver);',
          '    return typeof value === "function" ? value.bind(target) : value;',
          '  }}',
          '}});',
          'export default mod.default ?? null;',
        ].join('\\n');
        window.__llamadartLiteRtLmModuleUrl = URL.createObjectURL(
          new Blob([moduleSource], {{ type: 'text/javascript' }})
        );
      }};
      window.__llamadartRealLiteRtLmInstallModuleWrapper();

      {local_storage_init_script(
          seeded_settings,
          remove_keys=("flutter.mmproj_path",),
      )}
    """

    console_logs: list[dict[str, str]] = []
    page_errors: list[str] = []
    request_failures: list[str] = []
    started_at = time.monotonic()

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(
            headless=not args.headed,
            args=browser_args(args.browser_angle),
        )
        page = browser.new_page(viewport={"width": 1440, "height": 1100})
        page.set_default_timeout(120000)
        page.add_init_script(init_script)
        page.on(
            "console",
            lambda message: append_console_log(console_logs, message),
        )
        page.on("pageerror", lambda error: page_errors.append(str(error)))
        page.on(
            "requestfailed",
            lambda request: request_failures.append(
                f"{request.method} {request.url}: {request.failure}"
            ),
        )

        exit_code = 0
        try:
            load_elapsed_ms, runs = run_chat_benchmark(
                page,
                args,
                response_source,
                started_at,
            )
            emit(
                "result",
                ok=True,
                **build_success_result(
                    page,
                    args,
                    response_source,
                    load_elapsed_ms,
                    runs,
                    page_errors,
                    request_failures,
                    console_logs,
                ),
            )
        except Exception as error:
            emit(
                "result",
                ok=False,
                **build_failure_result(
                    page,
                    args,
                    response_source,
                    error,
                    started_at,
                    page_errors,
                    request_failures,
                    console_logs,
                ),
            )
            exit_code = 1
        finally:
            browser.close()

        return exit_code

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
