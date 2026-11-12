#!/usr/bin/env python3
import argparse
import json
import tempfile
import time
import wave
from pathlib import Path
from urllib.parse import urlsplit

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
    deadline = time.monotonic() + timeout_ms / 1000
    last_status = 0.0
    while time.monotonic() < deadline:
        body = safe_body_text(page)
        if needle.lower() in body.lower():
            return body
        if (
            "Speech synthesis failed:" in body
            or "does not expose dedicated text-to-speech" in body
            or "speaker references require encoded bytes" in body
        ):
            state = page.evaluate(
                """() => ({
                  error: window.__llamadartTtsLastError ?? null,
                  result: window.__llamadartTtsLastResult ?? null,
                  progressEvents: window.__llamadartTtsProgressEvents ?? 0,
                  playCalls: window.__llamadartTtsPlayCalls ?? 0,
                })"""
            )
            raise RuntimeError(
                f"TTS UI failed while waiting for {label}: "
                f"{json.dumps(state, ensure_ascii=False)}\n{body[-1200:]}"
            )
        now = time.monotonic()
        if now - last_status >= 30:
            last_status = now
            emit(
                "waiting",
                label=label,
                elapsed_seconds=round(now - (deadline - timeout_ms / 1000), 1),
                body_tail=body[-600:],
            )
        time.sleep(1)
    raise TimeoutError(f"Timed out waiting for {label}: {needle}")


def validate_wav(path: Path) -> dict[str, int | float]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_rate = wav_file.getframerate()
        sample_width = wav_file.getsampwidth()
        frame_count = wav_file.getnframes()
    if channels != 1 or sample_rate != 24000 or sample_width != 2:
        raise RuntimeError(
            "Exported WAV format mismatch: "
            f"{channels} channel(s), {sample_rate} Hz, {sample_width * 8}-bit"
        )
    if frame_count <= 0:
        raise RuntimeError("Exported WAV contains no audio frames")
    return {
        "channels": channels,
        "sampleRate": sample_rate,
        "sampleWidth": sample_width,
        "frameCount": frame_count,
        "durationSeconds": round(frame_count / sample_rate, 3),
    }


def wait_for_play_attempt(page, timeout_ms: int = 30000) -> None:
    deadline = time.monotonic() + timeout_ms / 1000
    while time.monotonic() < deadline:
        play_calls = page.evaluate("window.__llamadartTtsPlayCalls ?? 0")
        if int(play_calls or 0) > 0:
            return
        time.sleep(0.25)
    raise RuntimeError("The chat app did not attempt TTS autoplay")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("app_url")
    parser.add_argument("--model-url", required=True)
    parser.add_argument("--mmproj-url", required=True)
    parser.add_argument("--prompt", default="Hello from llamadart Web.")
    parser.add_argument("--speaker-audio-path")
    parser.add_argument("--max-frames", type=int, default=96)
    parser.add_argument("--top-k", type=int, default=50)
    parser.add_argument("--top-p", type=float, default=1.0)
    parser.add_argument("--temperature", type=float, default=0.8)
    parser.add_argument("--load-timeout-ms", type=int, default=40 * 60 * 1000)
    parser.add_argument("--response-timeout-ms", type=int, default=15 * 60 * 1000)
    parser.add_argument(
        "--browser-angle",
        choices=["auto", "default", "metal", "vulkan"],
        default="auto",
    )
    parser.add_argument("--headed", action="store_true")
    args = parser.parse_args()
    speaker_audio_path = None
    if args.speaker_audio_path:
        speaker_audio_path = Path(args.speaker_audio_path).resolve()
        if not speaker_audio_path.is_file():
            parser.error(f"--speaker-audio-path does not exist: {speaker_audio_path}")

    seeded_settings = {
        "flutter.model_path": json.dumps(args.model_url),
        "flutter.mmproj_path": json.dumps(args.mmproj_url),
        "flutter.preferred_backend": json.dumps(0),
        "flutter.context_size": json.dumps(4096),
        "flutter.max_tokens": json.dumps(args.max_frames),
        "flutter.gpu_layers": json.dumps(999),
        "flutter.auto_tune_model_params": json.dumps(False),
        "flutter.threads": json.dumps(2),
        "flutter.threads_batch": json.dumps(2),
        "flutter.temperature": json.dumps(args.temperature),
        "flutter.top_k": json.dumps(args.top_k),
        "flutter.top_p": json.dumps(args.top_p),
        "flutter.min_p": json.dumps(0.0),
        "flutter.penalty": json.dumps(1.0),
        "flutter.tools_enabled": json.dumps(False),
        "flutter.thinking_enabled": json.dumps(False),
        "flutter.single_turn_mode": json.dumps(True),
        "flutter.model_supports_audio": json.dumps(False),
        "flutter.model_supports_speech_to_text": json.dumps(False),
        "flutter.model_supports_text_to_speech": json.dumps(True),
        "flutter.model_bytes_hint": json.dumps(1482388192),
        "flutter.log_level": json.dumps(0),
        "flutter.native_log_level": json.dumps(2),
    }
    init_script = f"""
      window.__llamadartPreferLocalBridgeRuntime = true;
      window.__llamadartBridgeBootstrapVerbose = true;
      window.__llamadartBridgeEnableMem64 = true;
      window.__llamadartBridgePreferMemory64 = true;
      window.__llamadartBridgeThreadPoolSize = 2;
      window.__llamadartTtsLastCapabilities = null;
      window.__llamadartTtsLastOptions = null;
      window.__llamadartTtsLastResult = null;
      window.__llamadartTtsLastError = null;
      window.__llamadartTtsProgressEvents = 0;
      window.__llamadartTtsPlayCalls = 0;

      const originalPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function(...args) {{
        window.__llamadartTtsPlayCalls += 1;
        return originalPlay.apply(this, args);
      }};

      window.__llamadartTtsPatchTimer = setInterval(() => {{
        const BridgeClass = window.LlamaWebGpuBridge;
        if (typeof BridgeClass !== 'function') return;
        if (BridgeClass.__llamadartTtsE2ePatched === true) {{
          clearInterval(window.__llamadartTtsPatchTimer);
          return;
        }}
        const originalCapabilities =
          BridgeClass.prototype?.getTextToSpeechCapabilities;
        const originalSynthesize = BridgeClass.prototype?.synthesizeSpeech;
        if (typeof originalCapabilities !== 'function' ||
            typeof originalSynthesize !== 'function') return;

        BridgeClass.prototype.getTextToSpeechCapabilities = async function() {{
          const result = await originalCapabilities.call(this);
          window.__llamadartTtsLastCapabilities = {{
            apiVersion: result?.apiVersion ?? null,
            supported: result?.supported ?? null,
            modelType: result?.modelType ?? null,
            sampleRate: result?.sampleRate ?? null,
            channels: result?.channels ?? null,
          }};
          return result;
        }};
        BridgeClass.prototype.synthesizeSpeech = async function(options) {{
          window.__llamadartTtsLastError = null;
          window.__llamadartTtsLastResult = null;
          window.__llamadartTtsProgressEvents = 0;
          window.__llamadartTtsLastOptions = {{
            text: String(options?.text ?? ''),
            hasSpeakerAudio: Number(options?.speakerAudio?.byteLength ?? 0) > 0,
            maxFrames: options?.maxFrames ?? null,
            topK: options?.topK ?? null,
            topP: options?.topP ?? null,
            minP: options?.minP ?? null,
            temperature: options?.temperature ?? null,
          }};
          const downstreamProgress = options?.onProgress;
          if (typeof downstreamProgress === 'function') {{
            options.onProgress = function(progress) {{
              window.__llamadartTtsProgressEvents += 1;
              return downstreamProgress(progress);
            }};
          }}
          try {{
            const result = await originalSynthesize.call(this, options);
            window.__llamadartTtsLastResult = {{
              sampleRate: result?.sampleRate ?? null,
              channels: result?.channels ?? null,
              sampleCount: result?.sampleCount ?? result?.pcm?.length ?? 0,
              framesGenerated: result?.framesGenerated ?? null,
              truncated: result?.truncated ?? null,
            }};
            return result;
          }} catch (error) {{
            window.__llamadartTtsLastError = String(error);
            throw error;
          }}
        }};
        BridgeClass.__llamadartTtsE2ePatched = true;
        clearInterval(window.__llamadartTtsPatchTimer);
      }}, 20);
      {local_storage_init_script(seeded_settings)}
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
        app_parts = urlsplit(args.app_url)
        app_origin = f"{app_parts.scheme}://{app_parts.netloc}"
        context = browser.new_context(
            viewport={"width": 1440, "height": 1100},
            accept_downloads=True,
        )
        context.grant_permissions(
            ["clipboard-read", "clipboard-write"], origin=app_origin
        )
        page = context.new_page()
        page.set_default_timeout(120000)
        page.add_init_script(init_script)
        page.on(
            "console",
            lambda message: append_console_log(
                console_logs,
                message,
                echo_predicate=lambda record: record["type"] in ("warning", "error")
                or "llamadart" in record["text"],
            ),
        )
        page.on("pageerror", lambda error: page_errors.append(str(error)))
        page.on(
            "requestfailed",
            lambda request: request_failures.append(
                f"{request.method} {request.url}: {request.failure}"
            ),
        )

        emit("goto", app_url=args.app_url)
        page.goto(args.app_url, wait_until="domcontentloaded")
        enable_flutter_semantics(page)

        load_button = page.get_by_role("button", name="Load Model")
        load_button.wait_for(timeout=120000)
        emit("load_click", model_url=args.model_url, mmproj_url=args.mmproj_url)
        load_button.click()
        body = wait_for_text(
            page,
            "Model loaded successfully! Ready to chat.",
            args.load_timeout_ms,
            "model load",
        )
        emit(
            "loaded",
            elapsed_seconds=round(time.monotonic() - started_at, 1),
            body_tail=body[-500:],
        )

        if speaker_audio_path is not None:
            speaker_reference_control = page.get_by_role(
                "button", name="Add speaker reference", exact=True
            )
            speaker_reference_control.wait_for(state="visible", timeout=120000)
            with page.expect_file_chooser() as chooser:
                speaker_reference_control.click()
            chooser.value.set_files(str(speaker_audio_path))
            page.get_by_role(
                "button", name=speaker_audio_path.name, exact=True
            ).wait_for(state="visible", timeout=120000)
            emit(
                "speaker_reference_selected",
                filename=speaker_audio_path.name,
                encodedByteLength=speaker_audio_path.stat().st_size,
            )

        enter_chat_prompt(page, args.prompt, button_name="Synthesize speech")
        synthesize_button = page.get_by_role("button", name="Synthesize speech")
        synthesize_button.wait_for(state="visible")
        emit("synthesize_click", character_count=len(args.prompt))
        synthesize_button.click()
        wait_for_text(
            page,
            "Speech ready",
            args.response_timeout_ms,
            "speech synthesis",
        )
        wait_for_play_attempt(page)
        state = page.evaluate(
            """() => ({
              capabilities: window.__llamadartTtsLastCapabilities,
              options: window.__llamadartTtsLastOptions,
              result: window.__llamadartTtsLastResult,
              error: window.__llamadartTtsLastError,
              progressEvents: window.__llamadartTtsProgressEvents,
              playCalls: window.__llamadartTtsPlayCalls,
              crossOriginIsolated: window.crossOriginIsolated,
              preferMemory64: window.__llamadartBridgePreferMemory64 ?? null,
              assetSource: window.__llamadartBridgeAssetSource ?? null,
              loadError: window.__llamadartBridgeLoadError ?? null,
            })"""
        )
        result = state.get("result") or {}
        if state.get("error"):
            raise RuntimeError(f"Bridge TTS failed: {state['error']}")
        if result.get("sampleRate") != 24000 or result.get("channels") != 1:
            raise RuntimeError(f"Bridge returned unexpected PCM format: {result}")
        if int(result.get("sampleCount") or 0) <= 0:
            raise RuntimeError(f"Bridge returned empty PCM: {result}")
        if int(state.get("progressEvents") or 0) <= 0:
            raise RuntimeError("Bridge did not emit TTS progress")

        with tempfile.TemporaryDirectory(prefix="llamadart-web-tts-") as temp_dir:
            with page.expect_download(timeout=120000) as download_info:
                page.get_by_role("button", name="Save WAV").click()
            download = download_info.value
            wav_path = Path(temp_dir) / "llamadart-speech.wav"
            download.save_as(str(wav_path))
            wav_metadata = validate_wav(wav_path)

        emit(
            "result",
            ok=True,
            elapsedSeconds=round(time.monotonic() - started_at, 1),
            variant="textToSpeech",
            modelUrl=args.model_url,
            mmprojUrl=args.mmproj_url,
            promptCharacterCount=len(args.prompt),
            speakerReference=(
                {
                    "filename": speaker_audio_path.name,
                    "encodedByteLength": speaker_audio_path.stat().st_size,
                }
                if speaker_audio_path is not None
                else None
            ),
            bridge=state,
            wav=wav_metadata,
            bodyTail=body[-1000:],
            consoleTail=console_logs[-30:],
            pageErrors=page_errors[-10:],
            requestFailures=request_failures[-10:],
        )
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
