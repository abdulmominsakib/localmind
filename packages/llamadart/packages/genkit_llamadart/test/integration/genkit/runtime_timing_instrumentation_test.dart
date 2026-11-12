@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:dartastic_opentelemetry/proto/collector/metrics/v1/metrics_service.pb.dart';
import 'package:dartastic_opentelemetry/proto/collector/trace/v1/trace_service.pb.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart' as api;
import 'package:genkit/src/o11y/instrumentation.dart' show resetInstrumentation;
import 'package:genkit/telemetry.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_otel/genkit_otel.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../example/telemetry/runtime_timing_instrumentation.dart';
import '../../core/runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'OTLP records queued, structured, failed and cancelled calls once',
    () async {
      final collector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final metrics = ExportMetricsServiceRequest();
      final traces = ExportTraceServiceRequest();
      collector.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        if (request.uri.path == '/v1/metrics') metrics.mergeFromBuffer(bytes);
        if (request.uri.path == '/v1/traces') traces.mergeFromBuffer(bytes);
        request.response.headers.contentType = ContentType(
          'application',
          'x-protobuf',
        );
        await request.response.close();
      });
      final endpoint = 'http://127.0.0.1:${collector.port}';
      resetInstrumentation();
      await otel.OTel.initialize(
        serviceName: 'timing-test',
        enableLogs: false,
        detectPlatformResources: false,
        spanProcessor: otel.SimpleSpanProcessor(
          otel.OtlpHttpSpanExporter(
            otel.OtlpHttpExporterConfig(endpoint: endpoint),
          ),
        ),
        metricExporter: otel.OtlpHttpMetricExporter(
          otel.OtlpHttpMetricExporterConfig(endpoint: endpoint),
        ),
      );
      addTearDown(() async {
        resetInstrumentation();
        await otel.OTel.shutdown();
        await collector.close(force: true);
      });
      configureInstrumentation(
        GenAiInstrumentation(
          contentCapturingMode: ContentCapturingMode.noContent,
          captureActionIO: false,
        ),
      );
      final timing = RuntimeTimingInstrumentation(
        meter: otel.OTel.meter('timing-test'),
        tracer: otel.OTel.tracerProvider().getTracer('timing-test'),
      );
      configureInstrumentation(timing);
      final runtime = _TimingRuntime();
      final plugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(
            name: 'local',
            modelPath: '/private/model-secret',
          ),
        ],
        runtimeFactory: () => runtime,
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final action = (await plugin.init())
          .whereType<api.Model<LlamaDartGenerationConfig>>()
          .single;
      ModelRequest request({bool structured = false}) => ModelRequest(
        messages: [
          Message(
            role: Role.user,
            content: [TextPart(text: 'secret prompt')],
          ),
        ],
        output: structured ? OutputConfig(format: 'json') : null,
      );

      final first = action(request());
      await runtime.started.future;
      final queued = action(request());
      await Future<void>.delayed(const Duration(milliseconds: 15));
      runtime.release.complete();
      final responses = await Future.wait([first, queued]);
      expect(responses.last.raw!['queueMs'], greaterThan(0));
      await action(request(structured: true));
      runtime.failure = true;
      await expectLater(action(request()), throwsStateError);
      runtime.failure = false;
      final cancellation = CancellationController();
      await expectLater(
        action(
          request(),
          cancel: cancellation.token,
          onChunk: (_) => cancellation.cancel(),
        ),
        throwsA(isA<CancelledException>()),
      );
      await api.Model<void>(
        name: 'another/external',
        fn: (_, _) async => ModelResponse(
          message: Message(
            role: Role.model,
            content: [TextPart(text: 'other')],
          ),
          finishReason: FinishReason.stop,
          raw: {'queueMs': 5000, 'totalLatencyMs': 9000},
        ),
      )(request());
      await otel.OTel.meterProvider().forceFlush();
      await otel.OTel.tracerProvider().forceFlush();

      final exported = metrics.resourceMetrics
          .expand((r) => r.scopeMetrics)
          .expand((s) => s.metrics)
          .toList();
      final custom = exported
          .where((m) => m.name.startsWith('llamadart.model.'))
          .toList();
      expect(
        custom.map((m) => m.name),
        unorderedEquals([
          'llamadart.model.queue.duration',
          'llamadart.model.initialization.duration',
          'llamadart.model.action.duration',
          'llamadart.model.time_to_first_token',
        ]),
      );
      final actionDuration = custom.singleWhere(
        (m) => m.name.endsWith('action.duration'),
      );
      expect(actionDuration.unit, 's');
      final outcomes = {
        for (final p in actionDuration.histogram.dataPoints)
          p.attributes.single.value.stringValue: p.count.toInt(),
      };
      expect(outcomes, {'completed': 3, 'failed': 1, 'cancelled': 1});
      for (final metric in custom.where(
        (m) => !m.name.endsWith('action.duration'),
      )) {
        expect(
          metric.histogram.dataPoints.single.count.toInt(),
          metric.name.endsWith('time_to_first_token') ? 1 : 3,
        );
        for (final point in metric.histogram.dataPoints) {
          expect(point.attributes.map((a) => a.key), ['llamadart.outcome']);
        }
      }
      final ttft = custom.singleWhere(
        (m) => m.name.endsWith('time_to_first_token'),
      );
      expect(
        ttft.histogram.dataPoints.single.sum,
        0,
        reason: 'Zero must remain present',
      );
      final spans = traces.resourceSpans
          .expand((r) => r.scopeSpans)
          .expand((s) => s.spans)
          .where((s) => s.name == 'chat local')
          .toList();
      expect(spans, hasLength(5));
      expect(
        spans.every(
          (s) => s.attributes.any(
            (a) => a.key == 'llamadart.model.action.duration',
          ),
        ),
        isTrue,
      );
      expect(traces.toString(), isNot(contains('secret prompt')));
      expect(traces.toString(), isNot(contains('secret output')));
      expect(traces.toString(), isNot(contains('/private/model-secret')));
      final tokenMetric = exported.singleWhere(
        (m) => m.name == 'gen_ai.client.token.usage',
      );
      expect(
        tokenMetric.histogram.dataPoints.every((p) => p.count.toInt() == 1),
        isTrue,
      );
      final genAiDuration = exported.singleWhere(
        (m) => m.name == 'gen_ai.client.operation.duration',
      );
      expect(
        genAiDuration.histogram.dataPoints.fold<int>(
          0,
          (sum, p) => sum + p.count.toInt(),
        ),
        6,
      );
    },
  );
}

class _TimingRuntime extends FakeRuntime {
  final started = Completer<void>();
  final release = Completer<void>();
  bool failure = false;
  int calls = 0;
  @override
  Stream<llama.LlamaCompletionChunk> create(
    List<llama.LlamaChatMessage> messages, {
    llama.GenerationParams? params,
    List<llama.ToolDefinition>? tools,
    llama.ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = false,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
  }) async* {
    calls++;
    if (calls == 1) {
      started.complete();
      await release.future;
    }
    if (failure) throw StateError('Expected failure');
    yield textChunk('secret output');
    if (calls == 1) {
      yield llama.LlamaCompletionChunk(
        id: 'usage',
        object: 'chat.completion.chunk',
        created: 0,
        model: 'local',
        choices: [],
        usage: const llama.LlamaGenerationUsage(
          promptTokens: 3,
          completionTokens: 2,
          timeToFirstToken: Duration.zero,
        ),
      );
    }
    yield stopChunk();
  }

  @override
  Stream<String> generate(
    String prompt, {
    llama.GenerationParams params = const llama.GenerationParams(),
    List<llama.LlamaContentPart>? parts,
  }) async* {
    yield '{"answer":1}';
  }
}
