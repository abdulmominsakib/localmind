import 'dart:convert';

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:llamadart/llamadart.dart';

/// Application-owned example adapter, not a llamadart companion package.
final class OtelObserver extends LlamaEngineObserver {
  /// Use an approved, low-cardinality model alias, never a path or signed URL.
  const OtelObserver({
    required this.modelLabel,
    this.langfuse = false,
    this.sessionId,
  });

  final String modelLabel;
  final bool langfuse;
  final String? sessionId;

  @override
  LlamaOperationObserver onStart(LlamaOperation operation) {
    final name = switch (operation) {
      LlamaChatOperation() => 'chat',
      LlamaTextCompletionOperation() => 'text_completion',
      LlamaEmbeddingsOperation() => 'embeddings',
      LlamaModelLoadOperation() => 'model_load',
      _ => 'other',
    };
    final attributes = <String, Object>{
      'gen_ai.operation.name': name,
      'gen_ai.request.model': modelLabel,
      if (operation.runtime case final runtime?)
        'llamadart.runtime': runtime.name,
    };
    // Fetch after SDK initialization; objects fetched before it can be no-ops.
    final span = otel.OTel.tracer().startSpan(
      '$name $modelLabel',
      kind: otel.SpanKind.internal,
      context: otel.Context.current,
      attributes: otel.OTel.attributesFromMap({
        ...attributes,
        if (langfuse) ...{
          'langfuse.observation.type': switch (operation) {
            LlamaChatOperation() ||
            LlamaTextCompletionOperation() => 'generation',
            LlamaEmbeddingsOperation() => 'embedding',
            _ => 'span',
          },
          'langfuse.observation.model.name': modelLabel,
          'langfuse.session.id': ?sessionId,
        },
      }),
    );
    return _Operation(span, attributes, langfuse);
  }
}

final class _Operation extends LlamaOperationObserver {
  _Operation(this.span, this.labels, this.langfuse);

  final otel.Span span;
  final Map<String, Object> labels;
  final bool langfuse;
  final Stopwatch watch = Stopwatch()..start();

  @override
  void onEnd(LlamaOperationResult result) {
    watch.stop();
    final outcome = result.error != null
        ? 'error'
        : result.cancelled
        ? 'cancelled'
        : 'completed';
    final dimensions = otel.OTel.attributesFromMap({
      ...labels,
      'llamadart.outcome': outcome,
    });
    try {
      span.addAttributes(dimensions);
      // Error messages/stacks may contain prompts, paths or credentials.
      if (result.error != null) {
        span.setStatus(otel.SpanStatusCode.Error, 'Operation failed');
      }
      final meter = otel.OTel.meter('llamadart.docs');
      meter
          .createHistogram<double>(
            name: 'llamadart.operation.duration',
            unit: 's',
          )
          .record(watch.elapsedMicroseconds / 1000000, dimensions);
      final usage = result.usage;
      if (usage != null) {
        span.addAttributes(
          otel.OTel.attributesFromMap({
            'gen_ai.usage.input_tokens': usage.promptTokens,
            'gen_ai.usage.output_tokens': usage.completionTokens,
            'gen_ai.usage.cache_read.input_tokens': ?usage.cachedPromptTokens,
            if (usage.duration case final duration?)
              'llamadart.backend.duration_s': duration.inMicroseconds / 1000000,
            if (usage.timeToFirstToken case final first?)
              'llamadart.backend.time_to_first_token_s':
                  first.inMicroseconds / 1000000,
            if (langfuse)
              'langfuse.observation.usage_details': jsonEncode({
                'input': usage.promptTokens,
                'output': usage.completionTokens,
                'total': usage.totalTokens,
              }),
          }),
        );
        final tokens = meter.createHistogram<int>(
          name: 'llamadart.generation.tokens',
          unit: '{token}',
        );
        for (final entry in {
          'input': usage.promptTokens,
          'output': usage.completionTokens,
        }.entries) {
          tokens.record(
            entry.value,
            otel.OTel.attributesFromMap({
              ...labels,
              'llamadart.outcome': outcome,
              'gen_ai.token.type': entry.key,
            }),
          );
        }
        if (usage.timeToFirstToken case final first?) {
          meter
              .createHistogram<double>(
                name: 'llamadart.backend.time_to_first_token',
                unit: 's',
              )
              .record(first.inMicroseconds / 1000000, dimensions);
        }
      }
    } finally {
      span.end();
    }
  }
}
