import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart' as otel;
import 'package:genkit/genkit.dart';
import 'package:genkit/telemetry.dart';

/// Opt-in runtime timings for llamadart model actions, in seconds.
///
/// Register after `GenAiInstrumentation` so [tracer]'s current span is the
/// model span. The application owns both providers and their shutdown. This
/// recipe exports only timings and a fixed outcome; it does not inspect input,
/// export model names or duplicate GenAI token/generation-duration metrics.
final class RuntimeTimingInstrumentation implements Instrumentation {
  /// Uses the application's [meter] and [tracer], without initializing an SDK.
  RuntimeTimingInstrumentation({
    required otel.APIMeter meter,
    required this.tracer,
  }) : _histograms = {
         for (final name in _fields.keys)
           name: meter.createHistogram<double>(
             name: 'llamadart.model.$name',
             unit: 's',
             description: _fields[name]!,
           ),
       };

  /// Tracer sharing the context used by the application's model instrumentation.
  final otel.APITracer tracer;
  final Map<String, otel.APIHistogram<double>> _histograms;
  static const _fields = {
    'queue.duration': 'Time waiting for the serialized model slot.',
    'initialization.duration': 'Time obtaining and initializing the runtime.',
    'action.duration': 'Whole model-action latency, including queue and setup.',
    'time_to_first_token': 'Backend-reported time to first token.',
  };

  /// Records one observation per available timing, even on failure/cancellation.
  @override
  Future<O> runInNewSpan<O>(
    SpanMetadata metadata,
    Future<O> Function([SpanContext? span]) next,
  ) async {
    if (metadata.actionType != 'model' ||
        !metadata.name.startsWith('llamadart/')) {
      return next();
    }
    final span = tracer.currentSpan;
    final elapsed = Stopwatch()..start();
    ModelResponse? response;
    var outcome = 'completed';
    try {
      final output = await next();
      if (output is ModelResponse) {
        response = output;
        if (output.finishReason == FinishReason.failed) outcome = 'failed';
        if (output.finishReason == FinishReason.aborted) outcome = 'cancelled';
      }
      return output;
    } catch (error) {
      outcome = error is CancelledException ? 'cancelled' : 'failed';
      rethrow;
    } finally {
      elapsed.stop();
      final raw = response?.raw;
      final usage = raw?['usage'];
      final values = {
        'queue.duration': _seconds(raw?['queueMs']),
        'initialization.duration': _seconds(raw?['initializationMs']),
        'action.duration':
            _seconds(raw?['totalLatencyMs']) ??
            elapsed.elapsedMicroseconds / 1000000,
        'time_to_first_token': _seconds(
          usage is Map ? usage['time_to_first_token_ms'] : null,
        ),
      };
      // Exporter failures must not replace an inference result or exception.
      try {
        span?.setStringAttribute('llamadart.outcome', outcome);
        for (final entry in values.entries) {
          final value = entry.value;
          if (value == null) continue;
          span?.setDoubleAttribute('llamadart.model.${entry.key}', value);
          _histograms[entry.key]!.recordWithMap(value, {
            'llamadart.outcome': outcome,
          });
        }
      } catch (_) {}
    }
  }

  static double? _seconds(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value / 1000 : null;
}
