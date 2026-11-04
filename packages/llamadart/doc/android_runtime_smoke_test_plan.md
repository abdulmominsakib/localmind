# Android Runtime Smoke Test Plan

This checklist validates Android packaging + runtime behavior for CPU variant
selection (`cpu_profile` / `cpu_variants`) and catches old-device crashes.

## Scope

- Verify hook emits the expected `libggml-cpu-android_*` files from pubspec
  configuration.
- Verify runtime starts and loads a model on both old and modern devices.
- Verify no illegal-instruction crashes (`SIGILL`) on old devices.

## Device Matrix

- Old arm64 device (older cores / lower ISA support).
- Modern arm64 device (new flagship-class cores).

## Config Matrix

- `cpu_profile: full` (default).
- `cpu_profile: compact`.
- Optional targeted override:
  - `cpu_variants: [android_armv8.6_1, android_armv9.2_2]`.

## Pre-Run Setup

1. Update `hooks.user_defines.llamadart.llamadart_native_backends` in app
   `pubspec.yaml`.
2. Run:

```bash
flutter clean
flutter pub get
```

3. Build release APK/AAB:

```bash
flutter build apk --release
```

4. Install to device:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## One-Shot Helper Script

Use the helper to run build/install/log capture in one command:

```bash
./scripts/android_runtime_smoke.sh \
  --project-dir example/chat_app \
  --app-id com.example.llamadart_chat_example
```

Useful options:

- `--serial <device-serial>`: target a specific connected device.
- `--activity <activity>`: launch specific activity via `am start`.
- `--wait-seconds <n>`: adjust log capture window (default `20`).
- `--skip-clean|--skip-build|--skip-install|--skip-launch`: skip steps when
  iterating quickly.

The script builds, installs, launches, and captures logcat. It exits non-zero
when crash signatures are detected (`SIGILL`, `SIGSEGV`, fatal signals). It
does not drive the UI or generate tokens; run the manual smoke scenario below
after the helper completes when model load/generation proof is required.

## Smoke Scenario (each config x device)

1. Clear logs:

```bash
adb logcat -c
```

2. Launch app and load a known small GGUF model.
3. Run one deterministic prompt (`maxTokens` small, e.g. 32).
4. Confirm app stays alive and first tokens stream.
5. Capture logs:

```bash
adb logcat -d | grep -E "SIGILL|SIGSEGV|Fatal signal|llamadart|ggml"
```

## Pass Criteria

- No process crash.
- No `SIGILL` / illegal-instruction entries in logcat.
- Model load succeeds and at least one token is generated.
- `compact` works on old device.
- `full` works on modern device and is not slower than `compact` for the same
  prompt (within noise).

## Nice-to-Have Automation

- Keep unit + hook integration tests in CI for package composition.
- Run this runtime smoke checklist on a small physical-device pool before each
  release candidate.
