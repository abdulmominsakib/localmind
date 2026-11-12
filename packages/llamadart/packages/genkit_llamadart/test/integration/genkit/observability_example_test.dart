@Tags(['real-model'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry/proto/collector/metrics/v1/metrics_service.pb.dart';
import 'package:dartastic_opentelemetry/proto/collector/trace/v1/trace_service.pb.dart';
import 'package:test/test.dart';

import 'test_support/real_model_test_support.dart';

void main() {
  test(
    'example exports correlated spans and token metrics before exiting',
    () async {
      final model = await resolveIntegrationModelPath();
      if (model == null) return;
      final collector = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => collector.close(force: true));
      final traces = ExportTraceServiceRequest();
      final metrics = ExportMetricsServiceRequest();
      final received = <String>[];
      collector.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        received.add(request.uri.path);
        switch (request.uri.path) {
          case '/v1/traces':
            traces.mergeFromBuffer(bytes);
          case '/v1/metrics':
            metrics.mergeFromBuffer(bytes);
          default:
            request.response.statusCode = 404;
        }
        request.response.headers.contentType = ContentType(
          'application',
          'x-protobuf',
        );
        await request.response.close();
      });
      final process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'example/genkit_llamadart_observability_example.dart'],
        environment: {
          'LLAMADART_MODEL_SOURCE': model,
          'OTEL_EXPORTER_OTLP_ENDPOINT': 'http://127.0.0.1:${collector.port}',
          'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/protobuf',
          'OTEL_LOG_LEVEL': 'fatal',
          // The example must explicitly override content capture from the env.
          'OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT':
              'SPAN_AND_EVENT',
          'OTEL_METRIC_EXPORT_INTERVAL': '60000',
        },
      );
      addTearDown(() {
        process.kill();
      });
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.transform(utf8.decoder).join();
      expect(
        await process.exitCode.timeout(const Duration(minutes: 2)),
        0,
        reason: await errors,
      );
      final usage = (jsonDecode((await output).trim()) as Map)['usage'] as Map;
      expect(received, containsAll(['/v1/traces', '/v1/metrics']));
      final spans = traces.resourceSpans
          .expand((r) => r.scopeSpans)
          .expand((s) => s.spans)
          .toList();
      final modelSpan = spans.singleWhere((s) => s.name == 'chat local');
      final engineSpans = spans
          .where((s) => s.name.startsWith('llamadart.'))
          .toList();
      expect(
        engineSpans.map((s) => s.name),
        containsAll([
          'llamadart.LlamaModelLoadOperation',
          'llamadart.LlamaChatOperation',
        ]),
      );
      for (final span in engineSpans) {
        expect(span.traceId, modelSpan.traceId);
        expect(span.parentSpanId, modelSpan.spanId);
      }
      for (final span in spans) {
        expect(
          span.attributes.map((a) => a.key),
          isNot(
            anyOf(
              contains('gen_ai.input.messages'),
              contains('gen_ai.output.messages'),
              contains('genkit.input'),
              contains('genkit.output'),
            ),
          ),
        );
      }
      expect(traces.toString(), isNot(contains('Say hello briefly.')));
      expect(traces.toString(), isNot(contains(model)));
      final exported = metrics.resourceMetrics
          .expand((r) => r.scopeMetrics)
          .expand((s) => s.metrics)
          .toList();
      final tokens = exported.singleWhere(
        (m) => m.name == 'gen_ai.client.token.usage',
      );
      expect(tokens.histogram.dataPoints, hasLength(2));
      for (final point in tokens.histogram.dataPoints) {
        final type = point.attributes
            .singleWhere((a) => a.key == 'gen_ai.token.type')
            .value
            .stringValue;
        expect(
          point.count.toInt(),
          1,
          reason: 'One observation per token type',
        );
        expect(
          point.sum,
          usage[type == 'input' ? 'inputTokens' : 'outputTokens'],
        );
      }
      final duration = exported.singleWhere(
        (m) => m.name == 'gen_ai.client.operation.duration',
      );
      expect(duration.histogram.dataPoints.single.count.toInt(), 1);
      final timingMetrics = exported
          .where((m) => m.name.startsWith('llamadart.model.'))
          .toList();
      expect(timingMetrics, hasLength(4));
      for (final metric in timingMetrics) {
        expect(metric.unit, 's');
        final point = metric.histogram.dataPoints.single;
        expect(point.count.toInt(), 1);
        expect(point.attributes.single.key, 'llamadart.outcome');
        expect(point.attributes.single.value.stringValue, 'completed');
        expect(point.sum, greaterThanOrEqualTo(0));
        final attribute = modelSpan.attributes.singleWhere(
          (a) => a.key == metric.name,
        );
        expect(attribute.value.doubleValue, point.sum);
      }
    },
    tags: ['real-model'],
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
