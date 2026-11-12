@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(gpuLayers: 0, contextSize: 64);
const _build = 'llamadart-native-build/1;owner=abc;backends=cpu';

// Runs the real llama.cpp runtime on the CPU with a synthetic model; the
// build identity reader stands in for runtimes that predate it.
void main() {
  late String modelPath;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('llamadart_state_id_');
    addTearDown(() => dir.deleteSync(recursive: true));
    modelPath = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  });

  (LlamaCppService, int) open(
    String? Function() buildIdentity, {
    ModelParams params = _params,
  }) {
    final service = LlamaCppService(buildIdentity: buildIdentity)
      ..initializeBackend();
    addTearDown(service.dispose);
    final model = service.loadModel(modelPath, params);
    return (service, service.createContext(model, params));
  }

  test('reports the build, session version, context size and config', () {
    final (service, context) = open(() => _build);

    final identity = service.stateIdentity(context);

    expect(identity.runtimeBuild, _build);
    expect(identity.sessionFormatVersion, LLAMA_SESSION_VERSION);
    expect(identity.contextSize, service.getContextSize(context));
    expect(identity.contextConfigDigest, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('reads the build identity once per service', () {
    var reads = 0;
    final (service, context) = open(() {
      reads++;
      return _build;
    });

    service.stateIdentity(context);
    service.stateIdentity(context);

    expect(reads, 1);
  });

  test('another sequence count changes only the config digest', () {
    final (service, one) = open(() => _build);
    final two = service.createContext(
      service.loadModel(modelPath, _params),
      _params.copyWith(maxParallelSequences: 2),
    );

    final a = service.stateIdentity(one);
    final b = service.stateIdentity(two);

    expect(b.runtimeBuild, a.runtimeBuild);
    expect(b.contextSize, a.contextSize);
    expect(b.contextConfigDigest, isNot(a.contextConfigDigest));
    expect(a.matches(b), isFalse);
  });

  test('a runtime without llama_dart_build_identity is unsupported', () {
    final (service, context) = open(() => null);

    expect(
      () => service.stateIdentity(context),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('llama_dart_build_identity'),
            contains('v0.7.0-3 or newer'),
            contains('native release override'),
          ),
        ),
      ),
    );
  });

  test('an empty build identity is unsupported', () {
    final (service, context) = open(() => '');

    expect(
      () => service.stateIdentity(context),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('reports an empty one'), contains('v0.7.0-3')),
        ),
      ),
    );
  });

  test('an unknown context is a state error', () {
    final (service, _) = open(() => _build);

    expect(
      () => service.stateIdentity(999),
      throwsA(isA<LlamaStateException>()),
    );
  });
}
