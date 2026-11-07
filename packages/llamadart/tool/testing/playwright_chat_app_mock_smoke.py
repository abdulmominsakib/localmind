#!/usr/bin/env python3
import argparse
import json
import re

from playwright.sync_api import sync_playwright

from playwright_chat_app_utils import (
    append_console_log,
    enable_flutter_semantics,
    enter_chat_prompt,
    local_storage_init_script,
)


DEFAULT_APP_URL = "http://127.0.0.1:7357/?llamadart_mock_bridge=echo"
DEFAULT_MODEL_URL = "https://example.com/mock-qwen.gguf"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_url", nargs="?", default=DEFAULT_APP_URL)
    parser.add_argument("--model-url", default=DEFAULT_MODEL_URL)
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()

    console_logs: list[dict[str, str]] = []
    result: dict[str, object] = {}

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=not args.headed)
        page = browser.new_page(viewport={"width": 1440, "height": 1100})
        page.set_default_timeout(120000)
        seeded_settings = {
            "flutter.model_path": json.dumps(args.model_url),
            "flutter.preferred_backend": json.dumps(0),
            "flutter.context_size": json.dumps(4096),
            "flutter.max_tokens": json.dumps(256),
            "flutter.gpu_layers": json.dumps(99),
            "flutter.threads": json.dumps(4),
            "flutter.threads_batch": json.dumps(4),
            "flutter.temperature": json.dumps(0.7),
            "flutter.top_k": json.dumps(20),
            "flutter.top_p": json.dumps(0.8),
            "flutter.penalty": json.dumps(1.0),
            "flutter.tools_enabled": json.dumps(False),
            "flutter.thinking_enabled": json.dumps(False),
        }
        page.add_init_script(local_storage_init_script(seeded_settings))

        def on_console(message) -> None:
            append_console_log(console_logs, message)

        page.on("console", on_console)
        page.goto(args.app_url, wait_until="networkidle")

        enable_flutter_semantics(page)

        page.get_by_role("button", name=re.compile(r"Load Model", re.I)).click()
        page.get_by_text("Model loaded successfully! Ready to chat.").wait_for()

        enter_chat_prompt(page, "hi")
        page.get_by_role("button", name="Send message").click()

        page.wait_for_function(
            "() => typeof window.__llamadartMockBridgeLastResponse === 'string' && window.__llamadartMockBridgeLastResponse.length > 0"
        )

        result = {
            "ok": True,
            "bodyText": page.locator("body").inner_text(),
            "prompt": page.evaluate("window.__llamadartMockBridgeLastPrompt || null"),
            "response": page.evaluate("window.__llamadartMockBridgeLastResponse || null"),
            "scenario": page.evaluate(
                "window.__llamadartMockBridgeLastLoad?.scenario || null"
            ),
        }
        prompt = str(result.get("prompt") or "")
        assert "<|im_start|>user" in prompt, prompt
        assert "<|im_start|>assistant" in prompt, prompt
        browser.close()

    payload = {"result": result, "consoleTail": console_logs[-12:]}
    print(json.dumps(payload, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
