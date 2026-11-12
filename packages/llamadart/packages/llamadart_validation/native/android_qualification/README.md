# Paired Android diagnostic controls

This private harness refreshes only core [#1092](https://github.com/leehack/llamadart/issues/1092)
(Galaxy A35 fence timeout) and [#1304](https://github.com/leehack/llamadart/issues/1304)
(Pixel 8a EG2 Q8 correctness and warm wall time). It changes no production
selection, Android default guard, runtime pin or public API. It never sets
`qualified=true`; successful assertions require separate placement, provider,
cleanup and independent release assessment.

`AndroidQualificationPlan` freezes model revisions/hashes/sizes, requests and
case order. The model sizes and LFS hashes were read from the public Hugging Face
revision API on 2026-11-03. A35 uses the original 153406304-byte LFM2.5 Q4_K_M;
Pixel uses the original 309855456-byte EG2 Q8, not the multimodal BF16 pack.
`bin/android_qualification_plan.dart` exports the immutable download manifest and
request contract; models are pre-staged separately and hashed again on device.

Native controls are separate owned PIE processes linked to the exact APK
libraries, not replacements for the reporter's CLI. Each arms its own alarm;
the parent bounds stdout/stderr and kills/reaps a stuck child. Original bytes,
hashes and PID/case/source-runtime binding are persisted before parsing/oracles.
Mapped runtime paths must be the installed APK paths and their bytes must match
the admitted archive. Native IEEE float32 bytes and returned public float64 bytes
are captured before numerical predicates, retaining nonfinite failures that JSON
cannot encode. The consumer decodes raw little-endian float32, requires finite
768-dimensional values with a positive finite norm, binds input/phase/token
identity and requires its normalization to match the reported JSON within 1e-12
relative error per component (zero must match zero). The native producer uses
17 significant digits; a compiled
model-free C++ fixture shares that exact serializer and exercises the real
consumer. This transport bound leaves the 0.999 cosine/1e-4 norm oracle unchanged.
Native operation wall includes memory reset, embedding toggles,
compute and vector copy; it excludes normalization and record writes. Vulkan
selection requires exactly one Vulkan-registry discrete or integrated GPU;
no CPU or OpenCL substitution is accepted. Real placement still needs the raw
positive offload/compute records and hardware device facts independently assessed.

The public path uses `LlamaEngine(LlamaBackend())`, complete serialized engine
lifetimes and no client/service factory. Public cells share one Flutter OS
process; cache, order and thermal history limit timing comparisons. A Java thread
independent of Dart enforces each public stage deadline and native-stderr size
bound by terminating the owned app process on failure. It leaves a failure file
next to already flushed diagnostics. A provider timeout remains the outer bound.
Malformed native metadata is replacement-decoded only for its geometry view;
the original stderr bytes and hashes remain evidence. Wire/model text stays strict.

A35 retains explicit 512 batch/microbatch as a diagnostic override, never a
default-cap lift. Native CPU/default-Vulkan/conservative-Vulkan precede public
CPU/Vulkan/reload. Raw text stays exact; failed CPU/GPU parity remains FAIL even
when each public backend agrees with its native control. An error records the
active case and leaves later cases NOT_RUN. A completed short control does not
close the missing reporter details or qualify general Mali correctness.

Pixel counts use public tokenization with special tokens, matching embedding
ingestion and preserving the original 9/46 precondition; token IDs are retained.
Native CPU/Vulkan probe processes each produce both inputs before the
separate timing processes can start. Full vectors must be 768-dimensional,
finite, unit normalized within 1e-4 and cosine >= 0.999 against the same-artifact CPU
control. Public cells check their first vector before further timed calls and
each subsequent vector before continuing. Both 9/46-token inputs, every phase
and five warm measurements must be present, unique and valid. Raw failed vectors
and timings remain available; failed timings are not admitted. Native operation
wall and SDK wall remain separate. These controls do not assign shader/driver
ownership or qualify Q4/Q5/Q6, alternate full-model formats or another Mali stack.

## Model-free checks

Use the pinned Flutter SDK and prepare the workspace first. From the private
package directory:

```sh
dart pub get
TMPDIR="$(mktemp -d)" dart test -p vm test/android_qualification_test.dart
python3 -m unittest discover -s native/android_qualification -p 'test_*.py'
dart analyze
```

Host capture, process-death, malformed/truncated record, vector, build-binding
and hostile artifact checks load no model. Cross-compilation, ELF inspection and
these tests do not prove Android permits launching the installed executable.

## Local stage and APK preparation

Freeze clean committed source before staging. The root owns independent source
audit and metered admission. Use a new ignored output directory. From the root:

```sh
cd packages/llamadart_validation
dart run bin/android_qualification_plan.dart a35 /tmp/a35-plan.json
cd ../..
python3 packages/llamadart_validation/native/android_qualification/build_probe.py \
  --dart /path/to/pinned-flutter/bin/cache/dart-sdk/bin/dart \
  --ndk /path/to/android-ndk-28.2.13676358 \
  --native-archive /path/to/llamadart-native-android-arm64-v0.9.0.tar.gz \
  --headers-archive /path/to/llamadart-native-headers-v0.9.0.tar.gz \
  --plan /tmp/a35-plan.json --out .dart_tool/android-qualification/a35
```

Select `pixel8a` with a separate plan/stage for Pixel. The builder verifies both
archive hashes, confines extraction, compiles with 16KiB LOAD alignment and seals
the tracked source inventory, hook, probe, runtime files and request hash. It
retains all 15 owner archive files as provenance, then calls the real production
hook selector with its normal Android CPU/Vulkan policy: 14 packaged runtime
libraries plus the probe. OpenCL remains in archive provenance and is omitted
from the packaged lock; the stage does not inject it. The selection and selector
source hash are sealed. Runtime libraries come through the normal hook; the
optional stage adds only the probe and binding assets. Exact selected library
bytes are retained through AGP packaging.

After source audit, local APK preparation uses the existing Flutter
instrumentation recipe, with `LLAMADART_ANDROID_QUALIFICATION_STAGE` set to the
absolute stage directory for **both** commands:

```sh
cd example/chat_app
flutter build apk --debug --target integration_test/android_native_qualification_test.dart \
  --target-platform android-arm64
cd android
./gradlew app:assembleAndroidTest \
  -Ptarget=integration_test/android_native_qualification_test.dart \
  -Ptarget-platform=android-arm64
```

The matched APKs are `build/app/outputs/flutter-apk/app-debug.apk` and
`build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk`. Preserve both
hashes/source binding and the build logs. Check the app before admission:

```sh
python3 packages/llamadart_validation/native/android_qualification/verify_apk.py \
  --apk /path/to/app-debug.apk --plan /tmp/a35-plan.json \
  --binding .dart_tool/android-qualification/a35/stage/assets/llamadart_android_qualification/binding.json
```

Independent admission also checks the actual merged manifest/extraction policy,
instrumentation target/classes, source/APK provenance and test APK. The static
verifier alone deliberately cannot claim any of them from matching library hashes.

## Device execution contract (not dispatch authorization)

Use one selected device, zero flaky retries, a 20-minute provider timeout and the
shared bounded-budget journal. No dispatch helper is added here. Root must supply
fresh personal-account project/billing/quota/device receipts, record the admitted
APK pair and retain prior reservations. The existing instrumentation `stageModel`
path copies `/data/local/tmp/llamadart-smoke.gguf` into app cache. Supply exactly
the scenario's verified model there, `stageModel=true` and
`androidQualificationScenario=a35` or `pixel8a`. The app checks A35/API35 or
Pixel8a/API34 before loading. Changing the device/OS needs a separate prospective
scope decision; a different tuple never inherits qualification.

The very first child is an explicit **model-free launch probe**. Failure stops
all inference and retains captured loader stderr. Only successful real Android
launch can satisfy this gate; host tests and an ELF entry point cannot. A full
local device execution was not performed during implementation.

After source and APK admission, an app-UID packaging check can invoke the same
bounded probe directly without a model or the instrumentation preparation path:

```sh
<nativeLibraryDir>/libllamadart_android_qualification.so probe cpu /dev/null \
  <nativeLibraryDir> <64-hex-execution-binding> pixel8a.native.cpu-probe 10
```

It resolves linked runtime dependencies and emits actual maps before any backend
initialization or model loading. This proves only admitted executable launch and
linker resolution, not Vulkan initialization, placement or inference. Running it
on a temporary emulator remains a separate operator action, not a new APK-build
or device-dispatch permission inferred from this document.

Collect the whole exact `android_qualification/<nonce>` external app directory,
including failed raw bytes, `diagnostic.jsonl`, all native `capture.json` receipts,
public stderr/maps, `vkjson.json`, installed APK hash and any watchdog-failure
file. Do not import this envelope as a catalog suite or invent fixture passes.
The journal is not a replacement for native placement analysis, provider terminal
state, cleanup read-back or independent acceptance. Preserve original issue
failures; never use successful collection or process launch as inference evidence.

### Raw evidence transport

Test Lab may retain `diagnostic.jsonl` while omitting sibling captures. The
private harness therefore also exports each started native capture and public
stderr/maps as binary base64 chunks in that journal, before its final summary.
`raw_file_start` and `raw_file_end` bind name, byte length, SHA-256 and chunk
count; chunks have zero-based consecutive indexes. `raw_export_end` lists the
completed files. Missing files or the 4 MiB per-file / 32 MiB aggregate limit
make export incomplete and fail the test. Each chunk contains at most 24 KiB
of original bytes. Failed native cases retain their available raw captures too.

Reviewers must recover bytes without UTF-8 conversion, require every index and
matching start/end inventory, and verify lengths and hashes. A missing final
envelope, missing expected capture, or digest mismatch is an evidence failure;
functional PASS rows cannot override it. The original c327 A35 run remains
functional-only because its stderr/maps were not retained. The repaired export
still requires physical-device qualification; local round-trip tests are not
proof of provider retention.

Recover a collected journal offline into a new directory:

```sh
python3 packages/llamadart_validation/native/android_qualification/decode_raw.py \
  /local/diagnostic.jsonl --out /local/fresh-recovered-captures
python3 -m unittest discover \
  -s packages/llamadart_validation/native/android_qualification \
  -p test_decode_raw.py -v
```

Successful decoding proves raw integrity only. It does not establish GPU
placement, correct effective geometry, functional success or release readiness.

## Android full/compact consumer release smoke

`integration_test/android_consumer_profile_test.dart` closes the automation gap
in `doc/android_runtime_smoke_test_plan.md`; it does not reuse the A35 Vulkan
qualification as CPU-profile evidence. It exercises only the unmodified public
`LlamaEngine(LlamaBackend())` path. There is no native control, library-path
override or injected service/factory. The issue diagnostic above retains its
native/public controls. `full` and `compact` refer to consumer hook packaging,
not Flutter build mode: both APKs must be **release** builds.

Use two new isolated checkouts of the exact source being qualified. In each,
replace the chat app's complete `hooks.user_defines.llamadart` map with:

```yaml
llamadart_native_runtimes: llama_cpp
llamadart_native_tag: v0.9.0
llamadart_native_backends:
  platforms:
    android-arm64:
      cpu_profile: full # compact in the second checkout
```

In each isolated qualification checkout only, also move the existing
`integration_test: {sdk: flutter}` entry from `dev_dependencies` to `dependencies`.
Keep it under `dev_dependencies` in the normal chat example. Flutter 3.47.1 omits
dev-only Android plugins from release dependencies and release registrants; the
instrumentation target requires this SDK plugin in the release app itself. The
planner rejects missing, dev-only, duplicated or non-SDK entries before building.

Resolve the changed consumer with the pinned SDK (`flutter pub get --offline`
when dependencies are cached), then commit its `pubspec.yaml` and generated
`pubspec.lock`. Never edit the lock by hand. Retain both commit/tree identities
and the exact pubspec hashes. This narrows the example's optional `all` runtimes
to the default public llama.cpp consumer;
backend selection stays the normal CPU/Vulkan policy. Full packages all seven
CPU modules; compact packages only `android_armv8.0_1`. Never copy runtime `.so`
files into the stage. The real hook must emit every runtime library.

The following are preparation/build instructions for the authorized operator,
not device dispatch authorization. From each clean committed checkout:

```sh
python3 packages/llamadart_validation/native/android_qualification/prepare_consumer.py \
  --dart /path/to/pinned-flutter/bin/cache/dart-sdk/bin/dart \
  --native-archive /path/to/llamadart-native-android-arm64-v0.9.0.tar.gz \
  --profile full --out .dart_tool/android-consumer/full
```

The preparer checks the pinned archive SHA, reads the actual consumer pubspec,
uses the production selector, and binds the complete source inventory and
selected owner bytes. It does not compile a native probe, download inputs, read
models, build an APK or call a device/provider. The existing `verify_apk.py`
accepts this no-probe binding and rejects omitted/extra/modified runtime files.
This is static admission only. `--dry-run` reads no archive or model and emits prospective
build commands and old/modern NOT_RUN drafts without creating an output directory.
Actual preparation saves `operator-plan.json` with both commands and the same
base64-encoded Dart defines for Gradle.

Set `LLAMADART_ANDROID_CONSUMER_PROFILE_STAGE` to the absolute generated `stage`
directory for **both** build commands. This stages binding assets only, retains
installed library bytes and sets AGP's instrumentation test build type to release.
It also applies `consumer-profile-proguard-rules.pro` only to this qualification
release: the separate test APK needs the SDK runner/plugin, manifest-declared
`AndroidJUnitRunner`, `ActivityTestRule`, instrumentation registry and JUnit
`RunWith`/`Rule` annotations preserved through app-only R8 shrinking. The SDK
exports this framework on the app classpath, so AGP omits it from the test APK;
keeping only the Flutter plugin classes leaves a manifest runner that is absent
from both APKs. The rules keep these entry points and annotation metadata while
allowing internal framework shrinking. Other app release builds are unchanged.
From `example/chat_app`, substitute the committed profile's actual hashes:

```sh
flutter build apk --release --target integration_test/android_consumer_profile_test.dart \
  --target-platform android-arm64 \
  --dart-define=LLAMADART_ANDROID_CPU_PROFILE=full \
  --dart-define=LLAMADART_SOURCE_COMMIT=COMMITTED_40_HEX \
  --dart-define=LLAMADART_SOURCE_TREE=COMMITTED_TREE_40_HEX
cd android
./gradlew app:assembleAndroidTest \
  -Ptarget=integration_test/android_consumer_profile_test.dart \
  -Ptarget-platform=android-arm64
```

The APK pair is `app-release.apk` and
`outputs/apk/androidTest/release/app-release-androidTest.apk`. Preserve build logs,
source inventory, actual compiled defines, merged manifests, instrumentation
classes/target, APK hashes and static verification. Use the preparer's exact second command, including `-Pdart-defines`, so both
builds receive identical compiled profile/source identities.
Do not admit an unmatched test APK or a debug/profile build. Unset all other
qualification/NPU stage variables. `--no-pub` skips Flutter's tooling/registrant
regeneration; use it only after pub resolution has refreshed the final consumer
plugin metadata. Dropping `--no-pub` while leaving the plugin dev-only removes
the registrant reference but still excludes the required release plugin.

Verify both APKs' actual manifests/DEX as well as the bound runtime inventory:

```sh
python3 packages/llamadart_validation/native/android_qualification/verify_apk.py \
  --apk /path/to/app-release.apk \
  --test-apk /path/to/app-release-androidTest.apk \
  --binding /path/to/stage/assets/llamadart_android_qualification/binding.json \
  --plan /path/to/stage/assets/llamadart_android_qualification/plan.json \
  --apkanalyzer /path/to/android-sdk/cmdline-tools/latest/bin/apkanalyzer
```

The consumer verifier requires `--test-apk` and Android SDK `apkanalyzer`. It
checks the test manifest's single `AndroidJUnitRunner` declaration and target
package against the app, then requires actual `dex packages --defined-only`
class rows for the Flutter plugin in the app, the declared runner and reflective
framework across the pair, and `MainActivityTest` in the test APK. `dex code`
must show runtime `@RunWith(FlutterTestRunner.class)` and a public
`ActivityTestRule` field with runtime `@Rule` in that test. References,
method/package rows, removed/obfuscated classes and stripped/renamed annotations
cannot pass. The result binds the test APK hash too. This is static packaging
proof, not plugin registration, instrumentation launch or inference proof.

Before any paid device dispatch, retain a successful local release
instrumentation launch with this exact pair (or a separately identified
model-free release pipeline pair), using an explicitly selected
`MainActivityTest` and the manifest-declared runner. A provider validation error
or zero executed tests is not a launch result. Keep this evidence separate from
the model/device qualification below.

Run **both APK pairs on both admitted device classes**, zero flaky retries.
Before dispatch, freeze exact old/modern device model, API, build and CPU/ISA
facts and record why the old device has lower ISA support. The operator supplies:

- `stageModel=true`, with the exact A35 LFM2.5-230M Q4_K_M file at the existing
  `/data/local/tmp/llamadart-smoke.gguf` staging path;
- `androidQualificationScenario=consumer-cpu`;
- `androidConsumerDeviceClass=old` or `modern`;
- `androidConsumerDeviceModel=EXACT_BUILD_MODEL` and
  `androidConsumerDeviceApi=EXACT_API`.

The native Java preflight rejects a mismatched model/API tuple. Device class is
an operator assertion, not a hardware capability probe. Dart checks release mode,
compiled profile/source identity, model SHA/size and installed runtime bytes
before loading; runtime build identity, CPU backend/zero GPU layers, effective
geometry, streamed output, wall times and maps are retained. It requires Paris
in the frozen 24-token output and exact output equality after full disposal and
reload. A Java watchdog bounds native stalls independently of Dart.

Collect the same `android_qualification/<nonce>` envelope. Raw export includes
CPU facts, installed APK hash, stderr and mapped paths. A completed public summary
proves only its asserted cases; process-scoped logcat, successful provider terminal
state and liveness must separately show no SIGILL, illegal instruction, SIGSEGV,
fatal signal, watchdog failure or crash. A missing summary/raw export or later
process failure never counts as a pass. Compare full/compact wall times on the
same modern device under recorded thermal/order conditions before applying the
existing within-noise performance criterion. Timing samples from this short smoke
alone do not establish a regression benchmark.

The required acceptance inventory remains four rows, each tied to its actual APK:

| Device class | Consumer profile | Required evidence |
| --- | --- | --- |
| old arm64 | full | load, Paris generation, dispose/reload, no crash/SIGILL |
| old arm64 | compact | same |
| modern arm64 | full | same, plus full/compact timing comparison |
| modern arm64 | compact | same |

Source/model-free checks and draft plans leave every row **NOT_RUN**. No waiver,
qualification or final 0.18 release acceptance is implied. Rerun against the final
release-prep artifact or independently admit a complete source/artifact mapping;
keep unrelated native-family, Vulkan and LiteRT gates separate.

The maintained staging commands now bind native `v0.9.0`. They require new
source/plan/runtime receipts before final-runtime acceptance; retained native2
Pixel observations and captured library-name fixtures remain historical evidence.
Retargeting these bindings does not qualify a device or authorize a device run.
