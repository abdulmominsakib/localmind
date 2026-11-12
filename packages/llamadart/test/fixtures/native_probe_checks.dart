import 'dart:ffi';
import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

final LibraryMirror _owner =
    reflectClass(LlamaCppService).owner as LibraryMirror;

dynamic _read(Object object, String field) =>
    reflect(object).getField(MirrorSystem.getSymbol(field, _owner)).reflectee;

dynamic _invoke(
  LlamaCppService service,
  String method,
  List<Object?> arguments, [
  Map<Symbol, Object?> named = const {},
]) => reflect(
  service,
).invoke(MirrorSystem.getSymbol(method, _owner), arguments, named).reflectee;

void main(List<String> arguments) {
  final calls = LlamaCppObjectCalls.untracked();
  final service = LlamaCppService(
    objectCalls: calls,
    isWindows: arguments.single == 'windows-registry' ? true : null,
  );
  final wrapperClass =
      _owner.declarations[MirrorSystem.getSymbol('_LlamaModelWrapper', _owner)]
          as ClassMirror;
  final model = wrapperClass
      .newInstance(
        const Symbol(''),
        [Pointer<llama_model>.fromAddress(0x1000), calls],
        {#vocabSize: 1, #suppressedTokens: <int>[]},
      )
      .reflectee;
  (_read(service, '_models') as Map)[1] = model;

  _check(_read(service, '_reasoningBudgetApiLookupAttempted'), isFalse);
  _check(_read(service, '_reasoningBudgetApi'), isNull);
  switch (arguments.single) {
    case 'windows-registry':
      _invoke(service, '_resolveGgmlFallbackFunctions', []);
      final count =
          _read(service, '_ggmlBackendRegCountFallback') as int Function();
      final devices =
          _read(service, '_ggmlBackendDevCountFallback') as int Function();
      _check(count(), 3);
      _check(devices(), 4);
      _check(_read(service, '_ggmlBackendLoadAllFallback'), isNull);
    case 'placement':
      _check(service.getBackendInfo(), [
        'CPU',
        'Vulkan (Vulkan0)',
        'Metal (MTL0)',
        'Metal (MTL1)',
      ]);
      final backend =
          _invoke(service, '_resolveBackendNameForLoad', [], {
                #requestedBackend: GpuBackend.metal,
                #resolvedGpuLayers: ModelParams.maxGpuLayers,
                #forcedCpuFallback: false,
              })
              as String;
      _check(backend, 'Metal');
      (_read(service, '_modelBackendNames') as Map)[1] = backend;
      (_read(service, '_modelResolvedGpuLayers') as Map)[1] =
          ModelParams.maxGpuLayers;
      final params = _read(service, '_modelLoadParams') as Map;
      for (final (
            splitMode,
            mainGpu,
            expectedDevice,
            reportedBackend,
            reportedLayers,
          )
          in [
            (ModelSplitMode.none, -1, null, 'CPU', 0),
            (ModelSplitMode.none, -2, null, 'CPU', 0),
            (ModelSplitMode.none, 0, 12, 'Metal', ModelParams.maxGpuLayers),
            (ModelSplitMode.none, 1, 13, 'Metal', ModelParams.maxGpuLayers),
            (ModelSplitMode.layer, -1, 12, 'Metal', ModelParams.maxGpuLayers),
            (ModelSplitMode.row, -1, 12, 'Metal', ModelParams.maxGpuLayers),
            (ModelSplitMode.tensor, -1, 12, 'Metal', ModelParams.maxGpuLayers),
          ]) {
        params[1] = ModelParams(splitMode: splitMode, mainGpu: mainGpu);
        _invoke(service, '_activateModelReport', [1]);
        _check(service.getActiveBackendName(), reportedBackend);
        _check(service.getResolvedGpuLayers(), reportedLayers);
        final device =
            _invoke(service, '_decisionHeadDevice', [1]) as ggml_backend_dev_t?;
        _check(device?.address, expectedDevice);
      }
      (_read(service, '_modelBackendNames') as Map)[1] = 'CPU';
      _check(_invoke(service, '_decisionHeadDevice', [1]), isNull);
      (_read(service, '_modelBackendNames') as Map)[1] = 'CUDA';
      _check(_invoke(service, '_decisionHeadDevice', [1]), isNull);
    case 'cold':
      final capabilities = service.generationCapabilities(1);
      _check(capabilities.thinkingBudget, isTrue);
      _check(_read(service, '_reasoningBudgetApiLookupAttempted'), isTrue);
      final api = _read(service, '_reasoningBudgetApi');
      _check(api, isNotNull);
      _check(service.generationCapabilities(1).thinkingBudget, isTrue);
      _check(_read(service, '_reasoningBudgetApi'), same(api));
    case 'dead-model':
    case 'dead-vocab':
      final failuresOwner = reflect(calls.failures).type.owner as LibraryMirror;
      final freeOnly =
          reflect(calls.failures)
                  .getField(MirrorSystem.getSymbol('_freeOnly', failuresOwner))
                  .reflectee
              as Map;
      freeOnly[arguments.single == 'dead-model' ? 0x1000 : 0x2000] =
          'llama_dart_tokenize';
      try {
        service.generationCapabilities(1);
        throw StateError('An unusable model must not report capabilities.');
      } on LlamaStateException catch (error) {
        _check(error.message, contains('Unload the model and load it again'));
      }
      _check(_read(service, '_reasoningBudgetApiLookupAttempted'), isFalse);
    default:
      throw ArgumentError.value(arguments.single, 'mode');
  }
}

void _check(Object? actual, Object? expected) {
  final matcher = wrapMatcher(expected);
  if (!matcher.matches(actual, <Object?, Object?>{})) {
    throw StateError(
      'Expected ${matcher.describe(StringDescription())}; got $actual',
    );
  }
}
