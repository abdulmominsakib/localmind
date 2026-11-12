# Android Perfetto collection capability

This model-free probe asks whether a physical Android/API 34+ Test Lab device
can expose registered GPU render-stage producers and return a fresh trace with
app-attributed CPU/idle controls. It does not load a model, launch an Activity,
create a Flutter engine or issue GPU work. App hardware acceleration is disabled.
A pass proves trace collection only. Even actual render-stage events can belong
to unrelated system processes; they do not qualify LiteRT inference placement.

The probe uses Android's [UiAutomation stdout/stdin/stderr API](https://developer.android.com/reference/android/app/UiAutomation#executeShellCommandRwe(java.lang.String))
to save shell-produced bytes in app-owned external storage, avoiding a pull from
shell-owned `/data/misc/perfetto-traces`. It queries both human-readable and raw
service descriptors, requests a 15-second trace, and emits unique CPU and idle
ATrace sections. The test has a 90-second deadline, finite command/output limits,
and no retry. Config source names must be registered in the raw descriptor;
[GPU counters alone](https://perfetto.dev/docs/data-sources/gpu) are insufficient.

## Build and freeze

Use an existing JDK, Android SDK 36/build-tools 35.0.0, and Gradle 8.14. The
project pins Android Gradle Plugin 8.11.1 and runner 1.3.0 and builds offline.
A missing cached dependency is a build failure; do not silently download a new
SDK or change the pins. Set `JAVA_HOME`, `ANDROID_HOME`, and `GRADLE_BIN` to those
installations.

```sh
dart run tool/testing/run_local_e2e.dart --scenario android-perfetto-capability --dry-run
dart run tool/testing/run_local_e2e.dart --scenario android-perfetto-capability
python3 tool/testing/validation/android_perfetto/build_probe.py \
  --gradle "$GRADLE_BIN" --output /absolute/fresh/probe-bundle
```

The scenario runs the Python negatives and builds both APKs without creating a
cloud resource. `build_probe.py` additionally freezes source-input and APK
SHA256/size manifests. Cloud submission requires a clean committed checkout,
independently reviewed exact head, and `build.json` with `submittable=true`.
`--allow-dirty` makes a local review bundle only; its APKs must never be submitted.
Do not call an uncommitted patch an exact-main build. Verify the APKs against
`build.json` immediately before uploading and freeze uploaded object generations
and SHA256 separately in the cloud runner evidence.

For the schema-aware parser regression, point `TRACE_PROCESSOR` at an inspected
native [Perfetto trace processor](https://perfetto.dev/docs/analysis/trace-processor)
binary with the `query` subcommand (validated locally with v58.2):

```sh
TRACE_PROCESSOR=/absolute/trace_processor python3 -m unittest discover \
  -s tool/testing/validation/android_perfetto -p 'test_*.py'
```

The ordinary Python suite skips this one external-parser test when the variable
is absent. A cloud qualification must run the real parser, pin its native binary
SHA256, and record its version. The verifier never downloads an executable.

## Bounded physical-device run

Use the maintained cloud runner/reservation ledger described in
[cross-platform validation](cross_platform_validation.md). Allocate a new
**A6-capability** row, distinct from A6 model-inference qualification. Bound one
S24/API 36 instrumentation submission to a 2-minute timeout, reserve 3 physical
minutes (US$0.25 at the [US$5/hour physical-device rate](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)), and use no retry. Confirm current price/quota in
the runner before reserving. Cloud approval and budget come from the session's
explicit authorization; this document does not grant them.

The reviewed execution wrapper supplies these exact gcloud options:

```sh
gcloud firebase test android run --type instrumentation \
  --app /absolute/probe-bundle/app.apk \
  --test /absolute/probe-bundle/test.apk \
  --device model=DEVICE_ID,version=36,locale=en,orientation=portrait \
  --test-targets 'class dev.llamadart.validation.perfetto.PerfettoCapabilityTest#collectModelFreeTrace' \
  --environment-variables perfettoProbe=true,validationCommit=FULL_REVIEWED_HEAD \
  --timeout 2m \
  --directories-to-pull /sdcard/Android/data/dev.llamadart.validation.perfetto/files/perfetto_capability \
  --results-bucket APPROVED_BUCKET --results-dir UNIQUE_RUN_PREFIX
```

`DEVICE_ID`, full SHA and storage prefix are frozen plan inputs, not defaults.
Verify current catalog availability. The runner reserves before submitting,
records the returned matrix ID, polls that matrix without a second submission,
collects its matrix/test/application receipts and settles the original row.
Never substitute an inference label, device, API or retry. The test does not
launch a Firebase console UI or include any model weights.

Pull the app-owned directory from that exact matrix. Require exactly one fresh
UUID directory and preserve the original ten files unchanged, including every
stderr file. Do not flatten the directory or replace the trace with an earlier
trace. Verify both installed APK hashes against the frozen bundle:

```sh
python3 tool/testing/validation/android_perfetto/verify_probe.py \
  /absolute/pulled/UUID --build /absolute/probe-bundle/build.json \
  --trace-processor /absolute/native/trace_processor \
  --trace-processor-sha256 INSPECTED_NATIVE_BINARY_SHA256 \
  --output /absolute/fresh/collection-qualification.json
```

The verifier checks inventory, hashes, source declaration, UUID, process ID,
raw registered producers, bounded trace packets and real CPU/idle slices. It
rejects missing/duplicate/stale markers, PID/clock skew, incomplete slices,
parse/data-loss errors and unsupported compressed packet formats. A source
mismatch or unsupported schema stops qualification; retain the evidence.

## Interpret the result

- `trace_collection_validated=true`: fresh transport and CPU/idle attribution
  passed, including real parser checks.
- `render_stage_transport_observed=true`: a registered producer emitted event
  packets. This is only transport availability; specifications and counters
  alone do not set it. No event is attributed to the probe or a model.
- No registered producer or no event: collection can still pass, while the GPU
  route remains unavailable or unestablished on that device.
- `gpu_inference_qualified` and `gpu_execution_attribution_validated` always
  remain false.

A later inference experiment needs request-specific GPU dispatch/completion
identity and matching model/partition execution, with CPU and software-rendering
fallback controls. A timestamp overlap, producer name, busy counter, Activity
frame, or successful CPU result cannot supply that evidence. See the owning
LiteRT runtime's GPU qualification procedure before proposing that experiment.

The foreground launcher uses Perfetto v49-compatible `--background-wait` and
requires its successful all-data-sources-started acknowledgment before submitting
the judged controls. Global Android `Trace.isEnabled()` alone is insufficient.
Config and acknowledgment travel through actual shell pipes. Android mksh
heredocs use temporary regular files in `shell_data_file` storage, which the
Perfetto SELinux domain cannot read. Inherited shell-created PID/stderr files
are also prohibited across that domain boundary. The daemon creates only a
UUID-scoped trace under `/data/misc/perfetto-traces`; collection waits for its
normal finite-config exit by observing the acknowledged PID’s `/proc` directory,
reads the trace, and removes that file. Startup first requires that same PID to
be visible. Shell `kill -0` is unsuitable because SELinux can deny even a
non-signaling permission check against the Perfetto process. The app saves
config, startup acknowledgment and stderr before validating the acknowledgment,
so a failed session remains diagnosable after cleanup. No
termination signal, fallback startup delay, or automatic capture retry is used.
The receipt binds acknowledgment time/PID before the CPU marker, and the verifier
still requires both complete CPU and idle controls from the parsed trace.
See the [official background tracing procedure](https://perfetto.dev/docs/learning-more/tracing-in-background)
and [v49 implementation](https://github.com/google/perfetto/blob/v49.0/src/perfetto_cmd/perfetto_cmd.cc).

The opt-in instrumentation suite also rejects a deliberately malformed config
and verifies that config, acknowledgment and stderr remain in app-owned storage
after scratch cleanup. A bounded provider row may target only
`PerfettoCapabilityTest#collectModelFreeTrace`; its one-case provider contract
must match that explicit target. Local Android validation runs both tests.
