---
title: Observability
description: Observe local inference with optional OpenTelemetry instrumentation, a runnable Dart example, and Langfuse and Grafana export recipes.
---

`llamadart` exposes operation observers and per-request usage. Your app can use
these hooks for logging, tracing or metrics without installing OpenTelemetry.
The optional companion package planned in
[#696](https://github.com/leehack/llamadart/issues/696) is separate work; this
guide uses an application-owned adapter today.

## Choose the pieces you need

| Piece | Responsibility |
| --- | --- |
| `LlamaEngineObserver` | Receives operation start/end, chunks, errors and available usage in plain Dart types |
| An OpenTelemetry (OTel) SDK | Creates spans and metrics, propagates context and exports telemetry |
| An optional OTel Collector | Receives, processes and routes telemetry to one or more destinations |
| Langfuse | Displays LLM generations, usage and sessions from traces |
| Grafana with Tempo and a metrics store | Displays traces and operational dashboards |

The [runnable example](https://github.com/leehack/llamadart/tree/main/website/examples/observability)
pins `dartastic_opentelemetry` and its API to `0.11.0`. Its dependencies belong
only to that example. Core `llamadart` has no OTel SDK dependency. If you already
use a different SDK, implement the same observer callbacks with that SDK.

## What the observer sees

Pass an observer when constructing the engine:

```dart
final engine = LlamaEngine(
  LlamaBackend(),
  observers: [const OtelObserver(modelLabel: 'local-demo-model')],
);
```

`OtelObserver` comes from the example's `lib/otel_observer.dart`; it is not an
export of `package:llamadart/llamadart.dart`. Copy that file into your app and
add its pinned SDK dependencies to use it there.

The adapter creates an `INTERNAL` span for each chat completion, raw text
completion, embeddings request and model load. Inference runs in-process.
`createStructuredJson` and `ChatSession.create` use the chat observer too.
This hook does not automatically trace tool execution, model downloads,
next-token scoring, speech APIs or GPU kernels. Add application spans around
those operations as needed.

Streaming operations begin when listened to. Callbacks run in the zone that
called the engine method, so create the stream inside the desired parent
context, even if another part of your app subscribes later. See
[Observing operations](./generation-and-streaming#observing-operations) for
the lifecycle contract and a logger-only observer.

### Signals and their meaning

| Example signal | Meaning |
| --- | --- |
| Span `chat local-demo-model` | One observed chat operation, with its parent trace context |
| `llamadart.operation.duration` histogram, seconds | Observer lifetime, including work between start/end callbacks; not just backend generation time |
| `llamadart.generation.tokens` histogram, tokens | Input and output token counts per request, separated by `gen_ai.token.type` |
| `llamadart.backend.time_to_first_token` histogram, seconds | Backend time to first streamed text, before main-isolate stream batching |
| `llamadart.backend.duration_s` span attribute | Backend generation duration when reported |
| `llamadart.outcome` | `completed`, `cancelled` or `error`; cancellation alone is not an error |

The example uses application-specific metric names so it does not promise full
conformance with evolving GenAI metric conventions. Spans use `gen_ai.*`
operation/model/usage attributes where applicable. The future companion may
standardize a broader mapping; the example is not its API contract.

Metric dimensions are operation, approved model alias, runtime when known,
outcome and token direction. User/session identifiers never become metric
labels. Durations and token counts are separate distributions; their ratio is
not a reliable per-request tokens-per-second measurement.

### Backend coverage

| Path | Observed operations | Per-request generation usage |
| --- | --- | --- |
| Native llama.cpp | Yes | When the backend reports it on the final `create` chunk |
| WebGPU bridge `v0.1.54+` | Yes | When the bridge reports it on the final `create` chunk |
| Older WebGPU bridges | Yes | Unavailable |
| LiteRT-LM, native or Web | Yes | Unavailable |
| Raw `generate`, embeddings, model load | Yes | No final chat usage object |

Missing counts or timings are omitted, not converted to zero. A request
cancelled while queued may have no usage. Backend duration and time to first
token exclude queueing and template rendering. Cached prompt tokens are
already part of input tokens; do not add them again. Multimodal input counts
can represent context positions rather than image tokens. WebGPU output counts
may include tokens generated while a stop signal was in flight. See
[Token usage and timings](./generation-and-streaming#token-usage-and-timings).

## Run the example

Use Dart from the repository's pinned Flutter SDK and an existing local GGUF
chat model. From the repository root:

```bash
cd website/examples/observability
dart pub get
dart analyze --fatal-infos
dart test -p vm
```

Choose an export destination below, then run:

```bash
dart run bin/observe.dart /absolute/path/to/model.gguf
```

It loads the model, generates up to 64 tokens, and exports a model-load span
plus a chat span under `demo-request`. The adapter sends the alias
`local-demo-model`, never the model path. Prompts and generated text are omitted
from telemetry; the CLI still prints the answer locally.

The CLI uses `dart:io` and is a native Dart example. VM tests exercise the
adapter and OTLP/HTTP export; they do not qualify Flutter mobile or browser
export. Core observers also work on Web. For a browser integration, qualify
your chosen SDK and HTTP transport, configure CORS on your own authenticated
ingestion service, and keep provider secrets on the server. A Flutter app
should share one SDK instance for its lifetime rather than initialize it on
every request.

### Parent context, sampling and shutdown

The executable activates the parent context explicitly:

```dart
final parent = otel.OTel.tracer().startSpan('request');
try {
  await otel.Context.current.withSpan(parent).run(() async {
    await for (final chunk in engine.create(messages)) {
      // Consume the stream here.
    }
  });
} catch (_) {
  parent.setStatus(otel.SpanStatusCode.Error, 'Request failed');
  rethrow;
} finally {
  parent.end();
}
```

Here `otel` is the alias for
`package:dartastic_opentelemetry/dartastic_opentelemetry.dart`. The explicit
context scope avoids SDK helpers that automatically record raw exceptions.
The observer reports a generic failure status; it does not export exception
messages or stack traces.

For a 10% root-trace sample, pass
`sampler: otel.ParentBasedSampler(otel.TraceIdRatioSampler(0.1))` to
`OTel.initialize`. The example defaults to sampling every root trace. Keep
parent decisions consistent across your app. Trace sampling does not sample these metric
measurements; trace counts and metric request counts can therefore differ.

After operations and spans finish, the CLI flushes metrics (when enabled)
before `await otel.OTel.shutdown()`. Shutdown drains traces, but explicit
`await otel.OTel.meterProvider().forceFlush()` is needed for this short-lived
example's final metrics. Do not rely on a fixed sleep or abruptly exit the
process. Export failure is not inference failure; verify delivery at the
receiver and monitor SDK export diagnostics.

## Grafana: local traces and metrics

[Grafana's OTel LGTM image](https://grafana.com/docs/opentelemetry/docker-lgtm/)
is a development/test stack with a Collector and configured data sources.
Start it with loopback-only ports:

```bash
docker run --rm -d --name llamadart-otel \
  -p 127.0.0.1:13300:3000 -p 127.0.0.1:14318:4318 \
  grafana/otel-lgtm:0.34.0
```

Wait for readiness in `docker logs llamadart-otel`. In a fresh shell, configure
the example and run it from `website/examples/observability`:

```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:14318
export OBSERVABILITY_LANGFUSE=false
dart run bin/observe.dart /absolute/path/to/model.gguf
```

Use a fresh shell to avoid leftover signal-specific endpoints or authorization
headers from another destination; they override shared endpoint settings.

Open `http://localhost:13300` (initial login `admin` / `admin`). In Explore,
select Tempo and search for service `llamadart-observability-example`; expand
`demo-request` to find its chat child. In the metrics data source, find the
`llamadart` histogram series. Metric names may be normalized to underscores
and gain unit suffixes by the receiver. Use the actual exported names to plot
request counts, duration distributions and input/output token sums. The tested local image exposes, for example:

```promql
sum by (gen_ai_token_type) (llamadart_generation_tokens_sum)
```

This shows cumulative input/output tokens. For a long-running service, use
`rate(llamadart_operation_duration_seconds_count[5m])` for operation throughput.
Filter the `llamadart_outcome` label to separate failures and cancellations;
filter `gen_ai_operation_name="chat"` to exclude model loads.

Stop the disposable stack with `docker stop llamadart-otel`. For production,
use your existing Collector/Alloy and durable storage with authentication;
this local container is not a production deployment recipe.

## Langfuse: LLM generations and sessions

Langfuse accepts OTLP/HTTP traces. This recipe disables metric and log export;
usage remains available as span attributes. Configure a trusted development
machine or server, using keys injected by your secret manager:

```bash
export OBSERVABILITY_LANGFUSE=true
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://cloud.langfuse.com/api/public/otel/v1/traces
# LANGFUSE_AUTH is base64(public-key:secret-key), supplied securely.
export OTEL_EXPORTER_OTLP_TRACES_HEADERS="Authorization=Basic ${LANGFUSE_AUTH},x-langfuse-ingestion-version=4"
dart run bin/observe.dart /absolute/path/to/model.gguf
```

Choose the host for your region or self-hosted instance. Do not put project
secret keys in a distributed Flutter app, browser bundle or committed file.
Use an authenticated application ingestion service for those clients.

With `langfuse: true`, the adapter maps chat/text completion to `generation`,
embeddings to `embedding`, and other operations to `span`. It adds an approved
model alias and JSON `usage_details` (`input`, `output`, `total`). The example
sets `local-demo-session` on the parent and observation spans; real apps
should supply their own approved session identifier on every relevant span.
It does not capture content, infer local inference cost or create evaluation
scores. Verify a generation under `demo-request` and its token counts in your
project. Source references:
[OTel attribute mapping](https://langfuse.com/integrations/native/opentelemetry),
[v4 ingestion requirements](https://langfuse.com/integrations/native/opentelemetry/migration-to-v4).

## Content, privacy and other destinations

Keep prompt/response capture opt-in at the application level. If you add it,
redact content before export, cap its size, choose retention/access rules,
and handle multimodal data separately. The example deliberately does not
buffer streaming content. Model aliases also need review: model metadata and
file basenames can contain user-provided text even when directory paths are
removed. OTel resource attributes and baggage supplied elsewhere in your app
must follow the same policy.

You can route through an
[OTel Collector](https://opentelemetry.io/docs/collector/) to additional
compatible destinations. Confirm each destination's supported signals,
protocol, authentication and attribute mapping. OTLP acceptance alone does not
prove an LLM-specific UI will interpret every field. Logging remains a separate
integration; see [Logging](../configuration/logging).

## Validation and troubleshooting

The example's tests cover parent context, exact usage values, omitted usage,
cancellation vs errors, privacy, a real engine failure callback, and HTTP
trace/metric delivery before shutdown. They use synthetic operation data and
a loopback receiver, without downloading a model or contacting a vendor.

- **No spans:** initialize the SDK before fetching tracer/meter instances,
  consume the stream, check sampling and flush at shutdown.
- **No tokens:** check the backend coverage table; only supported final chat
  usage supplies counts. Successful model loads and embeddings have no counts.
- **Spans but no metrics:** Langfuse mode disables metrics. For Grafana, check
  the metrics endpoint and explicit metric flush.
- **Wrong endpoint or authorization error:** inspect signal-specific OTel
  environment variables and your region; avoid printing authorization headers.
- **No parent relation:** create the engine stream inside the parent context.
- **Content absent in Langfuse:** expected; this example captures metadata only.

A macOS arm64 smoke with Qwen3.5-0.8B Q4_K_M, native llama.cpp v0.5.0 and
LGTM 0.34.0 also verified the parent/child trace and received input/output token
metrics (17/64) through OTLP/HTTP. This is an integration check, not a model
quality benchmark.

Langfuse account ingestion and mobile/Web export need validation in your own
environment. The recipe does not claim those paths were exercised by the
model-free test suite.
