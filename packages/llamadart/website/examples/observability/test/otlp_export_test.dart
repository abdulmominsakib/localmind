@TestOn('vm')
library;

import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_observability_example/otel_observer.dart';
import 'package:test/test.dart';

void main() {
  test('CLI honors Langfuse signal endpoint and headers on failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final auth = <String?>[];
    final versions = <String?>[];
    final subscription = server.listen((request) async {
      paths.add(request.uri.path);
      auth.add(request.headers.value('authorization'));
      versions.add(request.headers.value('x-langfuse-ingestion-version'));
      await request.drain<void>();
      request.response.headers.contentType = ContentType(
        'application',
        'x-protobuf',
      );
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await subscription.cancel();
    });
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/observe.dart', '/missing/observability-test-model.gguf'],
      environment: {
        'OBSERVABILITY_LANGFUSE': 'true',
        'OTEL_EXPORTER_OTLP_PROTOCOL': 'http/protobuf',
        'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT':
            'http://127.0.0.1:${server.port}/api/public/otel/v1/traces',
        'OTEL_EXPORTER_OTLP_TRACES_HEADERS':
            'Authorization=Basic test-only,x-langfuse-ingestion-version=4',
      },
    );
    // A nonexistent model must still export its load failure before exiting.
    expect(result.exitCode, isNot(0));
    expect(paths, ['/api/public/otel/v1/traces']);
    expect(auth, ['Basic test-only']);
    expect(versions, ['4']);
  });

  for (final langfuse in [false, true]) {
    test('OTLP HTTP exports before shutdown (Langfuse: $langfuse)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final sizes = <int>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        sizes.add(
          await request.fold<int>(0, (size, chunk) => size + chunk.length),
        );
        request.response.headers.contentType = ContentType(
          'application',
          'x-protobuf',
        );
        request.response.statusCode = 200;
        await request.response.close();
      });
      addTearDown(() async {
        await otel.OTel.reset();
        await server.close(force: true);
        await subscription.cancel();
      });
      await otel.OTel.initialize(
        endpoint: 'http://127.0.0.1:${server.port}',
        secure: false,
        enableMetrics: !langfuse,
        enableLogs: false,
        detectPlatformResources: false,
      );
      OtelObserver(modelLabel: 'demo', langfuse: langfuse)
          .onStart(
            LlamaChatOperation(
              model: 'ignored',
              runtime: LlamaRuntime.llamaCpp,
              messages: [],
              params: const GenerationParams(),
            ),
          )
          .onEnd(
            const LlamaOperationResult(
              usage: LlamaGenerationUsage(
                promptTokens: 10,
                completionTokens: 2,
              ),
            ),
          );
      if (!langfuse) await otel.OTel.meterProvider().forceFlush();
      await otel.OTel.shutdown();
      expect(paths, contains('/v1/traces'));
      expect(paths.contains('/v1/metrics'), !langfuse);
      expect(paths, isNot(contains('/v1/logs')));
      expect(sizes, everyElement(greaterThan(0)));
    });
  }
}
