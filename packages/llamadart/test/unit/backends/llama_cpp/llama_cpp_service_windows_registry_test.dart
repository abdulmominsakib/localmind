@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:test/test.dart';

import '../../../support/recording_allocator.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _load = 'llama_dart_model_load_from_file';
const _splitBuffer = 'ggml_backend_split_buffer_type';

LibraryMirror get _owner =>
    reflectClass(LlamaCppService).owner as LibraryMirror;

T _invoke<T>(LlamaCppService service, String name, List<Object?> args) =>
    reflect(
          service,
        ).invoke(MirrorSystem.getSymbol(name, _owner), args).reflectee
        as T;

void main() {
  group('Windows row-split registry fallback', () {
    test('an absent proc-address export leaves the decision to llama.cpp', () {
      final fixture = _RegistryFixture(procExported: false);
      fixture.expectLoadReached();
      expect(fixture.calls, [fixture.deviceCall, 'primary']);
    });

    test('a null device registry leaves the decision to llama.cpp', () {
      final fixture = _RegistryFixture(registryAvailable: false);
      fixture.expectLoadReached();
      expect(fixture.calls, [fixture.deviceCall]);
    });

    test('invokes the bound native callback and refuses a missing split '
        'buffer before loading', () {
      final fixture = _RegistryFixture();
      expect(
        fixture.load,
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ModelSplitMode.row'),
              contains('CPU (CPU)'),
              contains('split buffer'),
              contains('ModelSplitMode.layer'),
            ),
          ),
        ),
      );
      expect(fixture.calls, [fixture.deviceCall, fixture.procCall]);
      expect(fixture.recorder.calls, isNot(contains(_load)));
      // Only the device list is allocated before the refusal.
      expect(fixture.allocator.allocations, 1);
      fixture.allocator.expectAllFreed();
    });

    test('a split-buffer address from the native callback reaches loading', () {
      final fixture = _RegistryFixture(splitBuffers: true);
      fixture.expectLoadReached();
      expect(fixture.calls, [fixture.deviceCall, fixture.procCall]);
    });

    test('layer mode never probes row split before loading', () {
      final fixture = _RegistryFixture();
      fixture.expectLoadReached(splitMode: ModelSplitMode.layer);
      expect(fixture.calls, isEmpty);
    });
  });
}

/// The callbacks are native function pointers bound by the production binder,
/// not overrides of the row-split probe. Real CPU pointers keep a bypassed
/// fallback safe; the recording loader stops before native model construction.
final class _RegistryFixture {
  _RegistryFixture({
    bool procExported = true,
    bool registryAvailable = true,
    bool splitBuffers = false,
  }) {
    final bootstrap = LlamaCppService()..initializeBackend();
    addTearDown(bootstrap.dispose);
    final cpu =
        _invoke<List<GgmlDeviceEntry>>(bootstrap, '_registeredDevices', [])
            .firstWhere(
              (entry) =>
                  entry.type ==
                  ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
            )
            .device!;
    expect(cpu, isNot(nullptr));
    ggml_backend_reg_t registry = nullptr;
    final registryCount = _invoke<int>(bootstrap, '_ggmlBackendRegCount', []);
    for (var i = 0; i < registryCount; i++) {
      final candidate = _invoke<ggml_backend_reg_t>(
        bootstrap,
        '_ggmlBackendRegGet',
        [i],
      );
      final name = _invoke<Pointer<Char>>(bootstrap, '_ggmlBackendRegName', [
        candidate,
      ]);
      if (name.cast<Utf8>().toDartString() == 'CPU') registry = candidate;
    }
    expect(registry, isNot(nullptr));
    deviceCall = 'registry:${cpu.address}';
    procCall = 'proc:${registry.address}:$_splitBuffer';
    final count = NativeCallable<Size Function()>.isolateLocal(
      () => 1,
      exceptionalReturn: 0,
    );
    final deviceByType =
        NativeCallable<ggml_backend_dev_t Function(UnsignedInt)>.isolateLocal(
          (int type) => cpu,
        );
    final deviceRegistry =
        NativeCallable<
          ggml_backend_reg_t Function(ggml_backend_dev_t)
        >.isolateLocal((ggml_backend_dev_t device) {
          if (!_loadReached) calls.add('registry:${device.address}');
          return registryAvailable ? registry : nullptr;
        });
    final proc =
        NativeCallable<
          Pointer<Void> Function(ggml_backend_reg_t, Pointer<Char>)
        >.isolateLocal((ggml_backend_reg_t reg, Pointer<Char> name) {
          if (!_loadReached) {
            calls.add(
              'proc:${reg.address}:${name.cast<Utf8>().toDartString()}',
            );
          }
          // The guard checks only whether an address exists; it never calls it.
          return splitBuffers ? registry.cast<Void>() : nullptr;
        });
    addTearDown(count.close);
    addTearDown(deviceByType.close);
    addTearDown(deviceRegistry.close);
    addTearDown(proc.close);
    recorder =
        RecordingExitTeardown(
            ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
          )
          ..fail = (name) {
            if (name != _load) return false;
            _loadReached = true;
            return true;
          };
    service = LlamaCppService(
      isWindows: true,
      isMacosX64: false,
      objectCalls: LlamaCppObjectCalls.tracked(
        recorder.api,
        isWindows: Platform.isWindows,
      ),
      registeredDevices: () => [
        GgmlDeviceEntry(
          name: 'CPU',
          registry: 'CPU',
          description: 'test CPU',
          type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
          device: cpu,
        ),
      ],
      modelLoadAllocator: allocator,
    );
    addTearDown(service.dispose);
    reflect(service).invoke(
      MirrorSystem.getSymbol('_resolveGgmlFallbackFunctions', _owner),
      [],
      {
        #assetSymbol: (String symbol) => switch (symbol) {
          'ggml_backend_reg_count' => count.nativeFunction,
          'ggml_backend_dev_by_type' => deviceByType.nativeFunction,
          'ggml_backend_dev_backend_reg' => deviceRegistry.nativeFunction,
          'ggml_backend_reg_get_proc_address' when procExported =>
            proc.nativeFunction,
          _ => throw ArgumentError('optional export absent'),
        },
      },
    );
    // Windows' generated llama.dll asset need not export the ggml getter.
    // Reproduce that absence on hosts whose consolidated asset exports it.
    reflect(service).setField(
      MirrorSystem.getSymbol('_ggmlBackendRegGetProcAddressPrimary', _owner),
      (ggml_backend_reg_t reg, Pointer<Char> name) {
        if (!_loadReached) calls.add('primary');
        throw ArgumentError('primary export absent');
      },
    );
    service.initializeBackend();
    calls.clear();
    final dir = Directory.systemTemp.createTempSync('windows_registry_');
    addTearDown(() => dir.deleteSync(recursive: true));
    model = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
  }

  // Failure diagnostics query devices again after the intercepted load.
  final List<String> calls = [];
  bool _loadReached = false;
  final RecordingAllocator allocator = RecordingAllocator();
  late final RecordingExitTeardown recorder;
  late final LlamaCppService service;
  late final String model;
  late final String deviceCall;
  late final String procCall;

  void load({ModelSplitMode splitMode = ModelSplitMode.row}) {
    service.loadModel(
      model,
      ModelParams(
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
        splitMode: splitMode,
      ),
    );
  }

  void expectLoadReached({ModelSplitMode splitMode = ModelSplitMode.row}) {
    expect(
      () => load(splitMode: splitMode),
      throwsA(isNot(isA<LlamaUnsupportedException>())),
    );
    expect(recorder.calls.where((name) => name == _load), hasLength(1));
    expect(recorder.loadSplitModes, [splitMode.llamaCppValue]);
    expect(allocator.allocations, 2);
    allocator.expectAllFreed();
  }
}
