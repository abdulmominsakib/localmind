import '../core/exceptions.dart';
import '../core/models/config/lora_config.dart';
import '../core/url_redaction.dart';

/// Applies [loras], the `ModelParams.loras` of a model load, in order through
/// [apply], the backend's runtime LoRA call, on a newly created context.
///
/// When an adapter fails, runs [rollback], ignoring its errors, and throws an
/// exception that names the adapter with its URL secrets redacted: a
/// [LlamaUnsupportedException] when the failure is a
/// [LlamaUnsupportedException] or [UnsupportedError], otherwise a
/// [LlamaModelException].
Future<void> applyModelParamsLoras(
  List<LoraAdapterConfig> loras, {
  required Future<void> Function(LoraAdapterConfig lora) apply,
  required Future<void> Function() rollback,
}) async {
  for (final lora in loras) {
    try {
      await apply(lora);
    } catch (error) {
      try {
        await rollback();
      } catch (_) {}
      throw _modelParamsLoraError(lora.path, error);
    }
  }
}

LlamaException _modelParamsLoraError(String path, Object error) {
  String redacted(String text) =>
      redactUrlSecrets(text, sourceUrls: <String>[path]);
  final adapter = redacted(path);
  if (error is LlamaUnsupportedException || error is UnsupportedError) {
    final reason = switch (error) {
      LlamaUnsupportedException(:final message) => message,
      UnsupportedError(:final message) => message ?? 'unsupported',
      _ => error.toString(),
    };
    return LlamaUnsupportedException(
      'Cannot apply the ModelParams.loras adapter $adapter: '
      '${redacted(reason)}',
    );
  }
  return LlamaModelException(
    'Failed to apply the ModelParams.loras adapter $adapter',
    redacted(error.toString()),
  );
}
