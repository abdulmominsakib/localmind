import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_observability_example/otel_observer.dart';
import 'package:test/test.dart';

Map<String, Object> attributes(otel.Span span) =>
    span.attributes.toMap().map((key, value) => MapEntry(key, value.value));

LlamaChatOperation chat({LlamaRuntime? runtime = LlamaRuntime.llamaCpp}) =>
    LlamaChatOperation(
      model: '/private/secret-model.gguf?token=secret',
      runtime: runtime,
      messages: [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'private prompt',
        ),
      ],
      params: const GenerationParams(),
    );

void main() {
  late InMemorySpanExporter spans;
  late InMemoryMetricExporter metrics;
  late OnDemandMetricReader reader;
  setUp(() async {
    spans = InMemorySpanExporter();
    metrics = InMemoryMetricExporter();
    reader = OnDemandMetricReader(metrics);
    await otel.OTel.initialize(
      spanProcessor: otel.SimpleSpanProcessor(spans),
      metricReader: reader,
      enableLogs: false,
      detectPlatformResources: false,
    );
  });
  tearDown(() async => otel.OTel.reset());

  test(
    'exports child span, exact usage and metrics without private data',
    () async {
      const observer = OtelObserver(
        modelLabel: 'approved-model',
        langfuse: true,
        sessionId: 'session-1',
      );
      final tracer = otel.OTel.tracer();
      final parent = tracer.startSpan('request');
      await tracer.withSpanAsync(parent, () async {
        final operation = observer.onStart(chat());
        await Future<void>.delayed(Duration.zero);
        operation.onEnd(
          const LlamaOperationResult(
            usage: LlamaGenerationUsage(
              promptTokens: 20,
              cachedPromptTokens: 5,
              completionTokens: 7,
              timeToFirstToken: Duration(milliseconds: 250),
              duration: Duration(seconds: 1),
            ),
          ),
        );
      });
      parent.end();
      await otel.OTel.tracerProvider().forceFlush();
      await reader.forceFlush();
      final child = spans.findSpanByName('chat approved-model')!;
      expect(child.kind, otel.SpanKind.internal);
      expect(child.parentSpanContext!.spanId, parent.spanContext.spanId);
      final attrs = attributes(child);
      expect(attrs['gen_ai.usage.input_tokens'], 20);
      expect(attrs['gen_ai.usage.output_tokens'], 7);
      expect(attrs['gen_ai.usage.cache_read.input_tokens'], 5);
      expect(attrs['llamadart.backend.time_to_first_token_s'], 0.25);
      expect(attrs['langfuse.observation.type'], 'generation');
      expect(
        jsonDecode(attrs['langfuse.observation.usage_details'] as String),
        {'input': 20, 'output': 7, 'total': 27},
      );
      expect(attrs['langfuse.session.id'], 'session-1');
      expect(jsonEncode(attrs), isNot(contains('secret')));
      expect(jsonEncode(attrs), isNot(contains('private prompt')));
      final tokens = metrics.findMetricByName('llamadart.generation.tokens')!;
      expect(
        tokens.points.map((point) => (point.value as otel.HistogramValue).sum),
        unorderedEquals([20, 7]),
      );
      for (final point in tokens.points) {
        expect(
          point.attributes.toMap(),
          isNot(contains('langfuse.session.id')),
        );
      }
      expect(
        metrics.findMetricByName('llamadart.operation.duration'),
        isNotNull,
      );
    },
  );

  test(
    'missing usage emits no invented zeros, no Langfuse attributes',
    () async {
      const OtelObserver(modelLabel: 'approved-model')
          .onStart(chat(runtime: LlamaRuntime.liteRtLm))
          .onEnd(const LlamaOperationResult());
      await otel.OTel.tracerProvider().forceFlush();
      await reader.forceFlush();
      final attrs = attributes(spans.spans.single);
      expect(attrs.keys.any((key) => key.startsWith('gen_ai.usage.')), isFalse);
      expect(attrs.keys.any((key) => key.startsWith('langfuse.')), isFalse);
      expect(metrics.findMetricByName('llamadart.generation.tokens'), isNull);
      expect(
        metrics.findMetricByName('llamadart.backend.time_to_first_token'),
        isNull,
      );
    },
  );

  test(
    'cancellation and failure are distinct and errors are redacted',
    () async {
      const observer = OtelObserver(modelLabel: 'approved-model');
      observer
          .onStart(chat())
          .onEnd(const LlamaOperationResult(cancelled: true));
      observer
          .onStart(chat())
          .onEnd(LlamaOperationResult(error: StateError('secret credential')));
      await otel.OTel.tracerProvider().forceFlush();
      expect(attributes(spans.spans[0])['llamadart.outcome'], 'cancelled');
      expect(spans.spans[0].status, isNot(otel.SpanStatusCode.Error));
      expect(attributes(spans.spans[1])['llamadart.outcome'], 'error');
      expect(spans.spans[1].status, otel.SpanStatusCode.Error);
      expect(spans.spans[1].statusDescription, 'Operation failed');
      expect(spans.spans[1].spanEvents ?? [], isEmpty);
    },
  );

  test(
    'actual engine load failure reaches the observer in caller context',
    () async {
      final directory = await Directory.systemTemp.createTemp('secret');
      addTearDown(() => directory.delete(recursive: true));
      final model = File('${directory.path}/secret.gguf')
        ..writeAsBytesSync([0]);
      final engine = LlamaEngine(
        _FailingBackend(),
        observers: [const OtelObserver(modelLabel: 'safe')],
      );
      final parent = otel.OTel.tracer().startSpan('request');
      await otel.OTel.tracer().withSpanAsync(parent, () async {
        await expectLater(
          engine.setModel(LlamaModel(ModelSource.path(model.path))),
          throwsA(isA<Exception>()),
        );
      });
      parent.end();
      await engine.dispose();
      await otel.OTel.tracerProvider().forceFlush();
      final load = spans.findSpanByName('model_load safe')!;
      expect(load.parentSpanContext!.spanId, parent.spanContext.spanId);
      expect(attributes(load)['llamadart.outcome'], 'error');
      expect(load.statusDescription, isNot(contains('secret')));
    },
  );
}

class _FailingBackend implements LlamaBackend {
  @override
  bool get supportsUrlLoading => false;
  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<int> modelLoad(String path, ModelParams params) async =>
      throw Exception('secret path: $path');
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
