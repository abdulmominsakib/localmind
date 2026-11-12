import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Thrown by [SentinelResolver] once a load gets past its pre-I/O checks.
final class ReachedIo implements Exception {}

/// A resolver that counts its calls and stops every load at the first file.
final class SentinelResolver implements ModelResolver {
  /// How many sources the engine asked to resolve.
  int calls = 0;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    calls++;
    throw ReachedIo();
  }
}

/// Expects [LlamaEngine.setModel] to throw [report]'s error before [resolver]
/// runs exactly when [report] is unsupported, and to reach [resolver]
/// otherwise.
Future<void> expectSetModelAgrees(
  LlamaEngine engine,
  SentinelResolver resolver,
  LlamaModel model,
  ModelParams params,
  LlamaLoadCheckReport report,
) async {
  resolver.calls = 0;
  Object? thrown;
  try {
    await engine.setModel(model, params: params);
  } catch (error) {
    thrown = error;
  }
  if (report.status == LlamaLoadCheckStatus.unsupported) {
    expect(resolver.calls, 0, reason: '$report');
    expect(thrown, isA<LlamaUnsupportedException>(), reason: '$report');
    expect(thrown.runtimeType, report.error.runtimeType, reason: '$report');
    expect(
      (thrown! as LlamaUnsupportedException).message,
      report.error!.message,
    );
  } else {
    expect(thrown, isA<ReachedIo>(), reason: '$report');
    expect(resolver.calls, greaterThan(0), reason: '$report');
  }
  resolver.calls = 0;
}
