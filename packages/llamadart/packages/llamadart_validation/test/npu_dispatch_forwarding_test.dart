import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

class _ParamsCapturingEngine implements LlamaEngine {
  ModelParams? params;

  @override
  bool get isReady => true;

  @override
  Future<void> setModel(
    LlamaModel model, {
    ModelParams params = const ModelParams(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    this.params = params;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Monitor implements NpuExecutionMonitor {
  @override
  String get dispatchDirectory => '/data/app/native-libs';

  @override
  Map<String, dynamic> get identity => const {};

  @override
  List<int> snapshot() => const [1, 0, 0, 0, 0, 0, 0];
}

void main() {
  test(
    'the NPU host hands its dispatch directory to the public load',
    () async {
      final profile = ValidationProfile.fromJson(
        jsonDecode(
              File(
                'assets/profiles/npu-qualcomm-sm8650.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final engine = _ParamsCapturingEngine();
      final adapter = PublicValidationEngine(
        engineFactory: () => engine,
        npu: _Monitor(),
      );

      await adapter.load('model.litertlm', profile);

      final params = engine.params;
      expect(params, isA<LiteRtLmModelParams>());
      expect(
        (params! as LiteRtLmModelParams).dispatchLibDir,
        '/data/app/native-libs',
      );
    },
  );
}
