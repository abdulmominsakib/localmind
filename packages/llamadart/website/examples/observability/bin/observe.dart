import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_observability_example/otel_observer.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run bin/observe.dart <model.gguf>');
    exitCode = 64;
    return;
  }
  final langfuse = Platform.environment['OBSERVABILITY_LANGFUSE'] == 'true';
  await otel.OTel.initialize(
    serviceName: 'llamadart-observability-example',
    tracerName: 'llamadart.docs',
    enableMetrics: !langfuse,
    enableLogs: false,
    detectPlatformResources: false,
  );
  final observer = OtelObserver(
    modelLabel: 'local-demo-model',
    langfuse: langfuse,
    sessionId: langfuse ? 'local-demo-session' : null,
  );
  final engine = LlamaEngine(LlamaBackend(), observers: [observer]);
  try {
    await engine.setModel(
      LlamaModel(ModelSource.path(args.single)),
      params: const ModelParams(contextSize: 2048),
    );
    final tracer = otel.OTel.tracer();
    final parent = tracer.startSpan(
      'demo-request',
      attributes: otel.OTel.attributesFromMap({
        if (langfuse) 'langfuse.session.id': 'local-demo-session',
      }),
    );
    try {
      await otel.Context.current.withSpan(parent).run(() async {
        await for (final chunk in engine.create([
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Say hello in one short sentence.',
          ),
        ], params: const GenerationParams(maxTokens: 64))) {
          stdout.write(chunk.text);
        }
      });
    } catch (_) {
      parent.setStatus(otel.SpanStatusCode.Error, 'Request failed');
      rethrow;
    } finally {
      parent.end();
    }
    stdout.writeln();
  } finally {
    try {
      await engine.dispose();
    } finally {
      // Drain pending telemetry before this short-lived process exits.
      try {
        if (!langfuse) await otel.OTel.meterProvider().forceFlush();
      } finally {
        await otel.OTel.shutdown();
      }
    }
  }
}
