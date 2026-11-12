@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/config/gpu_backend.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('backend module asset probe', () {
    const candidate = 'package:llamadart/fake-vulkan';
    final firstCandidate = '$candidate-first';

    bool register(
      LlamaCppService service,
      BackendProbeFailures failures, {
      List<String> candidates = const <String>[candidate],
      int? Function(DynamicLibrary)? lookupScore,
      ggml_backend_reg_t Function() Function(DynamicLibrary)? lookupInit,
      bool Function(ggml_backend_reg_t)? register,
    }) => _invoke<bool>(
      service,
      '_tryRegisterBackendModuleViaAsset',
      <Object?>['vulkan', failures],
      {
        #candidates: candidates,
        #open: (String _) => _openSystemLibrary(),
        #lookupScore: ?lookupScore,
        #lookupInit: ?lookupInit,
        #register: ?register,
      },
    );

    ggml_backend_reg_t Function() Function(DynamicLibrary) initReturning(
      ggml_backend_reg_t reg,
    ) =>
        (_) =>
            () => reg;

    test('a candidate that passes score, init and register is loaded', () {
      final service = LlamaCppService();
      final failures = BackendProbeFailures();
      final registered = <ggml_backend_reg_t>[];

      final loaded = register(
        service,
        failures,
        lookupScore: (_) => 5,
        lookupInit: initReturning(Pointer.fromAddress(0x10)),
        register: (reg) {
          registered.add(reg);
          return true;
        },
      );

      expect(loaded, isTrue);
      expect(registered, hasLength(1));
      expect(registered.single.address, 0x10);
      expect(_read<Set<String>>(service, '_loadedBackendModules'), <String>{
        'vulkan',
      });
      expect(
        _read<Map<String, DynamicLibrary>>(
          service,
          '_loadedBackendLibraries',
        ).keys,
        <String>['vulkan'],
      );
      expect(failures.isEmpty, isTrue);
    });

    test('a candidate without a score export stays eligible', () {
      final service = LlamaCppService();
      final failures = BackendProbeFailures();

      final loaded = register(
        service,
        failures,
        lookupInit: initReturning(Pointer.fromAddress(0x10)),
        register: (_) => true,
      );

      expect(loaded, isTrue);
      expect(failures.isEmpty, isTrue);
    });

    test('the default score lookup reads the opened library export', () {
      final fixture = _compileScoreFixture();
      if (fixture == null) {
        markTestSkipped('no C compiler available to build a score export');
        return;
      }
      final service = LlamaCppService();
      final failures = BackendProbeFailures();

      final loaded = _invoke<bool>(
        service,
        '_tryRegisterBackendModuleViaAsset',
        <Object?>['vulkan', failures],
        {
          #candidates: <String>[fixture.path],
          #open: (String _) => DynamicLibrary.open(fixture.path),
        },
      );

      expect(loaded, isFalse);
      expect(
        failures.describe(),
        '`ggml_backend_score` returned 0 (${path.basename(fixture.path)})',
      );
    });

    final rejections =
        <
          String,
          ({
            int? Function(DynamicLibrary)? score,
            ggml_backend_reg_t Function() Function(DynamicLibrary)? init,
            bool Function(ggml_backend_reg_t)? register,
            String reason,
          })
        >{
          'an unsupported score': (
            score: (_) => 0,
            init: null,
            register: null,
            reason: '`ggml_backend_score` returned 0',
          ),
          'a missing init export': (
            score: null,
            init: null,
            register: null,
            reason: 'no `ggml_backend_init` export',
          ),
          'a null registration': (
            score: null,
            init: initReturning(nullptr),
            register: null,
            reason: '`ggml_backend_init` returned null',
          ),
          'a failed registration': (
            score: null,
            init: initReturning(Pointer.fromAddress(0x10)),
            register: (_) => false,
            reason: '`ggml_backend_register` unavailable',
          ),
          'a throwing probe': (
            score: (_) => throw StateError('private detail'),
            init: null,
            register: null,
            reason: 'probe threw StateError',
          ),
        };
    rejections.forEach((name, rejection) {
      test('$name is recorded and loads nothing', () {
        final service = LlamaCppService();
        final failures = BackendProbeFailures();

        final loaded = register(
          service,
          failures,
          lookupScore: rejection.score,
          lookupInit: rejection.init,
          register: rejection.register,
        );

        expect(loaded, isFalse);
        expect(failures.describe(), '${rejection.reason} ($candidate)');
        expect(_read<Set<String>>(service, '_loadedBackendModules'), isEmpty);
        expect(
          _read<Map<String, DynamicLibrary>>(
            service,
            '_loadedBackendLibraries',
          ),
          isEmpty,
        );
      });
    });

    test('a rejected candidate does not stop the next one loading', () {
      final service = LlamaCppService();
      final failures = BackendProbeFailures();
      var scored = 0;

      final loaded = register(
        service,
        failures,
        candidates: <String>[firstCandidate, candidate],
        lookupScore: (_) => scored++ == 0 ? 0 : 5,
        lookupInit: initReturning(Pointer.fromAddress(0x10)),
        register: (_) => true,
      );

      expect(loaded, isTrue);
      expect(scored, 2);
      expect(
        failures.describe(),
        '`ggml_backend_score` returned 0 ($firstCandidate)',
      );
      expect(_read<Set<String>>(service, '_loadedBackendModules'), <String>{
        'vulkan',
      });
    });
  });

  group('Windows ggml code assets', () {
    test('binds the registry through assets despite a module override', () {
      final service = LlamaCppService(isWindows: true);
      _write(service, '_backendModuleDirectory', '/external/runtime');
      final lookedUp = <String>[];
      final countAddress = Pointer.fromFunction<Size Function()>(
        _registryCount,
        0,
      );
      _invoke<void>(service, '_resolveGgmlFallbackFunctions', const [], {
        #assetSymbol: (String symbol) {
          lookedUp.add(symbol);
          return symbol == 'ggml_backend_reg_count'
              ? countAddress
              : Pointer<NativeType>.fromAddress(1);
        },
      });
      final count = _read<int Function()>(
        service,
        '_ggmlBackendRegCountFallback',
      );
      expect(count(), 7);
      expect(lookedUp, hasLength(20));
      expect(lookedUp.toSet(), hasLength(20));
      expect(
        lookedUp,
        containsAll([
          'ggml_backend_load',
          'ggml_backend_register',
          'ggml_backend_reg_count',
          'ggml_backend_reg_get_proc_address',
          'ggml_backend_dev_buffer_type',
        ]),
      );
      _write(service, '_backendModuleDirectory', '/another/runtime');
      _invoke<void>(service, '_resolveGgmlFallbackFunctions', const [], {
        #assetSymbol: (String symbol) => throw StateError('registry changed'),
      });
      expect(count(), 7);
    });

    test('missing optional getters do not reject a compatible registry', () {
      final service = LlamaCppService(isWindows: true);
      final countAddress = Pointer.fromFunction<Size Function()>(
        _registryCount,
        0,
      );
      _invoke<void>(service, '_resolveGgmlFallbackFunctions', const [], {
        #assetSymbol: (String symbol) => symbol == 'ggml_backend_reg_count'
            ? countAddress
            : throw ArgumentError('optional symbol not exported'),
      });
      expect(
        _read<int Function()>(service, '_ggmlBackendRegCountFallback')(),
        7,
      );
      expect(_read<Object?>(service, '_ggmlBackendDevMemoryFallback'), isNull);
      expect(_read<Object?>(service, '_ggmlBackendLoadAllFallback'), isNull);
    });

    test('missing asset symbols are unsupported on every attempt', () {
      final service = LlamaCppService(isWindows: true);
      for (var attempt = 0; attempt < 2; attempt++) {
        expect(
          () => _invoke<void>(
            service,
            '_resolveGgmlFallbackFunctions',
            const [],
            {
              #assetSymbol: (String symbol) =>
                  throw ArgumentError('not exported'),
            },
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains('Windows llama.cpp backend registration'),
            ),
          ),
        );
      }
      expect(_read<Object?>(service, '_ggmlBackendLoadFallback'), isNull);
    });
  });

  group('ggml fallback probe', () {
    List<String> resolve(
      LlamaCppService service,
      List<String> candidates,
      DynamicLibrary Function(String) open,
    ) {
      final opened = <String>[];
      _invoke<void>(service, '_resolveGgmlFallbackFunctions', const [], {
        #candidates: candidates,
        #open: (String candidate) {
          opened.add(candidate);
          return open(candidate);
        },
      });
      return opened;
    }

    test('names every opened candidate that lacks the symbols', () {
      final service = LlamaCppService();

      final opened = resolve(service, <String>[
        '/a/libfake-first.so',
        '/b/libfake-second.so',
      ], (_) => _openSystemLibrary());

      expect(opened, <String>['/a/libfake-first.so', '/b/libfake-second.so']);
      expect(
        _read<String?>(service, '_ggmlRuntimeProbeOutcome'),
        'the opened ggml runtime candidates '
        '(libfake-first.so, libfake-second.so) do not export it',
      );
      expect(_read<Object?>(service, '_ggmlBackendLoadFallback'), isNull);
      expect(service.getStartupDiagnostics(), isEmpty);
    });

    test('separates candidates that opened from those that did not', () {
      final service = LlamaCppService();

      resolve(
        service,
        <String>['/a/libfake-missing.so', '/b/libfake-opened.so'],
        (candidate) => candidate.contains('missing')
            ? throw ArgumentError(
                "Failed to load dynamic library '$candidate': $candidate: "
                'cannot open shared object file: No such file or directory',
              )
            : _openSystemLibrary(),
      );

      expect(
        _read<String?>(service, '_ggmlRuntimeProbeOutcome'),
        'the opened ggml runtime candidates (libfake-opened.so) do not '
        'export it; other candidates: not found (libfake-missing.so)',
      );
    });

    test('reports that no candidate opened', () {
      final service = LlamaCppService();

      resolve(
        service,
        <String>['/a/libfake-missing.so'],
        (candidate) => throw ArgumentError(
          "Failed to load dynamic library '$candidate': $candidate: cannot "
          'open shared object file: No such file or directory',
        ),
      );

      expect(
        _read<String?>(service, '_ggmlRuntimeProbeOutcome'),
        'no ggml runtime candidate opened (not found (libfake-missing.so))',
      );
    });

    test('keeps searching until the symbols are all bound, then stops', () {
      final library = _locateWrapperLibrary();
      if (library == null) {
        markTestSkipped('no built library exports the ggml backend symbols');
        return;
      }
      DynamicLibrary open(String candidate) => candidate == library
          ? DynamicLibrary.open(library)
          : _openSystemLibrary();
      final alone = LlamaCppService();
      resolve(alone, <String>[library], open);
      if (_ggmlFallbackFields.any(
        (field) => _read<Object?>(alone, field) == null,
      )) {
        markTestSkipped('$library does not export every ggml symbol alone');
        return;
      }

      final service = LlamaCppService();
      final opened = resolve(service, <String>[
        '/a/libfake-first.so',
        library,
        '/b/libfake-never.so',
      ], open);

      expect(opened, <String>['/a/libfake-first.so', library]);
    });
  });

  group('ggml fallback candidates', () {
    test('try asset URIs, then the module directory, then bare names', () {
      final moduleDirectory = Directory.systemTemp.createTempSync('ggml-');
      addTearDown(() => moduleDirectory.deleteSync(recursive: true));
      final service = LlamaCppService();
      _write(service, '_backendModuleDirectory', moduleDirectory.path);

      final candidates = _invoke<List<String>>(
        service,
        '_ggmlFallbackCandidates',
        const [],
      );

      final bareNames = candidates.where(
        (candidate) =>
            !candidate.startsWith('package:') &&
            path.basename(candidate) == candidate,
      );
      final inModule = candidates.where(
        (candidate) => path.dirname(candidate) == moduleDirectory.path,
      );
      expect(candidates.first, startsWith('package:'));
      expect(bareNames, isNotEmpty);
      expect(inModule, hasLength(bareNames.length));
      expect(candidates.toList(), <String>[
        ...candidates.where((candidate) => candidate.startsWith('package:')),
        ...inModule,
        ...bareNames,
      ]);
      expect(inModule.map(path.basename), bareNames);
    });
  });

  group('log-level wrapper probe', () {
    void resolve(
      LlamaCppService service,
      List<String> candidates,
      DynamicLibrary Function(String) open,
    ) => _invoke<void>(service, '_resolveLogLevelFallbackFunction', const [], {
      #candidates: candidates,
      #open: open,
    });

    test('a wrapper without the export names the candidate', () {
      final service = LlamaCppService();

      resolve(service, <String>[
        '/a/libfake-wrapper.so',
      ], (_) => _openSystemLibrary());

      expect(
        _read<String?>(service, '_logLevelProbeOutcome'),
        'no `llama_dart_set_log_level` export (libfake-wrapper.so)',
      );
      expect(_read<Object?>(service, '_llamaDartSetLogLevelFallback'), isNull);
    });

    test('the default candidates are the wrapper lookup candidates', () {
      final service = LlamaCppService();
      final expected = service
          .debugLlamadartWrapperLibraryCandidatesForTesting();

      _invoke<void>(service, '_resolveLogLevelFallbackFunction', const []);

      expect(expected, isNotEmpty);
      if (_read<Object?>(service, '_llamaDartSetLogLevelFallback') != null) {
        expect(_read<String?>(service, '_logLevelProbeOutcome'), isNull);
        return;
      }
      final outcome = _read<String?>(service, '_logLevelProbeOutcome');
      expect(outcome, isNot('no candidates'));
      expect(outcome, contains(path.basename(expected.last)));
    });

    test('the default candidates search the module directory', () {
      final moduleDirectory = Directory.systemTemp.createTempSync('log-level-');
      addTearDown(() => moduleDirectory.deleteSync(recursive: true));
      final service = LlamaCppService();
      _write(service, '_backendModuleDirectory', moduleDirectory.path);
      final opened = <String>[];

      _invoke<void>(service, '_resolveLogLevelFallbackFunction', const [], {
        #open: (String candidate) {
          opened.add(candidate);
          return _openSystemLibrary();
        },
      });

      expect(
        opened,
        service.debugLlamadartWrapperLibraryCandidatesForTesting(),
      );
      expect(
        opened.where(
          (candidate) => path.dirname(candidate) == moduleDirectory.path,
        ),
        isNotEmpty,
      );
    });

    test(
      'the default open loads the wrapper with its sibling dependencies',
      () {
        final fixture = _compileWindowsWrapperWithDependency();
        if (fixture == null) {
          markTestSkipped('no gcc available to build a dependent wrapper');
          return;
        }
        final service = LlamaCppService();

        _invoke<void>(service, '_resolveLogLevelFallbackFunction', const [], {
          #candidates: <String>[fixture.path],
        });

        expect(_read<String?>(service, '_logLevelProbeOutcome'), isNull);
        expect(
          _read<Object?>(service, '_llamaDartSetLogLevelFallback'),
          isNotNull,
        );
      },
      skip: Platform.isWindows
          ? null
          : 'sibling DLL lookup follows the altered search path on Windows only',
    );

    test('a wrapper that exports it is bound without an outcome', () {
      final library = _locateWrapperLibrary(symbol: 'llama_dart_set_log_level');
      if (library == null) {
        markTestSkipped('no built library exports llama_dart_set_log_level');
        return;
      }
      final service = LlamaCppService();

      resolve(
        service,
        <String>['/a/libfake-wrapper.so', library],
        (candidate) => candidate == library
            ? DynamicLibrary.open(library)
            : _openSystemLibrary(),
      );

      expect(
        _read<Object?>(service, '_llamaDartSetLogLevelFallback'),
        isNotNull,
      );
      expect(_read<String?>(service, '_logLevelProbeOutcome'), isNull);
    });
  });

  group('bundled backend modules', () {
    late Directory moduleDirectory;
    late LlamaCppService service;

    bool forcesCpuFallback() => _invoke<bool>(
      service,
      '_shouldForceCpuFallbackForMissingPreferredDevices',
      <Object?>[GpuBackend.vulkan],
    );

    setUp(() {
      moduleDirectory = Directory.systemTemp.createTempSync('bundled-modules-');
      service = LlamaCppService();
      _write(service, '_backendModuleDirectory', moduleDirectory.path);
    });

    tearDown(() => moduleDirectory.deleteSync(recursive: true));

    test('a module file in the directory is bundled', () {
      expect(forcesCpuFallback(), isTrue);

      final fileName = Platform.isWindows
          ? 'ggml-vulkan.dll'
          : Platform.isMacOS
          ? 'libggml-vulkan.dylib'
          : 'libggml-vulkan.so';
      File(path.join(moduleDirectory.path, fileName)).writeAsStringSync('');

      expect(forcesCpuFallback(), isFalse);
    });

    test('another backend module does not make the backend bundled', () {
      final fileName = Platform.isWindows
          ? 'ggml-cuda.dll'
          : Platform.isMacOS
          ? 'libggml-cuda.dylib'
          : 'libggml-cuda.so';
      File(path.join(moduleDirectory.path, fileName)).writeAsStringSync('');

      expect(forcesCpuFallback(), isTrue);
    });

    test('a consolidated runtime never forces the fallback', () {
      _write(service, '_backendModuleDirectory', null);

      expect(forcesCpuFallback(), isFalse);
    });
  });

  group('unavailable native APIs', () {
    test('the speculative API names the missing wrapper symbols', () {
      final service = LlamaCppService();
      _write(service, '_speculativeApiLookupAttempted', true);

      expect(
        () => _invoke<Object?>(service, '_resolveSpeculativeApi', const []),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'llama.cpp speculative decoding is unavailable in this native '
                'runtime bundle (missing llama_dart_speculative_* wrapper '
                'symbols). Use the package-pinned native runtime or an '
                'ABI-compatible build.',
          ),
        ),
      );
    });

    test('mtmd contexts get no eval callback without the TTS API', () {
      final service = LlamaCppService();
      _write(service, '_ttsApiLookupAttempted', true);

      expect(service.debugTtsCancelExportsForTesting(), isNull);
      expect(service.debugMtmdEvalCallbackAddressForTesting(), 0);
    });

    test('mtmd contexts get the TTS API eval callback', () {
      final service = LlamaCppService();
      final exports = service.debugTtsCancelExportsForTesting();
      if (exports == null) {
        markTestSkipped('no built library provides the TTS API');
        return;
      }
      final address = service.debugMtmdEvalCallbackAddressForTesting();

      if (exports.evalCallback) {
        expect(address, isNot(0));
      } else {
        expect(address, 0);
      }
    });
  });

  test('the running Linux ABI selects its bundle directory', () {
    final names = LlamaCppService().debugLinuxBundleNamesForTesting();

    expect(names, linuxNativeBundleNames(Abi.current()));
    expect(names, switch (Abi.current()) {
      Abi.linuxX64 => <String>['linux-x64'],
      Abi.linuxArm64 => <String>['linux-arm64'],
      _ => isEmpty,
    });
  }, skip: Platform.isLinux ? null : 'selects bundles on Linux only');

  group('Linux native bundle names', () {
    test('map the Linux ABIs to their bundle directories', () {
      expect(linuxNativeBundleNames(Abi.linuxX64), <String>['linux-x64']);
      expect(linuxNativeBundleNames(Abi.linuxArm64), <String>['linux-arm64']);
    });

    test('other ABIs have none', () {
      for (final abi in <Abi>[
        Abi.macosArm64,
        Abi.windowsX64,
        Abi.androidArm64,
        Abi.linuxRiscv64,
      ]) {
        expect(linuxNativeBundleNames(abi), isEmpty, reason: abi.toString());
      }
    });
  });
}

({String path})? _compileScoreFixture() {
  if (Platform.isWindows) {
    return null;
  }
  final directory = Directory.systemTemp.createTempSync('score-fixture-');
  addTearDown(() => directory.deleteSync(recursive: true));
  final source = File(path.join(directory.path, 'score.c'))
    ..writeAsStringSync('int ggml_backend_score(void) { return 0; }\n');
  final output = path.join(
    directory.path,
    Platform.isMacOS ? 'libscore.dylib' : 'libscore.so',
  );
  try {
    final result = Process.runSync('cc', <String>[
      '-shared',
      '-fPIC',
      '-o',
      output,
      source.path,
    ]);
    return result.exitCode == 0 ? (path: output) : null;
  } on ProcessException {
    return null;
  }
}

/// A wrapper DLL that exports `llama_dart_set_log_level` and imports a DLL
/// beside it, which Windows finds only on the altered search path.
({String path})? _compileWindowsWrapperWithDependency() {
  final directory = Directory.systemTemp.createTempSync('wrapper-fixture-');
  addTearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // The loaded DLLs stay locked until the process exits.
    }
  });
  File(path.join(directory.path, 'dep.c')).writeAsStringSync(
    '__declspec(dllexport) int probe_dependency(void) { return 7; }\n',
  );
  File(path.join(directory.path, 'wrapper.c')).writeAsStringSync(
    '__declspec(dllimport) int probe_dependency(void);\n'
    '__declspec(dllexport) void llama_dart_set_log_level(int level) {\n'
    '  (void)level;\n'
    '  (void)probe_dependency();\n'
    '}\n',
  );
  final dependency = path.join(directory.path, 'probe_dependency.dll');
  final wrapper = path.join(directory.path, 'wrapper.dll');
  try {
    final steps = <List<String>>[
      ['-shared', '-o', dependency, path.join(directory.path, 'dep.c')],
      [
        '-shared',
        '-o',
        wrapper,
        path.join(directory.path, 'wrapper.c'),
        dependency,
      ],
    ];
    for (final step in steps) {
      if (Process.runSync('gcc', step).exitCode != 0) {
        return null;
      }
    }
    return (path: wrapper);
  } on ProcessException {
    return null;
  }
}

DynamicLibrary _openSystemLibrary() => DynamicLibrary.open(
  Platform.isWindows
      ? 'kernel32.dll'
      : Platform.isMacOS
      ? '/usr/lib/libSystem.B.dylib'
      : 'libc.so.6',
);

const _ggmlFallbackFields = <String>[
  '_ggmlBackendLoadFallback',
  '_ggmlBackendLoadAllFallback',
  '_ggmlBackendLoadAllFromPathFallback',
  '_ggmlBackendRegisterFallback',
  '_ggmlBackendRegCountFallback',
  '_ggmlBackendRegGetFallback',
  '_ggmlBackendRegNameFallback',
  '_ggmlBackendRegByNameFallback',
  '_ggmlBackendRegDevCountFallback',
  '_ggmlBackendRegDevGetFallback',
  '_ggmlBackendDevCountFallback',
  '_ggmlBackendDevGetFallback',
  '_ggmlBackendDevNameFallback',
  '_ggmlBackendDevBackendRegFallback',
  '_ggmlBackendDevByTypeFallback',
  '_ggmlBackendDevTypeFallback',
  '_ggmlBackendDevGetPropsFallback',
  '_ggmlBackendDevMemoryFallback',
];

String? _locateWrapperLibrary({String symbol = 'ggml_backend_load'}) {
  final fileName = Platform.isWindows
      ? 'llamadart.dll'
      : Platform.isMacOS
      ? 'libllamadart.dylib'
      : 'libllamadart.so';
  final library = path.absolute('.dart_tool', 'lib', fileName);
  if (!File(library).existsSync()) {
    return null;
  }
  try {
    return DynamicLibrary.open(library).providesSymbol(symbol) ? library : null;
  } catch (_) {
    return null;
  }
}

LibraryMirror get _serviceLibrary =>
    reflectClass(LlamaCppService).owner as LibraryMirror;

T _invoke<T>(
  LlamaCppService service,
  String member,
  List<Object?> positionalArguments, [
  Map<Symbol, Object?> namedArguments = const <Symbol, Object?>{},
]) =>
    reflect(service)
            .invoke(
              MirrorSystem.getSymbol(member, _serviceLibrary),
              positionalArguments,
              namedArguments,
            )
            .reflectee
        as T;

T _read<T>(LlamaCppService service, String field) =>
    reflect(
          service,
        ).getField(MirrorSystem.getSymbol(field, _serviceLibrary)).reflectee
        as T;

void _write(LlamaCppService service, String field, Object? value) {
  reflect(
    service,
  ).setField(MirrorSystem.getSymbol(field, _serviceLibrary), value);
}

int _registryCount() => 7;
