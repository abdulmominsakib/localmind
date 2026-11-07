# Contributing into llamadart

Thank you for your interest in contributing to `llamadart`! We welcome contributions from the community to help improve this package.

## Prerequisites

Before you begin, ensure you have the following installed:

-   **Dart SDK**: >= 3.10.7
-   **Flutter SDK**: >= 3.38.0 (optional, for running UI examples)
-   **CMake**: >= 3.10
-   **C++ Compiler**:
    -   **macOS**: Xcode Command Line Tools (`xcode-select --install`)
    -   **Linux**: GCC/G++ (`build-essential`) or Clang
    -   **Windows**: Visual Studio 2022 (Desktop development with C++). 
        -   *Tip*: Install `ccache` or `sccache` via `choco install sccache` to speed up local builds.

## Project Structure

The project follows a modular, decoupled architecture:

-   `lib/src/core/engine/`: Core orchestration (`LlamaEngine`, `ChatSession`).
-   `lib/src/core/template/`: Chat template routing, handlers, parser logic.
-   `lib/src/backends/`: Platform-agnostic backend interface and native/web backends.
-   `lib/src/core/models/`: Shared data models (messages, params, tools, config).
-   `lib/src/core/`: Shared utilities (exceptions, logger, grammar helpers).

## 🛡️ Zero-Patch Strategy

Native source and build orchestration now live in
[`leehack/llamadart-native`](https://github.com/leehack/llamadart-native).

*   **Zero Direct Modifications**: Do not patch upstream `llama.cpp` sources in this repository.
*   **Sync-Only in this repo**: This repository consumes released native bundles and generated bindings.
*   **Build logic lives elsewhere**: Native build scripts and backend matrix changes belong in `llamadart-native`.

## 🏗️ Architecture: Native Assets & CI

`llamadart` uses a modern binary distribution lifecycle:

### 1. Binary Production (CI)
Native binaries are built and released from
[`leehack/llamadart-native`](https://github.com/leehack/llamadart-native).
That repository publishes multi-library native bundles for
**Android, iOS, macOS, Linux, and Windows**.

### 1b. Web Bridge Asset Production (CI)
Web bridge source/build and published runtime assets are managed in:

- [`leehack/llama-web-bridge`](https://github.com/leehack/llama-web-bridge)
- [`leehack/llama-web-bridge-assets`](https://github.com/leehack/llama-web-bridge-assets)

`llamadart` consumes pinned bridge assets from `llama-web-bridge-assets`
for `example/chat_app` and web backend testing via
`scripts/fetch_webgpu_bridge_assets.sh`.

### 2. Binary Consumption (Hook)
When a user adds `llamadart` as a dependency and runs their app:
- The **`hook/build.dart`** script executes automatically.
- It detects the user's current target OS and architecture.
- It downloads the matching pre-compiled native bundle from
  `leehack/llamadart-native` GitHub Releases.
- It reports the required shared libraries to the Dart VM as `CodeAsset`s,
  including `package:llamadart/llamadart`.

### 3. Runtime Resolution (FFI)
- The library uses **`@Native`** top-level bindings in `lib/src/backends/llama_cpp/bindings.dart`.
- The Dart VM automatically resolves these calls to the downloaded binary reported by the hook.
- This provides a "Zero-Setup" experience while maintaining high-performance native execution.

## Setting Up the Development Environment

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/leehack/llamadart.git
    cd llamadart
    ```

2.  **Initialize**:
    ```bash
    dart pub get
    ```

3.  **Build/Fetch Native Library**:
    In most cases, simply running the examples will handle everything:
    ```bash
    cd example/basic_app
    dart run
    ```
    The `hook/build.dart` will automatically download the correct pre-compiled binaries for your platform.

## Maintainer Workspace Conventions (Multi-Repo)

Maintainers often keep related repositories as siblings one level above
`llamadart`:

```text
../llamadart
../llamadart-native
../llama-web-bridge
../llama-web-bridge-assets
```

This is a convenience convention, not a hard requirement.
Always verify paths in your environment before using them.

- If changing native runtime behavior: edit `../llamadart-native`, release there,
  then sync/update `llamadart`.
- If changing web bridge runtime behavior: edit `../llama-web-bridge`,
  publish assets to `../llama-web-bridge-assets`, then update pinned tag/docs
  in `llamadart`.
- Keep ownership boundaries clear: this repo should avoid direct upstream
  source patching for native/web runtime internals.

## 🧪 Testing

We take testing seriously. CI enforces **>=70% line coverage on maintainable `lib/` code**. Auto-generated files are excluded when they are marked with `// coverage:ignore-file`.

The authoritative contributor test matrix lives in
[`doc/testing_matrix.md`](doc/testing_matrix.md) and
`tool/testing/test_matrix.dart`. Use it to decide which runtime/model/feature
rows apply to a PR and to generate the evidence table for the pull request:

```bash
dart run tool/testing/test_matrix.dart --list
dart run tool/testing/test_matrix.dart --pr-template
dart run tool/testing/test_matrix.dart --tier platform
```

### 1. Unified Test Runner
We use `dart_test.yaml` and `@TestOn` tags to manage multi-platform execution.
Running `dart test` will run VM and Chrome-compatible tests. Tests tagged
`local-only` are intentionally skipped in default and CI runs.

```bash
# Run default suite (VM + Chrome-compatible tests)
dart test

# Discover heavyweight local-only E2E scenarios
dart run tool/testing/run_local_e2e.dart --list

# Preview the commands for one scenario without running it
dart run tool/testing/run_local_e2e.dart --scenario chat-app-model-cache --device macos --dry-run

# Run representative local real-model feature smokes
dart run tool/testing/run_local_e2e.dart --scenario gguf-chat-features-smoke --model-path models/Qwen3.5-0.8B-Q4_K_M.gguf --backend auto
dart run tool/testing/run_local_e2e.dart --scenario litert-lm-chat-features-smoke --model-path /path/to/gemma-4-E2B-it.litertlm --backend auto
dart run tool/testing/run_local_e2e.dart --scenario chat-app-web-mock-smoke

# Benchmark native generate/create TTFT and throughput
dart run tool/testing/native_inference_benchmark.dart --model models/Qwen3.5-0.8B-Q4_K_M.gguf --gpu-layers 0 --mode all --runs 3 --max-tokens 128

# Run root local-only Dart E2E tests directly
dart test --run-skipped -t local-only
```

### 2. Manual Platform Selection
You can still target specific platforms if needed:

```bash
# Run only VM tests
dart test -p vm

# Run only Chrome tests
dart test -p chrome

# Verify architecture boundaries (shared/web-safe code has no dart:io/dart:ffi)
dart run tool/testing/check_platform_boundaries.dart
```

### 3. Coverage
To collect and view coverage reports:

```bash
# 1. Run VM tests with coverage
dart test -p vm --coverage=coverage

# 2. Format into LCOV (respects // coverage:ignore-file)
dart pub global run coverage:format_coverage --lcov --in=coverage/test --out=coverage/lcov.info --report-on=lib --check-ignore

# 3. Enforce >=70% threshold
dart run tool/testing/check_lcov_threshold.dart coverage/lcov.info 70
```

### 4. Testing Standards
- **Structure**:
  - Unit tests live in `test/unit/` and mirror `lib/src/` paths.
  - Generated/native-bridge files are excluded from strict mirroring when marked with `// coverage:ignore-file`.
  - Scenario, regression, and diagnostic tests live in `test/integration/`.
  - Slow, local-machine scenarios live in `test/e2e/` with `@Tags(['local-only'])`.
- **Manual scripts**: Do not leave one-off repro scripts in `tool/testing/`.
  Durable checks should become unit/integration/e2e tests. Heavyweight manual
  checks should be wired into `tool/testing/run_local_e2e.dart`, represented in
  `tool/testing/test_matrix.dart`, and mentioned in contributor docs when
  broadly useful.
- **Refactoring**: If you refactor shared logic, ensure both Native and Web tests pass.
- **New Features**: Every new public API or feature must include unit or integration tests.
- **Platform-Safety**: `LlamaEngine` must remain `dart:ffi` and `dart:io` free to maintain web support.

## Maintainer: Building Binaries

If you need to build binaries for a new release:

1.  Use the native build repository:
    ```bash
    git clone https://github.com/leehack/llamadart-native.git
    cd llamadart-native
    git submodule update --init --recursive
    ```

2.  Build/release with the native pipeline:
    - Run `Native Build & Release` in `llamadart-native` (`.github/workflows/native_release.yml`), or
    - Build locally via `python3 tools/build.py ...` as documented in that repository.

3.  Sync `llamadart` hook pin:
    - Run `Sync Native Version & Bindings`
      (`.github/workflows/sync_native_bindings.yml`) in this repository to:
      - resolve a `llamadart-native` release tag,
      - sync headers from the matching release header bundle,
      - regenerate Dart bindings from the matching native headers,
      - open an automated PR with the updates.
    - For local regeneration, run:
      ```bash
      tool/native/sync_native_headers_and_bindings.sh --tag latest
      ```

## Running Examples

### Basic App (CLI)
1.  ```bash
    cd example/basic_app
    dart run
    ```

### Chat App (Flutter)
1.  ```bash
    cd example/chat_app
    flutter run -d macos  # or linux, windows, android, ios
    ```

## Development Guidelines

-   **Code Style**: We follow standard Dart linting rules. Run `dart format .` before committing.
-   **Native Assets**: The package uses the modern **Dart Native Assets** (hooks) mechanism.
-   **Testing**: Add unit tests for new features where possible. Use `dart test` for full integration and unit verification.

## Submitting a Pull Request

1.  Fork the repository.
2.  Create a new branch (`git checkout -b feature/my-feature`).
3.  Commit your changes.
4.  Push to your fork and submit a Pull Request.
5.  Complete the production-readiness sections in the pull request template.

### Production-readiness expectations

`main` should remain production-ready. A pull request may reduce its scope, but
the scope it declares must be complete, documented, and tested before merge.
Use the pull request template to make that claim explicit.

Every non-trivial pull request should explain:

- **User-facing scope**: what users can do after the PR merges.
- **Supported platform matrix**: native, WebGPU, Flutter examples, docs-only, or
  any other relevant path.
- **Matrix evidence**: applicable row IDs from `tool/testing/test_matrix.dart`,
  including exact commands, CI workflow names, model/backend/device selections,
  and PASS/FAIL/N/A status.
- **Unsupported paths**: combinations that are intentionally unavailable must
  fail loudly with clear errors, disabled UI, or documented fallback behavior.
  They must not appear to succeed silently.
- **Docs and release notes**: README, website docs, examples, support matrices,
  and changelog entries are updated when public behavior changes.
- **Regression coverage**: tests cover the original issue and important
  negative/version-skew paths where applicable.
- **Security/privacy**: logs, errors, cache keys, metadata, and snapshots must
  not expose credentials, bearer tokens, signed URLs, or raw secret-bearing
  paths.
- **Follow-ups**: useful future work that is outside the declared scope should
  be linked as GitHub Issues before merge.

If a feature is not ready across all originally imagined paths, prefer reducing
the declared scope and tracking follow-up issues over merging incomplete or
ambiguous behavior.

### PR type examples

- **Feature PR**: describes the new API or behavior, supported platforms,
  unsupported combinations and their errors/fallbacks, docs/examples/changelog
  updates, and happy-path plus negative-path tests.
- **Bugfix PR**: states the root cause, the affected platform matrix, the
  targeted regression coverage, and any manual validation needed to reproduce
  the fix.
- **Docs-only PR**: states that runtime behavior is unchanged and lists the docs
  build/link checks or review performed.

Thank you for contributing!
