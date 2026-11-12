@TestOn('mac-os')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart' as native;
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/native_owner_api.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();
  test(
    'production parent handshake activates owned service creators and releases once after exit',
    () async {
      final probePath = Platform.environment['OWNER_CHAIN_PROBE'];
      if (probePath == null) {
        markTestSkipped(
          'Set OWNER_CHAIN_PROBE, runtime/model paths and hash variables.',
        );
        return;
      }
      final runtimePath = await _verified('OWNER_CHAIN_RUNTIME');
      final modelPath = await _verified('OWNER_CHAIN_MODEL');
      expect(
        (await sha256.bind(File(probePath).openRead()).first).toString(),
        Platform.environment['OWNER_CHAIN_PROBE_SHA256'],
      );
      final probe = DynamicLibrary.open(probePath);
      final runtime = DynamicLibrary.open(runtimePath);
      _expectSelectedImage(runtime);
      final initialize = probe
          .lookupFunction<
            Void Function(Pointer<Utf8>),
            void Function(Pointer<Utf8>)
          >('owner_chain_probe_initialize');
      final path = runtimePath.toNativeUtf8();
      try {
        initialize(path);
      } finally {
        malloc.free(path);
      }
      final count = probe
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'owner_chain_probe_count',
          );
      final markParentRelease = probe
          .lookupFunction<Void Function(Bool), void Function(bool)>(
            'owner_chain_probe_parent_release',
          );
      final owners = runtime.lookupFunction<Int32 Function(), int Function()>(
        'llama_dart_owner_count',
      );
      final tracked = runtime.lookupFunction<Int32 Function(), int Function()>(
        'llama_dart_exit_tracked_count',
      );
      expect(owners(), 0);
      expect(tracked(), 0);
      var cleanups = 0;
      final backend = NativeLlamaBackend(
        workerExitCleanup: (release) async {
          cleanups++;
          markParentRelease(true);
          try {
            await release();
          } finally {
            markParentRelease(false);
          }
        },
      );
      late List<int> live;
      try {
        final model = await backend.modelLoad(modelPath, _params);
        await backend.contextCreate(model, _params);
        // An existing GGUF is deliberately invalid as a projector. This checks
        // production creator routing and typed refusal, not projector inference.
        await expectLater(
          backend.multimodalContextCreate(model, modelPath),
          throwsA(isA<LlamaModelException>()),
        );
        live = [for (var index = 0; index < 12; index++) count(index)];
        expect(
          cleanups,
          0,
          reason: 'Parent release must wait for worker exit.',
        );
        expect(owners(), 1);
      } finally {
        await backend.dispose();
      }
      expect(
        live.take(4),
        [1, 1, 1, 1],
        reason:
            'Parent bootstrap, forwarded token, worker activation and both owned creators must all execute.',
      );
      expect(
        live[4],
        2,
        reason: 'Model/context already belong to the native registry.',
      );
      expect(
        live[5],
        greaterThanOrEqualTo(1),
        reason: 'Raw session state adopts the same staged owner.',
      );
      expect(
        live[9],
        0,
        reason:
            'Token identity, activation and model/context stages must match.',
      );
      expect(
        live[11],
        1,
        reason: 'Projector call must use the owned service creator.',
      );
      expect(
        count(9),
        0,
        reason: 'Native entries must not be untracked before ordinary free.',
      );
      expect(cleanups, 1);
      expect(
        count(10),
        1,
        reason:
            'Exactly one parent cleanup release, separately from the worker finalizer.',
      );
      expect(owners(), 0);
      expect(tracked(), 0);
    },
  );

  test(
    'published old-pin asset selects real legacy fallback and still loads disposes',
    () async {
      if (Platform.environment['OWNER_CHAIN_OLD_PIN'] != '1') {
        markTestSkipped(
          'Run separately with the published old-pin native asset.',
        );
        return;
      }
      final runtime = DynamicLibrary.open(
        await _verified('OWNER_CHAIN_RUNTIME'),
      );
      final modelPath = await _verified('OWNER_CHAIN_MODEL');
      _expectSelectedImage(runtime);
      expect(runtime.providesSymbol('llama_dart_owner_api_version'), isFalse);
      expect(NativeOwnerApi.tryResolve(), isNull);
      final backend = NativeLlamaBackend();
      try {
        final model = await backend.modelLoad(modelPath, _params);
        await backend.contextCreate(model, _params);
      } finally {
        await backend.dispose();
      }
      expect(
        runtime.lookupFunction<Int32 Function(), int Function()>(
          'llama_dart_exit_tracked_count',
        )(),
        0,
      );
    },
  );
}

const ModelParams _params = ModelParams(
  contextSize: 256,
  gpuLayers: 0,
  preferredBackend: GpuBackend.cpu,
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
);
Future<String> _verified(String name) async {
  final path = Platform.environment[name];
  if (path == null) throw StateError('Set $name for this local-only check.');
  expect(
    (await sha256.bind(File(path).openRead()).first).toString(),
    Platform.environment['${name}_SHA256'],
  );
  return path;
}

void _expectSelectedImage(DynamicLibrary runtime) {
  expect(
    Native.addressOf<NativeFunction<Pointer<Char> Function()>>(
      native.llama_dart_build_identity,
    ).address,
    runtime
        .lookup<NativeFunction<Pointer<Char> Function()>>(
          'llama_dart_build_identity',
        )
        .address,
    reason:
        'DynamicLibrary fixture and production @Native asset must resolve the same underlying runtime image.',
  );
}
