# Observability

Configure a production instrumentation provider with
`configureInstrumentation(...)` from `package:genkit/telemetry.dart` before
creating `Genkit`. Genkit's development provider activates when a telemetry
server is configured; installing this plugin alone does not export telemetry.

The model response supplies backend-reported `usage.inputTokens`, `outputTokens`,
`totalTokens`, and `cachedContentTokens`. Missing measurements remain absent;
zero counts remain zero. Native llama.cpp and capable WebGPU bridges report
usage; do not assume every backend provides it.

Successful chat and batch media responses also supply `inputCharacters`,
`outputCharacters`, `inputImages`, `outputImages`, `inputAudioFiles` and
`outputAudioFiles`. Known empty counts are zero. A response can therefore have
`usage` while its token fields remain null.

Character counts use Dart `String.length` (UTF-16 code units). Chat input counts
delivered message text across the whole history, compact JSON tool arguments
and rendered tool results, including text-part joining. Omitted input reasoning
is excluded. Output counts final text, reasoning and compact JSON tool arguments
once, after streaming. These counts exclude templates, tool names/schemas,
configuration, metadata, media URLs/encoded bytes and hidden runtime work.
If returned tool arguments cannot be JSON-encoded, `outputCharacters` remains
null while the response and its other usage measurements are preserved.

For batch synthesis/image prompts, input text includes the newlines joining
text parts. Media counts count parts/files, not frames, patches, samples or
bytes. A reference audio file counts as input; each returned WAV/PNG counts as
one output. Progress events do not count as output. Video and separate reasoning
token measurements remain absent. Failed/cancelled operations do not fabricate
completed-output counts. Character/media counts are available in responses;
`genkit_otel` 0.2.0's standard token metrics still use only reported token fields.

`response.raw` additionally includes:

- `usage`: llamadart's usage map, with `time_to_first_token_ms` and `duration_ms`
  when reported. These backend timings exclude the plugin queue and model load.
- `queueMs`: time waiting for the model's serialized execution slot.
- `initializationMs`: time obtaining the runtime, including lazy model/projector
  loading on its first request.
- `totalLatencyMs`: elapsed time in the model action, including queue and setup.

`response.latencyMs` retains its existing generation-path timing after runtime
initialization. Usage is captured for ordinary chat and constrained JSON output.
These are per-model-call measurements. In Genkit Dart 1.0, `GenerateResult.usage`
reports the final model turn rather than the sum of all tool-loop turns. Genkit
instrumentation records each model call separately; aggregate those measurements
in your application or collector when you need whole-run usage.

Pass `observers: [yourObserver]` to `llamaDart(...)`, `prepareModel(...)`, or
`prepareModelTask(...)` to observe engine model loads, chat/text generation,
and embeddings, including failures and cancellation. Extend
`LlamaEngineObserver` and `LlamaOperationObserver`. Callbacks execute in the
request's Dart zone, allowing your instrumentation provider to correlate them
with the surrounding Genkit span, including after queue waits. Observer errors
are logged by llamadart without breaking inference. With a custom runtime
factory, that factory is responsible for installing its observers.

Observers receive request content. Export prompts, responses and tool data only
with an explicit application opt-in. Count token usage once at the model level;
engine diagnostics can carry the same measurements and should not increment a
second model-usage counter.

See [the observability example](../example/genkit_llamadart_observability_example.dart)
for `genkit_otel`'s `GenAiInstrumentation` and correlated engine spans. The
example initializes and shuts down the OpenTelemetry SDK, exporting model token
and duration metrics once. Message capture and raw action I/O are explicitly
disabled. Engine spans include only operation names and outcomes; upstream
instrumentation may still export exception details on failures.

The telemetry packages are development dependencies here; applications adopting
this example should add `genkit_otel` and `dartastic_opentelemetry` to their own
dependencies. They are not required by the plugin itself.

## Optional runtime timing recipe

The example also installs
[RuntimeTimingInstrumentation](../example/telemetry/runtime_timing_instrumentation.dart).
Copy this recipe into your application and register it **after**
`GenAiInstrumentation`. Supply your existing meter and tracer so it annotates
the active model span. Both providers must use the same OpenTelemetry context.
The application owns exporters, flushing and shutdown.

These custom histograms and matching span attributes use seconds:

| Name | Meaning |
| --- | --- |
| `llamadart.model.queue.duration` | Wait for the serialized model slot |
| `llamadart.model.initialization.duration` | Obtain the runtime, including first-load setup |
| `llamadart.model.action.duration` | Whole action, including queue, setup and inference |
| `llamadart.model.time_to_first_token` | Backend-reported TTFT, excluding queue/setup |

These are recipe names, not standard OpenTelemetry GenAI metrics. The recipe
does not duplicate backend-generation duration or token metrics. Each model
turn is observed once, including separate turns in tool loops. Histogram
attributes contain only `llamadart.outcome`: `completed`, `failed` or `cancelled`.
Prompts, outputs, paths, exception strings and arbitrary action metadata are not
read or exported by this recipe; other providers can still capture them.

Absent backend timings remain absent and zero remains zero. Successful responses
use the adapter's measurements. When an action throws, queue/setup/TTFT are
unavailable; only whole-action elapsed time from the instrumentation wrapper is
recorded. It includes validation and the wait before a queued cancellation is
observed. Negative, non-finite or non-numeric timing values are ignored.
Telemetry recording errors do not replace inference results or exceptions.

The example's final flush matters for short CLI runs: periodic metric export
may not have happened yet. Long-running applications flush and shut down
providers at their lifecycle boundary rather than after every model call.

Add the telemetry packages to your application:

```bash
dart pub add genkit_otel dartastic_opentelemetry
```

Start an OpenTelemetry collector accepting OTLP HTTP on port 4318, then run:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 \
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
LLAMADART_MODEL_PATH=/models/chat.gguf \
dart run example/genkit_llamadart_observability_example.dart
```
