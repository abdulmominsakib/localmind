#!/usr/bin/env python3
import json
from typing import Any, Callable

from playwright.sync_api import sync_playwright


DEFAULT_APP_URL = "http://127.0.0.1:7357"
DEFAULT_MODEL_URL = (
    "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/"
    "Qwen3.5-0.8B-Q4_K_M.gguf?download=true"
)
DEFAULT_MMPROJ_URL = (
    "https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/"
    "mmproj-F16.gguf?download=true"
)

_DEFAULT_CHROMIUM_ARGS = [
    "--enable-unsafe-webgpu",
    "--disable-vulkan-surface",
    "--enable-features=Vulkan",
]


def default_console_echo_predicate(entry: dict[str, str]) -> bool:
    text = entry.get("text", "").lower()
    return "llamadart:" in text or "runtimeerror" in text or "failed" in text


def run_bridge_evaluation(
    *,
    app_url: str,
    evaluate_script: str,
    payload: dict[str, Any],
    channel: str = "chromium",
    headed: bool = False,
    default_timeout_ms: int = 120000,
    ready_timeout_ms: int = 120000,
    console_tail_count: int = 14,
    echo_console: bool = False,
    console_echo_predicate: Callable[[dict[str, str]], bool] | None = None,
) -> dict[str, Any]:
    console_logs: list[dict[str, str]] = []
    if console_echo_predicate is None:
        console_echo_predicate = default_console_echo_predicate

    with sync_playwright() as playwright:
        launch_kwargs: dict[str, Any] = {
            "headless": not headed,
            "args": list(_DEFAULT_CHROMIUM_ARGS),
        }
        if channel and channel != "chromium":
            launch_kwargs["channel"] = channel

        browser = playwright.chromium.launch(**launch_kwargs)
        page = browser.new_page()
        page.set_default_timeout(default_timeout_ms)

        def on_console(message: Any) -> None:
            try:
                text = message.text
            except Exception:  # pragma: no cover
                text = str(message)

            entry = {"type": str(message.type), "text": str(text)}
            console_logs.append(entry)
            if echo_console and console_echo_predicate(entry):
                print(f"[browser:{entry['type']}] {entry['text']}", flush=True)

        page.on("console", on_console)
        page.goto(app_url, wait_until="domcontentloaded", timeout=ready_timeout_ms)
        page.wait_for_function(
            "() => typeof window.LlamaWebGpuBridge === 'function'",
            timeout=ready_timeout_ms,
        )
        result = page.evaluate(evaluate_script, payload)
        browser.close()

    return {
        "result": result,
        "consoleTail": console_logs[-console_tail_count:],
    }


def print_json_result(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, indent=2))
