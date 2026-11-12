import 'dart:convert';
import 'dart:io';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:genkit/genkit.dart';
import 'package:genkit/telemetry.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_otel/genkit_otel.dart';

import 'telemetry/runtime_timing_instrumentation.dart';
import 'support/chat_model.dart';

Future<void> main() async {
  final prepared = await prepareExampleChat(
    'local',
    observers: [OtelEngineObserver()],
  );
  final ai = prepared.createGenkit(isDevEnv: false);
  try {
    await otel.OTel.initialize(
      serviceName: 'genkit-llamadart-example',
      enableLogs: false,
      detectPlatformResources: false,
    );
    configureInstrumentation(
      GenAiInstrumentation(
        contentCapturingMode: ContentCapturingMode.noContent,
        captureActionIO: false,
      ),
    );
    configureInstrumentation(
      RuntimeTimingInstrumentation(
        meter: otel.OTel.meter('llamadart-runtime'),
        tracer: otel.OTel.tracerProvider().getTracer('llamadart-runtime'),
      ),
    );
    final response = await ai.generate(
      model: llamaDart.model('local'),
      prompt: 'Say hello briefly.',
      config: const LlamaDartGenerationConfig(maxTokens: 32),
    );
    if (response.finishReason == FinishReason.failed ||
        response.finishReason == FinishReason.aborted) {
      throw response.cause ?? StateError('Generation did not complete.');
    }
    // Print measurements only: no prompts, generated text, paths or tool data.
    stdout.writeln(
      jsonEncode({
        'usage': response.usage?.toJson(),
        'finishReason': response.finishReason.toString(),
      }),
    );
  } finally {
    try {
      await prepared.dispose();
    } finally {
      try {
        await ai.shutdown();
      } finally {
        try {
          // A short CLI run may finish before the periodic metric export.
          await otel.OTel.meterProvider().forceFlush();
        } finally {
          await otel.OTel.shutdown();
        }
      }
    }
  }
}

/// Records engine spans without duplicating Genkit model token metrics.
final class OtelEngineObserver extends LlamaEngineObserver {
  @override
  LlamaOperationObserver onStart(LlamaOperation operation) {
    final span = otel.OTel.tracerProvider()
        .getTracer('llamadart-engine')
        .startSpan(
          'llamadart.${operation.runtimeType}',
          kind: otel.SpanKind.internal,
        );
    return _OtelOperation(span);
  }
}

final class _OtelOperation extends LlamaOperationObserver {
  _OtelOperation(this.span);
  final otel.APISpan span;

  @override
  void onEnd(LlamaOperationResult result) {
    // Avoid exporting exception messages, model paths or request content.
    span.setStringAttribute(
      'llamadart.outcome',
      result.cancelled
          ? 'cancelled'
          : result.error != null
          ? 'failed'
          : 'completed',
    );
    span.end();
  }
}
