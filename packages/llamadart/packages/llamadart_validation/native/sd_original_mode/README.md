# Original SD24 load/generation diagnostic

This private, local-only harness extends the maintained image-container
qualification. It is a proposed PR41 diagnostic, not final-published-runtime
qualification or evidence that SD24 is closed. No runtime/model download occurs.
The patch-specific local-report exception is approved and merged. The upstream
ZIP report stays local; this harness does not post it or change the general
patch-retirement policy.

## Fixed case graph and oracle

The operator runs exactly six fresh processes, serially:

1. Native original Safetensors establishes a prospective raw RGB baseline.
2. Public original Safetensors matches native and that baseline.
3. Native original flat ZIP matches that same baseline.
4. Public original flat ZIP matches its direct-C result and baseline.
5. Native original nested ZIP matches that same baseline.
6. Public original nested ZIP matches its direct-C result and baseline.

Any failure stops the graph; all later cases remain `NOT_RUN`. No retries,
cache purges, prompt changes, alternate weights or substitute decoders are
allowed. A failed baseline never selects another oracle. Native and public
children write exact P6/128x128/255 RGB bytes; raw output hashes precede grading.
Every accepted image has 49,152 RGB bytes and more than 64 distinct byte values,
then must match byte-for-byte. The historical embedded-VAE `f08a13...` hash is
not this oracle. This is prospective same-weight parity, not an invented
historical generation measurement.

| Input | SHA256 | Bytes |
| --- | --- | ---: |
| Original Safetensors | `4505ca3da482f3e01679f6301bf23cde136e0cb3ffeb66b7e809038f619a19b4` | 2612796864 |
| Original flat ZIP | `05e2a2fef17ef03962c522374c01c373a71d5cbde20380f7800678c3ae99a75d` | 2613072319 |
| Original nested ZIP | `52dfdb8aa825c27bded6f11c5f25f8c4fe57405c0fc633e2f74f375186a36309` | 2613072319 |
| External full TAESD | `db169d69145ec4ff064e49d99c95fa05d3eb04ee453de35824a6d0f325513549` | 9793292 |

Metadata equality alone proves no tensor-value identity. Original input hashes
and retained trusted-producer receipts remain separate provenance. Keep all
earlier timeouts, load controls, metadata diagnoses and failed cases.

## Exact mode

Public loading uses `ImageConditioningCacheParams(capacity:4,
device:ComputeDevice.cpu, threads:4, flashAttention:true,
vaeDirectConvolution:false)` and explicit
`ImageModelPlacement(autoFit:true)`, with checkpoint and external TAESD roles.
No factory, driver, backend override or mock is used by the real child.
The normal mapper fixes eager loading and unbatched CFG. Its direct-C match is
`backend="cpu"`, `n_threads=4`, `eager_load=true`,
`conditioning_cache_size=4`, `batched_cfg=false`,
legacy `flash_attn=false`, `diffusion_flash_attn=true`,
`diffusion_conv_direct=false`, `vae_conv_direct=false`,
`flash_attn_mode="off,diffusion=on"`, `conv_direct_mode="off"`, and
`auto_fit=true`. There is no `offloadDiffusion` setting here;
`off,diffusion=on` is the recorded flash-attention mode.

Every request uses `a red fox in a green forest, watercolor painting`, 128x128,
one Euler/discrete step, CFG 1 and seed 42. Existing embedded-VAE/cache0/flash-off
container tests and native CLI behavior remain distinct and unchanged.

## Bounds, capture and provenance

Each whole case, from before RUNNING/launch through grade acceptance, has a
strict 180-second absolute cap. The model child has at most 177 active seconds
and up to 3 seconds for owned group termination/reaping. Grading consumes only
the remaining case time; it receives no extra allocation after model capture.
Both model and grader are also clamped to the aggregate deadline. The original
45-second load threshold remains a failing gate: reaching a valid image after
a late load never converts it to a pass. The public timer includes the cold
runtime check and binding verification before `ImageGenerationEngine.load`;
that diagnostic overhead is included conservatively, never hidden as a warm-up.
A 45-second pending-load observation
is captured when reached; a completed child records its reported load time.
Six 180-second case budgets plus the separately admitted two 30-second metadata
budgets total 19 minutes of case allocation. Those metadata runs are already
settled and are never replayed by this operator. Cleanup failure is failure.

The maintained aggregate controller additionally enforces three absolute
monotonic phases. Preflight has 57 active seconds plus up to 3 cleanup seconds,
60 total, for scoped Git metadata and all identity hashing. Before the first
model launch it starts one shared case deadline: 1,074 active seconds plus
up to 6 seconds of cleanup reserve, 1,080 total. Every model capture and pure
grader worker is clamped to that same deadline; no case or PASS can extend it.
Each grader has its own 7 active plus 3 cleanup maximum, charged inside the
case phase. Post/finalization has 7 active plus 3 cleanup seconds, 10 total.
Thus the current run allocates at most 1,150 seconds across these phases;
the earlier metadata's 60-second allocation is separate. Compilation is
separately performed and receipted, never run inside a measured case.

All blocking hashing and grading runs in owned data-only Python workers.
There are no asynchronous alarm contexts crossing a launch boundary. Active
or OS-pending foreign SIGALRM is refused before Popen, including a cancelled
timer whose signal remains pending. The two read-only Git builtins are direct
owned captures with hooks, fsmonitor, paging and submodule recursion disabled;
no unjoined Git child is hidden inside a successful hashing worker. A stale
grade/PASS after expiry is rejected. Unknown/unreaped cleanup or cancellation
prevents any new worker or model case; incomplete receipts stay failures.
Only exit zero plus the complete on-time receipts and diagnostic summary may
be accepted, never a summary file alone.

`owned_capture.py` adapts the independently reviewed metadata runner: mask
SIGINT/SIGTERM through Popen registration, defer repeated signals, kill the
owned group on abnormal paths before wait/reap, and atomically retain terminal
raw/hash receipts on exceptions or interruption. The admitted native and
compiled-Dart and data-only worker entrypoints spawn no processes. Only the
two explicitly scoped Git builtins are additionally admitted. Do not repurpose
this limited operator for arbitrary commands. Each raw stdout/stderr stream is limited
to 2 MiB; oversized/incomplete/malformed captures fail. The native program and
compiled Dart snapshot run directly, not through `dart run`, test launchers,
shell strings or build hooks. Missing/ambiguous configuration fails closed.

Hash-bind the native executable, Dart executable, public kernel snapshot,
native-assets manifest, raw native library, actual public staged library,
native/public build receipts, runtime staging receipt, independent artifact
review and source/plan admission. Both children reject a canonical mapped-path mismatch before any model
context construction; root prehashes that expected file. The operator also
refuses loader search/preload override variables. Run it from a clean loader
environment (unset DYLD/LD search/preload overrides).
Public `dladdr` identifies the address of
the actual default native-asset `sd_dart_new_sd_ctx` export before model load,
and its mapped-file SHA must match before runtime probing or model load. Native `dladdr` identifies its linked
export; the operator verifies that exact path/file hash. Public CPU/family and
runtime-version observations and native family logs are retained. This is
source-and-binding evidence, not a measured route counter or per-operation
hardware trace. Rewritten public install-name bytes require their own hash and
staging proof; an archive hash is not their identity.

The fixed diagnostic artifact is owner source
`6f54ed2d257faa0ed27d2a93cc5d89ea268e622d`, upstream
`be486498eadc29dc3cd234d944c2180ed42b1415`, PR41 run 41673639935,
artifact 13249907568. Its raw macOS arm64 library SHA is
`3c371373a9d91599c44a1301c3a3b8c3dca629c1b0cbfb3c1cf687bde4a3a5c8`.
The independent static artifact review is accepted for separately admitted PR
diagnostics only; it authorizes no model execution or final release claim.

## Prepare and inspect

Root prepares the native executable from the exact artifact's headers/library:

```sh
clang++ -std=c++17 example/basic_app/test/fixtures/image_container_native_reference.cpp \
  -I"$bundle/include" -L"$bundle/lib" -lstable-diffusion \
  -Wl,-rpath,"$bundle/lib" -o /local/prepared/native-original
```

For public execution, root stages the accepted candidate into an isolated
consumer native-asset binding, without changing production pins or shared
caches. Compile `image_original_container_child.dart` to a kernel snapshot
with that exact native-assets manifest. Use the existing
`compileDartScriptWithBundledNativeAssets` command pattern in
`test/support/dart_script_snapshot.dart` (`gen_kernel_aot.dart.snapshot`,
`--packages`, `--native-assets`, `--output`); retain the exact argv, source,
manifest, runtime/staging and resulting snapshot hashes. Do not invoke the
hooks inside the six measured cases. The planned bindings/build receipts
must be independently reviewed before execution.

The local JSON plan has `schema:1`,
`scope:"pr41-original-mode-diagnostic"`, exact `sourceCommit`, `ownerCommit`,
`artifactRun`, `artifactId`, three ordered `models` (`id`, `path`, `sha256`,
`bytes`), and `taesd` (`path`, `sha256`, `bytes`). Each required binding above
is an object containing an absolute `path` and full `sha256`; the keys are
`nativeExecutable`, `dartExecutable`, `publicSnapshot`, `nativeLibrary`,
`publicLibrary`, `artifactReview`, `sourceAdmission`, `nativeAssets`,
`nativeBuildReceipt`, `publicBuildReceipt`, `runtimeStagingReceipt`.
An unresolved field is not admission. Inspect the maintained scenario first:

```sh
dart run tool/testing/run_local_e2e.dart --scenario image-original-containers \
  --model-path /local/admitted-plan.json --dry-run
```

Only root removes `--dry-run` after exact source/artifact/build/plan admission.
The operator creates a fresh output directory, preserves raw/hash receipts
before grading and records all six statuses. `qualified` stays false; a
complete pass is labelled `diagnosticPassed`, not final-published qualification.

Model-free checks (no originals opened):

```sh
python3 -m unittest discover -s packages/llamadart_validation/native/sd_original_mode -v
dart test -p vm test/unit/tooling/run_local_e2e_test.dart \
  test/unit/tooling/test_matrix_test.dart \
  test/unit/backends/stable_diffusion/stable_diffusion_params_test.dart
```

The C ABI recording fixture is synthetic test infrastructure, never a qualified
runtime. It checks actual filled settings/request fields, old/new mode
separation, failure disposal and genuine parameter/prompt mutants. Transport
tests cover signals during Popen registration, repeated cleanup signals,
exceptions, actual short deadline/output limit and leader death. Protocol
tests reject late loads, trivial/wrong pixels, missing disposal, wrong raw
hashes, input substitution and continuing after a failed baseline.
Aggregate tests exercise shared deadlines winning over per-case limits,
prehash/grading/post timeout, no launch after expiry, late-result invalidation,
unknown-cleanup blocking, real owned Git completion and a real cancelled but
OS-pending alarm. Native/public child source bytes are unchanged from the
separately reviewed and built `0e214a5d` revision.
