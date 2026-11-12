@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/decision_head.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/ggml_graph_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/token_batch.dart';
import 'package:llamadart/src/backends/llama_cpp/load_device_selection.dart';
import 'package:llamadart/src/backends/llama_cpp/safetensors.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/engine/engine.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/config/compute_device.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:llamadart/src/core/models/config/gpu_device_info.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../../../support/recording_allocator.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  group('recurrent rollback reservation policy', () {
    for (final (isRecurrent, isHybrid) in [
      (false, false),
      (true, false),
      (false, true),
      (true, true),
    ]) {
      for (final capacity in [0, 1, 48]) {
        test('capacity=$capacity recurrent=$isRecurrent hybrid=$isHybrid', () {
          void validate() => _invokePrivateForTesting<Object?>(
            LlamaCppService(),
            '_validateRollbackReservation',
            [ModelParams(speculativeRollbackTokenMax: capacity)],
            {#isRecurrent: isRecurrent, #isHybrid: isHybrid},
          );
          if (capacity == 0 || (!isRecurrent && !isHybrid)) {
            expect(validate, returnsNormally);
          } else {
            expect(
              validate,
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (error) => error.message,
                  'actionable diagnostic',
                  allOf(
                    contains('speculativeRollbackTokenMax=$capacity'),
                    contains('graph'),
                    contains('speculativeRollbackTokenMax=0'),
                  ),
                ),
              ),
            );
          }
        });
      }
    }

    test('production context creation retains nonrecurrent reservations', () {
      final temp = Directory.systemTemp.createTempSync(
        'rollback_nonrecurrent_',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      final model = writeSyntheticLlamaGguf(path.join(temp.path, 'llama.gguf'));
      const params = ModelParams(
        contextSize: 512,
        gpuLayers: 0,
        speculativeRollbackTokenMax: 48,
      );
      final handle = service.loadModel(model.path, params);
      expect(service.createContext(handle, params), greaterThan(0));
    });
  });

  test('preserved template tokens remain excluded from native text stops', () {
    final stops = _invokePrivateForTesting<List<String>>(
      LlamaCppService(),
      '_effectiveStopSequences',
      [
        ['<tool_call>', 'cedar17', '<tool_call>suffix'],
        ['<tool_call>'],
      ],
    );
    expect(stops, ['cedar17', '<tool_call>suffix']);
  });

  group('loaded-model generation capabilities', () {
    late LlamaCppService service;
    late int handle;
    setUp(() {
      final temp = Directory.systemTemp.createTempSync('generation-caps-');
      addTearDown(() => temp.deleteSync(recursive: true));
      service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      final file = writeSyntheticLlamaGguf(path.join(temp.path, 'model.gguf'));
      handle = service.loadModel(file.path, const ModelParams(gpuLayers: 0));
    });

    test('unknown and freed handles report no generation controls', () {
      expect(service.generationCapabilities(-1).thinkingBudget, isFalse);
      expect(service.generationCapabilities(-1).penalty, isFalse);
      expect(
        service.generationCapabilities(-1).speculativeDecodingStrategies,
        isEmpty,
      );
      service.freeModel(handle);
      expect(service.generationCapabilities(handle).presencePenalty, isFalse);
    });

    for (final present in [false, true]) {
      test(
        'reasoning-budget symbol present=$present controls the snapshot',
        () {
          final candidates = [
            present
                ? path.absolute(
                    '.dart_tool',
                    'lib',
                    Platform.isWindows
                        ? 'llamadart.dll'
                        : Platform.isMacOS
                        ? 'libllamadart.dylib'
                        : 'libllamadart.so',
                  )
                : 'no-export',
          ];
          Object? resolve() => _invokePrivateForTesting<Object?>(
            service,
            '_resolveReasoningBudgetApi',
            const [],
            {
              #candidates: candidates,
              if (!present)
                #open: (String _) => DynamicLibrary.open(
                  Platform.isWindows
                      ? 'kernel32.dll'
                      : Platform.isMacOS
                      ? '/usr/lib/libSystem.B.dylib'
                      : 'libc.so.6',
                ),
            },
          );
          if (present) {
            expect(resolve(), isNotNull);
          } else {
            expect(resolve, throwsA(isA<LlamaUnsupportedException>()));
          }
          final caps = service.generationCapabilities(handle);
          expect(caps.thinkingBudget, present);
          expect(caps.penalty, isTrue);
          expect(caps.presencePenalty, isTrue);
          expect(caps.minP, isTrue);
          expect(caps.streamBatching, isTrue);
          // MTP can use an external draft even when this model has no MTP head.
          expect(
            caps.speculativeDecodingStrategies,
            SpeculativeDecodingStrategy.values.toSet(),
          );
          expect(
            service.generationCapabilities(handle).thinkingBudget,
            present,
          );
          if (!present) {
            expect(resolve, throwsA(isA<LlamaUnsupportedException>()));
          }
        },
      );
    }

    test(
      'missing draft stays typed through worker, backend and engine',
      () async {
        final temp = Directory.systemTemp.createTempSync('draft-argument-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final file = writeSyntheticLlamaGguf(
          path.join(temp.path, 'model.gguf'),
        );
        final engine = LlamaEngine(NativeLlamaBackend());
        addTearDown(engine.dispose);
        await engine.loadModel(
          file.path,
          modelParams: const ModelParams(gpuLayers: 0, contextSize: 512),
        );
        for (final strategy in [
          SpeculativeDecodingStrategy.draftSimple,
          SpeculativeDecodingStrategy.draftEagle3,
          SpeculativeDecodingStrategy.draftDflash,
          SpeculativeDecodingStrategy.draftDspark,
        ]) {
          await expectLater(
            engine
                .generate(
                  'Hello',
                  params: GenerationParams(
                    maxTokens: 1,
                    speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                      strategies: [strategy],
                    ),
                  ),
                )
                .drain<void>(),
            throwsA(
              isA<LlamaArgumentException>().having(
                (error) => error.message,
                'message',
                'llama.cpp draft-${strategy.name.substring(5).toLowerCase()} requires SpeculativeDecodingConfig.draftModel.',
              ),
            ),
          );
        }
      },
    );
  });

  group('reasoning-budget resolver diagnostics', () {
    Object? resolve(
      LlamaCppService service,
      List<String> candidates, {
      DynamicLibrary Function(String)? open,
    }) => _invokePrivateForTesting<Object?>(
      service,
      '_resolveReasoningBudgetApi',
      const [],
      {#candidates: candidates, #open: open},
    );

    String failure(void Function() action) {
      try {
        action();
      } on LlamaUnsupportedException catch (error) {
        return error.message;
      }
      fail('Expected the production resolver to reject an unavailable helper');
    }

    test('a real library without the export reports lookup, not open', () {
      final systemLibrary = Platform.isWindows
          ? 'kernel32.dll'
          : Platform.isMacOS
          ? '/usr/lib/libSystem.B.dylib'
          : 'libc.so.6';
      final service = LlamaCppService();
      final message = failure(() => resolve(service, [systemLibrary]));
      expect(message, contains('lookup: required export unavailable'));
      expect(message, isNot(contains('open:')));
      expect(message, contains('llama_dart_sampler_init_reasoning_budget'));
      expect(message, isNot(contains(systemLibrary)));
      // A cached failure must preserve the explanation without re-opening.
      expect(
        failure(
          () => resolve(service, [], open: (_) => throw StateError('retry')),
        ),
        message,
      );
    });

    test('an actual missing library reports an opening failure', () {
      final directory = Directory.systemTemp.createTempSync('budget-loader-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final candidate = path.join(directory.path, 'secret-token', 'absent.dll');
      final message = failure(() => resolve(LlamaCppService(), [candidate]));
      expect(message, contains('open:'));
      expect(message, isNot(contains('lookup:')));
      expect(message, isNot(contains(directory.path)));
      expect(message, isNot(contains('secret-token')));
    });

    test(
      'retains safe Windows causes and bounds repeated sensitive errors',
      () {
        for (final code in [5, 126, 127, 193, 1114]) {
          final message = failure(
            () => resolve(
              LlamaCppService(),
              List.filled(
                1000,
                'https://user:password@host/wrapper?token=secret',
              ),
              open: (_) => throw ArgumentError(
                'Failed to load C:\\private\\secret\\wrapper.dll\n'
                'https://user:password@host/?token=secret (error code: $code)',
              ),
            ),
          );
          expect(message, contains('Windows error $code'));
          expect(message, contains('1000 attempts'));
          expect(message.length, lessThan(700));
          for (final secret in [
            'private',
            'secret',
            'password',
            'https:',
            '\n',
          ]) {
            expect(message, isNot(contains(secret)));
          }
        }
      },
    );

    test('continues after opening failure and caches the real wrapper API', () {
      final service = LlamaCppService();
      final wrapper = path.absolute(
        '.dart_tool',
        'lib',
        Platform.isWindows
            ? 'llamadart.dll'
            : Platform.isMacOS
            ? 'libllamadart.dylib'
            : 'libllamadart.so',
      );
      final api = resolve(service, ['$wrapper.absent', wrapper]);
      expect(api, isNotNull);
      expect(
        resolve(service, [], open: (_) => throw StateError('retry')),
        same(api),
      );
      final message = _invokePrivateForTesting<String>(
        service,
        '_reasoningBudgetUnavailableMessage',
        const [],
      );
      expect(message, contains('loaderDiagnostics=[]'));
    });
  });

  group('wrapper sibling dependency loading', () {
    final absolute = path.join(Directory.systemTemp.path, 'llamadart.dll');
    final handle = Pointer<Void>.fromAddress(123);

    test('holds the preload until the wrapper acquires its reference', () {
      final events = <String>[];
      final library = DynamicLibrary.process();
      final result = LlamaCppService.openWrapperLibraryWithDependencies(
        absolute,
        isWindows: true,
        preload: (candidate) {
          expect(candidate, absolute);
          events.add('preload');
          return handle;
        },
        open: (candidate) {
          expect(events, ['preload']);
          events.add('open');
          return library;
        },
        release: (actual, candidate) {
          expect(actual, handle);
          events.add('release');
        },
        exists: (_) => true,
      );
      expect(result, same(library));
      expect(events, ['preload', 'open', 'release']);
    });

    test('releases the preload and preserves the original opening error', () {
      final failure = StateError('missing transitive import');
      var released = false;
      expect(
        () => LlamaCppService.openWrapperLibraryWithDependencies(
          absolute,
          isWindows: true,
          preload: (_) => handle,
          open: (_) => throw failure,
          release: (_, _) => released = true,
          exists: (_) => true,
        ),
        throwsA(same(failure)),
      );
      expect(released, isTrue);
    });

    for (final candidate in [
      'llamadart.dll',
      'package:llamadart/llamadart_wrapper',
    ]) {
      test('does not alter search semantics for $candidate', () {
        LlamaCppService.openWrapperLibraryWithDependencies(
          candidate,
          isWindows: true,
          preload: (_) => throw StateError('unexpected preload'),
          open: (_) => DynamicLibrary.process(),
          release: (_, _) => fail('unexpected release'),
        );
      });
    }

    test('does not preload a missing absolute candidate', () {
      final failure = StateError('not found');
      final checked = <String>[];
      expect(
        () => LlamaCppService.openWrapperLibraryWithDependencies(
          absolute,
          isWindows: true,
          preload: (_) => throw StateError('unexpected preload'),
          open: (_) => throw failure,
          release: (_, _) => fail('unexpected release'),
          exists: (candidate) {
            checked.add(candidate);
            return false;
          },
        ),
        throwsA(same(failure)),
      );
      expect(checked, [absolute]);
    });

    test('checks the file system by default', () {
      final directory = Directory.systemTemp.createTempSync('llamadart_wrap_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final present = path.join(directory.path, 'llamadart.dll');
      File(present).writeAsBytesSync(const []);
      final preloaded = <String>[];
      for (final candidate in [
        present,
        path.join(directory.path, 'missing.dll'),
      ]) {
        LlamaCppService.openWrapperLibraryWithDependencies(
          candidate,
          isWindows: true,
          preload: (candidate) {
            preloaded.add(candidate);
            return nullptr;
          },
          open: (_) => DynamicLibrary.process(),
          release: (_, _) => fail('unexpected release'),
        );
      }
      expect(preloaded, [present]);
    });

    test('does not preload on non-Windows or release a failed preload', () {
      for (final isWindows in [false, true]) {
        LlamaCppService.openWrapperLibraryWithDependencies(
          absolute,
          isWindows: isWindows,
          preload: (_) => nullptr,
          open: (_) => DynamicLibrary.process(),
          release: (_, _) => fail('unexpected release'),
          exists: (_) => true,
        );
      }
    });
  });

  group('aLoRA eager-activation guard', () {
    final adapter = Pointer<llama_adapter_lora>.fromAddress(1);

    test('preserves an ordinary LoRA adapter', () {
      var freed = 0;

      LlamaCppService.debugValidateLoraForEagerActivationForTesting(
        adapter,
        'ordinary.gguf',
        invocationTokenCount: (_) => 0,
        invocationTokenData: (_) => nullptr,
        freeAdapter: (_) => freed++,
      );

      expect(freed, 0);
    });

    test('rejects and frees an aLoRA adapter', () {
      var freed = 0;

      expect(
        () => LlamaCppService.debugValidateLoraForEagerActivationForTesting(
          adapter,
          'activated.gguf',
          invocationTokenCount: (_) => 3,
          invocationTokenData: (_) => Pointer<llama_token>.fromAddress(2),
          freeAdapter: (_) => freed++,
        ),
        throwsA(
          isA<LlamaUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('activated.gguf is an aLoRA adapter'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('3 invocation token(s)'),
              ),
        ),
      );
      expect(freed, 1);
    });

    test('fails closed and frees on missing metadata symbol', () {
      var freed = 0;

      expect(
        () => LlamaCppService.debugValidateLoraForEagerActivationForTesting(
          adapter,
          'unknown.gguf',
          invocationTokenCount: (_) => throw ArgumentError(
            'Could not resolve '
            'llama_adapter_get_alora_n_invocation_tokens',
          ),
          invocationTokenData: (_) => nullptr,
          freeAdapter: (_) => freed++,
        ),
        throwsA(
          isA<LlamaUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('Cannot safely load the LoRA adapter'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('llama_adapter_get_alora_n_invocation_tokens'),
              )
              .having(
                (error) => error.message,
                'message',
                contains("matches this package's bindings"),
              ),
        ),
      );
      expect(freed, 1);
    });

    test('fails closed and frees on a partial metadata ABI', () {
      var freed = 0;

      expect(
        () => LlamaCppService.debugValidateLoraForEagerActivationForTesting(
          adapter,
          'partial-abi.gguf',
          invocationTokenCount: (_) => 0,
          invocationTokenData: (_) => throw ArgumentError(
            'Could not resolve llama_adapter_get_alora_invocation_tokens',
          ),
          freeAdapter: (_) => freed++,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('llama_adapter_get_alora_invocation_tokens'),
          ),
        ),
      );
      expect(freed, 1);
    });

    test('fails closed and frees on inconsistent aLoRA metadata', () {
      var freed = 0;

      expect(
        () => LlamaCppService.debugValidateLoraForEagerActivationForTesting(
          adapter,
          'inconsistent-metadata.gguf',
          invocationTokenCount: (_) => 1,
          invocationTokenData: (_) => nullptr,
          freeAdapter: (_) => freed++,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Cannot safely load the LoRA adapter'),
          ),
        ),
      );
      expect(freed, 1);
    });

    test('keeps version-skew failure typed if cleanup also fails', () {
      expect(
        () => LlamaCppService.debugValidateLoraForEagerActivationForTesting(
          adapter,
          'severely-skewed.gguf',
          invocationTokenCount: (_) => throw ArgumentError('missing getter'),
          invocationTokenData: (_) => nullptr,
          freeAdapter: (_) => throw ArgumentError('missing free'),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });

  group('getVramInfo', () {
    test('returns a non-negative (total, free) record without throwing', () {
      // Shape invariant: callers destructure these two fields. A
      // rename or struct change in `LlamaCppService.getVramInfo`
      // would break every backend that forwards the worker
      // SystemInfoResponse fields. Hosts with GPU runtimes available
      // may return real memory here; hosts without them return (0, 0).
      final service = LlamaCppService();
      final info = service.getVramInfo();
      expect(info.total, isA<int>());
      expect(info.free, isA<int>());
      expect(info.total, greaterThanOrEqualTo(0));
      expect(info.free, greaterThanOrEqualTo(0));
    });
  });

  group('listGpuDevices', () {
    test('returns a List<GpuDeviceInfo> without throwing', () {
      // Hosts with a GPU runtime return real devices; CI hosts without one
      // return an empty list. Either way the call must not throw and every
      // element must satisfy the field contract callers rely on. A rename or
      // struct change in `LlamaCppService.listGpuDevices` breaks this.
      final service = LlamaCppService();
      final devices = service.listGpuDevices();
      expect(devices, isA<List<GpuDeviceInfo>>());
      for (final device in devices) {
        expect(device.type, isNot(GpuDeviceType.cpu));
        expect(device.mainGpu, greaterThanOrEqualTo(0));
        expect(device.memoryFreeBytes, greaterThanOrEqualTo(0));
        expect(device.memoryTotalBytes, greaterThanOrEqualTo(0));
      }
    });

    test('does not throw when probing an unavailable backend', () {
      // probeBackends opt-in must stay safe: requesting a backend whose module
      // or symbols are absent (as on CI hosts) returns a list rather than
      // throwing.
      final service = LlamaCppService();
      final devices = service.listGpuDevices(
        probeBackends: const [GpuBackend.vulkan, GpuBackend.cuda],
      );
      expect(devices, isA<List<GpuDeviceInfo>>());
    });
  });

  group('gpuBackendFromRegName', () {
    test('maps ggml registry names (incl. Metal MTL) to GpuBackend', () {
      expect(
        LlamaCppService.gpuBackendFromRegName('Vulkan'),
        GpuBackend.vulkan,
      );
      expect(LlamaCppService.gpuBackendFromRegName('CUDA'), GpuBackend.cuda);
      expect(LlamaCppService.gpuBackendFromRegName('Metal'), GpuBackend.metal);
      // Regression: macOS reports the registry name as "MTL", which previously
      // fell through to GpuBackend.auto.
      expect(LlamaCppService.gpuBackendFromRegName('MTL'), GpuBackend.metal);
      expect(LlamaCppService.gpuBackendFromRegName('ROCm'), GpuBackend.hip);
      expect(LlamaCppService.gpuBackendFromRegName('HIP'), GpuBackend.hip);
      expect(
        LlamaCppService.gpuBackendFromRegName('OpenCL'),
        GpuBackend.opencl,
      );
      expect(LlamaCppService.gpuBackendFromRegName('BLAS'), GpuBackend.blas);
      expect(LlamaCppService.gpuBackendFromRegName('CPU'), GpuBackend.cpu);
      expect(
        LlamaCppService.gpuBackendFromRegName('SomethingElse'),
        GpuBackend.auto,
      );
    });
  });

  group('explicit GpuBackend device lookup', () {
    test('names the ggml registries of the pinned llama.cpp', () {
      // Registry names returned by each ggml *_reg_get_name at the llama.cpp
      // commit pinned by native v0.5.0; HIP builds define GGML_CUDA_NAME as
      // "ROCm" and Metal defines GGML_METAL_NAME as "MTL".
      expect(
        {
          for (final backend in GpuBackend.values)
            backend: LlamaCppService.ggmlGpuRegistryName(backend),
        },
        {
          GpuBackend.auto: null,
          GpuBackend.cpu: null,
          GpuBackend.vulkan: 'Vulkan',
          GpuBackend.metal: 'MTL',
          GpuBackend.cuda: 'CUDA',
          GpuBackend.blas: 'BLAS',
          GpuBackend.opencl: 'OpenCL',
          GpuBackend.hip: 'ROCm',
        },
      );
    });

    test('names the backend of a load from ggml registry labels', () {
      final service = LlamaCppService();
      // Labels as getBackendInfo builds them: '<registry> (<device>)'.
      const labels = <GpuBackend, String>{
        GpuBackend.vulkan: 'Vulkan (Vulkan0)',
        GpuBackend.metal: 'MTL (MTL0)',
        GpuBackend.cuda: 'CUDA (CUDA0)',
        GpuBackend.blas: 'BLAS',
        GpuBackend.opencl: 'OpenCL (GPUOpenCL)',
        GpuBackend.hip: 'ROCm (ROCm0)',
      };
      const displayNames = <GpuBackend, String>{
        GpuBackend.vulkan: 'Vulkan',
        GpuBackend.metal: 'Metal',
        GpuBackend.cuda: 'CUDA',
        GpuBackend.blas: 'BLAS',
        GpuBackend.opencl: 'OpenCL',
        GpuBackend.hip: 'HIP',
      };
      for (final MapEntry(key: backend, value: label) in labels.entries) {
        expect(
          _invokePrivateForTesting<String>(
            service,
            '_resolveExplicitBackendName',
            [backend, 'CPU, $label'],
          ),
          displayNames[backend],
          reason: label,
        );
      }
      expect(
        _invokePrivateForTesting<String?>(service, '_resolveAutoBackendName', [
          'CPU, ROCm (ROCm0)',
        ]),
        'HIP',
      );
    });

    test('resolves devices exactly for registered GPU registries', () {
      final service = LlamaCppService();
      _invokePrivateForTesting<void>(service, '_prepareBackendsForModelLoad', [
        GpuBackend.auto,
      ]);
      final registeredWithDevices = <GpuBackend>{};
      final registryCount = _invokePrivateForTesting<int>(
        service,
        '_ggmlBackendRegCount',
        [],
      );
      for (var i = 0; i < registryCount; i++) {
        final reg = _invokePrivateForTesting<ggml_backend_reg_t>(
          service,
          '_ggmlBackendRegGet',
          [i],
        );
        if (reg == nullptr) continue;
        final namePtr = _invokePrivateForTesting<Pointer<Char>>(
          service,
          '_ggmlBackendRegName',
          [reg],
        );
        if (namePtr == nullptr) continue;
        final name = namePtr.cast<Utf8>().toDartString();
        final deviceCount = _invokePrivateForTesting<int>(
          service,
          '_ggmlBackendRegDevCount',
          [reg],
        );
        if (deviceCount > 0) {
          registeredWithDevices.add(
            LlamaCppService.gpuBackendFromRegName(name),
          );
        }
      }

      for (final backend in GpuBackend.values) {
        if (backend == GpuBackend.auto || backend == GpuBackend.cpu) continue;
        final devices = _invokePrivateForTesting<List<ggml_backend_dev_t>?>(
          service,
          '_resolvePreferredDevices',
          [backend],
        );
        expect(
          devices?.isNotEmpty ?? false,
          registeredWithDevices.contains(backend),
          reason: '$backend; registries with devices: $registeredWithDevices',
        );
      }
    });
  });

  group('loadModel preflight validation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('llamadart-loadmodel-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('throws when model file does not exist', () {
      final service = LlamaCppService();
      final missingPath = path.join(tempDir.path, 'missing.gguf');

      expect(
        () => service.loadModel(missingPath, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when model file is empty', () {
      final service = LlamaCppService();
      final emptyFile = File(path.join(tempDir.path, 'empty.gguf'))
        ..writeAsBytesSync(const <int>[]);

      expect(
        () => service.loadModel(emptyFile.path, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('throws when model file does not look like GGUF', () {
      final service = LlamaCppService();
      final badFile = File(path.join(tempDir.path, 'bad.gguf'))
        ..writeAsBytesSync(const <int>[0x00, 0x01, 0x02, 0x03]);

      expect(
        () => service.loadModel(badFile.path, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('speculative validation', () {
    late LlamaCppService service;
    late Directory tempDir;

    setUp(() {
      service = LlamaCppService();
      tempDir = Directory.systemTemp.createTempSync('llamadart-spec-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('de-duplicates mixed strategies before native mapping', () {
      final typeNames = service.debugResolveSpeculativeTypeNamesForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: [
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.mtp,
              SpeculativeDecodingStrategy.mtp,
            ],
            draftTokenMax: 4,
          ),
        ),
      );

      expect(typeNames, 'ngram-mod,draft-mtp');
    });

    test('maps DSpark exactly as an external non-MTP draft context', () {
      final resolved = service.debugResolveSpeculativeNativeParamsForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
            draftModelPath: 'dspark.gguf',
            draftTokenMax: 7,
          ),
        ),
      );

      expect(resolved['typeNames'], 'draft-dspark');
      expect(resolved['draftTokenMax'], 7);
      expect(resolved['hasDraftContextStrategy'], isTrue);
      expect(resolved['requiresExternalDraftModel'], isTrue);
      expect(resolved['usesMtp'], isFalse);
      expect(resolved['suppressDraftProcessLogits'], isTrue);
    });

    test('mixes DSpark with draftless n-gram strategies in order', () {
      final typeNames = service.debugResolveSpeculativeTypeNamesForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
            strategies: [
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.draftDspark,
            ],
            draftModelPath: 'dspark.gguf',
          ),
        ),
      );

      expect(typeNames, 'ngram-mod,draft-dspark');
    });

    test('rejects speculative decoding with a thinking budget', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            thinkingBudget: ThinkingBudget(maxTokens: 64),
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMod(),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('uses ngram size M as native draft cap for map strategies', () {
      final configs = <String, SpeculativeDecodingConfig>{
        'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
          draftTokenMax: 8,
        ),
        'ngram-map-k': const SpeculativeDecodingConfig.ngramMapK(
          draftTokenMax: 8,
        ),
        'ngram-map-k4v': const SpeculativeDecodingConfig.ngramMapK4v(
          draftTokenMax: 8,
        ),
      };

      for (final entry in configs.entries) {
        final defaults = service.debugResolveSpeculativeNativeParamsForTesting(
          GenerationParams(speculativeDecodingConfig: entry.value),
        );

        expect(defaults['typeNames'], entry.key);
        expect(defaults['draftTokenMax'], 48);
        expect(defaults['ngramSizeM'], isNull);
      }

      final explicitConfigs = <String, SpeculativeDecodingConfig>{
        'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
        'ngram-map-k': const SpeculativeDecodingConfig.ngramMapK(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
        'ngram-map-k4v': const SpeculativeDecodingConfig.ngramMapK4v(
          draftTokenMax: 8,
          ngramSizeM: 16,
        ),
      };

      for (final entry in explicitConfigs.entries) {
        final explicit = service.debugResolveSpeculativeNativeParamsForTesting(
          GenerationParams(speculativeDecodingConfig: entry.value),
        );

        expect(explicit['typeNames'], entry.key);
        expect(explicit['draftTokenMax'], 16);
        expect(explicit['ngramSizeM'], 16);
      }
    });

    test('uses upstream ngram size M default when draft cap is omitted', () {
      final resolved = service.debugResolveSpeculativeNativeParamsForTesting(
        const GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramMapK(),
        ),
      );

      expect(resolved['draftTokenMax'], 48);
      expect(resolved['ngramSizeM'], isNull);
    });

    test('rejects mixed configs with more than one draft strategy', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [
                SpeculativeDecodingStrategy.mtp,
                SpeculativeDecodingStrategy.draftSimple,
              ],
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('at most one draft-model strategy'),
          ),
        ),
      );
    });

    test('rejects DSpark mixed with another draft-context strategy', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [
                SpeculativeDecodingStrategy.draftDspark,
                SpeculativeDecodingStrategy.mtp,
              ],
              draftModelPath: 'dspark.gguf',
            ),
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('at most one draft-model strategy'),
          ),
        ),
      );
    });

    for (final strategy in [
      SpeculativeDecodingStrategy.draftSimple,
      SpeculativeDecodingStrategy.draftEagle3,
      SpeculativeDecodingStrategy.draftDflash,
      SpeculativeDecodingStrategy.draftDspark,
    ]) {
      test('$strategy missing draft is a typed argument error', () {
        expect(
          () => service.debugResolveSpeculativeTypeNamesForTesting(
            GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                strategies: [strategy],
              ),
            ),
          ),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              'llama.cpp draft-${strategy.name.substring(5).toLowerCase()} requires SpeculativeDecodingConfig.draftModel.',
            ),
          ),
        );
        expect(
          service.debugResolveSpeculativeTypeNamesForTesting(
            GenerationParams(
              speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                strategies: [strategy],
                draftModelPath: 'draft.gguf',
              ),
            ),
          ),
          startsWith('draft-'),
        );
      });
    }

    test('requires a non-empty draftModelPath for DSpark', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
              strategies: [SpeculativeDecodingStrategy.draftDspark],
            ),
          ),
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            contains('requires SpeculativeDecodingConfig.draftModel'),
          ),
        ),
      );
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
              draftModelPath: ' ',
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('must be null or a non-empty path'),
          ),
        ),
      );
    });

    test('suppresses process logits only for external draft strategies', () {
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftEagle3(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        isTrue,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
          ),
        ),
        isFalse,
      );
      expect(
        service.debugSuppressesDraftProcessLogitsForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(),
          ),
        ),
        isFalse,
      );
    });

    test('requires loadMtp for bundled MTP tensors', () {
      const generationParams = GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
      );

      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          generationParams,
          const ModelParams(),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('ModelParams(loadMtp: true)'),
          ),
        ),
      );
      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          generationParams,
          const ModelParams(loadMtp: true),
        ),
        returnsNormally,
      );
    });

    test('external MTP draft does not require target bundled tensors', () {
      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(
              draftModelPath: 'draft.gguf',
            ),
          ),
          const ModelParams(),
        ),
        returnsNormally,
      );
    });

    test('DSpark never requires target bundled MTP tensors', () {
      expect(
        () => service.debugValidateMtpModelLoadForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
              draftModelPath: 'draft.gguf',
            ),
          ),
          const ModelParams(),
        ),
        returnsNormally,
      );
    });

    test('reports DSpark native version skew as a typed failure', () {
      expect(
        () => service.debugThrowSpeculativeInitFailureForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDspark(
              draftModelPath: 'draft.gguf',
            ),
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>()
              .having(
                (error) => error.message,
                'message',
                contains('draft-dspark'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('llamadart-native@b10356'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('draft-context support'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('draftTokenMax'),
              ),
        ),
      );
    });

    test('temporarily zeros and restores suppressed batch logits', () {
      final logits = malloc<Int8>(3);
      addTearDown(() => malloc.free(logits));
      logits[0] = 1;
      logits[1] = 0;
      logits[2] = 1;

      final seenLogits = <int>[];
      final result = LlamaCppService.debugWithSuppressedBatchLogitsForTesting(
        logits,
        3,
        true,
        () {
          seenLogits.addAll([logits[0], logits[1], logits[2]]);
          logits[1] = 7;
          return 'processed';
        },
      );

      expect(result, 'processed');
      expect(seenLogits, [0, 0, 0]);
      expect([logits[0], logits[1], logits[2]], [1, 0, 1]);
    });

    test('leaves batch logits untouched when suppression is disabled', () {
      final logits = malloc<Int8>(2);
      addTearDown(() => malloc.free(logits));
      logits[0] = 1;
      logits[1] = 0;

      final seenLogits = <int>[];
      LlamaCppService.debugWithSuppressedBatchLogitsForTesting(
        logits,
        2,
        false,
        () {
          seenLogits.addAll([logits[0], logits[1]]);
        },
      );

      expect(seenLogits, [1, 0]);
      expect([logits[0], logits[1]], [1, 0]);
    });

    test('rejects invalid ngram-cache paths', () {
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          const GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
              ngramCacheStaticPath: ' ',
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('must be null or a non-empty path'),
          ),
        ),
      );

      final missingPath = path.join(tempDir.path, 'missing.ngram');
      expect(
        () => service.debugResolveSpeculativeTypeNamesForTesting(
          GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.ngramCache(
              ngramCacheStaticPath: missingPath,
            ),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('must exist before enabling llama.cpp ngram-cache'),
          ),
        ),
      );
    });
  });

  test(
    'scoped prompt penalties seed only penalties and never activate a lazy grammar',
    () {
      final directory = Directory.systemTemp.createTempSync(
        'prompt-penalty-grammar-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = writeSyntheticLlamaGguf(
        path.join(directory.path, 'model.gguf'),
      );
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);
      final handle = service.loadModel(
        file.path,
        const ModelParams(gpuLayers: 0),
      );
      final model = _readPrivateForTesting<Map<int, Object>>(
        service,
        '_models',
      )[handle]!;
      final vocab = llama_model_get_vocab(
        reflect(model).getField(#pointer).reflectee as Pointer<llama_model>,
      );
      final tokens = [service.tokenize(handle, 'B', false).last];
      final prompt = calloc<Int32>(1)..value = tokens.single;
      final grammar = 'root ::= "A"'.toNativeUtf8();
      final root = 'root'.toNativeUtf8();
      addTearDown(() {
        calloc.free(prompt);
        malloc.free(grammar);
        malloc.free(root);
      });
      for (final withGrammar in [false, true]) {
        for (final enabled in [false, true]) {
          final params = GenerationParams(
            temp: 0,
            penalty: 1,
            presencePenalty: 3,
            grammar: withGrammar ? 'root ::= "A"' : null,
            grammarLazy: withGrammar,
            grammarTriggers: [GenerationGrammarTrigger(type: 0, value: 'B')],
          );
          final lazy = withGrammar
              ? _invokePrivateForTesting<Object>(
                  service,
                  '_buildLazyGrammarConfig',
                  [params],
                )
              : null;
          final sampler = _invokePrivateForTesting<Pointer<llama_sampler>>(
            service,
            '_initializeSampler',
            [
              params,
              vocab,
              llama_vocab_n_tokens(vocab),
              <int>[],
              withGrammar ? grammar : nullptr,
              root,
              lazy,
              null,
              null,
              1,
              prompt,
              enabled,
            ],
          );
          try {
            final data = calloc<llama_token_data>(1);
            final array = calloc<llama_token_data_array>();
            try {
              data.ref
                ..id = tokens.single
                ..logit = 5
                ..p = 0;
              array.ref
                ..data = data
                ..size = 1
                ..selected = -1
                ..sorted = false;
              llama_sampler_apply(llama_sampler_chain_get(sampler, 0), array);
              expect(
                data.ref.logit,
                !withGrammar || enabled ? 2 : 5,
                reason: 'grammar=$withGrammar policy=$enabled',
              );
              if (withGrammar) {
                data.ref.logit = 5;
                llama_sampler_apply(llama_sampler_chain_get(sampler, 1), array);
                expect(
                  data.ref.logit,
                  5,
                  reason:
                      'Prompt trigger B must not activate the grammar that only accepts A.',
                );
              }
            } finally {
              calloc.free(data);
              calloc.free(array);
            }
          } finally {
            _invokePrivateForTesting<void>(service, '_freeSamplerChain', [
              sampler,
            ]);
            if (lazy != null) reflect(lazy).invoke(#dispose, []);
          }
        }
      }
    },
  );

  test('maps presence penalty to the native penalty sampler', () {
    final service = LlamaCppService();

    expect(
      service.debugResolvePenaltySamplerParamsForTesting(
        const GenerationParams(penalty: 1.0, presencePenalty: 1.5),
      ),
      <String, Object>{
        'lastN': 64,
        'repeat': 1.0,
        'frequency': 0.0,
        'presence': 1.5,
      },
    );
  });

  group('thinking-budget validation', () {
    test(
      'rejects a token budget that exceeds the native signed 32-bit limit',
      () {
        final service = LlamaCppService();

        expect(
          () => service.debugValidateThinkingBudgetForTesting(
            const GenerationParams(
              thinkingBudget: ThinkingBudget(maxTokens: 2147483648),
            ),
          ),
          throwsA(
            isA<RangeError>().having(
              (error) => error.toString(),
              'message',
              contains('signed 32-bit'),
            ),
          ),
        );
      },
    );
  });

  group('startup diagnostics', () {
    group('buffer retention', () {
      test('drops repeats and keeps the first position', () {
        final buffer = StartupDiagnosticBuffer()
          ..record('first')
          ..record('second')
          ..record('first')
          ..record('')
          ..record('second', category: StartupDiagnosticCategory.teardown);

        expect(buffer.entries, <String>[
          'first',
          'second',
          '${startupTeardownDiagnosticPrefix}second',
        ]);
      });

      test('teardown overflow never evicts the discovery failure', () {
        final buffer = StartupDiagnosticBuffer();
        const discovery =
            'Failed to preload Windows backend dependency '
            r'`C:\app\cudart64_12.dll` for `cuda`: error code 126';
        buffer.record(discovery);
        for (var i = 0; i < 100; i++) {
          buffer.record(
            'Failed to release temporary Windows backend module preload for '
            '`C:\\app\\ggml-cuda-$i.dll` (`cuda`).',
            category: StartupDiagnosticCategory.teardown,
          );
        }
        const outcome = 'Backend asset `package:llamadart/cuda` failed';
        buffer.record(outcome);

        final entries = buffer.entries;
        expect(entries, hasLength(StartupDiagnosticBuffer.maxEntries));
        expect(entries.first, discovery);
        expect(entries.last, outcome);
        expect(entries[1], contains('ggml-cuda-70.dll'));
        expect(entries[entries.length - 2], contains('ggml-cuda-99.dll'));

        final formatted = formatStartupDiagnostics(entries, maxLength: 512);
        expect(formatted, contains(discovery));
        expect(formatted, contains(outcome));
        expect(
          formatted.length,
          lessThanOrEqualTo(', startupDiagnostics=[]'.length + 512),
        );
      });

      test('causal overflow evicts teardown, then the unpinned middle', () {
        final buffer = StartupDiagnosticBuffer();
        for (var i = 0; i < 4; i++) {
          buffer.record(
            'noise $i',
            category: StartupDiagnosticCategory.teardown,
          );
        }
        for (var i = 0; i < 40; i++) {
          buffer.record('probe $i');
        }
        buffer.record(
          'late noise',
          category: StartupDiagnosticCategory.teardown,
        );

        expect(buffer.entries, <String>[
          for (var i = 0; i < StartupDiagnosticBuffer.pinnedCausalEntries; i++)
            'probe $i',
          for (var i = 24; i < 40; i++) 'probe $i',
        ]);
      });

      test('a failed Windows module release records as teardown', () {
        final service = LlamaCppService();
        for (final error in <Object?>[null, 'error code 5']) {
          _invokePrivateForTesting<void>(
            service,
            '_recordWindowsBackendModuleReleaseFailure',
            <Object?>[r'C:\app\ggml-cuda.dll', 'cuda', error],
          );
        }

        expect(service.getStartupDiagnostics(), <String>[
          '${startupTeardownDiagnosticPrefix}Failed to release temporary '
              r'Windows backend module preload for `C:\app\ggml-cuda.dll` '
              '(`cuda`).',
          '${startupTeardownDiagnosticPrefix}Failed to release temporary '
              r'Windows backend module preload for `C:\app\ggml-cuda.dll` '
              '(`cuda`): error code 5',
        ]);
      });

      test('stores sanitized entries and bounds each one', () {
        final buffer = StartupDiagnosticBuffer()
          ..record(
            'failed at https://user:pass@example.com/lib.so'
            '?X-Amz-Signature=secret&access_token=bearer-secret#secret',
          )
          ..record('control\u0000split\nline')
          ..record(
            'https://user:pass@example.com/${'a' * 5000}?token=secret',
            category: StartupDiagnosticCategory.teardown,
          );

        final entries = buffer.entries;
        expect(entries[0], 'failed at https://example.com/lib.so');
        expect(entries[1], 'control split line');
        expect(entries[2], startsWith(startupTeardownDiagnosticPrefix));
        expect(entries[2], endsWith('...'));
        expect(entries[2], hasLength(StartupDiagnosticBuffer.maxEntryLength));
        for (final entry in entries) {
          expect(entry, isNot(contains('pass')));
          expect(entry, isNot(contains('secret')));
          expect(entry, isNot(contains('X-Amz')));
        }
        expect(
          formatStartupDiagnostics(entries),
          ', startupDiagnostics=[${entries.join('; ')}]',
        );
      });
    });

    test('a fresh service has nothing recorded', () {
      expect(LlamaCppService().getStartupDiagnostics(), isEmpty);
    });

    group('native null-return branches', () {
      late Directory tempDir;
      late String corruptGgufPath;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync(
          'llamadart-load-failure-',
        );
        corruptGgufPath = path.join(tempDir.path, 'corrupt.gguf');
        File(
          corruptGgufPath,
        ).writeAsBytesSync(const <int>[0x47, 0x47, 0x55, 0x46]);
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('main-model failure uses the service diagnostics buffer', () {
        final service = _warmedLoadFailureService(corruptGgufPath);
        _recordStartupDiagnosticForTesting(
          service,
          'failed at '
          'https://safe.example/a,'
          'HTTPS:\n//user\n:pass@example.com/libggml.so'
          '?token=secret#fragment',
        );
        _recordStartupDiagnosticForTesting(
          service,
          'next\u0000line\u0085more\u2028last\u2029line',
        );

        expect(
          () => service.loadModel(corruptGgufPath, const ModelParams()),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              allOf(
                contains('Failed to load model (size=4 bytes,'),
                contains(
                  'startupDiagnostics=[<redacted-startup-diagnostic>; '
                  'next line more last line]',
                ),
                isNot(contains('user:pass')),
                isNot(contains('token=secret')),
                isNot(contains('\n')),
                isNot(contains('\u0000')),
              ),
            ),
          ),
        );
      });

      test('main-model failure omits the suffix for an empty buffer', () {
        final service = _warmedLoadFailureService(corruptGgufPath);

        expect(
          () => service.loadModel(corruptGgufPath, const ModelParams()),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              isNot(contains('startupDiagnostics=')),
            ),
          ),
        );
      });

      test('draft-model failure uses its label and bounded root cause', () {
        final service = _warmedLoadFailureService(corruptGgufPath);
        _recordStartupDiagnosticForTesting(service, 'oldest:${'a' * 5000}');
        for (var i = 0; i < 40; i++) {
          _recordStartupDiagnosticForTesting(
            service,
            'FreeLibrary failed for module $i ${'b' * 100}',
            category: StartupDiagnosticCategory.teardown,
          );
        }
        _recordStartupDiagnosticForTesting(service, 'newest failure');

        expect(
          () => _loadDraftModelForTesting(
            service,
            corruptGgufPath,
            'speculative draft model',
          ),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              allOf(
                contains(
                  'Failed to load speculative draft model '
                  '(size=4 bytes, path=$corruptGgufPath,',
                ),
                contains('startupDiagnostics=[oldest:aaa'),
                contains(
                  'aaa...; ${startupTeardownDiagnosticPrefix}FreeLibrary',
                ),
                endsWith('; ...; newest failure]'),
                predicate<String>((message) {
                  final marker = 'startupDiagnostics=[';
                  final start = message.indexOf(marker);
                  final content = message.substring(
                    start + marker.length,
                    message.length - 1,
                  );
                  return content.length <= 4096 && content.length > 3900;
                }, 'caps rendered diagnostic content at 4096 characters'),
              ),
            ),
          ),
        );
      });

      test('draft-model failure omits the suffix for an empty buffer', () {
        final service = _warmedLoadFailureService(corruptGgufPath);

        expect(
          () => _loadDraftModelForTesting(service, corruptGgufPath, 'draft'),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              allOf(
                contains('Failed to load draft (size=4 bytes,'),
                isNot(contains('startupDiagnostics=')),
              ),
            ),
          ),
        );
      });
    });
  });

  group('invalid-handle guard rails', () {
    late LlamaCppService service;

    setUp(() {
      service = LlamaCppService();
    });

    test('createContext throws for unknown model handle', () {
      expect(
        () => service.createContext(-1, const ModelParams()),
        throwsA(isA<Exception>()),
      );
    });

    test('generate stream reports error for unknown context handle', () async {
      expect(
        service
            .generate(-1, 'hello', const GenerationParams(), 0)
            .drain<void>(),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'generate reports unknown context before speculative decoding',
      () async {
        expect(
          service
              .generate(
                -1,
                'hello',
                const GenerationParams(speculativeDecoding: true),
                0,
              )
              .drain<void>(),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'generate reports unknown context before speculative config',
      () async {
        expect(
          service
              .generate(
                -1,
                'hello',
                const GenerationParams(
                  speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
                ),
                0,
              )
              .drain<void>(),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('embed and embedBatch throw for unknown context handle', () {
      expect(() => service.embed(-1, 'hello'), throwsA(isA<Exception>()));
      expect(
        () => service.embedBatch(-1, const <String>['hello']),
        throwsA(isA<Exception>()),
      );
    });

    test('state file methods throw for unknown context handle', () {
      expect(
        () => service.stateSaveFile(-1, '/tmp/state.bin', const <int>[]),
        throwsA(isA<LlamaStateException>()),
      );
      expect(
        () => service.stateLoadFile(-1, '/tmp/state.bin', 16),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('createMultimodalContext throws for unknown model handle', () {
      expect(
        () => service.createMultimodalContext(-1, 'mmproj.gguf'),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'token and metadata methods return safe defaults for unknown model',
      () {
        expect(service.tokenize(-1, 'hello', true), isEmpty);
        expect(service.detokenize(-1, const <int>[1, 2, 3], false), isEmpty);
        expect(service.getMetadata(-1), isEmpty);
      },
    );

    test(
      'state/introspection methods return safe defaults before model load',
      () {
        expect(service.getContextSize(-1), 0);
        expect(service.getResolvedGpuLayers(), isNull);
        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getAvailableBackendInfo(), contains('CPU'));
      },
    );

    test('handleLora and free methods are no-op for unknown handles', () {
      service.handleLora(-1, '/tmp/a.lora', 0.5, 'set');
      service.freeModel(-1);
      service.freeContext(-1);
      service.freeMultimodalContext(-1);
    });
  });

  group('decision heads', () {
    late LlamaCppService service;

    setUp(() {
      service = LlamaCppService();
    });

    test('unknown models and heads fail with typed errors', () {
      final capabilities = service.decisionCapabilities(-1);
      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('handle -1'));
      expect(
        () => service.loadDecisionHead(-1, 'head.safetensors', null),
        throwsA(isA<LlamaStateException>()),
      );
      expect(
        () => service.runDecision(-1, const []),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('Load the decision head again'),
          ),
        ),
      );
      service.freeDecisionHead(-1);
    });

    group('head lifecycle', () {
      late Directory tempDir;

      setUpAll(() => LlamaCppService().initializeBackend());

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('decision_lifecycle_');
      });

      tearDown(() {
        service.dispose();
        tempDir.deleteSync(recursive: true);
      });

      test('single-device CPU placement reports a CPU decision head', () {
        var registryReads = 0;
        var exposeGpu = false;
        var integrated = false;
        final gpu = Pointer<ggml_backend_device>.fromAddress(0x1234);
        service = LlamaCppService(
          registeredDevices: () {
            registryReads++;
            return exposeGpu
                ? [
                    GgmlDeviceEntry(
                      name: 'Description only',
                      registry: 'Metal',
                      type: ggml_backend_dev_type
                          .GGML_BACKEND_DEVICE_TYPE_GPU
                          .value,
                    ),
                    GgmlDeviceEntry(
                      name: 'Null device',
                      registry: 'Metal',
                      device: nullptr,
                      type: ggml_backend_dev_type
                          .GGML_BACKEND_DEVICE_TYPE_GPU
                          .value,
                    ),
                    GgmlDeviceEntry(
                      name: 'CPU',
                      registry: 'Metal',
                      device: Pointer.fromAddress(0x5678),
                      type: ggml_backend_dev_type
                          .GGML_BACKEND_DEVICE_TYPE_CPU
                          .value,
                    ),
                    GgmlDeviceEntry(
                      name: 'Fake Metal GPU',
                      registry: 'Metal',
                      type: integrated
                          ? ggml_backend_dev_type
                                .GGML_BACKEND_DEVICE_TYPE_IGPU
                                .value
                          : ggml_backend_dev_type
                                .GGML_BACKEND_DEVICE_TYPE_GPU
                                .value,
                      device: gpu,
                    ),
                  ]
                : [];
          },
        );
        final encoderPath = path.join(tempDir.path, 'encoder.gguf');
        final headPath = path.join(tempDir.path, 'head.safetensors');
        final configPath = path.join(tempDir.path, 'config.json');
        writeSyntheticModernBertGguf(encoderPath, decisionTokens: true);
        SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(headPath);
        File(configPath).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
        final model = service.loadModel(
          encoderPath,
          const ModelParams(splitMode: ModelSplitMode.none, mainGpu: -1),
        );
        // Preserve the GPU load metadata even on a host without GPU devices.
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        )[model] = 'Metal';
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        )[model] = 99;
        exposeGpu = true;
        registryReads = 0;
        final head = service.loadDecisionHead(model, headPath, configPath);
        expect(head.deviceName, 'CPU');
        expect(
          registryReads,
          0,
          reason: 'CPU placement must skip GPU selection',
        );
        _readPrivateForTesting<Map<int, ModelParams>>(
          service,
          '_modelLoadParams',
        )[model] = const ModelParams();
        expect(
          _invokePrivateForTesting<ggml_backend_dev_t?>(
            service,
            '_decisionHeadDevice',
            [model],
          ),
          gpu,
          reason: 'the fake GPU registry must discriminate on a CPU-only host',
        );
        integrated = true;
        expect(
          _invokePrivateForTesting<ggml_backend_dev_t?>(
            service,
            '_decisionHeadDevice',
            [model],
          ),
          gpu,
        );
      });

      // On a CPU-only host the model's GPU placement is written into the
      // service, and the GPU device a load selects is the CPU device, so the
      // head runs on the CPU while its context and scheduler still get the
      // GPU choices.
      final offloaded = (
        offloadKqv: true,
        opOffload: true,
        flashAttnType: llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_AUTO.value,
      );
      final cpuOnly = (
        offloadKqv: false,
        opOffload: false,
        flashAttnType:
            llama_flash_attn_type.LLAMA_FLASH_ATTN_TYPE_DISABLED.value,
      );
      for (final (name, :android, :onGpu, :gpuDevice, :context, :opOffload) in [
        (
          'CPU',
          android: false,
          onGpu: false,
          gpuDevice: true,
          context: cpuOnly,
          opOffload: false,
        ),
        (
          'GPU',
          android: false,
          onGpu: true,
          gpuDevice: true,
          context: offloaded,
          opOffload: true,
        ),
        (
          'GPU backend without a device',
          android: false,
          onGpu: true,
          gpuDevice: false,
          context: offloaded,
          opOffload: false,
        ),
        (
          'conservative Android Vulkan',
          android: true,
          onGpu: true,
          gpuDevice: true,
          context: cpuOnly,
          opOffload: false,
        ),
      ]) {
        test('passes the $name offload choices to the head context and '
            'scheduler', () {
          final cpu = GgmlGraphApi.current.devByType(
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
          );
          final schedulerOpOffload = <bool>[];
          final recorder = RecordingExitTeardown(
            ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
          );
          service = LlamaCppService(
            isAndroid: android,
            objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
            decisionHeadGraphApi: _withGgmlOverrides(GgmlGraphApi.current, {
              #schedNew:
                  (
                    Pointer<ggml_backend_t> backends,
                    Pointer<ggml_backend_buffer_type_t> types,
                    int count,
                    int graphSize,
                    bool parallel,
                    bool opOffload,
                  ) {
                    schedulerOpOffload.add(opOffload);
                    return GgmlGraphApi.current.schedNew(
                      backends,
                      types,
                      count,
                      graphSize,
                      parallel,
                      opOffload,
                    );
                  },
            }),
            registeredDevices: () => [
              if (gpuDevice)
                GgmlDeviceEntry(
                  name: 'Vulkan0',
                  registry: 'Vulkan',
                  type:
                      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
                  device: cpu,
                ),
            ],
          );
          final encoderPath = path.join(tempDir.path, 'encoder.gguf');
          final headPath = path.join(tempDir.path, 'head.safetensors');
          final configPath = path.join(tempDir.path, 'config.json');
          writeSyntheticModernBertGguf(encoderPath, decisionTokens: true);
          SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(headPath);
          File(
            configPath,
          ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
          final model = service.loadModel(
            encoderPath,
            const ModelParams(gpuLayers: 0, contextSize: 64),
          );
          if (onGpu) {
            _readPrivateForTesting<Map<int, String>>(
              service,
              '_modelBackendNames',
            )[model] = 'Vulkan';
            _readPrivateForTesting<Map<int, int>>(
              service,
              '_modelResolvedGpuLayers',
            )[model] = 99;
            _readPrivateForTesting<Map<int, ModelParams>>(
              service,
              '_modelLoadParams',
            )[model] = const ModelParams(
              gpuLayers: 99,
              contextSize: 64,
              preferredBackend: GpuBackend.vulkan,
            );
          }

          service.loadDecisionHead(model, headPath, configPath);

          expect(recorder.contextOffload, [context]);
          expect(schedulerOpOffload, [opOffload]);
        });
      }

      DecisionHeadRuntime tinyRuntime() {
        final headPath = path.join(
          tempDir.path,
          'head_${tempDir.listSync().length}.safetensors',
        );
        SyntheticDecisionHead(d: 4, layers: 1, seed: 0).write(headPath);
        final file = SafetensorsFile.open(headPath);
        try {
          return DecisionHeadRuntime.create(
            DecisionHeadWeights.read(file, hiddenSize: 4, layers: 1),
            cpuThreads: 1,
            opOffload: false,
          );
        } finally {
          file.close();
        }
      }

      BackendDecisionOutput runDirect(DecisionHeadRuntime runtime) =>
          runtime.run(
            Float32List(8),
            2,
            DecisionQuestionType.choice,
            Int32List.fromList([1]),
          );

      test('freeModel and dispose free the heads they own', () {
        final first = tinyRuntime();
        final second = tinyRuntime();
        final firstHandle = _registerDecisionHead(service, 7, first);
        final secondHandle = _registerDecisionHead(service, 8, second);
        expect(runDirect(first).logits, hasLength(1));

        service.freeModel(7);
        expect(
          () => service.runDecision(firstHandle, const []),
          throwsA(isA<LlamaStateException>()),
        );
        expect(() => runDirect(first), throwsA(isA<LlamaStateException>()));
        expect(service.runDecision(secondHandle, const []), isEmpty);
        expect(runDirect(second).logits, hasLength(1));

        service.dispose();
        expect(
          () => service.runDecision(secondHandle, const []),
          throwsA(isA<LlamaStateException>()),
        );
        expect(() => runDirect(second), throwsA(isA<LlamaStateException>()));
      });

      test('freeDecisionHead frees only that head', () {
        final first = tinyRuntime();
        final second = tinyRuntime();
        final firstHandle = _registerDecisionHead(service, 7, first);
        _registerDecisionHead(service, 7, second);

        service.freeDecisionHead(firstHandle);
        service.freeDecisionHead(firstHandle);
        expect(() => runDirect(first), throwsA(isA<LlamaStateException>()));
        expect(
          () => service.runDecision(firstHandle, const []),
          throwsA(isA<LlamaStateException>()),
        );
        expect(runDirect(second).logits, hasLength(1));
      });

      test('runDecision encodes and answers sequences in order', () {
        final runtime = tinyRuntime();
        final encoder = _EncoderSpy(fail: false);
        final handle = _registerDecisionHead(
          service,
          7,
          runtime,
          encoder: encoder,
        );
        final sequences = [
          for (final (tokens, markers, type) in [
            ([1, 2, 3], [1], DecisionQuestionType.choice),
            ([4, 5], [0, 1], DecisionQuestionType.noul),
            ([6, 7, 8, 9], [3, 1, 2], DecisionQuestionType.score),
          ])
            BackendDecisionSequence(
              tokens: Int32List.fromList(tokens),
              markers: Int32List.fromList(markers),
              questionType: type,
            ),
        ];

        final outputs = service.runDecision(handle, sequences);

        expect(encoder.batches, [
          [1, 2, 3],
          [4, 5],
          [6, 7, 8, 9],
        ]);
        expect(encoder.batchErrors, isEmpty);
        expect(outputs, hasLength(3));
        for (final (i, sequence) in sequences.indexed) {
          final expected = runtime.run(
            _EncoderSpy.hiddenFor(sequence.tokens),
            sequence.tokens.length,
            sequence.questionType,
            sequence.markers,
          );
          expect(outputs[i].logits, expected.logits, reason: 'sequence $i');
          expect(outputs[i].actLogits, expected.actLogits);
        }
      });

      test('runDecision validates every sequence before encoding', () {
        final encoder = _EncoderSpy();
        final handle = _registerDecisionHead(
          service,
          7,
          tinyRuntime(),
          encoder: encoder,
        );
        final valid = BackendDecisionSequence(
          tokens: Int32List.fromList([1, 2]),
          markers: Int32List.fromList([1]),
          questionType: DecisionQuestionType.choice,
        );
        final tooLong = BackendDecisionSequence(
          tokens: Int32List.fromList([1, 2, 3, 4, 5]),
          markers: Int32List.fromList([1]),
          questionType: DecisionQuestionType.choice,
        );
        expect(
          () => service.runDecision(handle, [valid, tooLong]),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              contains('sequence 1 has 5 tokens'),
            ),
          ),
        );
        expect(encoder.batches, isEmpty);
      });
    });

    group('validateDecisionSequences', () {
      BackendDecisionSequence sequence({
        List<int> tokens = const [1, 4, 2, 3, 5, 2],
        List<int> markers = const [2, 3],
        DecisionQuestionType questionType = DecisionQuestionType.choice,
      }) => BackendDecisionSequence(
        tokens: Int32List.fromList(tokens),
        markers: Int32List.fromList(markers),
        questionType: questionType,
      );

      void validate(List<BackendDecisionSequence> sequences) =>
          LlamaCppService.validateDecisionSequences(
            sequences,
            tokenLimit: 6,
            vocabSize: 10,
          );

      Matcher rejects(String fragment) => throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          contains(fragment),
        ),
      );

      test('accepts sequences within the head limits', () {
        validate([
          sequence(),
          sequence(
            tokens: const [9],
            markers: const [0],
            questionType: DecisionQuestionType.noul,
          ),
        ]);
      });

      test('rejects empty and over-long sequences', () {
        expect(
          () => validate([sequence(tokens: const [], markers: const [])]),
          rejects('0 tokens'),
        );
        expect(
          () => validate([
            sequence(),
            sequence(tokens: const [1, 1, 1, 1, 1, 1, 1]),
          ]),
          rejects('sequence 1 has 7 tokens'),
        );
      });

      test('rejects tokens outside the vocabulary', () {
        expect(
          () => validate([
            sequence(tokens: const [1, 10]),
          ]),
          rejects('token 10'),
        );
        expect(
          () => validate([
            sequence(tokens: const [-1, 2]),
          ]),
          rejects('token -1'),
        );
      });

      test('rejects missing and out-of-range markers', () {
        expect(
          () => validate([sequence(markers: const [])]),
          rejects('no option markers'),
        );
        expect(
          () => validate([
            sequence(markers: const [2, 6]),
          ]),
          rejects('marker 6'),
        );
        expect(
          () => validate([
            sequence(markers: const [-1]),
          ]),
          rejects('marker -1'),
        );
      });

      test('rejects more markers than tokens, as the Web bridge does', () {
        validate([
          sequence(tokens: const [1, 2], markers: const [0, 1]),
        ]);
        expect(
          () => validate([
            sequence(),
            sequence(tokens: const [1, 4, 2], markers: const [0, 1, 2, 1]),
          ]),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              'Decision sequence 1 has 4 markers for its 3 tokens; a '
                  'sequence holds at most one marker per token.',
            ),
          ),
        );
      });
    });

    group('resolveDecisionHeadConfigText', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('decision_config_');
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      test('prefers the config file over head metadata', () {
        final config = File(path.join(tempDir.path, 'rl_agent_config.json'))
          ..writeAsStringSync('{"max_len": 256}');
        expect(
          LlamaCppService.resolveDecisionHeadConfigText(
            headPath: 'head.safetensors',
            configPath: config.path,
            metadata: const {'laya.config': '{"max_len": 512}'},
          ),
          '{"max_len": 256}',
        );
      });

      test('falls back to the laya.config metadata', () {
        expect(
          LlamaCppService.resolveDecisionHeadConfigText(
            headPath: 'head.safetensors',
            configPath: null,
            metadata: const {'laya.config': '{"max_len": 512}'},
          ),
          '{"max_len": 512}',
        );
      });

      test('reports a missing config source as a model error', () {
        expect(
          () => LlamaCppService.resolveDecisionHeadConfigText(
            headPath: 'head.safetensors',
            configPath: null,
            metadata: const {},
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              contains("Pass the head's rl_agent_config.json as its config"),
            ),
          ),
        );
        expect(
          () => LlamaCppService.resolveDecisionHeadConfigText(
            headPath: 'head.safetensors',
            configPath: path.join(tempDir.path, 'missing.json'),
            metadata: const {'laya.config': '{}'},
          ),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              contains('missing.json'),
            ),
          ),
        );
      });
    });

    group('parseDecisionHeadConfig', () {
      test('returns the parsed config', () {
        final config = LlamaCppService.parseDecisionHeadConfig(
          '{"max_len": 256, "head_layers": 1}',
          source: 'config.json',
        );
        expect(config.maxTokens, 256);
        expect(config.headLayers, 1);
      });

      test('rejects malformed configs as model errors', () {
        for (final text in [
          '{',
          '[1, 2]',
          '{"max_len": 0}',
          '{"head_layers": 0}',
        ]) {
          expect(
            () => LlamaCppService.parseDecisionHeadConfig(
              text,
              source: 'config.json',
            ),
            throwsA(
              isA<LlamaModelException>().having(
                (error) => error.message,
                'message',
                contains('config.json'),
              ),
            ),
            reason: text,
          );
        }
      });
    });

    group('decisionModelUnsupportedReason', () {
      String? reason({
        String? architecture = 'modern-bert',
        int clsToken = 1,
        int sepToken = 2,
        int maskToken = 3,
        String maskText = '[MASK]',
        int outputSize = 0,
      }) => LlamaCppService.decisionModelUnsupportedReason(
        architecture: architecture,
        vocabSize: 10,
        clsToken: clsToken,
        sepToken: sepToken,
        maskToken: maskToken,
        maskText: maskText,
        hiddenSize: 8,
        outputSize: outputSize,
      );

      test('accepts a ModernBERT encoder with its special tokens', () {
        expect(reason(), isNull);
        expect(reason(outputSize: 8), isNull);
      });

      test('names another or a missing architecture', () {
        expect(reason(architecture: 'llama'), contains('architecture "llama"'));
        expect(reason(architecture: null), contains('no architecture'));
      });

      test('rejects missing CLS, SEP and MASK tokens', () {
        expect(reason(clsToken: -1), contains('no CLS token'));
        expect(reason(sepToken: 10), contains('no SEP token'));
        expect(reason(maskToken: -1), contains('no MASK token'));
      });

      test('rejects a MASK token without text', () {
        expect(reason(maskText: ''), contains('MASK token has no text'));
      });

      test('rejects an encoder whose output is not its hidden state', () {
        expect(reason(outputSize: 4), contains('outputs 4 values per token'));
      });
    });

    group('checkDecisionHeadFitsEncoder', () {
      void check({required int trainedContext}) =>
          LlamaCppService.checkDecisionHeadFitsEncoder(
            trainedContext: trainedContext,
            maxTokens: 512,
          );

      test('accepts a max_len within the encoder training context', () {
        check(trainedContext: 512);
        check(trainedContext: 8192);
      });

      test('rejects a max_len past the encoder training context', () {
        expect(
          () => check(trainedContext: 511),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'message',
              contains('trained for 511 tokens'),
            ),
          ),
        );
      });
    });

    group('checkDecisionEncoderContext', () {
      final none = llama_pooling_type.LLAMA_POOLING_TYPE_NONE.value;

      test('accepts per-token output with room for max_len', () {
        LlamaCppService.checkDecisionEncoderContext(
          poolingType: none,
          tokenLimit: 512,
          maxTokens: 512,
        );
      });

      test('rejects pooled output', () {
        expect(
          () => LlamaCppService.checkDecisionEncoderContext(
            poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_CLS.value,
            tokenLimit: 512,
            maxTokens: 512,
          ),
          throwsA(
            isA<LlamaContextException>().having(
              (error) => error.message,
              'message',
              contains('pooling is not NONE'),
            ),
          ),
        );
      });

      test('rejects a micro-batch below max_len', () {
        expect(
          () => LlamaCppService.checkDecisionEncoderContext(
            poolingType: none,
            tokenLimit: 511,
            maxTokens: 512,
          ),
          throwsA(
            isA<LlamaContextException>().having(
              (error) => error.message,
              'message',
              contains('accepts 511 tokens per pass'),
            ),
          ),
        );
      });
    });

    test('decisionHeadRunsOnCpu follows the model placement', () {
      expect(
        LlamaCppService.decisionHeadRunsOnCpu(
          params: const ModelParams(),
          modelBackendName: 'CPU',
          resolvedGpuLayers: 99,
        ),
        isTrue,
      );
      expect(
        LlamaCppService.decisionHeadRunsOnCpu(
          params: const ModelParams(),
          modelBackendName: 'Metal',
          resolvedGpuLayers: 0,
        ),
        isTrue,
      );
      expect(
        LlamaCppService.decisionHeadRunsOnCpu(
          params: const ModelParams(),
          modelBackendName: 'Metal',
          resolvedGpuLayers: 99,
        ),
        isFalse,
      );
      expect(
        LlamaCppService.decisionHeadRunsOnCpu(
          params: const ModelParams(),
          modelBackendName: null,
          resolvedGpuLayers: 99,
        ),
        isFalse,
      );
    });

    for (final splitMode in ModelSplitMode.values) {
      for (final mainGpu in [-2, -1, 0, 1, 99]) {
        test('decision head placement: $splitMode / $mainGpu', () {
          final cpu = splitMode == ModelSplitMode.none && mainGpu < 0;
          expect(
            LlamaCppService.decisionHeadRunsOnCpu(
              modelBackendName: 'Metal',
              resolvedGpuLayers: 99,
              params: ModelParams(splitMode: splitMode, mainGpu: mainGpu),
            ),
            cpu,
          );
          expect(
            LlamaCppService.decisionHeadDeviceIndex(
              modelBackendName: 'Metal',
              deviceBackends: [
                GpuBackend.vulkan,
                GpuBackend.metal,
                GpuBackend.metal,
              ],
              mainGpu: mainGpu,
              splitMode: splitMode,
            ),
            cpu ? null : (mainGpu == 1 ? 2 : 1),
          );
        });
      }
    }

    test('decisionHeadDeviceIndex picks a device of the model backend', () {
      int? index(
        String? modelBackendName,
        List<GpuBackend> deviceBackends, {
        int mainGpu = 0,
      }) => LlamaCppService.decisionHeadDeviceIndex(
        splitMode: ModelSplitMode.layer,
        modelBackendName: modelBackendName,
        deviceBackends: deviceBackends,
        mainGpu: mainGpu,
      );
      const devices = [
        GpuBackend.vulkan,
        GpuBackend.cuda,
        GpuBackend.vulkan,
        GpuBackend.cuda,
      ];

      expect(index('Metal', [GpuBackend.metal]), 0);
      expect(index('HIP', [GpuBackend.vulkan, GpuBackend.hip]), 1);
      expect(index('CUDA', devices), 1);
      expect(index('CUDA', devices, mainGpu: 1), 3);
      expect(index('Vulkan', devices, mainGpu: 1), 2);
      expect(index('CUDA', devices, mainGpu: 2), 1);
      expect(index('CUDA', devices, mainGpu: -1), 1);
      expect(index('BLAS', devices), isNull);
      expect(index('CPU', [GpuBackend.cpu]), isNull);
      expect(index(null, [GpuBackend.auto]), isNull);
      expect(index('Unknown', [GpuBackend.auto]), isNull);
    });
  });

  group('an explicit GPU backend without a bundled module', () {
    late Directory tempDir;
    late List<LlamaLogRecord> records;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('unbundled_backend_');
      records = <LlamaLogRecord>[];
      LlamaLogger.instance
        ..setLevel(LlamaLogLevel.warn)
        ..setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance
        ..setLevel(LlamaLogLevel.none)
        ..setHandler(null);
      tempDir.deleteSync(recursive: true);
    });

    test('loads on CPU and warns how to bundle the backend', () {
      final service = LlamaCppService();
      addTearDown(service.dispose);
      if (service.getBackendInfo().join().toLowerCase().contains('cuda')) {
        markTestSkipped('This process already registered a CUDA backend.');
        return;
      }
      final moduleDir = Directory(path.join(tempDir.path, 'modules'))
        ..createSync();
      _writePrivateForTesting(
        service,
        '_backendModuleDirectory',
        moduleDir.path,
      );
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);

      final handle = service.loadModel(
        modelPath,
        const ModelParams(
          contextSize: 512,
          preferredBackend: GpuBackend.cuda,
          gpuLayers: 99,
        ),
      );

      expect(
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        )[handle],
        'CPU',
      );
      expect(
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        )[handle],
        0,
      );
      expect(records.map((record) => record.level), [LlamaLogLevel.warn]);
      expect(
        records.single.message,
        'preferredBackend cuda was requested, but its backend module is not '
        'bundled for this platform, so the model loaded on CPU with 0 GPU '
        'layers. To bundle it, add cuda to the llamadart_native_backends '
        'hook user-define in your app pubspec.yaml.',
      );
    });

    group('whose module is bundled but offers no device', () {
      late LlamaCppService service;
      late String modelPath;

      setUp(() {
        service = LlamaCppService(
          deviceTypes: (_) => [
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
          ],
        );
        addTearDown(service.dispose);
        final moduleDir = Directory(path.join(tempDir.path, 'modules'))
          ..createSync();
        final moduleName = Platform.isWindows
            ? 'ggml-cuda.dll'
            : Platform.isMacOS
            ? 'libggml-cuda.dylib'
            : 'libggml-cuda.so';
        File(path.join(moduleDir.path, moduleName)).writeAsStringSync('junk');
        _writePrivateForTesting(
          service,
          '_backendModuleDirectory',
          moduleDir.path,
        );
        modelPath = path.join(tempDir.path, 'llama.gguf');
        writeSyntheticLlamaGguf(modelPath);
      });

      test('reports the CPU, 0 GPU layers and warns why', () {
        final handle = service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 99,
          ),
        );

        expect(
          _readPrivateForTesting<Map<int, String>>(
            service,
            '_modelBackendNames',
          )[handle],
          'CPU',
        );
        expect(service.getResolvedGpuLayers(), 0);
        expect(records.map((record) => record.level), [LlamaLogLevel.warn]);
        expect(
          records.single.message,
          'preferredBackend cuda was requested, but its backend module '
          'failed to load or found no usable device, so the model loaded on '
          'CPU with 0 GPU layers.',
        );
      });

      test('does not warn when no layer was requested on the GPU', () {
        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 0,
          ),
        );
        expect(records, isEmpty);
      });

      test('leaves the load alone while another GPU device is registered', () {
        final other = LlamaCppService(
          deviceTypes: (_) => [
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
          ],
        );
        addTearDown(other.dispose);
        _writePrivateForTesting(
          other,
          '_backendModuleDirectory',
          path.join(tempDir.path, 'modules'),
        );
        other.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 99,
          ),
        );
        expect(other.getResolvedGpuLayers(), 99);
        expect(records, isEmpty);
      });

      test('reports 0 GPU layers under auto without a warning or a change to '
          'the load', () {
        final handle = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, gpuLayers: 99),
        );
        expect(service.getResolvedGpuLayers(), 0);
        expect(
          _readPrivateForTesting<Map<int, int>>(
            service,
            '_modelResolvedGpuLayers',
          )[handle],
          99,
        );
        expect(records, isEmpty);

        service.freeModel(handle);
        expect(
          _readPrivateForTesting<Set<int>>(service, '_modelsOnNoGpu'),
          isEmpty,
        );
      });

      test('keeps the layers of an explicit backend when only a GPU of '
          'another backend is registered', () {
        final other = LlamaCppService(
          deviceTypes: (backend) => [
            backend == GpuBackend.auto
                ? ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value
                : ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
          ],
        );
        addTearDown(other.dispose);
        _writePrivateForTesting(
          other,
          '_backendModuleDirectory',
          path.join(tempDir.path, 'modules'),
        );
        other.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 99,
          ),
        );
        expect(other.getResolvedGpuLayers(), 99);
        expect(records, isEmpty);
      });

      test('reads the registry symbol flag after the device probe sets it', () {
        late final LlamaCppService probing;
        probing = LlamaCppService(
          deviceTypes: (_) {
            _writePrivateForTesting(
              probing,
              '_backendRegistrySymbolUnavailable',
              true,
            );
            return [ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value];
          },
        );
        addTearDown(probing.dispose);
        probing.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, gpuLayers: 99),
        );
        expect(probing.getResolvedGpuLayers(), 99);
      });

      test('creates the context with the layers the load resolved', () {
        const params = ModelParams(
          contextSize: 64,
          preferredBackend: GpuBackend.cuda,
          gpuLayers: 99,
        );
        final handle = service.loadModel(modelPath, params);
        final context = service.createContext(handle, params);

        final contextParams =
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;
        expect(contextParams.offload_kqv, isFalse);
        expect(contextParams.op_offload, isFalse);
      });

      test('keeps the requested layers under auto with a GPU device', () {
        final other = LlamaCppService(
          deviceTypes: (_) => [
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value,
          ],
        );
        addTearDown(other.dispose);
        other.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, gpuLayers: 99),
        );
        expect(other.getResolvedGpuLayers(), 99);
      });

      test('reports 0 GPU layers without blaming a module on a runtime with '
          'none', () {
        _writePrivateForTesting(service, '_backendModuleDirectory', null);
        final handle = service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 99,
          ),
        );
        expect(service.getResolvedGpuLayers(), 0);
        expect(
          _readPrivateForTesting<Map<int, int>>(
            service,
            '_modelResolvedGpuLayers',
          )[handle],
          99,
        );
        expect(records, isEmpty);
      });

      group('on a runtime without the device registry functions', () {
        setUp(() {
          _writePrivateForTesting(
            service,
            '_backendRegistrySymbolUnavailable',
            true,
          );
        });

        test('claims no module failure for an explicit backend', () {
          service.loadModel(
            modelPath,
            const ModelParams(
              contextSize: 512,
              preferredBackend: GpuBackend.cuda,
              gpuLayers: 99,
            ),
          );
          expect(service.getResolvedGpuLayers(), 99);
          expect(records, isEmpty);
        });

        test('keeps the requested layers under auto', () {
          service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, gpuLayers: 99),
          );
          expect(service.getResolvedGpuLayers(), 99);
        });
      });

      test('no longer lists the backend as available once it failed to '
          'load', () {
        expect(service.getAvailableBackendInfo(), contains('CUDA'));
        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.cuda,
            gpuLayers: 99,
          ),
        );
        expect(service.getAvailableBackendInfo(), isNot(contains('CUDA')));
      });
    });

    test('throws for ComputeDevice.gpu instead of loading on CPU', () {
      final service = LlamaCppService();
      addTearDown(service.dispose);
      if (service.getBackendInfo().join().toLowerCase().contains('cuda')) {
        markTestSkipped('This process already registered a CUDA backend.');
        return;
      }
      final moduleDir = Directory(path.join(tempDir.path, 'modules'))
        ..createSync();
      _writePrivateForTesting(
        service,
        '_backendModuleDirectory',
        moduleDir.path,
      );
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);

      expect(
        () => service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            device: ComputeDevice.gpu,
            preferredBackend: GpuBackend.cuda,
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ComputeDevice.gpu'),
              contains('cuda'),
              contains(Platform.operatingSystem),
            ),
          ),
        ),
      );
      expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
      expect(records, isEmpty);
    });

    test('does not warn when CPU is requested', () {
      final service = LlamaCppService();
      addTearDown(service.dispose);
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);

      service.loadModel(
        modelPath,
        const ModelParams(
          contextSize: 512,
          preferredBackend: GpuBackend.cpu,
          gpuLayers: 0,
        ),
      );

      expect(records, isEmpty);
    });
  });

  group('negative gpuLayers', () {
    late Directory tempDir;
    late String modelPath;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('negative_gpu_layers_');
      modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    // What a load with [gpuLayers] passes to llama.cpp, resolves and reports,
    // and whether its context offloads the KV cache and ops.
    ({
      int nativeGpuLayers,
      int? resolvedGpuLayers,
      String backendName,
      bool offloadKqv,
      bool opOffload,
    })
    load(int gpuLayers, {ComputeDevice device = ComputeDevice.auto}) {
      final recorder = RecordingExitTeardown(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      );
      final service = LlamaCppService(
        isMacosX64: false,
        objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        deviceTypes: _hostWithGpu,
      );
      addTearDown(service.dispose);
      final params = ModelParams(
        contextSize: 64,
        gpuLayers: gpuLayers,
        device: device,
      );
      final handle = service.loadModel(modelPath, params);
      final context = service.createContext(handle, params);
      final contextParams =
          _readPrivateForTesting<Map<int, llama_context_params>>(
            service,
            '_contextParams',
          )[context]!;
      return (
        nativeGpuLayers: recorder.loadGpuLayers.single,
        resolvedGpuLayers: service.getResolvedGpuLayers(),
        backendName: service.getActiveBackendName(),
        offloadKqv: contextParams.offload_kqv,
        opOffload: contextParams.op_offload,
      );
    }

    for (final gpuLayers in [-1, -2, -2147483648]) {
      test('$gpuLayers loads, offloads and reports like maxGpuLayers', () {
        final all = load(ModelParams.maxGpuLayers);
        final negative = load(gpuLayers);

        expect(all.nativeGpuLayers, ModelParams.maxGpuLayers);
        expect(all.resolvedGpuLayers, ModelParams.maxGpuLayers);
        expect(all.offloadKqv, isTrue);
        expect(all.opOffload, isTrue);
        expect(negative, all);
      });
    }

    test('0 keeps the model, KV cache and backend name on the CPU', () {
      final cpu = load(0);

      expect(cpu.nativeGpuLayers, 0);
      expect(cpu.resolvedGpuLayers, 0);
      expect(cpu.backendName, 'CPU');
      expect(cpu.offloadKqv, isFalse);
      expect(cpu.opOffload, isFalse);
    });

    test('a positive count is passed through with context offload', () {
      final partial = load(12);

      expect(partial.nativeGpuLayers, 12);
      expect(partial.resolvedGpuLayers, 12);
      expect(partial.backendName, load(ModelParams.maxGpuLayers).backendName);
      expect(partial.offloadKqv, isTrue);
      expect(partial.opOffload, isTrue);
    });

    test('ComputeDevice.cpu still loads no GPU layers for -1', () {
      final cpu = load(-1, device: ComputeDevice.cpu);

      expect(cpu.nativeGpuLayers, 0);
      expect(cpu.resolvedGpuLayers, 0);
      expect(cpu.backendName, 'CPU');
      expect(cpu.offloadKqv, isFalse);
    });

    test('ComputeDevice.gpu with -1 loads or throws like maxGpuLayers', () {
      Object attempt(int gpuLayers) {
        try {
          return load(gpuLayers, device: ComputeDevice.gpu);
        } on LlamaUnsupportedException catch (error) {
          return error.message;
        }
      }

      expect(attempt(-1), attempt(ModelParams.maxGpuLayers));
    });
  });

  group('ComputeDevice', () {
    test('auto keeps every llama.cpp field', () {
      const params = ModelParams(
        preferredBackend: GpuBackend.vulkan,
        gpuLayers: 12,
      );

      expect(
        LlamaCppService.resolveComputeDeviceParams(params, isAndroid: true),
        same(params),
      );
    });

    test('cpu forces the CPU module and 0 GPU layers', () {
      final resolved = LlamaCppService.resolveComputeDeviceParams(
        const ModelParams(device: ComputeDevice.cpu),
      );

      expect(resolved.preferredBackend, GpuBackend.cpu);
      expect(resolved.gpuLayers, 0);
      expect(
        LlamaCppService.shouldDisableContextGpuOffload(
          resolved,
          resolvedGpuLayers: LlamaCppService.resolveGpuLayersForLoad(resolved),
        ),
        isTrue,
      );
      expect(
        LlamaCppService.resolveComputeDeviceParams(
          const ModelParams(
            device: ComputeDevice.cpu,
            preferredBackend: GpuBackend.blas,
          ),
        ).preferredBackend,
        GpuBackend.blas,
      );
    });

    test('gpu resolves auto to Vulkan on Android only', () {
      const params = ModelParams(device: ComputeDevice.gpu);

      final android = LlamaCppService.resolveComputeDeviceParams(
        params,
        isAndroid: true,
      );
      expect(android.preferredBackend, GpuBackend.vulkan);
      expect(android.gpuLayers, ModelParams.maxGpuLayers);
      expect(
        LlamaCppService.resolveGpuLayersForLoad(android, isAndroid: true),
        ModelParams.maxGpuLayers,
      );
      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          android,
          isAndroid: true,
        ),
        isTrue,
      );
      expect(LlamaCppService.resolveComputeDeviceParams(params), same(params));
      expect(
        LlamaCppService.resolveComputeDeviceParams(
          const ModelParams(
            device: ComputeDevice.gpu,
            preferredBackend: GpuBackend.opencl,
          ),
          isAndroid: true,
        ).preferredBackend,
        GpuBackend.opencl,
      );
    });

    test('gpu resolves auto to Metal on an iOS simulator only', () {
      const params = ModelParams(device: ComputeDevice.gpu);

      final simulator = LlamaCppService.resolveComputeDeviceParams(
        params,
        isIosSimulator: true,
      );
      expect(simulator.preferredBackend, GpuBackend.metal);
      expect(
        LlamaCppService.resolveGpuLayersForLoad(
          simulator,
          isIosSimulator: true,
        ),
        ModelParams.maxGpuLayers,
      );
      expect(
        LlamaCppService.resolveComputeDeviceParams(
          params,
          isIosSimulator: false,
        ),
        same(params),
      );
      const auto = ModelParams();
      expect(
        LlamaCppService.resolveComputeDeviceParams(auto, isIosSimulator: true),
        same(auto),
      );
    });

    test('gpu resolves auto to Metal on macOS x64 only', () {
      const params = ModelParams(device: ComputeDevice.gpu);

      final intel = LlamaCppService.resolveComputeDeviceParams(
        params,
        isMacosX64: true,
      );
      expect(intel.preferredBackend, GpuBackend.metal);
      expect(
        LlamaCppService.resolveGpuLayersForLoad(intel, isMacosX64: true),
        ModelParams.maxGpuLayers,
      );
      expect(
        LlamaCppService.resolveComputeDeviceParams(params, isMacosX64: false),
        same(params),
      );
      const auto = ModelParams();
      expect(
        LlamaCppService.resolveComputeDeviceParams(auto, isMacosX64: true),
        same(auto),
      );
    });

    test('npu throws LlamaUnsupportedException naming the platform', () {
      expect(
        () => LlamaCppService.resolveComputeDeviceParams(
          const ModelParams(device: ComputeDevice.npu),
          platform: 'linux',
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('ComputeDevice.npu'),
              contains('llama.cpp'),
              contains('linux'),
            ),
          ),
        ),
      );
    });

    group('loads', () {
      late Directory tempDir;
      late String modelPath;

      setUpAll(() => LlamaCppService().initializeBackend());

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('compute_device_');
        modelPath = path.join(tempDir.path, 'llama.gguf');
        writeSyntheticLlamaGguf(modelPath);
      });

      tearDown(() => tempDir.deleteSync(recursive: true));

      test('negative single-device placement changes only reporting', () {
        final service = _MetalReportingService();
        addTearDown(service.dispose);
        final handle = service.loadModel(
          modelPath,
          const ModelParams(splitMode: ModelSplitMode.none, mainGpu: -1),
        );

        expect(
          _readPrivateForTesting<Map>(service, '_modelBackendNames')[handle],
          'Metal',
        );
        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getResolvedGpuLayers(), 0);
        expect(
          _readPrivateForTesting<Map>(
            service,
            '_modelResolvedGpuLayers',
          )[handle],
          ModelParams.maxGpuLayers,
        );
      });

      test('freeing a model restores the remaining model placement report', () {
        final service = LlamaCppService(
          isMacosX64: false,
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);
        service.loadModel(
          modelPath,
          const ModelParams(splitMode: ModelSplitMode.none, mainGpu: -1),
        );
        final other = service.loadModel(modelPath, const ModelParams());
        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);

        service.freeModel(other);
        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getResolvedGpuLayers(), 0);
      });

      test('cpu on the CPU with 0 GPU layers, whatever gpuLayers says', () {
        final service = LlamaCppService();
        addTearDown(service.dispose);

        final handle = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, device: ComputeDevice.cpu),
        );
        service.createContext(
          handle,
          const ModelParams(contextSize: 512, device: ComputeDevice.cpu),
        );

        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getResolvedGpuLayers(), 0);
      });

      test('gpu on a GPU, or throws and loads nothing', () {
        final service = LlamaCppService();
        addTearDown(service.dispose);
        const params = ModelParams(contextSize: 512, device: ComputeDevice.gpu);

        try {
          service.loadModel(modelPath, params);
        } on LlamaUnsupportedException catch (error) {
          expect(error.message, contains('ComputeDevice.gpu'));
          expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
          return;
        }
        expect(service.getActiveBackendName(), isNot(anyOf('CPU', 'BLAS')));
        expect(service.getResolvedGpuLayers(), greaterThan(0));
      });

      test('gpu throws when no device is a GPU or integrated GPU', () {
        final requested = <GpuBackend>[];
        final pathAllocator = RecordingAllocator();
        final service = LlamaCppService(
          isMacosX64: false,
          deviceTypes: (backend) {
            requested.add(backend);
            return [
              ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
              ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL.value,
            ];
          },
          modelLoadAllocator: pathAllocator,
        );
        addTearDown(service.dispose);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('ComputeDevice.gpu needs a GPU'),
                contains('no GPU device is available'),
              ),
            ),
          ),
        );
        expect(requested, [GpuBackend.auto]);
        expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
        pathAllocator.expectAllFreed();
      });

      for (final type in [
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU,
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU,
      ]) {
        test('gpu loads when a device is a ${type.name}', () {
          final pathAllocator = RecordingAllocator();
          final service = LlamaCppService(
            deviceTypes: (_) => [
              ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
              type.value,
            ],
            modelLoadAllocator: pathAllocator,
          );
          addTearDown(service.dispose);

          expect(
            service.loadModel(
              modelPath,
              const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
            ),
            isPositive,
          );
          expect(pathAllocator.allocations, 1);
          pathAllocator.expectAllFreed();
        });
      }

      test('an explicit backend with no device reports where llama.cpp '
          'offloads instead', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        // As on the consolidated Apple runtime, which registers Metal and no
        // Vulkan device and has no module directory to force a CPU fallback.
        final service = _MetalReportingService(
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
          registeredDevices: () => const <GgmlDeviceEntry>[],
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);

        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.vulkan,
            gpuLayers: 42,
          ),
        );
        if (recorder.loadDevices.single != null) {
          markTestSkipped('This process registered a Vulkan device.');
          return;
        }

        expect(recorder.loadGpuLayers.single, 42);
        expect(service.getActiveBackendName(), 'Metal');
        expect(service.getResolvedGpuLayers(), 42);
      });

      group('gpu with an explicit backend that has no GPU device', () {
        GgmlDeviceEntry device(String registry, ggml_backend_dev_type type) =>
            GgmlDeviceEntry(
              name: '${registry}0',
              registry: registry,
              type: type.value,
            );
        String loadError(List<GgmlDeviceEntry> registered) {
          final service = LlamaCppService(
            deviceTypes: (_) => const <int>[],
            registeredDevices: () => registered,
          );
          addTearDown(service.dispose);
          try {
            service.loadModel(
              modelPath,
              const ModelParams(
                contextSize: 512,
                device: ComputeDevice.gpu,
                preferredBackend: GpuBackend.vulkan,
              ),
            );
          } on LlamaUnsupportedException catch (error) {
            expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
            return error.message;
          }
          fail('ComputeDevice.gpu loaded without a Vulkan GPU device.');
        }

        // As on the consolidated Apple runtime, where ComputeDevice.auto with
        // GpuBackend.vulkan runs on Metal rather than on the CPU.
        test('names the other registered GPU backend', () {
          expect(
            loadError([
              device('CPU', ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU),
              device('MTL', ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU),
            ]),
            allOf(
              contains(
                'ComputeDevice.gpu needs the vulkan backend for llama.cpp on '
                '${Platform.operatingSystem}, but no vulkan GPU device is '
                'available',
              ),
              endsWith(
                'Use GpuBackend.metal to run on the metal GPU, or '
                'ComputeDevice.cpu to run on the CPU.',
              ),
              isNot(contains('ComputeDevice.auto')),
            ),
          );
        });

        test('points to the CPU when no other GPU is registered', () {
          expect(
            loadError([
              device('CPU', ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU),
              device(
                'BLAS',
                ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_ACCEL,
              ),
            ]),
            allOf(
              contains('but no GPU device is available'),
              endsWith('Use ComputeDevice.auto to run on the CPU instead.'),
            ),
          );
        });
      });

      test('a draft load frees its model path, also when it throws before '
          'the native load', () {
        var registryFails = false;
        final pathAllocator = RecordingAllocator();
        final service = LlamaCppService(
          isMacosX64: false,
          registeredDevices: () {
            if (registryFails) throw StateError('registry read failed');
            return const <GgmlDeviceEntry>[];
          },
          modelLoadAllocator: pathAllocator,
        );
        addTearDown(service.dispose);
        final target = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, gpuLayers: 42),
        );
        // A draft of a target on a GPU reads the registry on every host.
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        )[target] = 'Metal';
        void loadDraft(String draftPath) => _invokePrivateForTesting<Object?>(
          service,
          '_loadSpeculativeDraftModel',
          [target, draftPath, 'Draft model'],
          {#loadMtp: false},
        );

        loadDraft(modelPath);
        expect(pathAllocator.allocations, 2, reason: 'the target and draft');
        pathAllocator.expectAllFreed();

        registryFails = true;
        final otherDraft = path.join(tempDir.path, 'draft.gguf');
        writeSyntheticLlamaGguf(otherDraft);
        expect(() => loadDraft(otherDraft), throwsStateError);
        expect(pathAllocator.allocations, 2);
        pathAllocator.expectAllFreed();
      });

      test('createContext applies the device of its own params', () {
        final service = LlamaCppService();
        addTearDown(service.dispose);
        final handle = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512),
        );

        final context = service.createContext(
          handle,
          const ModelParams(contextSize: 512, device: ComputeDevice.cpu),
        );

        final contextParams =
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;
        expect(contextParams.offload_kqv, isFalse);
        expect(contextParams.op_offload, isFalse);
        expect(
          () => service.createContext(
            handle,
            const ModelParams(contextSize: 512, device: ComputeDevice.npu),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      });
    });
  });

  group('iOS simulator', () {
    const issue = 'https://github.com/leehack/llamadart/issues/950';

    test('warns only for a simulator load that offloads GPU layers', () {
      expect(
        LlamaCppService.iosSimulatorMetalWarning(
          isIosSimulator: true,
          resolvedGpuLayers: 1,
        ),
        allOf(contains('Metal'), contains('iOS simulator'), contains(issue)),
      );
      expect(
        LlamaCppService.iosSimulatorMetalWarning(
          isIosSimulator: true,
          resolvedGpuLayers: 0,
        ),
        isNull,
      );
      expect(
        LlamaCppService.iosSimulatorMetalWarning(
          isIosSimulator: false,
          resolvedGpuLayers: ModelParams.maxGpuLayers,
        ),
        isNull,
      );
    });

    group('loads', () {
      late Directory tempDir;
      late String modelPath;
      late List<LlamaLogRecord> records;

      Iterable<String> simulatorWarnings() => records
          .where((record) => record.level == LlamaLogLevel.warn)
          .map((record) => record.message)
          .where((message) => message.contains(issue));

      setUpAll(() => LlamaCppService().initializeBackend());

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('ios_simulator_');
        modelPath = path.join(tempDir.path, 'llama.gguf');
        writeSyntheticLlamaGguf(modelPath);
        records = <LlamaLogRecord>[];
        LlamaLogger.instance
          ..setLevel(LlamaLogLevel.warn)
          ..setHandler(records.add);
      });

      tearDown(() {
        LlamaLogger.instance
          ..setLevel(LlamaLogLevel.none)
          ..setHandler(null);
        tempDir.deleteSync(recursive: true);
      });

      test('auto on the CPU with 0 GPU layers and no context offload', () {
        final service = LlamaCppService(isIosSimulator: true);
        addTearDown(service.dispose);
        const params = ModelParams(contextSize: 512);

        final handle = service.loadModel(modelPath, params);
        final context = service.createContext(handle, params);

        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getResolvedGpuLayers(), 0);
        final contextParams =
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;
        expect(contextParams.offload_kqv, isFalse);
        expect(contextParams.op_offload, isFalse);
        expect(simulatorWarnings(), isEmpty);
      });

      test('auto lists only the CPU device for the load', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final service = LlamaCppService(
          isIosSimulator: true,
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        );
        addTearDown(service.dispose);

        service.loadModel(modelPath, const ModelParams(contextSize: 512));

        final cpuDevices = _invokePrivateForTesting<List<ggml_backend_dev_t>?>(
          service,
          '_resolvePreferredDevices',
          [GpuBackend.cpu],
        );
        expect(cpuDevices, hasLength(1));
        expect(recorder.loadDevices, [
          [cpuDevices!.single.address],
        ]);
      });

      test('gpu with auto loads on Metal', () {
        final checked = <GpuBackend>[];
        final service = LlamaCppService(
          isIosSimulator: true,
          // Pins a Metal device, so a host without one still loads and warns.
          deviceTypes: (backend) {
            checked.add(backend);
            return [ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value];
          },
          registeredDevices: () => const <GgmlDeviceEntry>[],
        );
        addTearDown(service.dispose);

        service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
        );

        expect(checked.first, GpuBackend.metal);
        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
        expect(simulatorWarnings(), hasLength(1));
      });

      test('gpu with auto throws naming Metal off macOS', () {
        final service = LlamaCppService(isIosSimulator: true);
        addTearDown(service.dispose);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('ComputeDevice.gpu needs the metal backend'),
            ),
          ),
        );
        expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
        expect(simulatorWarnings(), isEmpty);
      }, testOn: '!mac-os');

      test('gpu with auto names Metal when no device is a GPU', () {
        final service = LlamaCppService(
          isIosSimulator: true,
          deviceTypes: (_) => [
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
          ],
        );
        addTearDown(service.dispose);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('ComputeDevice.gpu needs the metal backend'),
                isNot(contains('needs the cpu backend')),
              ),
            ),
          ),
        );
        expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
        expect(simulatorWarnings(), isEmpty);
      });

      test('auto keeps its GPU layers off the simulator', () {
        final service = LlamaCppService(
          isIosSimulator: false,
          isMacosX64: false,
          registeredDevices: () => const <GgmlDeviceEntry>[],
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);

        service.loadModel(modelPath, const ModelParams(contextSize: 512));

        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
        expect(simulatorWarnings(), isEmpty);
      });

      test(
        'negative single-device placement suppresses the simulator warning',
        () {
          final service = LlamaCppService(isIosSimulator: true);
          addTearDown(service.dispose);
          const params = ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.metal,
            gpuLayers: 42,
            splitMode: ModelSplitMode.none,
            mainGpu: -1,
          );
          final handle = service.loadModel(modelPath, params);
          expect(
            _readPrivateForTesting<Map>(
              service,
              '_modelResolvedGpuLayers',
            )[handle],
            42,
          );
          expect(service.getResolvedGpuLayers(), 0);
          expect(simulatorWarnings(), isEmpty);
        },
      );

      test('an explicit Metal request keeps its GPU layers and warns', () {
        // An uninitialized service has no module directory, so no host forces
        // the missing Metal module onto the CPU, and no registered device can
        // refuse the load: every host keeps the layers.
        final service = LlamaCppService(
          isIosSimulator: true,
          registeredDevices: () => const <GgmlDeviceEntry>[],
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);

        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.metal,
            gpuLayers: 42,
          ),
        );

        expect(service.getResolvedGpuLayers(), 42);
        expect(simulatorWarnings(), hasLength(1));
      });

      // Records [handle] as a simulator load that kept 42 layers on Metal, as
      // `GpuBackend.metal` does, whatever this host has.
      void placeOnMetal(LlamaCppService service, int handle) {
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        )[handle] = 'Metal';
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        )[handle] = 42;
        _readPrivateForTesting<Map<int, ModelParams>>(
          service,
          '_modelLoadParams',
        )[handle] = const ModelParams(
          contextSize: 512,
          preferredBackend: GpuBackend.metal,
          gpuLayers: 42,
        );
      }

      test('a context follows its model onto the CPU or Metal', () {
        final service = LlamaCppService(isIosSimulator: true);
        addTearDown(service.dispose);
        const auto = ModelParams(contextSize: 512);
        const gpu = ModelParams(contextSize: 512, device: ComputeDevice.gpu);
        llama_context_params contextParams(int context) =>
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;

        final onCpu = service.loadModel(modelPath, auto);
        final cpuContext = contextParams(service.createContext(onCpu, gpu));
        expect(cpuContext.offload_kqv, isFalse);
        expect(cpuContext.op_offload, isFalse);

        final onMetal = service.loadModel(modelPath, auto);
        placeOnMetal(service, onMetal);
        for (final params in [auto, gpu]) {
          final metalContext = contextParams(
            service.createContext(onMetal, params),
          );
          expect(metalContext.offload_kqv, isTrue, reason: '$params');
          expect(metalContext.op_offload, isTrue, reason: '$params');
        }
      });

      test('a draft model follows its target onto the CPU or Metal', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final service = LlamaCppService(
          isIosSimulator: true,
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        );
        addTearDown(service.dispose);
        void loadDraft(int target) => _invokePrivateForTesting<Object?>(
          service,
          '_loadSpeculativeDraftModel',
          [target, modelPath, 'Draft model'],
          {#loadMtp: false},
        );

        final onCpu = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512),
        );
        loadDraft(onCpu);
        final onMetal = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512),
        );
        placeOnMetal(service, onMetal);
        loadDraft(onMetal);

        expect(
          recorder.loadGpuLayers,
          [0, 0, 0, 42],
          reason:
              'the CPU target, its draft, the target placed on Metal, '
              'its draft',
        );
        expect(recorder.loadDevices[1], recorder.loadDevices[0]);
        expect(recorder.loadDevices[3], isNot(recorder.loadDevices[0]));
      });

      test('a decision head follows its encoder onto the CPU or Metal', () {
        var registryReads = 0;
        final service = LlamaCppService(
          isIosSimulator: true,
          registeredDevices: () {
            registryReads++;
            return const <GgmlDeviceEntry>[];
          },
        );
        addTearDown(service.dispose);
        final encoderPath = path.join(tempDir.path, 'encoder.gguf');
        final headPath = path.join(tempDir.path, 'head.safetensors');
        final configPath = path.join(tempDir.path, 'config.json');
        writeSyntheticModernBertGguf(encoderPath, decisionTokens: true);
        SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(headPath);
        File(configPath).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
        const params = ModelParams(contextSize: 512);

        final onCpu = service.loadModel(encoderPath, params);
        registryReads = 0;
        final cpuHead = service.loadDecisionHead(onCpu, headPath, configPath);
        expect(cpuHead.deviceName, 'CPU');
        expect(registryReads, 0, reason: 'a CPU encoder skips GPU selection');

        final onMetal = service.loadModel(encoderPath, params);
        placeOnMetal(service, onMetal);
        registryReads = 0;
        service.loadDecisionHead(onMetal, headPath, configPath);
        expect(
          registryReads,
          greaterThan(0),
          reason: 'an encoder on Metal selects a GPU for its head',
        );
      });
    });
  });

  group('macOS x64', () {
    const issue = 'https://github.com/leehack/llamadart/issues/1597';

    test('warns only for a macOS x64 load that offloads GPU layers', () {
      expect(
        LlamaCppService.macosX64MetalWarning(
          isMacosX64: true,
          resolvedGpuLayers: 1,
        ),
        allOf(contains('Metal'), contains('Intel Mac'), contains(issue)),
      );
      expect(
        LlamaCppService.macosX64MetalWarning(
          isMacosX64: true,
          resolvedGpuLayers: 0,
        ),
        isNull,
      );
      expect(
        LlamaCppService.macosX64MetalWarning(
          isMacosX64: false,
          resolvedGpuLayers: ModelParams.maxGpuLayers,
        ),
        isNull,
      );
    });

    group('loads', () {
      late Directory tempDir;
      late String modelPath;
      late List<LlamaLogRecord> records;

      Iterable<String> intelWarnings() => records
          .where((record) => record.level == LlamaLogLevel.warn)
          .map((record) => record.message)
          .where((message) => message.contains(issue));

      setUpAll(() => LlamaCppService().initializeBackend());

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('macos_x64_');
        modelPath = path.join(tempDir.path, 'llama.gguf');
        writeSyntheticLlamaGguf(modelPath);
        records = <LlamaLogRecord>[];
        LlamaLogger.instance
          ..setLevel(LlamaLogLevel.warn)
          ..setHandler(records.add);
      });

      tearDown(() {
        LlamaLogger.instance
          ..setLevel(LlamaLogLevel.none)
          ..setHandler(null);
        tempDir.deleteSync(recursive: true);
      });

      test('auto loads on the CPU device only, with 0 GPU layers, a CPU '
          'projector and no context offload', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final service = LlamaCppService(
          isMacosX64: true,
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        );
        addTearDown(service.dispose);
        const params = ModelParams(contextSize: 512);

        final handle = service.loadModel(modelPath, params);
        final context = service.createContext(handle, params);

        expect(service.getActiveBackendName(), 'CPU');
        expect(service.getResolvedGpuLayers(), 0);
        final cpuDevices = _invokePrivateForTesting<List<ggml_backend_dev_t>?>(
          service,
          '_resolvePreferredDevices',
          [GpuBackend.cpu],
        );
        expect(recorder.loadGpuLayers, [0]);
        expect(recorder.loadDevices, [
          [cpuDevices!.single.address],
        ]);
        expect(
          _readPrivateForTesting<Map<int, bool>>(
            service,
            '_modelToMtmdUseGpu',
          )[handle],
          isFalse,
        );
        final contextParams =
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;
        expect(contextParams.offload_kqv, isFalse);
        expect(contextParams.op_offload, isFalse);
        expect(intelWarnings(), isEmpty);
      });

      test('auto keeps its GPU layers on arm64 macOS', () {
        final service = LlamaCppService(
          isMacosX64: false,
          registeredDevices: () => const <GgmlDeviceEntry>[],
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);

        service.loadModel(modelPath, const ModelParams(contextSize: 512));

        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
        expect(intelWarnings(), isEmpty);
      });

      test('gpu with auto loads on Metal and warns', () {
        final checked = <GpuBackend>[];
        final service = LlamaCppService(
          isMacosX64: true,
          // Pins a Metal device, so a host without one still loads and warns.
          deviceTypes: (backend) {
            checked.add(backend);
            return [ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value];
          },
          registeredDevices: () => const <GgmlDeviceEntry>[],
        );
        addTearDown(service.dispose);

        service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512, device: ComputeDevice.gpu),
        );

        expect(checked.first, GpuBackend.metal);
        expect(service.getResolvedGpuLayers(), ModelParams.maxGpuLayers);
        expect(intelWarnings(), hasLength(1));
      });

      test('an explicit Metal request keeps its GPU layers and warns', () {
        // An uninitialized service has no module directory, so no host forces
        // the missing Metal module onto the CPU, and no registered device can
        // refuse the load: every host keeps the layers.
        final service = LlamaCppService(
          isMacosX64: true,
          registeredDevices: () => const <GgmlDeviceEntry>[],
          deviceTypes: _hostWithGpu,
        );
        addTearDown(service.dispose);

        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 512,
            preferredBackend: GpuBackend.metal,
            gpuLayers: 42,
          ),
        );

        expect(service.getResolvedGpuLayers(), 42);
        expect(intelWarnings(), hasLength(1));
      });

      test('a draft model follows its auto target onto the CPU', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final service = LlamaCppService(
          isMacosX64: true,
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        );
        addTearDown(service.dispose);

        final target = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 512),
        );
        // The target's recorded backend name would short-circuit the draft to
        // the CPU; without it the draft must resolve auto itself.
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        ).remove(target);
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        ).remove(target);
        _invokePrivateForTesting<Object?>(
          service,
          '_loadSpeculativeDraftModel',
          [target, modelPath, 'Draft model'],
          {#loadMtp: false},
        );

        expect(recorder.loadGpuLayers, [0, 0]);
        expect(recorder.loadDevices[1], recorder.loadDevices[0]);
      });

      test('a decision head follows its auto encoder onto the CPU', () {
        var registryReads = 0;
        final service = LlamaCppService(
          isMacosX64: true,
          registeredDevices: () {
            registryReads++;
            return const <GgmlDeviceEntry>[];
          },
        );
        addTearDown(service.dispose);
        final encoderPath = path.join(tempDir.path, 'encoder.gguf');
        final headPath = path.join(tempDir.path, 'head.safetensors');
        final configPath = path.join(tempDir.path, 'config.json');
        writeSyntheticModernBertGguf(encoderPath, decisionTokens: true);
        SyntheticDecisionHead(d: 16, layers: 1, seed: 1).write(headPath);
        File(configPath).writeAsStringSync('{"max_len": 64, "head_layers": 1}');

        final encoder = service.loadModel(
          encoderPath,
          const ModelParams(contextSize: 512),
        );
        // Without the encoder's recorded placement the head must resolve auto
        // itself.
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        ).remove(encoder);
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        ).remove(encoder);
        registryReads = 0;
        final head = service.loadDecisionHead(encoder, headPath, configPath);

        expect(head.deviceName, 'CPU');
        expect(registryReads, 0, reason: 'a CPU encoder skips GPU selection');
      });

      test('row split with auto is refused naming the CPU before the load', () {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final probed = <String>[];
        // Windows hosts may not resolve the split-buffer symbol, which the
        // real probe treats as supported, or read device names; this test
        // covers the CPU routing, which named hosts check exactly.
        final service = LlamaCppService(
          isMacosX64: true,
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
          splitBufferTypeProbe: (device) {
            probed.add(device.name);
            return false;
          },
        );
        addTearDown(service.dispose);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, splitMode: ModelSplitMode.row),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('ModelSplitMode.row'),
            ),
          ),
        );
        expect(probed, hasLength(1));
        expect(probed.single, isNot(startsWith('MTL')));
        if (!Platform.isWindows) expect(probed.single, 'CPU');
        expect(recorder.loadGpuLayers, isEmpty);
      });

      test('gpuDevices with auto is refused and names a GPU request', () {
        final service = LlamaCppService(isMacosX64: true);
        addTearDown(service.dispose);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 512, gpuDevices: [0]),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('ModelParams.gpuDevices'),
                contains('GpuBackend.auto loads on the CPU'),
                contains('ComputeDevice.gpu'),
              ),
            ),
          ),
        );
        expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
      });
    });
  });

  group('media parts', () {
    const params = ModelParams(
      contextSize: 512,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    const fakeMtmdHandle = -771;
    late Directory tempDir;
    late LlamaCppService service;
    late int modelHandle;
    late int contextHandle;
    late Pointer<Int8> cancelFlag;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('media_parts_');
      service = LlamaCppService();
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);
      modelHandle = service.loadModel(modelPath, params);
      contextHandle = service.createContext(modelHandle, params);
      cancelFlag = calloc<Int8>();
    });

    tearDown(() {
      _readPrivateForTesting<Map>(service, '_modelToMtmd').remove(modelHandle);
      _readPrivateForTesting<Map>(
        service,
        '_mtmdContexts',
      ).remove(fakeMtmdHandle);
      calloc.free(cancelFlag);
      service.dispose();
      tempDir.deleteSync(recursive: true);
    });

    void registerFakeProjector() {
      _readPrivateForTesting<Map>(service, '_mtmdContexts')[fakeMtmdHandle] =
          Pointer<mtmd_context>.fromAddress(0x30);
      _readPrivateForTesting<Map>(service, '_modelToMtmd')[modelHandle] =
          fakeMtmdHandle;
    }

    Stream<List<int>> generate(List<LlamaContentPart> parts) =>
        service.generate(
          contextHandle,
          'Describe <__media__>',
          const GenerationParams(maxTokens: 4, temp: 0, seed: 1),
          cancelFlag.address,
          parts: parts,
        );

    Matcher unsupported(Matcher message) => emitsError(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        message,
      ),
    );

    test('rejects image and audio input without a projector', () async {
      await expectLater(
        generate([
          LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
        ]),
        unsupported(
          allOf(
            startsWith('Image input needs a multimodal projector'),
            contains('LlamaModel(source, projector: ...)'),
          ),
        ),
      );
      await expectLater(
        generate([LlamaAudioContent(samples: Float32List(16))]),
        unsupported(startsWith('Audio input needs a multimodal projector')),
      );
      await expectLater(
        generate([
          const LlamaImageContent(path: '/tmp/image.png'),
          LlamaAudioContent(samples: Float32List(16)),
        ]),
        unsupported(startsWith('Image and audio input needs')),
      );
    });

    test('still generates text-only prompts without a projector', () async {
      final bytes = await service
          .generate(
            contextHandle,
            'Hello',
            const GenerationParams(maxTokens: 2, temp: 0, seed: 1),
            cancelFlag.address,
          )
          .toList();
      expect(bytes, isNotEmpty);
    });

    test('rejects remote image URLs before multimodal evaluation', () async {
      registerFakeProjector();
      await expectLater(
        generate([const LlamaImageContent(url: 'https://example.com/a.png')]),
        unsupported(
          allOf(
            contains('remote image URLs'),
            contains('LlamaImageContent.url'),
          ),
        ),
      );
    });

    test('accepts local image paths and encoded bytes with a projector', () {
      void check(List<LlamaContentPart> parts, {required bool projector}) =>
          _invokePrivateForTesting<void>(
            service,
            '_checkLlamaCppMediaParts',
            [parts],
            {#projectorLoaded: projector},
          );

      check(const [LlamaImageContent(path: '/tmp/image.png')], projector: true);
      check([
        LlamaImageContent(
          bytes: Uint8List.fromList([1, 2, 3]),
          url: 'https://example.com/a.png',
        ),
        LlamaAudioContent(samples: Float32List(16)),
      ], projector: true);
      expect(
        () => check(const [
          LlamaImageContent(url: 'https://example.com/a.png'),
        ], projector: true),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });

  group('prompt evaluation cancel', () {
    const params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: 512,
      batchSize: 100,
      microBatchSize: 64,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    const greedy = GenerationParams(maxTokens: 8, temp: 0, seed: 1);
    final prompt = 'a' * 226;
    final longerPrompt = prompt + 'b' * 30;
    late Directory tempDir;
    late LlamaCppService service;
    late int modelHandle;
    late int contextHandle;
    late Pointer<Int8> cancelFlag;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prompt_cancel_');
      service = LlamaCppService();
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);
      modelHandle = service.loadModel(modelPath, params);
      contextHandle = service.createContext(modelHandle, params);
      cancelFlag = calloc<Int8>();
    });

    tearDown(() {
      calloc.free(cancelFlag);
      service.dispose();
      tempDir.deleteSync(recursive: true);
    });

    Object context() => _readPrivateForTesting<Map<int, Object>>(
      service,
      '_contexts',
    )[contextHandle]!;

    List<int>? cachedPromptTokens() =>
        reflect(context()).getField(#cachedPromptTokens).reflectee
            as List<int>?;

    Pointer<llama_context> contextPointer() =>
        reflect(context()).getField(#pointer).reflectee
            as Pointer<llama_context>;

    Pointer<llama_model> modelPointer() =>
        reflect(
              _readPrivateForTesting<Map<int, Object>>(
                service,
                '_models',
              )[modelHandle]!,
            ).getField(#pointer).reflectee
            as Pointer<llama_model>;

    llama_batch batch() => _readPrivateForTesting<Map<int, TokenBatch>>(
      service,
      '_batches',
    )[contextHandle]!.batch;

    int positionsInMemory() =>
        llama_memory_seq_pos_max(llama_get_memory(contextPointer()), 0) + 1;

    /// Ingests [text] as a generation does and reports a cancel at the
    /// [cancelAt]th check. Returns the decoded token count and the positions
    /// in memory at each check.
    (int, List<int>) ingest(String text, {int? cancelAt}) {
      final vocab = llama_model_get_vocab(modelPointer());
      final tokens = malloc<Int32>(params.contextSize);
      final checks = <int>[];
      try {
        final decoded = _invokePrivateForTesting<int>(
          service,
          '_ingestTextPrompt',
          [batch(), vocab, text, tokens, params.contextSize, context()],
          {
            #maxBatchTokens: params.batchSize,
            #allowPromptReuse: true,
            #speculativeSession: nullptr,
            #speculativeApi: null,
            #speculativeConfig: null,
            #isCancelled: () {
              checks.add(positionsInMemory());
              return checks.length == cancelAt;
            },
          },
        );
        return (decoded, checks);
      } finally {
        malloc.free(tokens);
      }
    }

    Future<List<int>> generate(
      String text, {
      GenerationParams params = greedy,
    }) async => [
      for (final bytes
          in await service
              .generate(contextHandle, text, params, cancelFlag.address)
              .toList())
        ...bytes,
    ];

    test('decodes each n_batch chunk in n_ubatch calls and checks the cancel '
        'before each call', () {
      final promptTokens = service.tokenize(modelHandle, prompt, true);
      expect(promptTokens, hasLength(230));

      final (decoded, checks) = ingest(prompt);

      expect(checks, [0, 64, 100, 164, 200]);
      expect(decoded, 230);
      expect(positionsInMemory(), 230);
      expect(cachedPromptTokens(), promptTokens);
    });

    test(
      'decodes each n_batch chunk in one call for a speculative session',
      () {
        const speculative = GenerationParams(
          speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(),
        );
        final api = _invokePrivateForTesting<Object>(
          service,
          '_resolveSpeculativeApi',
          const [],
        );
        final config = _invokePrivateForTesting<Object>(
          service,
          '_resolveLlamaCppSpeculativeConfig',
          [speculative],
          {#hasMediaParts: false},
        );
        final session =
            reflect(api).invoke(#initSession, const [], {
                  #targetModel: modelPointer(),
                  #draftModel: null,
                  #targetContext: contextPointer(),
                  #contextParams:
                      _readPrivateForTesting<Map<int, llama_context_params>>(
                        service,
                        '_contextParams',
                      )[contextHandle]!,
                  #config: config,
                }).reflectee
                as Pointer<llama_dart_speculative>;
        final promptTokens = service.tokenize(modelHandle, prompt, true);
        final tokens = malloc<Int32>(promptTokens.length);
        tokens.asTypedList(promptTokens.length).setAll(0, promptTokens);
        final checks = <int>[];
        try {
          final decoded = _invokePrivateForTesting<int>(
            service,
            '_decodePromptSegment',
            [batch(), tokens, context()],
            {
              #startTokenIndex: 0,
              #tokenCount: promptTokens.length,
              #maxBatchTokens: params.batchSize,
              #outputAllLogits: true,
              #speculativeSession: session,
              #speculativeApi: api,
              #speculativeConfig: config,
              #isCancelled: () {
                checks.add(positionsInMemory());
                return false;
              },
            },
          );

          expect(checks, [0, 100, 200]);
          expect(decoded, 230);
        } finally {
          (reflect(api).getField(#free).reflectee as Function)(session);
          malloc.free(tokens);
        }
      },
    );

    test('a cancel between micro-batches keeps only the decoded tokens '
        'cached', () {
      final (decoded, checks) = ingest(prompt, cancelAt: 3);

      expect(checks, [0, 64, 100]);
      expect(decoded, 100);
      expect(positionsInMemory(), 100);
      expect(
        cachedPromptTokens(),
        service.tokenize(modelHandle, prompt, true).sublist(0, 100),
      );

      final (resumed, resumedChecks) = ingest(longerPrompt, cancelAt: 2);

      expect(resumedChecks, [100, 164]);
      expect(resumed, 164);
      expect(positionsInMemory(), 164);
      expect(
        cachedPromptTokens(),
        service.tokenize(modelHandle, longerPrompt, true).sublist(0, 164),
      );
    });

    test('a generation after a prompt cancelled between micro-batches matches '
        'one from a cleared context', () async {
      final uncancelled = await generate(
        longerPrompt,
        params: greedy.copyWith(reusePromptPrefix: false),
      );
      expect(uncancelled, isNotEmpty);

      ingest(prompt, cancelAt: 3);

      expect(await generate(longerPrompt), uncancelled);
    });

    test('a cancel raised before prompt evaluation ends the generation '
        'without output and keeps only the reused prefix cached', () async {
      final uncancelled = await generate(
        longerPrompt,
        params: greedy.copyWith(reusePromptPrefix: false),
      );
      await generate(prompt);
      final promptTokens = service.tokenize(modelHandle, prompt, true);
      final longerTokens = service.tokenize(modelHandle, longerPrompt, true);
      var reused = 0;
      while (reused < promptTokens.length &&
          promptTokens[reused] == longerTokens[reused]) {
        reused += 1;
      }
      cancelFlag.value = 1;

      expect(await generate(longerPrompt), isEmpty);
      expect(reused, greaterThan(200));
      expect(cachedPromptTokens(), longerTokens.sublist(0, reused));
      expect(positionsInMemory(), reused);

      cancelFlag.value = 0;
      expect(await generate(longerPrompt), uncancelled);
    });

    test('a cancel raised before prompt evaluation reports only the reused '
        'prefix as prompt tokens', () async {
      await generate(prompt);
      final reused = cachedPromptTokens()!.length;
      cancelFlag.value = 1;

      expect(await generate(longerPrompt), isEmpty);
      expect(reused, greaterThan(200));
      expect(service.lastGenerationTokenCounts(contextHandle), (
        promptTokens: reused,
        cachedPromptTokens: reused,
        completionTokens: 0,
      ));
    });

    test('a cancel raised before prompt evaluation of a repeated prompt '
        'caches no tokens', () async {
      final uncancelled = await generate(prompt);
      cancelFlag.value = 1;

      expect(await generate(prompt), isEmpty);
      expect(cachedPromptTokens(), isEmpty);
      expect(positionsInMemory(), 0);

      cancelFlag.value = 0;
      expect(await generate(prompt), uncancelled);
    });

    test('a cancel raised before the last token of a loaded state is decoded '
        'keeps the other tokens cached', () async {
      await generate(prompt);
      final promptTokens = service.tokenize(modelHandle, prompt, true);
      final statePath = path.join(tempDir.path, 'state.bin');
      expect(
        service.stateSaveFile(contextHandle, statePath, promptTokens),
        isTrue,
      );
      service.stateLoadFile(contextHandle, statePath, params.contextSize);
      final resumed = await generate(prompt);
      service.stateLoadFile(contextHandle, statePath, params.contextSize);
      cancelFlag.value = 1;

      expect(await generate(prompt), isEmpty);
      expect(
        cachedPromptTokens(),
        promptTokens.sublist(0, promptTokens.length - 1),
      );
      expect(positionsInMemory(), promptTokens.length - 1);

      cancelFlag.value = 0;
      expect(await generate(prompt), resumed);
    });
  });

  group('text with an embedded U+0000', () {
    const params = ModelParams(
      contextSize: 64,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    const text = 'ab\u0000cd';
    // The synthetic vocabulary holds only byte tokens, at id 3 + byte, and
    // SentencePiece prefixes U+2581.
    final textIds = [for (final byte in utf8.encode('\u2581$text')) 3 + byte];
    late Directory tempDir;
    late LlamaCppService service;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nul_text_');
      service = LlamaCppService();
    });

    tearDown(() {
      service.dispose();
      tempDir.deleteSync(recursive: true);
    });

    int loadLlama() {
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);
      return service.loadModel(modelPath, params);
    }

    test('tokenize keeps the text after it', () {
      final modelHandle = loadLlama();

      expect(service.tokenize(modelHandle, text, false), textIds);
      expect(service.tokenize(modelHandle, text, true), [1, ...textIds]);
    });

    test('a generation prompt keeps the text after it', () async {
      final contextHandle = service.createContext(loadLlama(), params);
      final cancelFlag = calloc<Int8>();
      try {
        await service
            .generate(
              contextHandle,
              text,
              const GenerationParams(maxTokens: 1, temp: 0, seed: 1),
              cancelFlag.address,
            )
            .drain<void>();
      } finally {
        calloc.free(cancelFlag);
      }

      final context = _readPrivateForTesting<Map<int, Object>>(
        service,
        '_contexts',
      )[contextHandle]!;
      expect(reflect(context).getField(#cachedPromptTokens).reflectee, [
        1,
        ...textIds,
      ]);
      expect(
        service.lastGenerationTokenCounts(contextHandle)?.promptTokens,
        textIds.length + 1,
      );
    });

    test('preserved tokens keep the text after it', () {
      final modelHandle = loadLlama();
      final model = _readPrivateForTesting<Map<int, Object>>(
        service,
        '_models',
      )[modelHandle]!;
      final vocab = llama_model_get_vocab(
        reflect(model).getField(#pointer).reflectee as Pointer<llama_model>,
      );

      expect(
        _invokePrivateForTesting<Set<int>>(
          service,
          '_resolvePreservedTokenIds',
          [
            vocab,
            [text],
          ],
        ),
        textIds.toSet(),
      );
    });

    test('embed keeps the text after it', () {
      final modelPath = path.join(tempDir.path, 'modern_bert.gguf');
      writeSyntheticModernBertGguf(
        modelPath,
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_MEAN.value,
      );
      final contextHandle = service.createContext(
        service.loadModel(modelPath, params),
        params,
      );

      expect(
        service.embed(contextHandle, text),
        isNot(service.embed(contextHandle, 'ab')),
      );
    });
  });

  group('embedding pass limits', () {
    late Directory tempDir;
    late LlamaCppService service;
    late int modelHandle;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('embedding_');
      service = LlamaCppService();
    });

    tearDown(() {
      service.dispose();
      tempDir.deleteSync(recursive: true);
    });

    int context(
      ModelParams params, {
      int poolingType = 1,
      List<String>? classifierLabels,
    }) {
      final modelPath = path.join(tempDir.path, 'modern_bert.gguf');
      writeSyntheticModernBertGguf(
        modelPath,
        poolingType: poolingType,
        classifierLabels: classifierLabels,
      );
      final cpuParams = params.copyWith(
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, cpuParams);
      return service.createContext(modelHandle, cpuParams);
    }

    String textOfTokens(int tokens, {String letter = 'a'}) {
      final text = letter * (tokens - 4);
      expect(service.tokenize(modelHandle, text, true), hasLength(tokens));
      return text;
    }

    test('a model with a KV cache embeds input above the micro-batch', () {
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(
        modelPath,
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_LAST.value,
      );
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 1024,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, params);
      final handle = service.createContext(modelHandle, params);

      final vector = service.embed(handle, textOfTokens(600));

      expect(vector, hasLength(16));
      expect(vector.every((value) => value.isFinite), isTrue);
    });

    int decoderContext({
      String architecture = 'llama',
      int poolingType = 3,
      bool? causalAttention,
      ModelParams params = const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 1024,
        batchSize: 1024,
        microBatchSize: 64,
        maxParallelSequences: 2,
      ),
    }) {
      final modelPath = path.join(tempDir.path, 'decoder.gguf');
      writeSyntheticLlamaGguf(
        modelPath,
        architecture: architecture,
        poolingType: poolingType,
        causalAttention: causalAttention,
      );
      final cpuParams = params.copyWith(
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, cpuParams);
      return service.createContext(modelHandle, cpuParams);
    }

    for (final pooling in [
      llama_pooling_type.LLAMA_POOLING_TYPE_MEAN,
      llama_pooling_type.LLAMA_POOLING_TYPE_CLS,
    ]) {
      test(
        '$pooling with memory rejects partial pooling for embed and embedBatch',
        () {
          final handle = decoderContext(poolingType: pooling.value);
          final fits = textOfTokens(64);
          final exceeds = textOfTokens(65);
          final rejectsPartialPooling = throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('at most 64 tokens'),
                contains('ModelParams.microBatchSize'),
                contains('ModelParams.batchSize'),
              ),
            ),
          );
          expect(service.embed(handle, fits), hasLength(16));
          expect(() => service.embed(handle, exceeds), rejectsPartialPooling);
          expect(
            () => service.embedBatch(handle, [fits, exceeds]),
            rejectsPartialPooling,
          );
          expect(service.embed(handle, fits), hasLength(16));
        },
      );

      test(
        '$pooling limits grouped input to one micro-batch without corrupting vectors',
        () {
          final handle = decoderContext(poolingType: pooling.value);
          final first = textOfTokens(40);
          final second = textOfTokens(40, letter: 'b');
          final expected = [
            service.embed(handle, first, normalize: false),
            service.embed(handle, second, normalize: false),
          ];
          final vectors = service.embedBatch(handle, [
            first,
            second,
          ], normalize: false);
          expect(vectors[0], orderedEquals(expected[0]));
          expect(vectors[1], orderedEquals(expected[1]));
        },
      );

      test(
        '$pooling with memory embeds a longer input when the micro-batch is raised',
        () {
          final handle = decoderContext(
            poolingType: pooling.value,
            params: const ModelParams(
              numberOfThreads: 2,
              numberOfThreadsBatch: 2,
              contextSize: 1024,
              batchSize: 1024,
              microBatchSize: 1024,
              maxParallelSequences: 2,
            ),
          );
          final text = textOfTokens(600);
          final vector = service.embed(handle, text);
          expect(vector, hasLength(16));
          expect(vector.every((value) => value.isFinite), isTrue);
          final vectors = service.embedBatch(handle, [text, 'short']);
          expect(
            vectors.first,
            orderedEquals(vector.map((value) => closeTo(value, 1e-6))),
          );
        },
      );
    }

    for (final pooling in [
      llama_pooling_type.LLAMA_POOLING_TYPE_LAST,
      llama_pooling_type.LLAMA_POOLING_TYPE_NONE,
    ]) {
      test('non-causal $pooling with memory rejects split decoding', () {
        final handle = decoderContext(
          poolingType: pooling.value,
          causalAttention: false,
        );
        final fits = textOfTokens(64);
        final exceeds = textOfTokens(65);
        final rejectsSplit = throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('at most 64 tokens'),
          ),
        );
        expect(service.embed(handle, fits), hasLength(16));
        expect(() => service.embed(handle, exceeds), rejectsSplit);
        expect(() => service.embedBatch(handle, [fits, exceeds]), rejectsSplit);
      });

      test('causal $pooling with memory keeps supported chunking', () {
        final handle = decoderContext(
          poolingType: pooling.value,
          causalAttention: true,
        );
        final first = textOfTokens(100);
        final second = textOfTokens(100, letter: 'b');
        final expected = [
          service.embed(handle, first),
          service.embed(handle, second),
        ];
        final vectors = service.embedBatch(handle, [first, second]);
        expect(vectors[0], orderedEquals(expected[0]));
        expect(vectors[1], orderedEquals(expected[1]));
      });
    }

    test(
      'non-causal grouped decode fits total input within one micro-batch',
      () {
        final handle = decoderContext(causalAttention: false);
        final first = textOfTokens(40);
        final second = textOfTokens(40, letter: 'b');
        final expected = [
          service.embed(handle, first),
          service.embed(handle, second),
        ];
        final vectors = service.embedBatch(handle, [first, second]);
        expect(vectors[0], orderedEquals(expected[0]));
        expect(vectors[1], orderedEquals(expected[1]));
      },
    );

    test('non-causal input succeeds when its one-pass capacity is raised', () {
      final handle = decoderContext(
        causalAttention: false,
        params: const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 1024,
        ),
      );
      final text = textOfTokens(600);
      expect(service.embed(handle, text), hasLength(16));
      expect(service.embedBatch(handle, [text, 'short']).first, hasLength(16));
    });

    for (final metadata in [
      <String, String>{},
      {
        'general.architecture': 'llama',
        'llama.attention.causal': 'not-a-boolean',
      },
    ]) {
      test('unverifiable causal metadata $metadata fails before decoding', () {
        service.dispose();
        service = _EmbeddingMetadataService(metadata);
        final handle = decoderContext();
        final rejectsProbe = throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('Cannot verify causal attention'),
          ),
        );
        expect(() => service.embed(handle, 'short'), rejectsProbe);
        expect(
          () => service.embedBatch(handle, ['short', 'other']),
          rejectsProbe,
        );
      });
    }

    test(
      'batch rejects a later oversized pooled input before clearing any context',
      () {
        final handle = decoderContext(
          poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_MEAN.value,
        );
        final context = _readPrivateForTesting<Map<int, Object>>(
          service,
          '_contexts',
        )[handle]!;
        reflect(context).setField(#cachedPromptTokens, [7, 8, 9]);
        final fits = textOfTokens(64);
        final exceeds = textOfTokens(65);
        expect(
          () => service.embedBatch(handle, [fits, exceeds]),
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(reflect(context).getField(#cachedPromptTokens).reflectee, [
          7,
          8,
          9,
        ]);
        expect(service.embed(handle, fits), hasLength(16));
      },
    );

    test('one-pass limit uses the effective native micro-batch', () {
      final handle = decoderContext(
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_MEAN.value,
        params: const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
          batchSize: 64,
          microBatchSize: 128,
        ),
      );
      final context = _readPrivateForTesting<Map<int, Object>>(
        service,
        '_contexts',
      )[handle]!;
      final pointer =
          reflect(context).getField(#pointer).reflectee
              as Pointer<llama_context>;
      expect(llama_n_ubatch(pointer), 64);
      expect(service.embed(handle, textOfTokens(64)), hasLength(16));
      expect(
        () => service.embed(handle, textOfTokens(65)),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('at most 64 tokens'),
          ),
        ),
      );
    });

    for (final pooling in [
      llama_pooling_type.LLAMA_POOLING_TYPE_NONE,
      llama_pooling_type.LLAMA_POOLING_TYPE_LAST,
    ]) {
      test('fallback $pooling preflights every input before decoding', () {
        final handle = decoderContext(
          poolingType: pooling.value,
          causalAttention: false,
          params: const ModelParams(
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
            contextSize: 1024,
            batchSize: 1024,
            microBatchSize: 64,
            maxParallelSequences: 1,
          ),
        );
        final context = _readPrivateForTesting<Map<int, Object>>(
          service,
          '_contexts',
        )[handle]!;
        reflect(context).setField(#cachedPromptTokens, [7, 8, 9]);
        expect(
          () => service.embedBatch(handle, ['short', textOfTokens(65)]),
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(reflect(context).getField(#cachedPromptTokens).reflectee, [
          7,
          8,
          9,
        ]);
        expect(service.embed(handle, 'short'), hasLength(16));
      });
    }

    for (final causalAttention in [null, true]) {
      test(
        'native diffusion probe overrides causal metadata $causalAttention',
        () {
          final handle = decoderContext(
            architecture: 'llada',
            causalAttention: causalAttention,
          );
          expect(
            _invokePrivateForTesting<bool>(
              service,
              '_embeddingModelHasCausalAttention',
              [modelHandle],
            ),
            isFalse,
          );
          expect(service.embed(handle, textOfTokens(64)), hasLength(16));
          expect(
            () => service.embed(handle, textOfTokens(65)),
            throwsA(isA<LlamaInferenceException>()),
          );
          expect(
            () => service.embedBatch(handle, ['short', textOfTokens(65)]),
            throwsA(isA<LlamaInferenceException>()),
          );
        },
      );

      test(
        'Gemma embedding forced attention overrides causal metadata $causalAttention',
        () {
          service.dispose();
          service = _EmbeddingMetadataService({
            'general.architecture': 'gemma-embedding',
            if (causalAttention != null)
              'gemma-embedding.attention.causal': 'true',
          });
          final handle = decoderContext();
          expect(service.embed(handle, textOfTokens(64)), hasLength(16));
          expect(
            () => service.embed(handle, textOfTokens(65)),
            throwsA(isA<LlamaInferenceException>()),
          );
          expect(
            () => service.embedBatch(handle, ['short', textOfTokens(65)]),
            throwsA(isA<LlamaInferenceException>()),
          );
        },
      );
    }

    test('unavailable native diffusion probe reports typed version skew', () {
      decoderContext();
      expect(
        () => _invokePrivateForTesting<bool>(
          service,
          '_embeddingModelHasCausalAttention',
          [modelHandle],
          {
            #diffusionProbe: (Pointer<llama_model> pointer) =>
                throw ArgumentError('missing native symbol'),
          },
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('llama_model_is_diffusion'),
          ),
        ),
      );
    });

    test('an encoder-only model rejects input above the micro-batch', () {
      final modelPath = path.join(tempDir.path, 't5encoder.gguf');
      writeSyntheticT5EncoderGguf(
        modelPath,
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_MEAN.value,
      );
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 1024,
        batchSize: 1024,
        microBatchSize: 64,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, params);
      final handle = service.createContext(modelHandle, params);

      expect(service.embed(handle, textOfTokens(64)), hasLength(16));
      expect(
        () => service.embed(handle, textOfTokens(65)),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains('at most 64 tokens'),
          ),
        ),
      );
    });

    test('embed and embedBatch reject a rank-pooled model', () {
      final handle = context(
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 64,
          maxParallelSequences: 2,
        ),
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_RANK.value,
        classifierLabels: const ['yes', 'no'],
      );
      final rejectsRank = throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          allOf(contains('rank-pooled'), contains('/issues/323')),
        ),
      );

      expect(() => service.embed(handle, 'query'), rejectsRank);
      expect(() => service.embedBatch(handle, ['a', 'b']), rejectsRank);
    });

    test('embed and embedBatch reject an encoder-decoder model', () {
      final modelPath = path.join(tempDir.path, 't5.gguf');
      writeSyntheticT5Gguf(modelPath);
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 64,
        maxParallelSequences: 2,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, params);
      final handle = service.createContext(modelHandle, params);
      final rejectsEncoderDecoder = throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('encoder-decoder'),
        ),
      );

      expect(() => service.embed(handle, 'query'), rejectsEncoderDecoder);
      expect(
        () => service.embedBatch(handle, ['a', 'b']),
        rejectsEncoderDecoder,
      );
    });

    test('embed and embedBatch reject input above the context', () {
      final modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(
        modelPath,
        poolingType: llama_pooling_type.LLAMA_POOLING_TYPE_LAST.value,
      );
      const params = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 256,
        maxParallelSequences: 1,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      );
      modelHandle = service.loadModel(modelPath, params);
      final handle = service.createContext(modelHandle, params);
      final rejectsOverflow = throwsA(
        isA<LlamaInferenceException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('has 257 tokens'),
            contains('at most 256 tokens'),
            contains('ModelParams.contextSize'),
          ),
        ),
      );

      expect(service.embed(handle, textOfTokens(256)), hasLength(16));
      expect(() => service.embed(handle, textOfTokens(257)), rejectsOverflow);
      expect(
        () => service.embedBatch(handle, ['a', textOfTokens(257)]),
        rejectsOverflow,
      );
    });

    test('default micro-batch rejects input above 512 tokens', () {
      final handle = context(
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
        ),
      );

      expect(service.embed(handle, textOfTokens(512)), hasLength(16));
      expect(
        () => service.embed(handle, textOfTokens(513)),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('at most 512 tokens'),
              contains('ModelParams.microBatchSize'),
            ),
          ),
        ),
      );
    });

    test('a raised micro-batch embeds input above 512 tokens', () {
      final handle = context(
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 1024,
        ),
      );

      final vector = service.embed(handle, textOfTokens(600));

      expect(vector, hasLength(16));
      expect(vector.every((value) => value.isFinite), isTrue);
    });

    test('embed rejects input above an explicit micro-batch', () {
      final handle = context(
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 64,
        ),
      );

      expect(service.embed(handle, textOfTokens(64)), hasLength(16));
      expect(
        () => service.embed(handle, textOfTokens(65)),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            contains(
              'has 65 tokens, but this model embeds its input in one '
              'pass of at most 64 tokens',
            ),
          ),
        ),
      );
    });

    test('embedBatch keeps grouped input within the micro-batch', () {
      final handle = context(
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          contextSize: 1024,
          batchSize: 1024,
          microBatchSize: 64,
          maxParallelSequences: 2,
        ),
      );
      final first = textOfTokens(40);
      final second = textOfTokens(40, letter: 'b');

      final vectors = service.embedBatch(handle, [first, second]);

      expect(vectors[0], orderedEquals(service.embed(handle, first)));
      expect(vectors[1], orderedEquals(service.embed(handle, second)));
      expect(vectors[0], isNot(orderedEquals(vectors[1])));
    });
  });

  group('real Qwen3 embedding safety', () {
    for (final entry in <(String, llama_pooling_type, String)>[
      (
        'LLAMADART_QWEN3_MEAN_MODEL',
        llama_pooling_type.LLAMA_POOLING_TYPE_MEAN,
        'true',
      ),
      (
        'LLAMADART_QWEN3_NONCAUSAL_MODEL',
        llama_pooling_type.LLAMA_POOLING_TYPE_LAST,
        'false',
      ),
    ]) {
      final (environmentKey, pooling, causal) = entry;
      final modelPath = Platform.environment[environmentKey];
      test(
        '$pooling causal=$causal rejects long input and recovers with a raised one-pass limit',
        () {
          final service = LlamaCppService()..initializeBackend();
          addTearDown(service.dispose);
          const params = ModelParams(
            contextSize: 2048,
            batchSize: 1024,
            microBatchSize: 512,
            maxParallelSequences: 2,
            preferredBackend: GpuBackend.cpu,
            gpuLayers: 0,
          );
          final model = service.loadModel(modelPath!, params);
          final metadata = service.getMetadata(model);
          expect(metadata['general.architecture'], 'qwen3');
          expect(metadata['qwen3.attention.causal'], causal);
          expect(metadata['qwen3.pooling_type'], pooling.value.toString());
          var context = service.createContext(model, params);
          final long = 'hello ' * 690;
          final tokenCount = service.tokenize(model, long, true).length;
          expect(tokenCount, greaterThan(512));
          expect(tokenCount, lessThanOrEqualTo(1024));
          final short = service.embed(context, 'hello', normalize: false);
          expect(short.length, greaterThan(1));
          expect(short.every((value) => value.isFinite), isTrue);
          final rejectsSplit = throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'message',
              contains('at most 512 tokens'),
            ),
          );
          expect(() => service.embed(context, long), rejectsSplit);
          expect(
            () => service.embedBatch(context, ['hello', long]),
            rejectsSplit,
          );
          expect(
            service.embed(context, 'hello', normalize: false),
            orderedEquals(short),
          );
          service.freeContext(context);
          context = service.createContext(
            model,
            params.copyWith(microBatchSize: 1024),
          );
          final vector = service.embed(context, long, normalize: false);
          final grouped = service.embedBatch(context, [
            long,
            'hello',
          ], normalize: false);
          expect(
            grouped.first,
            orderedEquals(vector.map((value) => closeTo(value, 1e-6))),
          );
          expect(vector.every((value) => value.isFinite), isTrue);
        },
        tags: 'local-only',
        skip: modelPath == null
            ? 'Set $environmentKey to the retagged Qwen3-Reranker GGUF.'
            : null,
      );
    }
  });

  group('resolveGpuLayersForLoad', () {
    test('prefers CPU for Android auto mode', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(params, isAndroid: true),
        GpuBackend.cpu,
      );
    });

    test('keeps auto mode on non-Android hosts', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(params),
        GpuBackend.auto,
      );
    });

    test('forces CPU mode to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 0);
    });

    test('forces Android auto mode to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isAndroid: true),
        0,
      );
    });

    test('resolves auto to CPU and zero gpu layers on an iOS simulator', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isIosSimulator: true,
        ),
        GpuBackend.cpu,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isIosSimulator: true),
        0,
      );
    });

    test('keeps auto and its gpu layers on an iOS device and on macOS', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isIosSimulator: false,
        ),
        GpuBackend.auto,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isIosSimulator: false),
        ModelParams.maxGpuLayers,
      );
    });

    test('keeps an explicit Metal request on an iOS simulator', () {
      const params = ModelParams(
        gpuLayers: 42,
        preferredBackend: GpuBackend.metal,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isIosSimulator: true,
        ),
        GpuBackend.metal,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isIosSimulator: true),
        42,
      );
    });

    test('resolves auto to CPU and zero gpu layers on macOS x64', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isMacosX64: true,
        ),
        GpuBackend.cpu,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isMacosX64: true),
        0,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(
          const ModelParams(gpuLayers: -1),
          isMacosX64: true,
        ),
        0,
      );
    });

    test('keeps auto and its gpu layers on arm64 macOS', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.auto,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isMacosX64: false,
        ),
        GpuBackend.auto,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isMacosX64: false),
        ModelParams.maxGpuLayers,
      );
    });

    test('keeps an explicit Metal request on macOS x64', () {
      const params = ModelParams(
        gpuLayers: 42,
        preferredBackend: GpuBackend.metal,
      );

      expect(
        LlamaCppService.resolvePreferredBackendForLoad(
          params,
          isMacosX64: true,
        ),
        GpuBackend.metal,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(params, isMacosX64: true),
        42,
      );
    });

    test('preserves configured gpu layers for non-CPU backends', () {
      const params = ModelParams(
        gpuLayers: 42,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(LlamaCppService.resolveGpuLayersForLoad(params), 42);
    });

    test('resolves negative gpu layers to every layer', () {
      for (final gpuLayers in [-1, -999]) {
        for (final backend in [GpuBackend.auto, GpuBackend.vulkan]) {
          expect(
            LlamaCppService.resolveGpuLayersForLoad(
              ModelParams(gpuLayers: gpuLayers, preferredBackend: backend),
            ),
            ModelParams.maxGpuLayers,
          );
        }
      }
    });

    test('still forces negative gpu layers to zero on the CPU', () {
      const negative = ModelParams(gpuLayers: -1);

      expect(
        LlamaCppService.resolveGpuLayersForLoad(
          negative.copyWith(preferredBackend: GpuBackend.cpu),
        ),
        0,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(negative, isAndroid: true),
        0,
      );
      expect(
        LlamaCppService.resolveGpuLayersForLoad(negative, isIosSimulator: true),
        0,
      );
    });
  });

  group('resolveContextBatchSizes', () {
    test('uses llama.cpp defaults when generative batch sizes are unset', () {
      const params = ModelParams(contextSize: 16384);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 16384);

      expect(resolved.batchSize, 2048);
      expect(resolved.microBatchSize, 512);
    });

    test('clamps automatic defaults to small contexts', () {
      const params = ModelParams(contextSize: 256);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 256);

      expect(resolved.batchSize, 256);
      expect(resolved.microBatchSize, 256);
    });

    test('preserves full-context defaults for encoder-only models', () {
      const params = ModelParams(contextSize: 4096);

      final resolved = LlamaCppService.resolveContextBatchSizes(
        params,
        4096,
        useFullContextDefaults: true,
      );

      expect(resolved.batchSize, 4096);
      expect(resolved.microBatchSize, 4096);
    });

    test('uses explicit batch and micro-batch values', () {
      const params = ModelParams(
        contextSize: 4096,
        batchSize: 512,
        microBatchSize: 128,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 512);
      expect(resolved.microBatchSize, 128);
    });

    test('clamps automatic micro-batch to a smaller explicit batch', () {
      const params = ModelParams(contextSize: 4096, batchSize: 384);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 384);
      expect(resolved.microBatchSize, 384);
    });

    test('caps an unset micro-batch at the llama.cpp default', () {
      const params = ModelParams(contextSize: 4096, batchSize: 1024);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 4096);

      expect(resolved.batchSize, 1024);
      expect(resolved.microBatchSize, 512);
    });

    test('clamps micro-batch to batch when only micro-batch is oversized', () {
      const params = ModelParams(contextSize: 1024, microBatchSize: 2048);

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 1024);

      expect(resolved.batchSize, 1024);
      expect(resolved.microBatchSize, 1024);
    });

    test('clamps batch sizes to safe bounds', () {
      const params = ModelParams(
        contextSize: 512,
        batchSize: 2048,
        microBatchSize: 1024,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 512);

      expect(resolved.batchSize, 512);
      expect(resolved.microBatchSize, 512);
    });

    test('falls back from invalid values to sane minimums', () {
      const params = ModelParams(
        contextSize: 0,
        batchSize: -10,
        microBatchSize: -20,
      );

      final resolved = LlamaCppService.resolveContextBatchSizes(params, 0);

      expect(resolved.batchSize, 1);
      expect(resolved.microBatchSize, 1);
    });
  });

  group('backend asset candidate scoring', () {
    test('accepts missing score symbol for compatibility', () {
      expect(LlamaCppService.isBackendCandidateScoreSupported(null), isTrue);
    });

    test('rejects non-positive scores', () {
      expect(LlamaCppService.isBackendCandidateScoreSupported(0), isFalse);
      expect(LlamaCppService.isBackendCandidateScoreSupported(-1), isFalse);
      expect(LlamaCppService.isBackendCandidateScoreSupported(1), isTrue);
    });

    test('skips unsupported Android CPU variants until score passes', () {
      final selected = LlamaCppService.selectFirstSupportedBackendCandidate(
        const <String>[
          'package:llamadart/ggml-cpu-android_armv9_2_2',
          'package:llamadart/ggml-cpu-android_armv8_6_1',
          'package:llamadart/ggml-cpu-android_armv8_2_2',
          'package:llamadart/ggml-cpu-android_armv8_0_1',
        ],
        scoreForCandidate: (candidate) {
          switch (candidate) {
            case 'package:llamadart/ggml-cpu-android_armv9_2_2':
            case 'package:llamadart/ggml-cpu-android_armv8_6_1':
              return 0;
            case 'package:llamadart/ggml-cpu-android_armv8_2_2':
              return 7;
            case 'package:llamadart/ggml-cpu-android_armv8_0_1':
              return 1;
          }
          return 0;
        },
      );

      expect(selected, 'package:llamadart/ggml-cpu-android_armv8_2_2');
    });

    test('keeps older backends without score symbol eligible', () {
      final selected = LlamaCppService.selectFirstSupportedBackendCandidate(
        const <String>[
          'package:llamadart/ggml-cpu-android_armv8_0_1',
          'package:llamadart/ggml-cpu',
        ],
        scoreForCandidate: (candidate) {
          if (candidate == 'package:llamadart/ggml-cpu-android_armv8_0_1') {
            return null;
          }
          return 1;
        },
      );

      expect(selected, 'package:llamadart/ggml-cpu-android_armv8_0_1');
    });

    test('returns null when every candidate is unsupported', () {
      final selected =
          LlamaCppService.selectFirstSupportedBackendCandidate(const <String>[
            'package:llamadart/ggml-cpu-android_armv9_2_2',
            'package:llamadart/ggml-cpu-android_armv8_6_1',
          ], scoreForCandidate: (_) => 0);

      expect(selected, isNull);
    });

    test('formats skipped backend asset diagnostics', () {
      expect(
        LlamaCppService.describeSkippedBackendAssetCandidate(
          'package:llamadart/ggml-cpu-android_armv8_6_1',
          0,
        ),
        'Skipped backend asset '
        '`package:llamadart/ggml-cpu-android_armv8_6_1` because '
        '`ggml_backend_score` returned 0.',
      );
    });

    test('formats loaded backend asset diagnostics with a score', () {
      expect(
        LlamaCppService.describeLoadedBackendAssetCandidate(
          'package:llamadart/ggml-cpu-android_armv8_2_2',
          7,
        ),
        'Loaded backend asset '
        '`package:llamadart/ggml-cpu-android_armv8_2_2` with '
        '`ggml_backend_score`=7.',
      );
    });

    test('formats loaded backend asset diagnostics without a score', () {
      expect(
        LlamaCppService.describeLoadedBackendAssetCandidate(
          'package:llamadart/ggml-cpu',
          null,
        ),
        'Loaded backend asset `package:llamadart/ggml-cpu` without '
        '`ggml_backend_score`.',
      );
    });
  });

  group('backend probe failure aggregation', () {
    test('an empty module directory names the expected module file', () {
      final tempDir = Directory.systemTemp.createTempSync('empty_module_dir_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      const backend = 'nonexistent-probe';
      final expectedFile = Platform.isWindows
          ? 'ggml-$backend.dll'
          : Platform.isMacOS
          ? 'libggml-$backend.dylib'
          : 'libggml-$backend.so';

      final service = LlamaCppService();
      _writePrivateForTesting(service, '_backendModuleDirectory', tempDir.path);
      final loaded = _invokePrivateForTesting<bool>(
        service,
        '_tryLoadBackendModule',
        <Object?>[backend],
      );

      expect(loaded, isFalse);
      final entry = service.getStartupDiagnostics().single;
      expect(
        entry,
        startsWith(
          'Backend module `$backend` not loaded from any candidate: '
          'file missing ($expectedFile); ',
        ),
      );
      expect(entry, contains('(package:llamadart/$backend'));
      expect(entry, isNot(contains(tempDir.path)));
    });

    test('a backend family with no usable candidate records one summary', () {
      final service = LlamaCppService();
      const backend = 'nonexistent-probe';

      final loaded = _invokePrivateForTesting<bool>(
        service,
        '_tryLoadBackendModule',
        <Object?>[backend],
      );

      expect(loaded, isFalse);
      final entries = service.getStartupDiagnostics();
      expect(entries, hasLength(1));
      final loaderUnavailable = _readPrivateForTesting<bool>(
        service,
        '_backendLoadSymbolUnavailable',
      );
      if (loaderUnavailable) {
        expect(
          entries.single,
          startsWith('`ggml_backend_load` is unavailable: the primary FFI '),
        );
      } else {
        expect(
          entries.single,
          startsWith(
            'Backend module `$backend` not loaded from any candidate: ',
          ),
        );
        expect(entries.single, contains('(package:llamadart/$backend'));
      }
      expect(
        entries.single,
        isNot(contains(path.dirname(Platform.resolvedExecutable))),
      );
      expect(entries.single, isNot(contains(Directory.current.path)));

      final retried = _invokePrivateForTesting<bool>(
        service,
        '_tryLoadBackendModule',
        <Object?>[backend],
      );
      expect(retried, isFalse);
      expect(service.getStartupDiagnostics(), entries);
    });

    test('ggml candidate failures are recorded only for a missing symbol', () {
      final service = LlamaCppService();
      _invokePrivateForTesting<void>(
        service,
        '_resolveGgmlFallbackFunctions',
        const <Object?>[],
      );
      expect(service.getStartupDiagnostics(), isEmpty);

      for (var i = 0; i < 2; i++) {
        _invokePrivateForTesting<void>(
          service,
          '_recordMissingGgmlSymbol',
          const <Object?>['`ggml_backend_load`'],
        );
      }

      final entries = service.getStartupDiagnostics();
      expect(entries, hasLength(1));
      expect(
        entries.single,
        startsWith(
          '`ggml_backend_load` is unavailable: the primary FFI asset does '
          'not export it and ',
        ),
      );
      expect(entries.single, contains('package:llamadart/ggml'));
      expect(entries.single, endsWith('.'));
      expect(
        entries.single,
        isNot(contains(path.dirname(Platform.resolvedExecutable))),
      );
      expect(entries.single, isNot(contains(Directory.current.path)));
    });

    test('a missing ggml symbol reports the candidates that opened', () {
      final service = LlamaCppService();
      _writePrivateForTesting(
        service,
        '_ggmlRuntimeProbeOutcome',
        'the opened ggml runtime candidates (libggml.so) do not export it; '
            'other candidates: not found (package:llamadart/ggml)',
      );
      _invokePrivateForTesting<void>(
        service,
        '_recordMissingGgmlSymbol',
        const <Object?>['`ggml_backend_load_all`'],
      );

      expect(service.getStartupDiagnostics(), <String>[
        '`ggml_backend_load_all` is unavailable: the primary FFI asset does '
            'not export it and the opened ggml runtime candidates (libggml.so) '
            'do not export it; other candidates: not found '
            '(package:llamadart/ggml).',
      ]);
    });

    test('a registry symbol missing everywhere flags the map only', () {
      final service = LlamaCppService();
      final value = _invokePrivateForTesting<Object?>(
        service,
        '_ggmlRegistryFallbackOr',
        <Object?>[-1, () => throw ArgumentError('primary'), () => null],
      );

      expect(value, -1);
      expect(
        _readPrivateForTesting<bool>(
          service,
          '_backendRegistrySymbolUnavailable',
        ),
        isTrue,
      );
      expect(service.getStartupDiagnostics(), isEmpty);
    });

    test('a ggml candidate that resolves the symbols records nothing', () {
      final source = _locateGgmlRuntimeLibraryForTesting();
      if (source == null) {
        markTestSkipped('no built library exports ggml_backend_load');
        return;
      }
      final tempDir = Directory.systemTemp.createTempSync('ggml_probe_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final ggmlFileName = Platform.isWindows
          ? 'ggml.dll'
          : Platform.isMacOS
          ? 'libggml.dylib'
          : 'libggml.so';
      final String moduleDir;
      if (path.basename(source) == ggmlFileName) {
        moduleDir = path.dirname(source);
      } else {
        if (Platform.isWindows) {
          markTestSkipped('a mapped DLL copy cannot be deleted on teardown');
          return;
        }
        final copy = path.join(tempDir.path, ggmlFileName);
        File(source).copySync(copy);
        if (!_exportsGgmlBackendLoad(copy)) {
          markTestSkipped('a copy of $source does not load standalone');
          return;
        }
        moduleDir = tempDir.path;
      }

      final service = LlamaCppService();
      _writePrivateForTesting(service, '_backendModuleDirectory', moduleDir);
      _invokePrivateForTesting<void>(
        service,
        '_resolveGgmlFallbackFunctions',
        const <Object?>[],
      );

      expect(
        _readPrivateForTesting<Object?>(service, '_ggmlBackendLoadFallback'),
        isNotNull,
      );
      final regCount = _readPrivateForTesting<Function?>(
        service,
        '_ggmlBackendRegCountFallback',
      );
      expect(regCount, isNotNull);
      final value = _invokePrivateForTesting<Object?>(
        service,
        '_ggmlRegistryFallbackOr',
        <Object?>[
          -1,
          () => throw ArgumentError('primary'),
          () => Function.apply(regCount!, const <Object?>[]),
        ],
      );

      expect(
        value,
        isA<int>().having((count) => count, 'count', isNonNegative),
      );
      expect(
        _readPrivateForTesting<bool>(
          service,
          '_backendRegistrySymbolUnavailable',
        ),
        isFalse,
      );
      expect(service.getStartupDiagnostics(), isEmpty);
    });
  });

  group('shouldDisableContextGpuOffload', () {
    test('disables offload for explicit CPU backend', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isTrue);
    });

    test('disables offload when effective gpu layers are zero', () {
      const params = ModelParams(
        gpuLayers: 0,
        preferredBackend: GpuBackend.auto,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isTrue);
    });

    test('keeps offload enabled for non-CPU backend with gpu layers', () {
      const params = ModelParams(
        gpuLayers: 12,
        preferredBackend: GpuBackend.hip,
      );

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isFalse);
    });

    test('keeps offload enabled for negative gpu layers', () {
      const params = ModelParams(gpuLayers: -1);

      expect(LlamaCppService.shouldDisableContextGpuOffload(params), isFalse);
      expect(
        LlamaCppService.resolveMtmdUseGpuForLoad(
          params,
          LlamaCppService.resolveGpuLayersForLoad(params),
        ),
        isTrue,
      );
    });

    test('honors resolved load-time fallback to zero gpu layers', () {
      const params = ModelParams(
        gpuLayers: 32,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldDisableContextGpuOffload(
          params,
          resolvedGpuLayers: 0,
        ),
        isTrue,
      );
    });
  });

  group('shouldUseConservativeAndroidVulkanContextConfig', () {
    test('returns false off Android', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(params),
        isFalse,
      );
    });

    test('returns true for Android Vulkan with GPU layers', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          isAndroid: true,
        ),
        isTrue,
      );
    });

    test('returns true for Android Vulkan with negative GPU layers', () {
      const params = ModelParams(
        gpuLayers: -1,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          isAndroid: true,
        ),
        isTrue,
      );
    });

    test('returns false for Android CPU mode', () {
      const params = ModelParams(
        gpuLayers: 0,
        preferredBackend: GpuBackend.cpu,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          isAndroid: true,
        ),
        isFalse,
      );
    });

    test('returns false after effective Vulkan fallback to zero layers', () {
      const params = ModelParams(
        gpuLayers: 16,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.shouldUseConservativeAndroidVulkanContextConfig(
          params,
          resolvedGpuLayers: 0,
          isAndroid: true,
        ),
        isFalse,
      );
    });
  });

  group('Android Vulkan prompt micro-batch', () {
    const vulkan = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: 256,
      preferredBackend: GpuBackend.vulkan,
    );
    const cpu = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: 256,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    final prompt = 'a' * 96;
    late Directory tempDir;
    late String modelPath;

    setUpAll(() => LlamaCppService().initializeBackend());

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('android_vulkan_ubatch_');
      modelPath = path.join(tempDir.path, 'llama.gguf');
      writeSyntheticLlamaGguf(modelPath);
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    /// The token count of each `llama_decode` call that ingests the 100-token
    /// [prompt] on a context created with [params], and the `n_ubatch` of
    /// that context.
    ///
    /// The model loads with [loadParams] on this host. [loadedGpuLayers]
    /// replaces the GPU layer count that load recorded, as a load that kept
    /// its layers on a GPU backend this host does not have.
    ///
    /// [vulkanDevices] is what the Vulkan device facts report, for a ggml
    /// registry of [registeredVulkanDevices] Vulkan devices; without it they
    /// are unavailable, so no case depends on the host's GPUs.
    Future<({List<int> calls, int microBatch})> ingest(
      ModelParams params, {
      bool isAndroid = true,
      ModelParams loadParams = cpu,
      int? loadedGpuLayers,
      SpeculativeDecodingConfig? speculativeDecodingConfig,
      VulkanDeviceProbe Function()? vulkanDevices,
      int registeredVulkanDevices = 1,
    }) async {
      final recorder = RecordingExitTeardown(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      );
      final service = LlamaCppService(
        isAndroid: isAndroid,
        objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        registeredDevices: () => [
          for (var index = 0; index < registeredVulkanDevices; index++)
            GgmlDeviceEntry(
              name: 'Vulkan$index',
              type: ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
              registry: 'Vulkan',
            ),
        ],
        vulkanDeviceProbe:
            vulkanDevices ??
            () => const VulkanDeviceProbe.unavailable('not read in this case'),
      );
      addTearDown(service.dispose);
      final model = service.loadModel(modelPath, loadParams);
      if (loadedGpuLayers != null) {
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        )[model] = loadedGpuLayers;
      }
      final context = service.createContext(model, params);
      expect(service.tokenize(model, prompt, true), hasLength(100));

      final cancel = calloc<Int8>();
      try {
        await service
            .generate(
              context,
              prompt,
              GenerationParams(
                maxTokens: 1,
                temp: 0,
                seed: 1,
                speculativeDecodingConfig: speculativeDecodingConfig,
              ),
              cancel.address,
            )
            .drain<void>();
      } finally {
        calloc.free(cancel);
      }

      final calls = <int>[];
      for (final tokens in recorder.decodedTokens) {
        if (calls.fold(0, (sum, call) => sum + call) == 100) break;
        calls.add(tokens);
      }
      final pointer =
          reflect(
                _readPrivateForTesting<Map<int, Object>>(
                  service,
                  '_contexts',
                )[context]!,
              ).getField(#pointer).reflectee
              as Pointer<llama_context>;
      return (calls: calls, microBatch: llama_n_ubatch(pointer));
    }

    Matcher decodes(List<int> calls, {int microBatch = 256}) =>
        isA<({List<int> calls, int microBatch})>()
            .having((result) => result.calls, 'calls', calls)
            .having((result) => result.microBatch, 'n_ubatch', microBatch);

    test('decodes a prompt in calls of at most 8 tokens on Android Vulkan '
        'and keeps n_ubatch', () async {
      expect(
        await ingest(vulkan, loadedGpuLayers: 1),
        decodes([8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4]),
      );
      expect(
        await ingest(
          const ModelParams(
            numberOfThreads: 2,
            numberOfThreadsBatch: 2,
            contextSize: 256,
            device: ComputeDevice.gpu,
          ),
          loadedGpuLayers: 1,
        ),
        decodes([8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4]),
      );
    });

    VulkanDeviceProbe Function() subgroups(List<int> sizes) =>
        () => VulkanDeviceProbe.devices([
          for (final (index, size) in sizes.indexed)
            VulkanDeviceFacts(
              name: 'GPU $index',
              deviceType: 2,
              instanceApiVersion: VulkanDeviceFacts.vulkan12,
              apiVersion: VulkanDeviceFacts.vulkan12,
              subgroupSize: size,
            ),
        ]);
    const capped = [8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4];

    test('decodes the whole prompt in one call on a GPU whose subgroup size '
        'ggml-vulkan tiles correctly', () async {
      for (final size in [8, 32, 64, 128]) {
        expect(
          await ingest(
            vulkan,
            loadedGpuLayers: 1,
            vulkanDevices: subgroups([size]),
          ),
          decodes([100]),
          reason: 'subgroup size $size',
        );
      }
    });

    test('keeps the cap on a GPU whose subgroup size ggml-vulkan mis-tiles '
        'or that does not report one', () async {
      for (final size in [16, 4, 1, 0]) {
        expect(
          await ingest(
            vulkan,
            loadedGpuLayers: 1,
            vulkanDevices: subgroups([size]),
          ),
          decodes(capped),
          reason: 'subgroup size $size',
        );
      }
    });

    test('keeps the cap when the device facts are unavailable, list no '
        'device, or do not match the devices ggml registered', () async {
      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          vulkanDevices: () => const VulkanDeviceProbe.unavailable(
            'the loaded llama.cpp runtime does not export '
            'llama_dart_vulkan_get_device_count',
          ),
        ),
        decodes(capped),
      );
      expect(
        await ingest(vulkan, loadedGpuLayers: 1, vulkanDevices: subgroups([])),
        decodes(capped),
      );
      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          vulkanDevices: subgroups([64]),
          registeredVulkanDevices: 2,
        ),
        decodes(capped),
      );
      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          vulkanDevices: subgroups([64, 16]),
          registeredVulkanDevices: 2,
        ),
        decodes(capped),
        reason: 'one affected device among the registered ones',
      );
      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          vulkanDevices: subgroups([64, 32]),
          registeredVulkanDevices: 2,
        ),
        decodes([100]),
      );
    });

    test('reads the device facts only for a context the cap would '
        'apply to', () async {
      var reads = 0;
      VulkanDeviceProbe counted() {
        reads++;
        return subgroups([64])();
      }

      await ingest(cpu, vulkanDevices: counted);
      await ingest(vulkan, vulkanDevices: counted);
      await ingest(
        vulkan.copyWith(microBatchSize: 64),
        loadedGpuLayers: 1,
        vulkanDevices: counted,
      );
      await ingest(
        vulkan,
        isAndroid: false,
        loadedGpuLayers: 1,
        vulkanDevices: counted,
      );
      expect(reads, 0);

      // Vulkan was asked for, but ggml-vulkan registered no device.
      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          vulkanDevices: counted,
          registeredVulkanDevices: 0,
        ),
        decodes(capped),
      );
      expect(reads, 0);

      await ingest(vulkan, loadedGpuLayers: 1, vulkanDevices: counted);
      expect(reads, 1);
    });

    test('caps the calls of a speculative session too', () async {
      const ngram = SpeculativeDecodingConfig.ngramSimple(
        ngramSizeN: 1,
        ngramSizeM: 4,
        ngramMinHits: 1,
      );

      expect(
        await ingest(
          vulkan,
          loadedGpuLayers: 1,
          speculativeDecodingConfig: ngram,
        ),
        decodes([8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4]),
      );
      expect(
        await ingest(cpu, speculativeDecodingConfig: ngram),
        decodes([100]),
      );
    });

    test('keeps an explicit micro-batch on Android Vulkan', () async {
      for (final (explicit, calls) in [
        (16, [16, 16, 16, 16, 16, 16, 4]),
        (33, [33, 33, 33, 1]),
        (64, [64, 36]),
        (256, [100]),
      ]) {
        expect(
          await ingest(
            vulkan.copyWith(microBatchSize: explicit),
            loadedGpuLayers: 1,
          ),
          decodes(calls, microBatch: explicit),
        );
      }
    });

    test('keeps the default when Android auto loads on the CPU', () async {
      const auto = ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 256,
      );

      expect(await ingest(auto, loadParams: auto), decodes([100]));
    });

    test('keeps the default for Android CPU and for a Vulkan load that kept '
        'no GPU layers', () async {
      expect(await ingest(cpu), decodes([100]));
      expect(await ingest(vulkan), decodes([100]));
    });

    test('keeps the default for Vulkan off Android', () async {
      expect(
        await ingest(vulkan, isAndroid: false, loadedGpuLayers: 1),
        decodes([100]),
      );
    });
  });

  group('Vulkan device facts', () {
    VulkanDeviceFacts device({
      String name = 'Mali-G68',
      int? instanceApiVersion,
      int? apiVersion,
      int subgroupSize = 4,
    }) => VulkanDeviceFacts(
      name: name,
      deviceType: 2,
      instanceApiVersion: instanceApiVersion ?? VulkanDeviceFacts.vulkan12,
      apiVersion: apiVersion ?? VulkanDeviceFacts.vulkan12,
      subgroupSize: subgroupSize,
    );
    const vulkan11 = 1 << 22 | 1 << 12;
    const vulkan = ModelParams(
      preferredBackend: GpuBackend.vulkan,
      gpuLayers: 16,
    );

    test('the cap resolver asks about the defect only when the cap would '
        'apply, and lifts it for a device without it', () {
      var asked = 0;
      bool defect(bool value) {
        asked++;
        return value;
      }

      expect(
        LlamaCppService.resolvePromptMicroBatchLimit(
          vulkan,
          isAndroid: true,
          hasSmallMatmulTileDefect: () => defect(true),
        ),
        LlamaCppService.androidVulkanPromptMicroBatchSize,
      );
      expect(
        LlamaCppService.resolvePromptMicroBatchLimit(
          vulkan,
          isAndroid: true,
          hasSmallMatmulTileDefect: () => defect(false),
        ),
        isNull,
      );
      expect(asked, 2);
      expect(
        LlamaCppService.resolvePromptMicroBatchLimit(vulkan, isAndroid: true),
        LlamaCppService.androidVulkanPromptMicroBatchSize,
        reason: 'without the facts the cap stays',
      );

      for (final (params, isAndroid, gpuLayers) in [
        (vulkan, false, null),
        (vulkan, true, 0),
        (vulkan.copyWith(microBatchSize: 64), true, null),
        (const ModelParams(), true, null),
      ]) {
        expect(
          LlamaCppService.resolvePromptMicroBatchLimit(
            params,
            isAndroid: isAndroid,
            resolvedGpuLayers: gpuLayers,
            hasSmallMatmulTileDefect: () => defect(true),
          ),
          isNull,
        );
      }
      expect(asked, 2);
    });

    test('unknown devices count as having the small matmul tile defect', () {
      bool defect(VulkanDeviceProbe probe, {int registered = 1}) =>
          LlamaCppService.vulkanSmallMatmulTileDefect(
            probe,
            registeredDeviceCount: registered,
          );

      expect(defect(const VulkanDeviceProbe.unavailable('no loader')), isTrue);
      expect(defect(const VulkanDeviceProbe.devices([])), isTrue);
      expect(
        defect(VulkanDeviceProbe.devices([device(subgroupSize: 64)])),
        isFalse,
      );
      expect(
        defect(VulkanDeviceProbe.devices([device(subgroupSize: 16)])),
        isTrue,
      );
      expect(
        defect(
          VulkanDeviceProbe.devices([device(subgroupSize: 64)]),
          registered: 2,
        ),
        isTrue,
      );
      expect(
        defect(
          VulkanDeviceProbe.devices([
            device(subgroupSize: 64),
            device(subgroupSize: 4),
          ]),
          registered: 2,
        ),
        isTrue,
      );
    });

    group('at model load', () {
      late Directory tempDir;
      late String modelPath;
      late List<String> warnings;

      setUpAll(() => LlamaCppService().initializeBackend());

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('vulkan_api_version_');
        modelPath = path.join(tempDir.path, 'llama.gguf');
        writeSyntheticLlamaGguf(modelPath);
        warnings = <String>[];
        LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
        LlamaLogger.instance.setHandler((record) {
          if (record.level == LlamaLogLevel.warn) warnings.add(record.message);
        });
      });

      tearDown(() {
        LlamaLogger.instance.setHandler(null);
        LlamaLogger.instance.setLevel(LlamaLogLevel.none);
        tempDir.deleteSync(recursive: true);
      });

      final gpuType = ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value;
      final igpuType =
          ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_IGPU.value;
      const vulkan13 = 1 << 22 | 3 << 12;

      // A registered ggml device; [description] is the Vulkan device name
      // its facts are found by.
      GgmlDeviceEntry entry(
        String name, {
        String description = '',
        int? type,
        String? deviceId,
        int? address,
      }) => GgmlDeviceEntry(
        name: name,
        type: type ?? gpuType,
        registry: name.replaceAll(RegExp(r'\d+$'), ''),
        description: description,
        deviceId: deviceId,
        device: address == null ? null : Pointer.fromAddress(address),
      );

      VulkanDeviceFacts fact(
        String name,
        int apiVersion, {
        bool integrated = false,
      }) => VulkanDeviceFacts(
        name: name,
        deviceType: integrated ? 1 : 2,
        instanceApiVersion: VulkanDeviceFacts.vulkan12,
        apiVersion: apiVersion,
        subgroupSize: 32,
      );

      final mali = entry('Vulkan0', description: 'Mali-G68');
      final maliOld = fact('Mali-G68', vulkan11);
      final rtx = entry('Vulkan0', description: 'RTX 4090');
      final rtxOk = fact('RTX 4090', vulkan13);
      final uhd = entry(
        'Vulkan1',
        description: 'UHD Graphics 630',
        type: igpuType,
      );
      final uhdOld = fact('UHD Graphics 630', vulkan11, integrated: true);

      // A host whose ggml registry holds [registered] and whose Vulkan
      // devices report [facts], or no facts at all. [reads] counts the reads
      // of the facts.
      var reads = 0;
      LlamaCppService serviceWith(
        List<GgmlDeviceEntry> registered,
        List<VulkanDeviceFacts>? facts, {
        LlamaCppObjectCalls? objectCalls,
        bool isAndroid = false,
      }) {
        reads = 0;
        final service = LlamaCppService(
          isAndroid: isAndroid,
          isMacosX64: false,
          deviceTypes: (_) => [gpuType],
          objectCalls: objectCalls,
          registeredDevices: () => registered,
          vulkanDeviceProbe: () {
            reads++;
            return facts == null
                ? const VulkanDeviceProbe.unavailable('no loader')
                : VulkanDeviceProbe.devices(facts);
          },
        );
        addTearDown(service.dispose);
        return service;
      }

      for (final gpuLayers in [ModelParams.maxGpuLayers, -1]) {
        test(
          'Android Adreno guard refuses explicit GPU and loads auto on CPU '
          'before a native model call can use the unsafe device ($gpuLayers layers)',
          () {
            final adreno = entry('Vulkan0', description: 'Adreno (TM) 750');
            const bad = VulkanDeviceFacts(
              name: 'Adreno (TM) 750',
              deviceType: 2,
              instanceApiVersion: vulkan13,
              apiVersion: vulkan13,
              subgroupSize: 64,
              vendorId: 0x5143,
              driverVersion: 2150604839,
            );
            // Metal supplies the host's real GPU module; the injected registry
            // and facts supply Android's selected Vulkan device. No driver is
            // initialized by the probe and the guarded load must use the CPU.
            final explicit = serviceWith([adreno], [bad], isAndroid: true);
            expect(
              () => explicit.loadModel(
                modelPath,
                ModelParams(
                  gpuLayers: gpuLayers,
                  contextSize: 64,
                  device: ComputeDevice.gpu,
                  preferredBackend: GpuBackend.metal,
                ),
              ),
              throwsA(
                isA<LlamaUnsupportedException>().having(
                  (e) => e.message,
                  'message',
                  contains('driver 2150604839'),
                ),
              ),
            );
            expect(_readPrivateForTesting<Map>(explicit, '_models'), isEmpty);
            final automatic = serviceWith([adreno], [bad], isAndroid: true);
            final model = automatic.loadModel(
              modelPath,
              ModelParams(
                gpuLayers: gpuLayers,
                contextSize: 64,
                preferredBackend: GpuBackend.metal,
              ),
            );
            expect(automatic.getResolvedGpuLayers(), 0);
            expect(automatic.getActiveBackendName(), 'CPU');
            expect(
              warnings,
              contains(
                allOf(
                  contains('driver 2150604839'),
                  contains('so the model loaded on CPU with 0 GPU layers'),
                ),
              ),
            );
            final context = automatic.createContext(
              model,
              const ModelParams(contextSize: 64),
            );
            final params =
                _readPrivateForTesting<Map<int, llama_context_params>>(
                  automatic,
                  '_contextParams',
                )[context]!;
            expect(params.op_offload, isFalse);
            expect(params.offload_kqv, isFalse);
          },
          testOn: 'mac-os',
        );
      }

      Matcher noVulkanWarning() => isNot(contains(contains('Vulkan 1.2')));

      test('ComputeDevice.gpu throws and loads nothing when the only '
          'selected device is below Vulkan 1.2', () {
        final service = serviceWith([mali], [maliOld]);

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 64, device: ComputeDevice.gpu),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              'ComputeDevice.gpu is not available for llama.cpp on '
                  "${Platform.operatingSystem}: llama.cpp's Vulkan backend "
                  'needs Vulkan 1.2 or later from both the Vulkan loader and '
                  'the GPU driver, and "Mali-G68" (Vulkan0) reports driver '
                  'API 1.1 with loader API 1.2. Use ComputeDevice.auto to '
                  'run on the CPU instead.',
            ),
          ),
        );
        expect(_readPrivateForTesting<Map>(service, '_models'), isEmpty);
      });

      test('ComputeDevice.auto loads on the CPU with a warning when the only '
          'selected device is below Vulkan 1.2', () {
        final service = serviceWith([mali], [maliOld]);

        final model = service.loadModel(
          modelPath,
          const ModelParams(contextSize: 64),
        );

        expect(service.getResolvedGpuLayers(), 0);
        expect(service.getActiveBackendName(), 'CPU');
        expect(
          warnings,
          contains(
            allOf(
              contains('needs Vulkan 1.2 or later'),
              contains('"Mali-G68" (Vulkan0) reports driver API 1.1'),
              contains('so the model loaded on CPU with 0 GPU layers.'),
            ),
          ),
        );
        // The context follows the load: nothing of it is offloaded.
        final context = service.createContext(
          model,
          const ModelParams(contextSize: 64),
        );
        final contextParams =
            _readPrivateForTesting<Map<int, llama_context_params>>(
              service,
              '_contextParams',
            )[context]!;
        expect(contextParams.offload_kqv, isFalse);
        expect(contextParams.op_offload, isFalse);
      });

      for (final device in [ComputeDevice.auto, ComputeDevice.gpu]) {
        test('${device.name}: a capable discrete GPU is used although an '
            'integrated GPU is on a driver below Vulkan 1.2', () {
          for (final registered in [
            [rtx, uhd],
            // The discrete GPU also registered by CUDA, as the same device.
            [
              entry('CUDA0', deviceId: '0000:01:00.0'),
              entry(
                'Vulkan0',
                description: 'RTX 4090',
                deviceId: '0000:01:00.0',
              ),
              uhd,
            ],
          ]) {
            final service = serviceWith(registered, [rtxOk, uhdOld]);

            service.loadModel(
              modelPath,
              ModelParams(contextSize: 64, device: device),
            );

            expect(service.getResolvedGpuLayers(), greaterThan(0));
            expect(warnings, noVulkanWarning());
          }
        });

        test('${device.name}: a CUDA GPU is used and a discrete Vulkan GPU '
            'below 1.2 is left out of the load', () {
          final service = serviceWith(
            [
              entry('CUDA0', deviceId: '0000:01:00.0'),
              entry(
                'Vulkan0',
                description: 'Mali-G68',
                deviceId: '0000:02:00.0',
              ),
            ],
            [maliOld],
          );

          service.loadModel(
            modelPath,
            ModelParams(contextSize: 64, device: device),
          );

          expect(service.getResolvedGpuLayers(), greaterThan(0));
          expect(
            warnings,
            contains(
              allOf(
                contains('"Mali-G68" (Vulkan0) reports driver API 1.1'),
                contains('so the model loaded without that device, on CUDA0.'),
              ),
            ),
          );
        });

        // ggml-vulkan and the facts can list different devices.
        test('${device.name}: facts that also list a device ggml did not '
            'register are matched by device name, not by position', () {
          final rx = entry('Vulkan1', description: 'RX 7900');
          final rxOk = fact('RX 7900', vulkan13);
          final gtxOld = fact('GTX 660', vulkan11);

          for (final (registered, facts) in [
            ([rtx], [uhdOld, rtxOk]),
            ([rtx, rx], [gtxOld, rtxOk, rxOk]),
            ([rtx, rx], [rtxOk, rxOk, gtxOld]),
            // No facts for one registered device.
            ([rtx, rx], [rtxOk]),
            // Identical GPUs.
            ([rtx, entry('Vulkan1', description: 'RTX 4090')], [rtxOk, rtxOk]),
          ]) {
            warnings.clear();
            final service = serviceWith(registered, facts);

            service.loadModel(
              modelPath,
              ModelParams(contextSize: 64, device: device),
            );

            expect(reads, 1);
            expect(service.getResolvedGpuLayers(), greaterThan(0));
            expect(warnings, noVulkanWarning());
          }
        });
      }

      test('an explicit Vulkan backend is matched by device name too', () {
        final service = serviceWith([rtx], [uhdOld, rtxOk]);

        service.loadModel(
          modelPath,
          const ModelParams(
            contextSize: 64,
            preferredBackend: GpuBackend.vulkan,
          ),
        );

        expect(warnings, noVulkanWarning());
      });

      test('names the registered device that is below Vulkan 1.2, wherever '
          'its facts are listed', () {
        final service = serviceWith(
          [entry('Vulkan0', description: 'GTX 660')],
          [rtxOk, fact('GTX 660', vulkan11)],
        );

        expect(
          () => service.loadModel(
            modelPath,
            const ModelParams(contextSize: 64, device: ComputeDevice.gpu),
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.message,
              'message',
              contains('"GTX 660" (Vulkan0) reports driver API 1.1'),
            ),
          ),
        );
      });

      // The load itself is stopped, so the stand-in devices are never used.
      RecordingExitTeardown stoppedLoads() => RecordingExitTeardown(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      )..fail = (name) => name == 'llama_dart_model_load_from_file';

      test('lists the usable devices for the load when it leaves one out, '
          'and lists none otherwise', () {
        List<int>? listedBy(List<GgmlDeviceEntry> registered) {
          final recorder = stoppedLoads();
          final service = serviceWith(registered, [
            rtxOk,
            fact('GTX 660', vulkan11),
            uhdOld,
          ], objectCalls: LlamaCppObjectCalls.tracked(recorder.api));
          expect(
            () => service.loadModel(
              modelPath,
              const ModelParams(contextSize: 64),
            ),
            throwsA(isA<Exception>()),
          );
          return recorder.loadDevices.single;
        }

        expect(
          listedBy([
            entry('CUDA0', address: 0xC0DA),
            entry('Vulkan0', description: 'RTX 4090', address: 0x1000),
            entry('Vulkan1', description: 'GTX 660', address: 0x2000),
          ]),
          [0xC0DA, 0x1000],
          reason: 'Vulkan1 is below Vulkan 1.2',
        );
        expect(
          listedBy([
            entry('Vulkan0', description: 'RTX 4090', address: 0x1000),
            entry(
              'Vulkan1',
              description: 'UHD Graphics 630',
              type: igpuType,
              address: 0x2000,
            ),
          ]),
          isNull,
          reason: 'llama.cpp does not select the integrated GPU itself',
        );
      });

      test('a speculative draft model is loaded on the same usable '
          'devices', () async {
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        var registered = <GgmlDeviceEntry>[];
        final service = LlamaCppService(
          isMacosX64: false,
          deviceTypes: (_) => [gpuType],
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
          registeredDevices: () => registered,
          vulkanDeviceProbe: () =>
              VulkanDeviceProbe.devices([fact('GTX 660', vulkan11)]),
        );
        addTearDown(service.dispose);
        const params = ModelParams(contextSize: 64, gpuLayers: 0);
        final model = service.loadModel(modelPath, params);
        final context = service.createContext(model, params);
        // The target as a load that kept its layers on a GPU backend this
        // host may not have.
        _readPrivateForTesting<Map<int, String>>(
          service,
          '_modelBackendNames',
        )[model] = 'CUDA';
        _readPrivateForTesting<Map<int, int>>(
          service,
          '_modelResolvedGpuLayers',
        )[model] = 1;
        _readPrivateForTesting<Map<int, ModelParams>>(
          service,
          '_modelLoadParams',
        )[model] = const ModelParams(
          contextSize: 64,
        );
        registered = [
          entry('CUDA0', address: 0xC0DA),
          entry('Vulkan0', description: 'GTX 660', address: 0x2000),
        ];
        recorder.fail = (name) => name == 'llama_dart_model_load_from_file';

        final cancel = calloc<Int8>();
        addTearDown(() => calloc.free(cancel));
        await expectLater(
          service
              .generate(
                context,
                'ab',
                GenerationParams(
                  maxTokens: 2,
                  temp: 0,
                  speculativeDecodingConfig:
                      SpeculativeDecodingConfig.draftSimple(
                        // ignore: deprecated_member_use_from_same_package
                        draftModelPath: modelPath,
                        draftTokenMax: 4,
                      ),
                ),
                cancel.address,
              )
              .drain<void>(),
          throwsA(isA<Exception>()),
        );

        expect(recorder.loadDevices, [
          null,
          [0xC0DA],
        ], reason: 'the target load, then the draft load');
      });

      test('an explicit CUDA backend does not read the Vulkan facts', () {
        final service = serviceWith(
          [
            entry('CUDA0', deviceId: '0000:01:00.0'),
            entry('Vulkan0', description: 'Mali-G68', deviceId: '0000:02:00.0'),
          ],
          [maliOld],
        );

        service.loadModel(
          modelPath,
          const ModelParams(contextSize: 64, preferredBackend: GpuBackend.cuda),
        );

        expect(reads, 0);
        expect(warnings, noVulkanWarning());
      });

      test('does not read the device facts for a CPU load', () {
        final service = serviceWith([mali], [maliOld]);

        service.loadModel(
          modelPath,
          const ModelParams(contextSize: 64, device: ComputeDevice.cpu),
        );
        service.loadModel(
          modelPath,
          const ModelParams(contextSize: 64, gpuLayers: 0),
        );

        expect(reads, 0);
        expect(warnings, noVulkanWarning());
      });

      test('loads on the GPU backend when the selected devices meet Vulkan '
          '1.2 or are unknown', () {
        for (final facts in [
          [fact('Mali-G68', vulkan13)],
          null,
        ]) {
          final service = serviceWith([mali], facts);

          service.loadModel(modelPath, const ModelParams(contextSize: 64));

          expect(reads, 1);
          expect(service.getResolvedGpuLayers(), greaterThan(0));
          expect(warnings, noVulkanWarning());
        }
      });
    });

    // Runs the real llama.cpp runtime: its registry has a CPU device.
    test('reads each registered device with its name, type, registry and '
        'description', () {
      final service = LlamaCppService()..initializeBackend();
      addTearDown(service.dispose);

      final registered = _invokePrivateForTesting<List<GgmlDeviceEntry>>(
        service,
        '_registeredDevices',
        const [],
      );

      final cpu = registered.firstWhere(
        (device) =>
            device.type ==
            ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
      );
      expect(cpu.name, 'CPU');
      expect(cpu.registry, 'CPU');
      expect(cpu.description, isNotEmpty);
      expect(cpu.deviceId, isNull);
      expect(cpu.device, isNot(nullptr));
      expect(cpu.isVulkan, isFalse);
      // The public listings read the same registry.
      expect({
        for (final device in registered)
          device.registry.toLowerCase() == device.name.toLowerCase()
              ? device.registry
              : '${device.registry} (${device.name})',
      }, service.getBackendInfo().toSet());
      for (final gpu in service.listGpuDevices()) {
        final device = registered.singleWhere(
          (entry) => entry.name == gpu.name,
        );
        expect(device.description, gpu.description);
        expect(device.deviceId ?? '', gpu.deviceId);
      }
    });
  });

  group('shouldKeepAndroidVulkanKqvOffloadEnabled', () {
    test('keeps KQV offload enabled for Qwen3.5 architecture metadata', () {
      expect(
        LlamaCppService.shouldKeepAndroidVulkanKqvOffloadEnabled('qwen35'),
        isTrue,
      );
      expect(
        LlamaCppService.shouldKeepAndroidVulkanKqvOffloadEnabled('Qwen3.5'),
        isTrue,
      );
    });

    test('keeps conservative KQV policy for other architectures', () {
      expect(
        LlamaCppService.shouldKeepAndroidVulkanKqvOffloadEnabled('llama'),
        isFalse,
      );
      expect(
        LlamaCppService.shouldKeepAndroidVulkanKqvOffloadEnabled(null),
        isFalse,
      );
    });
  });

  group('resolveMtmdUseGpuForLoad', () {
    test('forces CPU mode to disable projector GPU offload', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.cpu,
      );

      expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
    });

    test(
      'disables projector GPU offload when effective gpu layers are zero',
      () {
        const params = ModelParams(
          gpuLayers: 0,
          preferredBackend: GpuBackend.auto,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
      },
    );

    test(
      'enables projector GPU offload for non-CPU backend with gpu layers',
      () {
        const params = ModelParams(
          gpuLayers: 42,
          preferredBackend: GpuBackend.vulkan,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 42), isTrue);
      },
    );

    test(
      'keeps projector GPU offload disabled after effective CPU fallback',
      () {
        const params = ModelParams(
          gpuLayers: 42,
          preferredBackend: GpuBackend.vulkan,
        );

        expect(LlamaCppService.resolveMtmdUseGpuForLoad(params, 0), isFalse);
      },
    );
  });

  group('parseBackendModuleDirectoryFromProcMaps', () {
    test('extracts lib directory from standard maps entry', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /data/app/~~pkg/lib/arm64/libllamadart.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/data/app/~~pkg/lib/arm64',
      );
    });

    test('handles deleted mapping suffix', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /tmp/libllamadart.so (deleted)
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/tmp',
      );
    });

    test('accepts versioned Linux libllamadart mappings', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /opt/app/lib/libllamadart.so.0
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        '/opt/app/lib',
      );
    });

    test('returns null when libllamadart mapping is missing', () {
      const maps = '''
7f8a0000-7f8b0000 r-xp 00000000 103:04 12345 /system/lib64/libc.so
''';

      expect(
        LlamaCppService.parseBackendModuleDirectoryFromProcMaps(maps),
        isNull,
      );
    });

    test('forces CPU projector mode for Android Qwen3.5 0.8B', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.resolveMtmdUseGpuForLoad(
          params,
          ModelParams.maxGpuLayers,
          modelPath: '/data/user/0/app/models/Qwen3.5-0.8B-Q4_K_M.gguf',
          isAndroid: true,
        ),
        isFalse,
      );
    });

    test('keeps projector GPU path for unrelated Android models', () {
      const params = ModelParams(
        gpuLayers: ModelParams.maxGpuLayers,
        preferredBackend: GpuBackend.vulkan,
      );

      expect(
        LlamaCppService.resolveMtmdUseGpuForLoad(
          params,
          ModelParams.maxGpuLayers,
          modelPath: '/data/user/0/app/models/Llama-3.2-3B.gguf',
          isAndroid: true,
        ),
        isTrue,
      );
    });
  });

  group('resolveWindowsBackendModuleDirectory', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-windows-modules-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test(
      'prefers standard CLI sibling lib over unrelated working directory',
      () {
        final lib = Directory(
          path.join(tempRoot.path, 'portable bundle', 'lib'),
        )..createSync(recursive: true);
        final cwd = Directory(path.join(tempRoot.path, 'unrelated'))
          ..createSync();
        _createWindowsBundleMarkerFiles(lib.path);
        _createWindowsBundleMarkerFiles(cwd.path);
        final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
          resolvedExecutablePath: path.join(lib.parent.path, 'bin', 'app.exe'),
          currentDirectoryPath: cwd.path,
          environment: const {},
        );
        expect(path.normalize(resolved!), path.normalize(lib.path));
      },
    );

    test(
      'CLI layout preserves override and executable-adjacent precedence',
      () {
        final root = Directory(path.join(tempRoot.path, 'portable'))
          ..createSync();
        final bin = Directory(path.join(root.path, 'bin'))..createSync();
        final lib = Directory(path.join(root.path, 'lib'))..createSync();
        final override = Directory(path.join(tempRoot.path, 'override'))
          ..createSync();
        for (final dir in [bin, lib, override]) {
          _createWindowsBundleMarkerFiles(dir.path);
        }
        for (final useOverride in [false, true]) {
          final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
            resolvedExecutablePath: path.join(bin.path, 'app.exe'),
            currentDirectoryPath: tempRoot.path,
            environment: useOverride
                ? {'LLAMADART_NATIVE_LIB_DIR': override.path}
                : const {},
          );
          expect(
            path.normalize(resolved!),
            path.normalize(useOverride ? override.path : bin.path),
          );
        }
      },
    );

    test(
      'incomplete CLI sibling lib preserves valid working directory fallback',
      () {
        final lib = Directory(path.join(tempRoot.path, 'portable', 'lib'))
          ..createSync(recursive: true);
        File(path.join(lib.path, 'llama.dll')).writeAsStringSync('fixture');
        final cwd = Directory(path.join(tempRoot.path, 'working'))
          ..createSync();
        _createWindowsBundleMarkerFiles(cwd.path);
        final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
          resolvedExecutablePath: path.join(lib.parent.path, 'bin', 'app.exe'),
          currentDirectoryPath: cwd.path,
          environment: const {},
        );
        expect(path.normalize(resolved!), path.normalize(cwd.path));
      },
    );

    test('uses explicit environment override when valid', () {
      final overrideDir = Directory(path.join(tempRoot.path, 'override'))
        ..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(overrideDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart.exe'),
        currentDirectoryPath: tempRoot.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': overrideDir.path},
      );

      expect(path.normalize(resolved!), path.normalize(overrideDir.path));
    });

    test('uses altered search path for absolute Windows backend modules', () {
      expect(
        LlamaCppService.windowsBackendModuleLoadFlags(
          path.join(tempRoot.path, 'ggml-cuda.dll'),
        ),
        0x00000008,
      );
      expect(
        LlamaCppService.windowsBackendModuleLoadFlags('ggml-cuda.dll'),
        isZero,
      );
    });

    test('orders CUDA redistributable DLLs for best-effort preloading', () {
      final dependencyPaths = LlamaCppService.windowsBackendDependencyPaths(
        tempRoot.path,
        'cuda',
        fileNames: const <String>[
          'ggml-cuda.dll',
          'cublasLt64_12.dll',
          'notes.txt',
          'cudart64_12.dll',
          'cublas64_12.dll',
        ],
      );

      expect(dependencyPaths, <String>[
        path.join(tempRoot.path, 'cudart64_12.dll'),
        path.join(tempRoot.path, 'cublas64_12.dll'),
        path.join(tempRoot.path, 'cublasLt64_12.dll'),
      ]);
      expect(
        LlamaCppService.windowsBackendDependencyPaths(
          tempRoot.path,
          'vulkan',
          fileNames: const <String>['cudart64_12.dll'],
        ),
        isEmpty,
      );
    });

    test('falls back to hook cache extracted bundle directory', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles_v2',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('ignores legacy hook caches even when their tag sorts newer', () {
      Directory bundle(String root, String tag) {
        final directory = Directory(
          path.join(
            tempRoot.path,
            '.dart_tool',
            'llamadart',
            root,
            tag,
            'windows-x64',
            'extracted',
          ),
        )..createSync(recursive: true);
        _createWindowsBundleMarkerFiles(directory.path);
        return directory;
      }

      final legacy = bundle('native_bundles', 'v9.9.9');
      final compatible = bundle('native_bundles_v2', 'v0.8.0-2');
      String? resolve() => LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'sdk', 'dart.exe'),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolve()!), path.normalize(compatible.path));
      compatible.deleteSync(recursive: true);
      expect(path.normalize(resolve()!), isNot(path.normalize(legacy.path)));
    });

    test('finds custom GitHub hook cache namespace', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles_v2',
          'github',
          'example',
          'native-fork',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('finds local archive hook cache namespace', () {
      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles_v2',
          'local',
          '0123456789abcdef',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(extractedDir.path));
    });

    test('prefers .dart_tool/lib when suffixed native assets are present', () {
      final dartToolLibDir = Directory(
        path.join(tempRoot.path, '.dart_tool', 'lib'),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(
        dartToolLibDir.path,
        suffix: '-windows-x64',
      );

      final extractedDir = Directory(
        path.join(
          tempRoot.path,
          '.dart_tool',
          'llamadart',
          'native_bundles_v2',
          'b8095',
          'windows-x64',
          'extracted',
        ),
      )..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(extractedDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(
          tempRoot.path,
          'dart-sdk',
          'dart.exe',
        ),
        currentDirectoryPath: tempRoot.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(dartToolLibDir.path));
    });

    test('uses current directory when executable dir is not a bundle', () {
      final currentDir = Directory(path.join(tempRoot.path, 'cwd'))
        ..createSync(recursive: true);
      _createWindowsBundleMarkerFiles(currentDir.path);

      final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart.exe'),
        currentDirectoryPath: currentDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(currentDir.path));
    });

    test(
      'falls back to executable directory when no bundle can be detected',
      () {
        final exeDir = Directory(path.join(tempRoot.path, 'bin'))
          ..createSync(recursive: true);
        final resolved = LlamaCppService.resolveWindowsBackendModuleDirectory(
          resolvedExecutablePath: path.join(exeDir.path, 'dart.exe'),
          currentDirectoryPath: tempRoot.path,
          environment: const {},
        );

        expect(path.normalize(resolved!), path.normalize(exeDir.path));
      },
    );
  });

  group('resolveLinuxPrimaryLibraryDirectory', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-linux-primary-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('uses explicit environment override when valid', () {
      final overrideDir = Directory(path.join(tempRoot.path, 'override'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(overrideDir.path);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart'),
        currentDirectoryPath: tempRoot.path,
        environment: {'LLAMADART_NATIVE_LIB_DIR': overrideDir.path},
      );

      expect(path.normalize(resolved!), path.normalize(overrideDir.path));
    });

    test('prefers executable-adjacent lib directory for packaged bundles', () {
      final bundleDir = Directory(path.join(tempRoot.path, 'bundle'))
        ..createSync(recursive: true);
      final executableDir = Directory(path.join(bundleDir.path, 'app'))
        ..createSync(recursive: true);
      final libDir = Directory(path.join(executableDir.path, 'lib'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(libDir.path);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(executableDir.path, 'my_app'),
        currentDirectoryPath: bundleDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(libDir.path));
    });

    test('falls back to current working directory lib folder', () {
      final currentDir = Directory(path.join(tempRoot.path, 'cwd'))
        ..createSync(recursive: true);
      final libDir = Directory(path.join(currentDir.path, 'lib'))
        ..createSync(recursive: true);
      _createLinuxBundleMarkerFiles(libDir.path, versionedPrimary: true);

      final resolved = LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
        resolvedExecutablePath: path.join(tempRoot.path, 'dart'),
        currentDirectoryPath: currentDir.path,
        environment: const {},
      );

      expect(path.normalize(resolved!), path.normalize(libDir.path));
    });
  });

  group('Linux runtime dependency helpers', () {
    late Directory tempRoot;

    setUp(() {
      tempRoot = Directory.systemTemp.createTempSync(
        'llamadart-linux-runtime-helpers-',
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('dependency fallback copies only from the v2 cache', () {
      final target = Directory(path.join(tempRoot.path, '.dart_tool', 'lib'))
        ..createSync(recursive: true);
      File(path.join(target.path, 'libllamadart.so')).writeAsStringSync('');
      final service = LlamaCppService();
      IOOverrides.runZoned(() {
        final bundles = service.debugLinuxBundleNamesForTesting();
        expect(bundles, isNotEmpty);
        expect(
          LlamaCppService.resolveLinuxPrimaryLibraryDirectory(
            resolvedExecutablePath: Platform.resolvedExecutable,
            currentDirectoryPath: tempRoot.path,
            environment: Platform.environment,
          ),
          target.path,
        );
        for (final root in ['native_bundles', 'native_bundles_v2']) {
          for (final bundle in bundles) {
            final source = Directory(
              path.join(
                tempRoot.path,
                '.dart_tool',
                'llamadart',
                root,
                'v0.8.0-2',
                bundle,
                'extracted',
              ),
            )..createSync(recursive: true);
            File(path.join(source.path, 'libggml.so')).writeAsStringSync(root);
            if (root == 'native_bundles') {
              File(
                path.join(source.path, 'libggml-hip.so'),
              ).writeAsStringSync('legacy-only');
            }
          }
        }
        _invokePrivateForTesting<Object?>(
          service,
          '_prepareLinuxRuntimeDependenciesBeforeBinding',
          const <Object?>[],
        );
        expect(
          File(path.join(target.path, 'libggml.so')).readAsStringSync(),
          'native_bundles_v2',
        );
        expect(
          File(path.join(target.path, 'libggml.so.0')).readAsStringSync(),
          'native_bundles_v2',
        );
        expect(
          File(path.join(target.path, 'libggml-hip.so')).existsSync(),
          isFalse,
        );
      }, getCurrentDirectory: () => tempRoot);
    }, skip: !Platform.isLinux);

    test('copyMissingLinuxLibrary copies from the first available source', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourceA = Directory(path.join(tempRoot.path, 'source-a'))
        ..createSync(recursive: true);
      final sourceB = Directory(path.join(tempRoot.path, 'source-b'))
        ..createSync(recursive: true);
      File(path.join(sourceB.path, 'libggml.so')).writeAsStringSync('ggml');

      final diagnostics = <String>[];
      final copied = LlamaCppService.copyMissingLinuxLibrary(
        targetDirectory: targetDir.path,
        sourceDirectories: <String>[sourceA.path, sourceB.path],
        fileName: 'libggml.so',
        onDiagnostic: diagnostics.add,
      );

      expect(copied, isTrue);
      expect(
        File(path.join(targetDir.path, 'libggml.so')).readAsStringSync(),
        'ggml',
      );
      expect(diagnostics, isEmpty);
    });

    test('copyMissingLinuxLibrary reports copy failures', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      Directory(path.join(targetDir.path, 'libggml.so')).createSync();
      final sourceDir = Directory(path.join(tempRoot.path, 'source'))
        ..createSync(recursive: true);
      File(path.join(sourceDir.path, 'libggml.so')).writeAsStringSync('ggml');

      final diagnostics = <String>[];
      final copied = LlamaCppService.copyMissingLinuxLibrary(
        targetDirectory: targetDir.path,
        sourceDirectories: <String>[sourceDir.path],
        fileName: 'libggml.so',
        onDiagnostic: diagnostics.add,
      );

      expect(copied, isFalse);
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single,
        contains('Failed to copy Linux runtime dependency'),
      );
    });

    test('ensureLinuxSonameAlias creates fallback alias when missing', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourcePath = path.join(targetDir.path, 'libllama.so');
      File(sourcePath).writeAsStringSync('llama');

      final diagnostics = <String>[];
      final created = LlamaCppService.ensureLinuxSonameAlias(
        directory: targetDir.path,
        baseFileName: 'libllama.so',
        onDiagnostic: diagnostics.add,
      );

      expect(created, isTrue);
      expect(
        File('$sourcePath.0').existsSync() ||
            Link('$sourcePath.0').existsSync(),
        isTrue,
      );
      expect(diagnostics, isEmpty);
    });

    test('ensureLinuxSonameAlias reports alias creation failures', () {
      final targetDir = Directory(path.join(tempRoot.path, 'target'))
        ..createSync(recursive: true);
      final sourcePath = path.join(targetDir.path, 'libllama.so');
      File(sourcePath).writeAsStringSync('llama');
      Directory('$sourcePath.0').createSync();

      final diagnostics = <String>[];
      final created = LlamaCppService.ensureLinuxSonameAlias(
        directory: targetDir.path,
        baseFileName: 'libllama.so',
        onDiagnostic: diagnostics.add,
      );

      expect(created, isFalse);
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single,
        contains('Failed to create or copy Linux SONAME alias'),
      );
    });
  });

  group('projector load failures', () {
    late LlamaCppService service;
    late int modelHandle;
    late Directory tempDir;
    late String projectorPath;
    late String missingPath;

    setUp(() {
      service = LlamaCppService();
      modelHandle = _registerNullModelForTesting(service);
      tempDir = Directory.systemTemp.createTempSync('llamadart_mmproj_');
      projectorPath = path.join(tempDir.path, 'mmproj.gguf');
      File(projectorPath).writeAsStringSync('GGUF');
      missingPath = path.join(tempDir.path, 'missing.gguf');
      _writePrivateForTesting(service, '_mtmdPrimarySymbolsUnavailable', true);
      _writePrivateForTesting(service, '_mtmdFallbackLookupAttempted', true);
    });

    tearDown(() {
      _readPrivateForTesting<Map<Object?, Object?>>(
        service,
        '_models',
      ).remove(modelHandle);
      tempDir.deleteSync(recursive: true);
    });

    final notFound = throwsA(
      isA<LlamaModelException>().having(
        (error) => error.message,
        'message',
        'Multimodal projector file not found.',
      ),
    );

    Matcher unsupportedFor(String symbol) => throwsA(
      isA<LlamaUnsupportedException>().having(
        (error) => error.message,
        'message',
        allOf(
          contains('`$symbol` cannot run'),
          contains('this package pins ($llamaCppTag)'),
        ),
      ),
    );

    test('reports a missing projector file before any mtmd call', () {
      expect(
        () => service.createMultimodalContext(modelHandle, missingPath),
        notFound,
      );
    });

    test('reports a runtime without mtmd as unsupported', () {
      expect(
        () => service.createMultimodalContext(modelHandle, projectorPath),
        unsupportedFor('mtmd_context_params_default'),
      );
      expect(
        () => _invokePrivateForTesting<Object?>(service, '_mtmdInitFromFile', [
          nullptr,
          nullptr,
          Struct.create<mtmd_context_params>(),
        ]),
        unsupportedFor('mtmd_init_from_file'),
      );
    });

    test('reports an audio probe without mtmd as unsupported', () {
      final mmHandle = _registerMtmdContextForTesting(service);
      addTearDown(
        () => _readPrivateForTesting<Map<Object?, Object?>>(
          service,
          '_mtmdContexts',
        ).remove(mmHandle),
      );

      expect(service.supportsAudio(-1), isFalse);
      expect(
        () => service.supportsAudio(mmHandle),
        unsupportedFor('mtmd_support_audio'),
      );
    });

    test('reports a vision probe without mtmd as unsupported', () {
      final mmHandle = _registerMtmdContextForTesting(service);
      addTearDown(
        () => _readPrivateForTesting<Map<Object?, Object?>>(
          service,
          '_mtmdContexts',
        ).remove(mmHandle),
      );

      expect(service.supportsVision(-1), isFalse);
      expect(
        () => service.supportsVision(mmHandle),
        unsupportedFor('mtmd_support_vision'),
      );
    });

    test('reports each mtmd generation call without mtmd as unsupported', () {
      final calls = <String, (String, List<Object?>)>{
        'mtmd_input_chunks_init': ('_mtmdInputChunksInit', []),
        'mtmd_helper_bitmap_init_from_file': (
          '_mtmdHelperBitmapInitFromFile',
          [nullptr, nullptr],
        ),
        'mtmd_helper_bitmap_init_from_buf': (
          '_mtmdHelperBitmapInitFromBuf',
          [nullptr, nullptr, 0],
        ),
        'mtmd_bitmap_init_from_audio': (
          '_mtmdBitmapInitFromAudio',
          [0, nullptr],
        ),
        'mtmd_tokenize': (
          '_mtmdTokenize',
          [nullptr, nullptr, nullptr, nullptr, 0],
        ),
        'mtmd_helper_eval_chunks': (
          '_mtmdHelperEvalChunks',
          [nullptr, nullptr, nullptr, 0, 0, 1, true, nullptr],
        ),
      };

      for (final MapEntry(key: symbol, value: (member, arguments))
          in calls.entries) {
        expect(
          () => _invokePrivateForTesting<Object?>(service, member, arguments),
          unsupportedFor(symbol),
          reason: member,
        );
      }
    });

    test('keeps the error types across the worker', () async {
      final mmHandle = _registerMtmdContextForTesting(service);
      final workerPort = ReceivePort();
      runLlamaWorkerForTesting(
        workerPort.sendPort,
        service,
        exitOnDispose: false,
      );
      final backend = NativeLlamaBackend(
        initialSendPort: await workerPort.first as SendPort,
      );
      try {
        await expectLater(
          backend.multimodalContextCreate(modelHandle, missingPath),
          notFound,
        );
        await expectLater(
          backend.multimodalContextCreate(modelHandle, projectorPath),
          unsupportedFor('mtmd_context_params_default'),
        );
        await expectLater(
          backend.supportsAudio(mmHandle),
          unsupportedFor('mtmd_support_audio'),
        );
        await expectLater(
          backend.supportsVision(mmHandle),
          unsupportedFor('mtmd_support_vision'),
        );
      } finally {
        _readPrivateForTesting<Map<Object?, Object?>>(
          service,
          '_mtmdContexts',
        ).remove(mmHandle);
        _readPrivateForTesting<Map<Object?, Object?>>(
          service,
          '_models',
        ).remove(modelHandle);
        await backend.dispose();
      }
    });
  });

  test('resolveBackendModuleDirectory returns null on unsupported hosts', () {
    if (Platform.isAndroid || Platform.isLinux || Platform.isWindows) {
      return;
    }

    expect(LlamaCppService.resolveBackendModuleDirectory(), isNull);
  });

  test('Apple wrapper lookup includes embedded framework binary names', () {
    if (!Platform.isMacOS) {
      return;
    }

    final candidates = LlamaCppService()
        .debugLlamadartWrapperLibraryCandidatesForTesting();
    expect(
      candidates,
      contains(endsWith(path.join('llamadart.framework', 'llamadart'))),
    );
    expect(
      candidates,
      contains(endsWith(path.join('llama.framework', 'llama'))),
    );
  });
}

int _registerNullModelForTesting(LlamaCppService service) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final wrapperClass =
      owner.declarations[MirrorSystem.getSymbol('_LlamaModelWrapper', owner)]
          as ClassMirror;
  final model = wrapperClass
      .newInstance(
        Symbol.empty,
        [nullptr, LlamaCppObjectCalls.upstream],
        {#vocabSize: 0, #suppressedTokens: const <int>[]},
      )
      .reflectee;
  final handle = _invokePrivateForTesting<int>(service, '_getHandle', []);
  _readPrivateForTesting<Map<Object?, Object?>>(service, '_models')[handle] =
      model;
  return handle;
}

int _registerMtmdContextForTesting(LlamaCppService service) {
  final handle = _invokePrivateForTesting<int>(service, '_getHandle', []);
  _readPrivateForTesting<Map<Object?, Object?>>(
    service,
    '_mtmdContexts',
  )[handle] = Pointer<mtmd_context>.fromAddress(
    0x10,
  );
  return handle;
}

LlamaCppService _warmedLoadFailureService(String corruptGgufPath) {
  final service = LlamaCppService();
  try {
    service.loadModel(corruptGgufPath, const ModelParams());
  } on Exception {
    // The first controlled failure initializes platform backend discovery.
  }
  _startupDiagnosticsForTesting(service).clear();
  return service;
}

void _recordStartupDiagnosticForTesting(
  LlamaCppService service,
  String diagnostic, {
  StartupDiagnosticCategory category = StartupDiagnosticCategory.causal,
}) {
  _invokePrivateForTesting<void>(
    service,
    '_recordStartupDiagnostic',
    <Object?>[diagnostic],
    category == StartupDiagnosticCategory.causal
        ? const <Symbol, Object?>{}
        : <Symbol, Object?>{#category: category},
  );
}

void _loadDraftModelForTesting(
  LlamaCppService service,
  String path,
  String label,
) {
  _invokePrivateForTesting<Object?>(
    service,
    '_loadSpeculativeDraftModel',
    <Object?>[-1, path, label],
    <Symbol, Object?>{#loadMtp: false},
  );
}

StartupDiagnosticBuffer _startupDiagnosticsForTesting(LlamaCppService service) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
        service,
      ).getField(MirrorSystem.getSymbol('_startupDiagnostics', owner)).reflectee
      as StartupDiagnosticBuffer;
}

T _invokePrivateForTesting<T>(
  LlamaCppService service,
  String member,
  List<Object?> positionalArguments, [
  Map<Symbol, Object?> namedArguments = const <Symbol, Object?>{},
]) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(service)
          .invoke(
            MirrorSystem.getSymbol(member, owner),
            positionalArguments,
            namedArguments,
          )
          .reflectee
      as T;
}

/// [base] with the functions in [overrides], by field name.
GgmlGraphApi _withGgmlOverrides(
  GgmlGraphApi base,
  Map<Symbol, Function> overrides,
) {
  final type = reflectClass(GgmlGraphApi);
  final instance = reflect(base);
  return type.newInstance(
        MirrorSystem.getSymbol('_', type.owner as LibraryMirror),
        const [],
        {
          for (final field
              in type.declarations.values.whereType<VariableMirror>())
            if (!field.isStatic)
              field.simpleName:
                  overrides[field.simpleName] ??
                  instance.getField(field.simpleName).reflectee,
        },
      ).reflectee
      as GgmlGraphApi;
}

T _readPrivateForTesting<T>(LlamaCppService service, String field) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
        service,
      ).getField(MirrorSystem.getSymbol(field, owner)).reflectee
      as T;
}

void _writePrivateForTesting(
  LlamaCppService service,
  String field,
  Object? value,
) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  reflect(service).setField(MirrorSystem.getSymbol(field, owner), value);
}

bool _exportsGgmlBackendLoad(String libraryPath) {
  try {
    return DynamicLibrary.open(libraryPath).providesSymbol('ggml_backend_load');
  } catch (_) {
    return false;
  }
}

String? _locateGgmlRuntimeLibraryForTesting() {
  final pattern = RegExp(
    r'^(lib)?(ggml|ggml-base|llama|llamadart)\.(dylib|so|dll)$',
  );
  final roots = <Directory>[
    Directory(path.join(Directory.current.path, '.dart_tool', 'lib')),
    Directory(
      path.join(
        Directory.current.path,
        '.dart_tool',
        'llamadart',
        'native_bundles_v2',
      ),
    ),
  ];
  for (final root in roots) {
    if (!root.existsSync()) {
      continue;
    }
    final files =
        root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => pattern.hasMatch(path.basename(file.path)))
            .map((file) => file.path)
            .toList()
          ..sort();
    for (final file in files) {
      if (_exportsGgmlBackendLoad(file)) {
        return file;
      }
    }
  }
  return null;
}

void _createWindowsBundleMarkerFiles(
  String directoryPath, {
  String suffix = '',
}) {
  final markerFiles = <String>[
    'llama$suffix.dll',
    'ggml$suffix.dll',
    'ggml-cpu$suffix.dll',
  ];
  for (final fileName in markerFiles) {
    File(path.join(directoryPath, fileName)).writeAsStringSync('');
  }
}

void _createLinuxBundleMarkerFiles(
  String directoryPath, {
  bool versionedPrimary = false,
}) {
  final markerFiles = <String>[
    versionedPrimary ? 'libllamadart.so.0' : 'libllamadart.so',
    'libllama.so',
    'libggml.so',
  ];
  for (final fileName in markerFiles) {
    File(path.join(directoryPath, fileName)).writeAsStringSync('');
  }
}

int _registerDecisionHead(
  LlamaCppService service,
  int modelHandle,
  DecisionHeadRuntime runtime, {
  _EncoderSpy? encoder,
}) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  final headClass =
      owner.declarations[MirrorSystem.getSymbol('_DecisionHead', owner)]
          as ClassMirror;
  final head = headClass.newInstance(Symbol.empty, const [], {
    #modelHandle: modelHandle,
    #context: nullptr,
    #runtime: runtime,
    #hiddenSize: 4,
    #tokenLimit: 4,
    #vocabSize: 10,
    #encode: (encoder ?? _EncoderSpy()).call,
    #freeContext: (Pointer<llama_context> _) {},
  }).reflectee;
  final handle = _invokePrivateForTesting<int>(service, '_getHandle', []);
  _readPrivateForTesting<Map<Object?, Object?>>(
    service,
    '_decisionHeads',
  )[handle] = head;
  return handle;
}

/// Stands in for `llama_encode`, which would abort on the null test context.
final class _EncoderSpy {
  _EncoderSpy({this.fail = true});

  final bool fail;
  final List<List<int>> batches = [];
  final List<String> batchErrors = [];

  static Float32List hiddenFor(List<int> tokens) => Float32List.fromList([
    for (final token in tokens)
      for (var j = 0; j < 4; j++) ((token * 7 + j * 3) % 11 - 5) / 5,
  ]);

  Float32List call(
    Pointer<llama_context> context,
    llama_batch batch,
    int valueCount,
  ) {
    final tokens = [for (var i = 0; i < batch.n_tokens; i++) batch.token[i]];
    batches.add(tokens);
    for (var i = 0; i < tokens.length; i++) {
      if (batch.pos[i] != i ||
          batch.n_seq_id[i] != 1 ||
          batch.seq_id[i][0] != 0 ||
          batch.logits[i] != 1) {
        batchErrors.add('token $i');
      }
    }
    if (fail) {
      throw LlamaInferenceException('The encoder spy refuses to encode.');
    }
    expect(valueCount, tokens.length * 4);
    return hiddenFor(tokens);
  }
}

class _EmbeddingMetadataService extends LlamaCppService {
  _EmbeddingMetadataService(this.metadata);
  final Map<String, String> metadata;
  @override
  Map<String, String> getMetadata(int modelHandle) => metadata;
}

List<int> _hostWithGpu(GpuBackend backend) => [
  ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_GPU.value,
];

class _MetalReportingService extends LlamaCppService {
  _MetalReportingService({
    super.objectCalls,
    super.registeredDevices,
    super.deviceTypes,
  }) : super(isMacosX64: false);

  @override
  List<String> getBackendInfo() => const ['CPU', 'Metal (fake GPU)'];
}
