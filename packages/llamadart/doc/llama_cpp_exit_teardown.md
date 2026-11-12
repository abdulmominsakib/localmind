# llama.cpp exit teardown

ggml-metal aborts in its static destructor
(`GGML_ASSERT([rsets->data count] == 0)`) when a process exits while a Metal
buffer is still allocated. `libllamadart` (`llamadart-native` `v0.5.0-1` and
later) keeps a registry of live objects and, on Apple platforms, frees what is
left of it during C `exit`, before that destructor. On other platforms nothing
runs at exit. The native contract is `src/llama_dart_wrapper.h` in
`llamadart-native`.

## Dart side

### Host shutdown precondition

A native host must stop and join its native workers and shut down its Dart
isolates or Flutter engine before calling C `exit()`. Await engine disposal,
including disposals already started elsewhere, then await engine/isolate
shutdown and native finalizers. A kill request cannot interrupt synchronous
native work; llama.cpp and image-worker disposal now await actual `onExit`.
Failed llama.cpp startups retain their exit listener so later disposal also
waits for a worker still finishing native initialization.

On Linux this protocol preserves ordinary host exit callbacks and C output
flushing. The runtime retains owned statics but does not force immediate
process termination or automatically free live objects at C exit. External
GPU/BLAS libraries still require all their workers to be joined. Direct C
exit with live Dart isolates is outside this contract: a no-model control
reproduces the Dart VM abort independently of llama.cpp. The Apple-specific
teardown coverage below does not establish safety for arbitrary live-isolate
exit on Linux.

Linux Flutter hosts must explicitly dispose their engines before process exit.
Flutter detaches its GTK windows when quitting `GApplication`; that alone does
not destroy the views, and plugins can retain engine references even after a
view is destroyed. The chat app's Linux Runner owns its windows and engines,
destroys the windows, and runs engine disposal during application shutdown.
The `chat-app-flutter-active-shutdown` matrix row checks this ordering with a
real native load and ongoing generation, including native host callbacks and
buffered C output. Its high-level startup case also awaits pending model
loading and repeated disposal before quitting. The image shutdown row checks
the same cooperative ordering during image loading and sampling. See
`doc/testing_matrix.md` for the bounded test scope.

### Object ownership

`lib/src/backends/llama_cpp/exit_teardown_api.dart` holds both ways a
`LlamaCppService` reaches llama.cpp:

- `ExitTeardownApi`: the tracked creators (`llama_dart_model_load_from_file`,
  `llama_dart_init_from_model`, `llama_dart_mtmd_init_from_file`),
  `llama_dart_exit_track` for the decision head's ggml objects,
  `llama_dart_exit_free`, and the guarded calls (decode, encode, synchronize,
  sample, state file and sequence state, LoRA init, mtmd tokenize and
  evaluation, scheduler graph compute). Every function is bound through the
  address `tryResolve` resolves, so the API exists only when the runtime
  exports all of them.
- `LlamaCppObjectCalls.upstream`: the upstream functions, which a runtime
  older than `v0.5.0-1` leaves as the only choice (`v0.5.0-2` is the oldest
  one to use: see "An exit during the last free"). The service then logs one
  warning at its first model load (visible at log level `warn` or lower) and
  exits behave as they did before exit teardown.

`lib/src/backends/llama_cpp/native_barrier_api.dart` holds the functions
`v0.6.0-1` adds (`NativeBarrierApi`): the last-error accessors, and wrappers
for the upstream functions the service used to call directly and that throw
(tokenize, token to piece, sampler accept, the lazy-grammar constructor,
memory clear, the three mtmd bitmap constructors, and the ggml device and
backend calls of the decision head). They are calls in flight for teardown
like the others, and are resolved all or nothing in the same way. See
"C++ exceptions".

`llama_dart_build_identity` (`v0.7.0-3`) is called directly, outside both:
it returns a constant of the library and touches no llama.cpp object, so
teardown cannot free anything under it.

One service uses one of the two for all of its calls.
`IsolateShutdownReleases` still holds every object and frees it when its
isolate shuts down; with exit teardown the hold's free function is
`llama_dart_exit_free`, which does nothing for an object teardown already
freed. `llama_dart_exit_call_begin`, `llama_dart_exit_call_end` and
`llama_dart_exit_teardown` are excluded from the bindings (`ffigen.yaml`):
they are not safe from an isolate that can be killed.

## What teardown waits for

Teardown waits up to two seconds for guarded calls in flight, then for a
250 ms settle after the end of the last guarded call, and frees the tracked
objects. It knows nothing about other native calls:

- An unguarded call on a tracked object (metadata reads, sampler
  construction other than the lazy-grammar one, and on a runtime older than
  `v0.6.0-1` also tokenize, detokenize, sampler accept, memory clear and
  media decode) that is in flight when teardown runs is not protected,
  however short it is. Teardown frees the object under it.
- A guarded call that is still running after two seconds (an image or audio
  evaluation, a long batch) makes teardown free nothing, and ggml-metal
  aborts as before.

## An exit during the last free

`llama_dart_exit_free` takes an object out of the registry before it has
finished freeing it. In `v0.5.0-1` teardown returned at once when the
registry was empty, so a direct C `exit()` that arrived while the last
tracked object was being freed did not wait for that free, and ggml-metal
aborted when the object still had Metal buffers allocated. The
`llamadart-native` investigation reproduced it with a projector or a split
(multi-file) model as the last object, and not with a single-file model. Only
a direct C `exit()` reached it; the exits that shut the isolates down wait
for the free.

`v0.5.0-2` fixes it: teardown waits for a free in flight. An exit that lands during the last free now takes that free plus the
rest of the 250 ms settle window, about 255 ms in the native measurements,
where it used to return at once.

The service is a second layer: `dispose()` and `freeModel` free contexts,
then the projector, then the model, so the last object a service frees is a
model and never a projector. That is also the lifetime order mtmd needs,
since a projector points at its model.

## C++ exceptions

llama.cpp reports some failures by throwing a C++ exception, which ends the
process when it crosses the C ABI into Dart. From `v0.6.0-1` every
`llama_dart_` function that calls llama.cpp catches it, records its message
for the calling thread (`llama_dart_last_error`) and returns a failure value.

- `LlamaCppObjectCalls.tracked` checks for that after a call returned its
  failure value (always, for a call that returns nothing) and throws the
  typed error of the operation: `LlamaModelException` for a model, LoRA or
  projector load, `LlamaContextException` for a context,
  `LlamaStateException` for a state call, `LlamaInferenceException`
  otherwise. The message names the upstream function and the details are
  llama.cpp's message. A failure value without a caught exception is
  returned as before.
- The message is per thread and the next call with a barrier clears it, so it
  is read in the same synchronous run as the call, before any other
  `llama_dart_` call. A call made outside `LlamaCppObjectCalls` (speculative
  decoding, the reasoning-budget sampler, TTS, the mtmd calls and the decision
  head's ggml calls) reads it with `NativeCallFailures.throwIfCaught` at the
  place that sees the failure value.
- The native contract leaves a llama or mtmd context in no defined state
  after a call on it caught an exception, and on Windows every object of the
  call, a model included. `NativeCallFailures` records those objects by
  address, the service refuses them with `LlamaStateException` at each entry
  point (`_ensureContextUsable`, `_ensureModelUsable`), and freeing an object
  forgets it. A decision head that caught an exception in one of its ggml
  calls stops running the same way.
- A runtime older than `v0.6.0-1` exports none of this: `NativeBarrierApi`
  does not resolve, the service calls the upstream functions as before and
  logs one warning at its first model load, and an exception still ends the
  process.

A failed `GGML_ASSERT` still aborts: the barrier catches exceptions only.

## Vulkan device facts

`lib/src/backends/llama_cpp/vulkan_device_probe.dart` binds
`llama_dart_vulkan_get_device_count` and `llama_dart_vulkan_get_device_info`
(`v0.6.0-1`), which list the system's Vulkan devices with their name, type,
API versions and subgroup size. Reading them makes the Vulkan loader load
the system's GPU drivers, so the service reads them once, and only where
ggml-vulkan has registered a device: for a load that selects one, and for an
Android Vulkan context.

The list follows ggml-vulkan's order but is not always its list: the two can
differ for a device below Vulkan 1.2 beside other GPUs and with more than 16
devices, so `VulkanN` is not entry `N`. A registered device is matched to its
facts by what both sides report, the Vulkan device name
(`ggml_backend_dev_props` `description`) and integrated or discrete. A device
with no such entry, or with several that disagree on Vulkan 1.2, has unknown
facts.

- llama.cpp `v0.7.0` needs Vulkan 1.2 (`ggml_vk_instance_init` refuses an
  older loader; for an older driver ggml-vulkan reads
  `VkPhysicalDeviceVulkan12Features` the driver never filled in and calls
  Vulkan 1.2 functions it lacks, once it initializes the device). A device
  is initialized only when a model uses it, so a load is judged by the
  devices llama.cpp would select for it, which
  `lib/src/backends/llama_cpp/load_device_selection.dart` mirrors from
  `llama_prepare_model_devices` (`src/llama.cpp`): the devices of an explicit
  backend, which llamadart lists; otherwise the discrete GPUs, one per
  device id, and integrated GPUs only when there is no discrete one; in
  single-device mode the one `mainGpu` indexes. A CUDA device, an unselected
  integrated GPU and a GPU of another backend never count. When every
  selected device is known to be below 1.2, `ComputeDevice.gpu` throws
  `LlamaUnsupportedException` and `ComputeDevice.auto` loads on the CPU with
  a warning. When usable devices remain, the load lists those and logs a
  warning naming the device it left out. A speculative draft model gets the
  same list. The projector and a decision head pick their own device and are
  not covered.
- An Android Vulkan context keeps the 8-token text-prompt decode cap unless
  the facts list exactly the registered devices and each has a subgroup size
  ggml-vulkan tiles correctly (8, or 32 and above). Before ggml `0.28.0`, a
  warp of the small matmul tile gets 8 rows only at a subgroup size of
  exactly 8 (`s_warptile_wm`), which is wrong at 16 and at every size below 8
  (https://github.com/ggml-org/llama.cpp/issues/28637). From `0.28.0` the cap
  is a speed default, and Qwen3.5 is no longer restricted on those GPUs.

A runtime without the functions, a loader that cannot be queried and a device
that cannot be matched all count as unknown: the cap stays, and no load is
refused or narrowed.

## Which exits are covered

| Exit | What happens |
| --- | --- |
| Flutter macOS quit (`-[NSApplication terminate:]`: the Quit menu item, a Quit Apple event, a last-window close, `exitApplication`) | The engine shuts the isolates down before C `exit`, so held objects are freed by their isolate. Teardown frees what no isolate held yet: a quit while a model loads, and a quit after a hot restart during a load, no longer abort. |
| Dart program returns from `main` or dies of an unhandled error; an isolate is killed | The VM shuts the isolates down first. An object created by a native call the isolate never returned from in Dart is freed by teardown. A killed worker in a process that keeps running: see "Forced worker exit". |
| `exit()` from `dart:io` | Runs no static destructors: no teardown and no abort. |
| C `exit()` while an isolate is still running (through FFI, or a native host that skips the engine shutdown) | Covered only while the isolate is idle, freeing an object, or inside a guarded call that returns within two seconds. Inside an unguarded call it is a use after free; inside a longer guarded call ggml-metal aborts. |

In a Flutter macOS quit with models idle, either layer is enough alone
(debug build on an M4 Max, each of the five quits `chat-app-macos-quit`
drives: the four paths in the table, with `exitApplication` once as
`AppExitType.required` and once as `AppExitType.cancelable`). With the
service on `LlamaCppObjectCalls.upstream`, the isolates' frees gave a clean
quit with a llama.cpp model loaded. With `IsolateShutdownReleases.hold`
doing nothing, teardown gave one with a llama.cpp and an image model loaded,
0.2 to 0.3 s later (its settle time). With both layers disabled at once,
every quit aborted. A Flutter hot restart shuts the old isolates down too:
the tracked counts after the restart and a second load equal the ones before
it.

Image models have their own registry in `libstable-diffusion`: see
"Image models".

## Creation-time owner preparation

When the loaded wrapper exports owner API v1, `NativeLlamaBackend` establishes
an empty parent-owned token before spawn. The worker attaches one stable native
finalizer before activation. Model, context and projector creators publish
ownership inside native code, before returning to Dart. Speculative and TTS
creators inherit ownership from their inputs. All service objects already
registered for shutdown share the native registry's stage ordering, so adding a
session or decision-head stage never detaches a model/context finalizer.

The parent drains after actual worker exit on a cleanup isolate; recorded exit
and `dispose()` wait for that cleanup. A failed cleanup retains its typed state
error, cause and original stack for current and later disposal/requests, and
prevents a worker restart. Closing startup ports does not create an unhandled
copy of that failed future. Dart cancellation flags and ports still close once
their worker has actually exited, even when native reclamation fails. Its bootstrap finalizer only aborts
pending tokens, never active payload used by a live worker. A separate worker
finalizer covers orderly isolate-group shutdown. The pinned Dart SDK guarantees
native finalization by group shutdown, rather than prompt callbacks at each
individual onExit. Host shutdown still has to stop/join workers first.

Opaque token IDs are never reused or dereferenced. Closing drains payload then
removes the control record; late duplicate finalizers are harmless. Killing the
parent between empty-token creation and bootstrap attachment may leave a small
control record until process termination. No guarantee covers arbitrary
simultaneous parent/worker death. Token registration is separate from payload
ownership.

The pinned `v0.9.0` runtime supplies owner API v1 for this creation-time
cleanup path. Capability resolution remains all-or-nothing: custom runtimes
with absent, partial or unsupported owner APIs use the existing path and
retain its creation-time gap rather than mixing ownership protocols.

Raw allocation-to-registration gaps remain under
[#629](https://github.com/leehack/llamadart/issues/629): token buffers, sampler
children/chain transfers, decision-head backend/buffer/scheduler and unheld ggml
contexts, LoRA and temporary allocations. Adoption of a held object preserves
cleanup order but does not make its earlier allocation kill-safe. This is a
bounded repair for [#1403](https://github.com/leehack/llamadart/issues/1403), not
universal allocation reclamation.

The local-only `llama_cpp_owner_creation_e2e_test.dart` uses a compiled test-only
FFI gate after real model/context creators return. It queues a real worker kill
before letting FFI return, checks no Dart result handling occurs, and checks
both parent-assisted drain and separate-isolate-group finalization. Set
`OWNER_TEST_LIBRARY`, `OWNER_TEST_GATE` and `OWNER_TEST_MODEL` to the exact local
wrapper, its `llamadart_owner_creation_gate` library and a cached GGUF. Run the
existing forced-exit suite too, including early/middle/late load kills on the
closest failing model, idle/generating kills and ordinary disposal controls.
Record library/model hashes and actual GPU metrics. Build hooks can replace a
manually copied candidate: use a local-bundle override or a direct pinned VM
package:test launcher with the prepared native-assets mapping, and verify the
library hash before and after each run.

### Production ownership-chain control

`llama_cpp_owner_chain_e2e_test.dart` also exercises the real parent backend,
its handshake, worker installation/activation, service model/context/projector
routing and parent release. It uses the test-only forwarding image in
`test/fixtures/llama_cpp_owner_chain_probe.cpp` to count those boundaries while
payload operations execute in one unchanged native image. This is instrumented
pipeline evidence, kept separate from unmodified-artifact model qualification.
The invalid-projector case proves typed refusal/routing, not projector inference.

On macOS, compile the fixture against the exact owner's wrapper and upstream
headers as a dynamic library, reexporting the candidate with
`-Wl,-reexport_library,<candidate>` and an rpath to its directory. The unchanged
candidate must be named `libllamadart.dylib` to satisfy its install name. Select
the forwarding image in the prepared native-assets map. Set `OWNER_CHAIN_PROBE`,
`OWNER_CHAIN_RUNTIME` (the same reexported candidate path), `OWNER_CHAIN_MODEL`
and each corresponding `_SHA256`. Do not separately load a second copy of the
runtime: independent native registries cannot exchange objects. The test checks
that production `@Native` and `DynamicLibrary` resolve the same underlying build
identity address, and counts parent release separately from worker finalization.

Run the old-pin test in a separate process with its real published asset selected,
`OWNER_CHAIN_OLD_PIN=1`, and the old library/model hash variables. It must have no
owner API, choose the production legacy fallback, and load/dispose cleanly. No
ownership improvement is claimed for that fallback. For exact-artifact model
cycles, select the unmodified candidate directly; the maintained forced-exit
suite pins decoding to two CPU threads for repeatable local qualification.

## Forced worker exit

`Isolate.kill` on a llama.cpp worker
([#629](https://github.com/leehack/llamadart/issues/629)) shuts its isolate
down, which frees every object the isolate held, as any isolate shutdown
does. Besides models, contexts and projectors the service holds each
context's token batch and sampler chain and the sampler chain of a running
generation, at the `session` stage, so they go before their context. The
batch is one `malloc` block (`token_batch.dart`) because `llama_batch_free`
takes the batch by value, which a native finalizer cannot call.

On runtimes without owner API v1, the process keeps running, so an object a
native call was still creating stays allocated until the process exits. The kill takes effect when the call
returns, before the isolate holds the object, so it stays tracked: teardown
frees it at C `exit` on Apple platforms, and nothing frees it elsewhere.
When the object is a context, the isolate still frees its model, and the
context outlives its model.

`test/e2e/backends/llama_cpp_forced_exit_reclamation_e2e_test.dart` measured
this on an M4 Max (macOS 26.7.1, llamadart-native `v0.7.0-2`), 10 cycles per
case, each cycle a new backend, `useMmap: false`, context 2048, with
stories15M and Qwen2.5-0.5B-Instruct Q4_K_M on the CPU and Metal, and
Qwen3-TTS-12Hz-0.6B-Base Q4_K_M with its Q8_0 projector on Metal:

| Case | Tracked objects left | Metal left | malloc in use, per cycle | `phys_footprint`, per cycle |
| --- | --- | --- | --- | --- |
| `dispose()` (control) | 0 | 0 | ≤ 12 KiB | ≤ 0.4 MiB |
| Kill while idle | 0 | 0 | ≤ 7 KiB | ≤ 0.4 MiB |
| Kill while generating | 0 | 0 | ≤ 19 KiB | ≤ 0.4 MiB |
| Kill while synthesizing speech | 0 | 0 | 12 to 17 KiB | 0.03 to 3.4 MiB |
| Kill inside the load (Qwen2.5, Metal) | 1 per kill, 10 of 10 | 374 MiB per kill | 30 MiB | 494 MiB |

Per-cycle values are medians. Before the batch and the sampler chains were
held, each kill left 0.1 MiB of malloc, and a kill during generation also
the chain's `n_vocab` × 12-byte candidate array (`llama_sampler_chain::cur`):
0.5 MiB with stories15M (32,000 tokens) and 1.8 MiB with Qwen2.5 (151,936
tokens). Loaded, a model held 2 tracked objects (4 for
speech), 107 to 1,194 MiB of footprint, and on Metal 139 MiB (stories15M),
704 MiB (Qwen2.5) or 2.7 GiB (speech). With `IsolateShutdownReleases.hold`
doing nothing, every kill left both objects, the whole Metal allocation and
about 110 MiB of footprint per cycle with stories15M.

With stories15M, kills late in the load left a context (80 MiB of Metal, its
KV and compute buffers) instead of a model. The first cycles grow the
footprint once, by about 200 MiB, or 830 MiB with speech, and later cycles
reuse it: after the speech cycles `vmmap` showed 831 MB of freed large malloc
blocks that libmalloc keeps dirty (`MALLOC_LARGE (empty)`) and 144 MB of
driver-owned graphics memory, while malloc in use and the Metal allocation
were back at their baselines.

## Rule for new code

A native call on a model, context, projector or decision-head object that
must not race exit teardown goes through `LlamaCppObjectCalls` or
`ExitTeardownApi`. When libllamadart has no guarded function for it, add one
in `llamadart-native` first; calling the upstream function leaves the call
unprotected at a direct C `exit()`.

A hires fix (`sd_img_gen_params_t.hires`) runs inside the one
`sd_dart_generate_image` call: both sampling passes and the latent upscale
use the generation's context and buffers, check the cancel flag as an
ordinary generation does, and need no new native call. The model upscaler
(`SD_HIRES_UPSCALER_MODEL`) would instead load an ESRGAN model from a path
inside that call, a load no cancel reaches; llamadart offers only the latent
upscaler.

Reference images (`sd_img_gen_params_t.ref_images`) are also encoded inside
`sd_dart_generate_image`, with the loaded autoencoder, before the first
sampling step, like an image-editing input; their pixel arrays live in the
generation's arena until the call returns. A cancel during the encode takes
effect at the first step. No new native call or object is added.

Every native call of an image worker goes through `StableDiffusionCalls`. A
new call on an `sd_ctx_t` that can run longer than the 250 ms settle time
(`generate_video`, `sd_ctx_load_control_net`, an upscaler) needs an
`sd_dart_` wrapper in `stable-diffusion-native` first.

## Tests

- `test/unit/backends/llama_cpp/exit_teardown_api_test.dart`: the stage
  values; the lookup requests all 22 names and resolves nothing when any one
  is missing; each member calls the function exported under its own name;
  `LlamaCppObjectCalls.tracked` uses the exit API for every call; one free per
  tracked object.
- `test/integration/backends/llama_cpp/native_symbol_integration_test.dart`:
  the address resolved for each name is the wrapper library's own export of
  that name.
- `test/unit/backends/llama_cpp/llama_cpp_service_exit_teardown_test.dart`: a
  recording `ExitTeardownApi` on a real CPU runtime. The whole recorded
  sequence is compared for creation and frees, plain generation (one decode
  and one sample per token), one-text and batch embedding on a decoder and on
  an encoder, state files, LoRA init, a decision head, a decision head that
  fails after its context was created, a fake projector, and an image the
  service rejects after the tokenize without an evaluating call. N-gram and
  draft-model speculation are matched against the sequences their loop
  allows. Everything created through the API has to be freed through it.
- `test/unit/backends/llama_cpp/mtmd_chunk_eval_test.dart`: `withExitTeardown`
  replaces the three evaluating calls and keeps the accessors, which are all
  the check of a media chunk against the micro-batch calls.
- `test/unit/backends/llama_cpp/native_barrier_api_test.dart`: the lookup
  requests all 18 names and resolves nothing when any one is missing or from
  a library that has none; each member calls the function exported under its
  own name; on the real runtime, a token outside the vocabulary, a trigger
  pattern that is not a regular expression and a grammar that rejects an
  accepted token are typed errors; `NativeCallFailures` marks and forgets
  free-only objects.
- `test/unit/backends/llama_cpp/exit_teardown_api_test.dart` also pins, for
  each tracked call, the error a caught exception throws and the objects it
  leaves free-only on every platform and under the Windows rule.
- `test/unit/backends/llama_cpp/llama_cpp_service_native_failure_test.dart`:
  a service on the real CPU runtime whose exit API and barrier fail the calls
  a test names. Each failed call is the typed error of its operation, the
  object it leaves undefined is refused afterwards and usable again once
  freed and recreated, and nothing created stays unfreed. It also loads a
  state file written by llama.cpp `v0.5.0`.
- `test/unit/backends/llama_cpp/vulkan_device_probe_test.dart`,
  `load_device_selection_test.dart` and the "Vulkan" groups of
  `llama_cpp_service_test.dart`: the device facts, the device selection and
  version check of a load, and the cap on each subgroup size, through an
  injected registry and injected facts. No default-CI test reads a real
  Vulkan device.
- No test forces an exception through speculative decoding, the
  reasoning-budget sampler or TTS: those functions are resolved inside the
  service and have no stand-in.
- Two cases of the service test do not run in default CI. The restore and
  replay of a rejected draft needs a model whose memory cannot drop a tail:
  set `LLAMADART_LFM2_MODEL` to an LFM2 GGUF. The decision head's device
  backend needs a GPU: it runs on a Mac unless `GGML_METAL_DEVICES=0`.
- No test reaches the free of a model whose vocabulary cannot be read after
  it loaded (`_createModelWrapper`).
- The same test pins the free order of `dispose()` and `freeModel`: context,
  projector, model.
- `test/unit/backends/llama_cpp/llama_cpp_service_shutdown_test.dart`: the
  free function and stage of every object the service holds, a running
  generation's sampler chain held until it ends and released when its setup
  fails, every hold released when its object is freed, and the exit of an
  isolate killed while idle or generating.
  `llama_cpp_service_native_release_test.dart` checks that `dispose()` frees
  a context's batch and sampler chain once.
- `native-exit-teardown` in `doc/testing_matrix.md`: local-only process exits
  on Metal, including a C `exit` while a service with a projector disposes.
- `chat-app-macos-quit` in `doc/testing_matrix.md`: local-only Flutter macOS
  quits with a llama.cpp model and, when their files are set, an image model
  and a decision head idle on Metal and nothing disposed, through a Quit
  Apple event, `terminate:`, a last-window close and `exitApplication`, and
  after a hot restart.
- `test/e2e/backends/llama_cpp_forced_exit_reclamation_e2e_test.dart`:
  local-only, macOS. Kills the worker while idle, generating or (with
  `FORCED_EXIT_TTS_MODEL` and `FORCED_EXIT_TTS_MMPROJ`) synthesizing speech,
  on the CPU and Metal, and requires every tracked object and Metal byte
  freed after each kill and a median growth per cycle under 48 KiB of
  malloc in use and under 8 MiB of `phys_footprint`. `FORCED_EXIT_KILL_LOADING=1` adds
  the kill inside a load, which fails until its object is freed (see "Forced
  worker exit"). Run it with
  `dart test -p vm --run-skipped -t local-only <file>`;
  `FORCED_EXIT_MODEL` replaces the cached stories15M.

## Image models

`libstable-diffusion` (`stable-diffusion-native` `v0.2.0-1` and later) keeps a
registry of its own and frees what is left of it during C `exit` on Apple
platforms, like libllamadart. The two libraries embed separate copies of
ggml and tear down independently. The native contract is
`src/sd_dart_wrapper.h` in `stable-diffusion-native`.

### Dart side

`lib/src/backends/stable_diffusion/stable_diffusion_calls.dart` holds every
native call an image worker makes, so a worker can run on a recording
stand-in:

- `sd_dart_new_sd_ctx` creates the context and tracks it inside the call.
  `sd_dart_generate_image` is the generation teardown cancels and waits for.
  `sd_dart_cancel_generation` cancels from the calling isolate and does
  nothing for a context that was already freed. `sd_dart_exit_free` frees a
  tracked context once; it is also the free function of the worker's
  `IsolateShutdownReleases` hold.
- `sd_dart_progress_enable` and `sd_dart_progress_read`: see "Image
  progress".
- `sd_dart_log_enable`, `sd_dart_log_set_level`, `sd_dart_log_read`,
  `sd_dart_log_dropped` and `sd_dart_last_error` (`v0.2.0-2`): see "Image
  log".
- `sd_dart_gpu_device_count` and `sd_dart_gpu_device_memory` (`v0.2.0-2`)
  read the memory of every GPU for the memory check of Vulkan GPUs. They run
  in a short-lived isolate of their own (`readStableDiffusionGpuMemory`), not
  in a worker.
- Upstream calls that return at once: `sd_ctx_params_init`,
  `sd_ctx_supports_image_generation`, `sd_ctx_has_control_net` and
  `sd_get_model_version_name` right after the load, `sd_img_gen_params_init`
  and `free_sd_images`.

`StableDiffusionCalls.tryResolve` binds the six `sd_dart_` functions through
the addresses it resolves, all or nothing. There is no fallback to the
upstream functions, unlike the llama.cpp backend: without the recorder a
runtime reports progress only through a Dart callback, which is the abort the
recorder removes, and without the callback the engine would report a
generation as successful while it emits none of the documented progress
events. `probeStableDiffusionRuntime` therefore reports such a runtime as
unavailable and names `v0.2.0-1`
(`StableDiffusionCalls.minimumNativeRelease`), and
`StableDiffusionImageWorker.start` throws the same
`LlamaUnsupportedException`. No supported configuration reaches an older
runtime: the hook downloads the pinned archives by checksum, this runtime has
no tag or path override, and the build rejects an Apple companion whose pin
differs from the core pin.

The functions `v0.2.0-2` added are optional: `StableDiffusionCalls.log` binds
the five log functions when the runtime exports all of them, and
`gpu` its two device queries, and each is `null` otherwise
(`StableDiffusionCalls.optionalNativeRelease`). On such a runtime image
generation works as it did on `v0.2.0-1`: no log call is made, a failed load
names the missing file roles and the release that reports reasons, and a
Vulkan GPU is not memory-checked. The same holds for the reason above: no
supported configuration reaches it, so the fallback is tested on the
stand-in and was run once by hand against the `v0.2.0-1` archive.

`sd_dart_exit_teardown`, `sd_dart_exit_call_begin`, `sd_dart_exit_call_end`,
`sd_dart_exit_track` and `sd_dart_exit_untrack` are excluded from the
bindings (`ffigen_stable_diffusion.yaml`): none is safe from an isolate that
can be killed. `sd_dart_exit_set_wait_ms` is bound and not called; the
runtime's default waits apply.

### What teardown waits for

- With no call in flight it frees the tracked contexts at once.
- While `sd_dart_new_sd_ctx` or `sd_dart_generate_image` is in flight it
  waits up to 15 seconds and asks the generation to cancel every 20 ms.
  stable-diffusion.cpp reads a cancel only before a sampling step and before
  the decode of each image, and a load cannot be cancelled, so the wait is as
  long as the phase that is running. A phase that outlasts the 15 seconds
  makes teardown free nothing, and ggml-metal aborts as before.
- It waits up to two seconds for an `sd_dart_exit_free` in flight, and gives
  a thread 250 ms after its last such call, which covers the short upstream
  calls after a load.
- A device query (`sd_dart_gpu_device_count`, `sd_dart_gpu_device_memory`)
  in flight is waited for like a load, up to 15 seconds, also when nothing
  is tracked: it reads ggml's device registry, which C `exit` destroys.
  llamadart makes the queries only for Vulkan GPUs, on Linux and Windows,
  where teardown runs only when a
  native host calls it. The probe's `sd_list_devices`, which initializes the
  devices first, is upstream's function and is not waited for.
- The log reads (`sd_dart_log_read`, `sd_dart_log_dropped`,
  `sd_dart_last_error`) are not calls in flight and need no wait: they touch
  no context and stay valid during and after teardown. Each can wait up to
  100 ms for a thread that is copying a message.
- The two runtimes wait one after the other: with a llama.cpp call and an
  image generation both in flight an exit can take about 17.5 seconds.

### Which exits are covered for image models

Measured on an M4 Max on Metal with SDXS and SD-Turbo; "before" is native
`v0.2.0` with the Dart progress callback.

| Exit | Before | Now |
| --- | --- | --- |
| Dart program returns from `main`, or dies of an unhandled error, with a model idle | Clean: the worker isolate's hold frees the context | The same |
| Dart program dies of an unhandled error while a model loads or generates | VM abort in the progress callback | Clean, once the native call returns. Nothing cancels the generation: the process ends when the generation does |
| Flutter macOS quit (`-[NSApplication terminate:]`) with a model idle | Clean | Clean |
| Flutter macOS quit while generating | VM abort in the progress callback | Clean, after the whole generation: the engine shuts the isolates down before C `exit`, so teardown's cancel never runs |
| Flutter macOS quit inside a load | VM abort in the progress callback | Clean: teardown frees the context the killed worker never held |
| Flutter hot restart inside a load, then quit | Crash at the restart (`Callback invoked after it has been deleted`) | Clean: the context of the discarded isolate stays tracked and teardown frees it |
| C `exit()` while the worker isolate is alive (through FFI, or a native host that skips the engine shutdown), model idle, loading or generating | ggml-metal abort | Clean within the waits above; a phase longer than 15 seconds aborts as before |
| `exit()` from `dart:io` | No static destructors run: no abort | The same |

So the 15 second wait applies only to a direct C `exit()`. A Dart or Flutter
exit waits for the native call itself, however long the generation is, which
is why the guides still tell apps to dispose an `ImageGenerationEngine` from
`onExitRequested`. A Flutter hot restart during a generation waits the same
way: the restart happens once the generation has finished. The wait after a
quit, a hot restart or an unhandled error is the rest of the generation; the
times measured with SDXS and SD-Turbo are examples, not a bound. A
one-argument native cancel that could run as a `NativeFinalizer` of the
calling isolate would let llamadart cancel a generation on those paths;
`sd_dart_cancel_generation` takes two arguments.

### Image progress

stable-diffusion.cpp reports progress through one process-wide callback on
the thread that loads or generates. A Dart callback there cannot be made
safe: the VM may already be shutting down, and the process aborts with
`GetFfiCallbackMetadata called after shutdown`. The runtime instead records
the reports in a ring, and Dart reads them:

- `StableDiffusionImageWorker.start` calls `sd_dart_progress_enable` on the
  calling isolate before it spawns the worker. The first call registers the
  recorder, unsynchronized, so it has to precede any load; it also keeps the
  runtime from printing progress bars. Nothing in llamadart calls
  `sd_set_progress_callback`, which would replace the recorder.
- `generate` asks for the newest sequence number before it sends the
  request, reads the reports after it every 50 ms and once more after the
  reply, and calls `onProgress(step, steps)` for each in order. One poll
  makes at most 64 reads of 64 reports, which is the 4095 reports the runtime
  keeps, so a runtime that reports faster than it is read cannot hold the
  calling isolate.
- Reports are numbered. When the first report of a read does not follow the
  last one read, the runtime dropped the ones in between: the worker delivers
  what is left in order and logs one warning with the count. A request at
  the limits (`maxCount` images of `maxSteps` steps) records 2416 reports, so
  one generation cannot overflow on its own; a second isolate generating at
  the same time could, and so could a tiled decode, which llamadart does not
  request but stable-diffusion.cpp falls back to when a decode fails with
  `GGML_STATUS_ALLOC_FAILED`. The effect is at most that warning and a gap
  in the progress events.
- Reports are process-wide, loads included. The engine's one-operation guard
  keeps one isolate from mixing two operations; two isolates that generate at
  once each see both runs' reports.
- stable-diffusion.cpp clears a cancel request when a generation starts. A
  cancel that arrived before then is applied again by each poll until the
  generation ends, so it lands at most one poll interval after the runtime
  started, whether or not a report arrives.

### Image log

stable-diffusion.cpp logs through a callback on whichever thread logs, with
a text that is only valid during the call, and returns only `NULL` from a
load that fails. From `v0.2.0-2` the runtime copies each message of
stable-diffusion.cpp and ggml into a 256 KiB buffer of its own, and Dart
reads them:

- `sd_dart_log_enable` and `sd_dart_log_set_level` run before anything that
  logs: in the runtime probe before `sd_list_devices`, in the isolate that
  asks a GPU for its memory before the query, and in
  `StableDiffusionImageWorker.start` on the calling isolate before the worker
  is spawned. The first registration is not synchronized, and none of the
  three runs beside a load, a generation or a device query of the same
  isolate. The recorder is registered at every log level, because
  `sd_dart_last_error` is empty without it; at `LlamaLogLevel.none` the level
  is `SD_LOG_ERROR + 1`, which records nothing. Once it is registered, ggml's
  messages no longer go to stderr.
- The level is the stricter of `LlamaLogging.level` and
  `LlamaLogging.nativeLevel` when the load starts
  (`imageRuntimeLogLevel`), since a message reaches the app through
  `LlamaLogger`. It is the process's: the last load sets it.
- The worker isolate reads the log, never the calling isolate: a read can
  wait 100 ms. It cannot read while it is inside a load or a generation, so
  it reads after each one and when it is disposed, up to 4096 messages a
  time, and sends them to the calling isolate before the reply of that
  operation. There is no timer, so an idle worker costs nothing, and at
  `LlamaLogLevel.none` nothing is read. Reading the 27 messages of an SDXS
  load at `info` took 84 microseconds on an M4 Max, and a read that finds
  nothing 2 to 4.
- After a load the worker first makes its calls on the context
  (`sd_ctx_supports_image_generation`, `sd_get_model_version_name`), which
  have to fall into teardown's 250 ms, and reads the log afterwards. After a
  failed load it reads `sd_dart_last_error` first, with no asynchronous gap,
  because the errors belong to the thread until its next load.
- The calling isolate keeps the position the log was read to and gives it to
  each worker with every command, so a second engine does not log the first
  one's messages again. Two isolates that load image models each read the
  whole log.
- `sd_dart_log_dropped` counts the messages that left the buffer unread. Its
  increase since the last read is logged as one warning.
- Texts are decoded leniently and file paths are replaced by roles
  (`stableDiffusionPathRedactor`), in forwarded records and in the reason of
  a failed load.

A C `exit()` while an isolate executes Dart code, rather than waiting in its
event loop or inside a native call, aborts in the Dart VM
(`runtime/vm/handles_impl.h: unreachable code`) when a model is loaded: with
an image model idle on Metal and a second isolate that only decoded UTF-8 in
a loop, 5 of 5 exits aborted, and none did without the model, where the
exit takes no time. So the rows of the table above hold for isolates that
are idle or inside a native call, and what reads the log during an exit can
only be shown from native code, as the tests of `stable-diffusion-native` do.

### Tests

- `test/unit/backends/stable_diffusion/stable_diffusion_calls_test.dart`: the
  lookup requests the six required names and resolves nothing when one is
  missing; the log and the device memory query are absent, each on its own,
  when a name of theirs is missing; each member calls the function exported
  under its own name; the generated bindings leave out the five unbound
  functions and mark only `sd_dart_progress_read` as a leaf call.
- `test/unit/backends/stable_diffusion/stable_diffusion_image_worker_test.dart`:
  the worker's two isolates on `test/support/fake_stable_diffusion_runtime.dart`,
  with a progress timer the test fires by hand. The whole call sequence of
  each isolate is compared for a load, a generation, a batch of three, a
  cancel before the runtime starts and one during a generation, dispose, a
  failed load, a model that cannot generate images and a runtime without the
  functions; with a log level, for the reads after a load, a generation, a
  failed load and dispose; and on a stand-in for `v0.2.0-1`, where no log
  function is called.
- `test/unit/backends/stable_diffusion/stable_diffusion_log_test.dart`: the
  level mapping, lenient decoding, a drain's reads, position and dropped
  count, and the reason of a failed load without paths.
- The root package does not bundle the runtime, so no default-CI test
  resolves the real exports. `image-exit-teardown` in
  `doc/testing_matrix.md` does, locally on Metal, along with the process
  exits, three of them with the log forwarded at debug level.
