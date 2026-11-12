# S24 LiteRT native/public qualifier

This private, prospective harness targets one `SC-51E`, API 36, SM8650 run. It
changes no production selector, owner guard, runtime pin or public API. Source
and model-free checks authorize no APK build or device/cloud execution.

The corrected CPU profile is unchanged `chat-litert-cpu`: Qwen3 SHA-256
`c5f39b4191926786c3e6668b62af4d6eb15248dfc7a5348252a9b406f33f2108`,
613,722,264 bytes, revision `e6687177`. The separate GPU profile retains
`555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4`,
614,236,160 bytes, revision `8414150f`. Their URLs, metadata, prompts and
oracles cannot be interchanged.

Both use the maintained C04 fixtures: “Reply with one short sentence saying
hello.” with `\bhello\b`, and “What is 3 + 4? Reply with only the number.” with
`^(?:3 \+ 4 = )?7[.!]?$`. Controls retain context 1024, four threads, temperature
0, effective top-k 1, top-p .9, seed 1, output 32 and thinking off. The native
control uses the exact exported Qwen template; the public route keeps its
normal bundle/template selection. Speculation is off; the legacy default
repetition penalty remains unapplied, matching the default service.

The immutable profiles retain `threads: 4`. Explicit public CPU uses four
threads; GPU ignores CPU thread counts, so public GPU and auto pass
`numberOfThreads: 0` (automatic). The service converts zero to an unset native
CPU-thread option. Auto therefore attempts GPU first; its CPU fallback also
uses automatic threads. Native CPU controls keep their four-thread setting.

## Fixed case graph

| Stage | Maximum seconds | Required result and dependent behavior |
| --- | ---: | --- |
| Staging and identity | 120 | Exact device, two model hashes, complete installed native inventory, final owner archive and compiled source/binding match. |
| Native launch and legacy GPU guard | 120 | Installed PIE launch probe loads no runtime/model. Separate native child requests GPU for `555…` and must refuse before generation. Guard failure stops dependent public GPU work. |
| Public legacy explicit GPU | 60 | Default service must expose the same native restriction as `LlamaUnsupportedException`; no backend override. |
| Native corrected CPU | 120 | Owned child runs both fixed C04 requests; raw native JSON, positive counters, mapped core and both semantic oracles must pass. |
| Public corrected CPU | 150 | Default service, two complete engine lifetimes, both C04 oracles each lifetime, cancellation and reload. |
| Public legacy auto | 150 | Real GPU failure warning, CPU selection, positive counters, process-wide CPU initialization plus fresh per-lifetime compilation, UTF-8 transport, cancellation and reload. Every legacy semantic result is recorded separately; transport success never qualifies legacy accuracy. |
| Native corrected GPU | 120 | Runs only after the native corrected CPU control passes. Owned child attempts the same two C04 requests once; exact raw JSON, positive counters, both semantic oracles and correlated Adreno/Vulkan or full OpenCL delegate initialization must pass. Failure/crash/timeout/malformed evidence is FAIL. |
| Public corrected auto | 150 | Runs only after the corrected native GPU control passes. Both C04 oracles in two fresh GPU engine lifetimes, positive counters, settled cancellation/reload, exact mapped core and correlated native GPU initialization are required. CPU fallback fails GPU qualification even with a real warning. |
| Cleanup and export | 60 | Persist final statuses, failed cases, legacy semantic failures and every unexecuted required case. |

Caps sum to 1,050 seconds. A Java watchdog independent of Dart enforces stage
bounds and a 19-minute app-process ceiling; Test Lab remains capped at 20
minutes, one execution, no retry. Native children also have an independent
115-second alarm and the shared owned-process helper's 120-second deadline,
2 MiB stdout and 8 MiB stderr limits. They cannot hang or crash a public engine
in the same process. Missing or exceeded captures fail; changing prompts or
models after a failed control is not part of this graph.

The owner guard presently recognizes only `555…`. The corrected model's GPU
attempt is therefore isolated in the owned native child. A failed corrected
GPU control leaves public corrected auto NOT_RUN, requires diagnosis/safe
restriction before qualification, and never authorizes an unguarded public
attempt. This harness does not extend the production guard.

## Evidence boundaries

The public route is the same uninjected default `LiteRtLmService` boundary as
the accepted macOS public qualifier. It has no explicit library path, runtime
factory, speech driver or backend override. Its default discovery probe and
each lifetime check exact mapped payload bytes. C API 1.0 plus frozen default
source and the mapped-library binding establish the selected route; no runtime
selection counter is exposed or claimed measured.

Corrected public auto requires the actual GPU backend, all GPU layers and
fresh per-lifetime initialization bytes without GPU errors or CPU fallback.
The product's automatic CPU retry remains unchanged; this GPU qualification
route must fail when that retry occurs. Legacy auto continues to require its
observed warning and CPU evidence. Earlier journals retain their recorded
results; an older all-PASS journal that selected CPU cannot establish public
GPU qualification.

Public chunks are exact default-service UTF-8 bytes. Finish is always labelled
`not_exposed_by_default_service`; settlement and positive token counters remain
separate observations. XNNPACK's delegate-created message is process-wide:
its first captured bytes/hash are retained once, while every lifetime needs a
new empty-at-load capture containing fresh native model compilation plus CPU
selection/layers zero. Reusing an earlier lifetime's compilation capture fails.
The retained prior S24 captures had 42/66 cumulative lines across two CPU
lifetimes but only one delegate-created line; no repeat initialization is invented. Native raw JSON comes only from the separate C API
control and is never attributed to the public route. Synchronous native finish
is likewise labelled unexposed. GPU delegate initialization is not per-request
accelerator execution proof, general GPU support or a throughput measurement.

The private GPU predicate admits two distinct initialization backends and
records the backend name. Vulkan retains the Adreno 750 hardware-adapter and
WebGPU-environment checks. The shared LiteRT GpuEnvironment message, a
recoverable OpenCL loader probe and an immediately compiled, single-signature
CPU embedder are not GPU fallback or conflicting OpenCL initialization. Unbound CPU delegation remains rejected.
Public qualification services use DEBUG (v1 API Debug, value 1). Upstream maps
both Debug and the direct child's Verbose (value 0) to TFLite VERBOSE output.
INFO suppresses the two full-delegation records required below; a GPU backend
name and correct answers cannot replace those records. The full proof stays
required for C04 and its cancellation predecessor.

OpenCL requires one created OpenCL device and
LiteRT GpuEnvironment, followed by fully delegated positive `LITERT_CL`
`decode` and `prefill_N` graphs, each with one partition, positive external
tensors and initialized OpenCL API, in order. Partial, repeated, malformed,
CPU-delegated, failed or conflicting-backend evidence fails. CPU accelerator
registration alone is availability, not CPU delegation. These predicates only
interpret the owned, source/model/PID-bound logs after the existing positive
C04 controls; they cannot qualify arbitrary unbound log text. OpenCL evidence
does not qualify Vulkan, and per-request GPU execution remains unobserved.

The saved-log fixture `test/fixtures/s24_opencl_stderr.txt` is the unchanged
11,951-byte GPU-child stderr retained from the failed mapsfix run, SHA-256
`f26a99f7e73e3d76b92a740794de3e9794ae843714a8a111a161d0624ebb5007`.
Its replay checks initialization recognition only. That run's protocol failure
and five dependent NOT_RUN cases remain unchanged; the fixture grants no
actual corrected-public-GPU or full-20-case qualification.

`test/fixtures/s24_public_auto_cpu_fallback.json` retains observation 432 from
`core018-litert019-s24-protocolfix-20261104`, including its original native
stderr capture and CPU fallback warning. Only unrelated answer and maps
fields were omitted. It is a negative regression
for corrected public GPU qualification. Its historical producer PASS result
is not rewritten or upgraded to GPU evidence.

The journal copies bytes with their original size and SHA-256 before parsing or
grading. Each capture contains exactly one `utf8` or `base64` payload. Strictly
valid UTF-8 is used only when it round-trips to the exact original bytes and its
escaped JSON envelope is smaller; binary, invalid UTF-8 and nonbeneficial text
retain base64. S24 explicitly opts into the compact writer; the existing
`captureS24LiteRtBytes` wrapper shared by Pixel continues emitting base64, so
Pixel source and host decoders keep their current wire format. Both S24 readers
share the bounded codec in
`lib/src/s24_litert_capture.dart`. It rejects ambiguous/missing encodings, invalid
Unicode, changed size/hash and oversized claims before payload allocation.
No raw line or mapping snapshot is filtered, truncated or reused across
lifetimes. The watchdog retains the same 16 MiB physical JSONL and 8 MiB native
stderr limits; its failure reason names the file basename, observed size and
limit. A real overflow or missing final completion still fails.

Child capture first validates owned PID, exit, deadline, byte limits
and file hashes, then its own strict S24 protocol. The shared helper's GGUF
`protocol_complete` field is not S24 acceptance. Invalid UTF-8 remains preserved
in raw capture and fails wire parsing. Mapped libraries must have the admitted
installed paths and hashes. Earlier failed/transport-only JNI runs are unchanged
and receive no public-path or corrected-model credit.

The maintained host transport decoder is `native/android_litert/decode_s24.py`
with `s24_capture.py`; both files must be copied and hash-admitted together into
a new operator package. The existing frozen private base64-only decoder and
past journals remain unchanged. This decoder verifies byte integrity and
completion, always reports `qualified: false`, and does not replace independent
semantic/GPU/cleanup grading.
Provider exports may contain up to 16 journal aliases. Every candidate must be
an ordinary nonsymlink file in the exact run directory, nonempty and within the
unchanged 16 MiB journal limit. The host compares every byte using 64 KiB read
buffers and verifies equal size and SHA-256; any differing or invalid alias
fails the collection. Discovery snapshots each file's device, inode, mode, link
count, size, and nanosecond modification/change times. Admission opens every
collection-relative parent through its directory descriptor and opens each leaf
with `O_NOFOLLOW`; regular-file descriptors remain open through comparison and
parsing. Directory identity and file snapshots are checked before and after reads
and after parsing; a final bounded reread verifies every admitted hash. Replaced,
deleted, resized or rewritten journals fail, including canonical or parent swaps.
The parser consumes only the bounded admitted canonical bytes, never a reopened
journal path. Comparisons fill bounded logical blocks across legal short reads;
individual `read` boundaries cannot make identical aliases differ. Final
rediscovery repeats the alias cap, file admission checks and exact alias-set and
identity checks. A streaming digest snapshots the identities and content-change
times of every directory inside the collection, including directories without
an original alias. New aliases and transient directory-content changes fail the
collection; shared ancestors outside it are excluded. All descriptors close on
success or error.

This private host decoder requires POSIX `O_NOFOLLOW`, `O_DIRECTORY`,
`O_NONBLOCK`, and descriptor-relative `open`/nonsymlink `stat`. A host without
these primitives reports `Host lacks required no-follow descriptor admission
primitives`; there is no path-following fallback. This requirement does not
change public Dart platform support.

The alias cap bounds discovery metadata and repeated reads while allowing the
observed pair of provider export paths. The lexicographically first
relative path is canonical; the report retains all alias paths, sizes and hashes.
Only that canonical directory supplies the independently retained child files.
No raw export is modified, and alias admission supplies no missing completion,
semantic assessment or GPU qualification. This host-only change needs a new
hash-admitted decoder alongside the unchanged codec; it changes no APK bytes.

JSONL records are framed on literal LF bytes, with optional CR immediately
before LF. Strict UTF-8 capture strings may contain U+0085, U+2028 or U+2029;
those characters never split a record. Each frame is byte-bounded before text
decoding, and empty, truncated, malformed or non-object frames fail.

Model-free codec/transport checks, without compiling or running the native child:

```sh
TMPDIR="$(mktemp -d)" dart test -p vm test/s24_litert_capture_test.dart \
  test/android_litert_qualification_test.dart test/android_litert_mappings_test.dart \
  test/s24_litert_gpu_observation_test.dart
DART_BIN="$(command -v dart)" python3 -m unittest discover \
  -s native/android_litert -p 'test_s24_capture.py'
```

Source-only alias/framing regressions use the pinned original Dart outputs in
`native/android_litert/fixtures/dart_transport`, including their raw child files
and SHA-256 manifest. Run them without Dart or a prepared package:

```sh
python3 -m unittest discover -s native/android_litert -p 'test_s24*.py'
```

The Python transport lane additionally invokes `DART_BIN` directly with the prepared package
configuration to serialize complete model-free20-case Unicode fixtures using
the actual Dart codec and `jsonEncode`, with both LF and CRLF framing.

`test/support/replay_s24_capture_encoding.dart RETAINED_JSONL NEW_ANALYSIS_DIR`
replays only capture encoding, verifies every original event/capture identity and
writes a clearly labelled derived artifact. It never supplies a missing
completion or upgrades an interrupted run. A future device confirmation still
requires independent exact-source review, a clean source/inventory/binding seal,
fresh APK build and static/model-free probe review, new hash-bound host decoder
and financial admission, and separate paid authorization. The existing bootstrap
and final binding build procedure below is unchanged; no native rebuild is
needed for this Dart/diagnostic-only change.

## Source and APK admission still required

Freeze clean source and independent review before preparing an APK. The final
binding must contain exact source commit/tree/inventory, runtime tag `v0.19.1`,
`v0.19.1-1`, `v0.19.1-3` or `v0.19.1-4` (same Android binaries) or `v0.19.1-2`
(requalified on S24 in `matrix-wmalbq6nz437a`, see
[the adoption notes](../../../../doc/litert_lm_v1_adoption.md)) and its owner
commit, runtime archive and manifest hashes, complete owner archive libraries,
complete installed APK libraries, child executable and canonical Qwen template
hashes, both unchanged profiles, run id and the existing shared budget receipt
hash. Owner `7ea10d0` is explicitly rejected as the aborted candidate.
No final owner payload is selected by these source files.

Future native preparation compiles `main.cpp` as an Android arm64 PIE executable
with NDK 28.2.13676358, links `-ldl`, and packages it as
`libllamadart_litert_child.so` in the installed native directory. Preserve an
executable ELF interpreter and verify the final APK's complete native inventory;
a host build is not Android launch proof. The root owns the model-free installed
PIE launch check on the API 34 arm64 emulator before paid-device admission.

The separate instrumentation target is exactly
`com.example.llamadart_chat_example.S24LiteRtPublicTest`. The frozen submission
must select only that class. It requires explicit
`qualificationMode=s24-litert-public-v1` and `qualificationBindingSha256`, and
copies only the fixed staged Test Lab inputs:

- `/data/local/tmp/s24-litert-public-binding.json`
- `/data/local/tmp/s24-litert-public-cpu.litertlm`
- `/data/local/tmp/s24-litert-public-gpu.litertlm`
- `/data/local/tmp/s24-litert-public-template.jinja`

There is no HTTP fallback. Stale directories/configuration fail. Build the Dart
entrypoint `integration_test/litert_lm_s24_public_qualification_test.dart` with
`S24_LITERT_SOURCE_COMMIT`, `S24_LITERT_SOURCE_INVENTORY_SHA256` and
`S24_LITERT_BINDING_SHA256` from the admitted binding. Bind the produced APK/test
APK and compiled target/defines in a separate build receipt, then independently
verify them; no self-declared binding substitutes for that review. Pull the app's
external-files run directory and require its journal/hash/captures, not just a
provider SUCCESS result.

Use the maintained shared budget/admission procedure in
[the validation runbook](../../../../doc/cross_platform_validation.md#firebase-setup-submission-and-collection).
This lane keeps the existing third reservation at **USD 2.50**, the unchanged
**USD 22.50** shared cap and a single 20-minute execution. Its binding is not a
new reservation or dispatch permission. Fresh source/APK/device/budget admission
and an exact class-targeted command are still required; these files contain no
cloud submission command.

The built target APK must request `libOpenCL.so` once under `<application>`
with `android:required="false"`. Check the effective merged manifest, not
just source XML, before source/APK admission:

```sh
python3 native/android_litert/verify_manifest.py \
  --apk /path/to/app.apk --apkanalyzer /path/to/apkanalyzer
```

This static check binds the APK hash and target SDK and grants no device or
GPU result. The app's Android 12+/target 31+ vendor-library allowlist and the
actual OpenCL load/device result still need fresh correlated evidence. The
manifest correction does not resolve #1677 or litert-lm-native#51 by itself.

## Model-free source checks

From `packages/llamadart_validation`, using the pinned SDK:

```sh
dart analyze
TMPDIR="$(mktemp -d)" dart test -p vm test/android_litert_qualification_test.dart
python3 -m unittest discover -s native/android_litert -p 'test_*.py'
```

The C++ host fixture executes the actual child against a synthetic C API and
checks exact settings/prompts, raw response copying, counters, refusal, missing
JSON and wrong ABI. It loads no model and establishes no device result.

`protocol_output_fixture.cpp` includes the actual child translation unit with its
entry point renamed. Its `channels` mode exercises `Record` alongside simulated
vendor `printf`, raw stderr and C++ `cout`; it calls no runtime API. Expected
stdout is exactly two JSON records (`started`, `finished`, sequences 0 and 1).
Expected stderr is exactly these raw lines, in order:

```text
INFO: Loaded OpenCL library with dlopen.
vendor stderr
vendor cout
```

The `probe` mode calls the actual production entry point with nonexistent input
paths and must return zero with exactly its two JSON records and empty stderr.
`closed-stdout`, `closed-stderr` and `broken-protocol` must exit 74 without a
`finished` record. The protocol owns a close-on-exec duplicate of original
stdout; ordinary FD 1 is redirected to stderr before any runtime load. Setup,
write, flush or close failure is fatal; the strict JSON decoder stays unchanged.

For an old-source contamination control, compile the same fixture with
`-DS24_OLD_PROTOCOL_CONTROL` and
`-DS24_CHILD_SOURCE='"/absolute/path/to/old-main.cpp"'`, where `old-main.cpp`
is the unchanged pre-isolation translation unit extracted from the admitted
source revision. Its `channels` mode must retain the OpenCL and `cout` lines
on stdout, making strict JSON parsing fail; only `vendor stderr` remains on
stderr. Compilation alone establishes no channel behavior. The operator owns
execution and raw-channel capture; this fixture grants no runtime/model, APK,
emulator or device-run authorization.
