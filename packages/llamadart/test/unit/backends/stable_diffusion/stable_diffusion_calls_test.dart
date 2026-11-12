@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_calls.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_runtime_io.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';

// The exports image generation depends on.
const _symbols = [
  'sd_dart_progress_enable',
  'sd_dart_progress_read',
  'sd_dart_new_sd_ctx',
  'sd_dart_generate_image',
  'sd_dart_cancel_generation',
  'sd_dart_exit_free',
];

// The exports of stable-diffusion-native v0.2.0-2 it works without.
const _logSymbols = [
  'sd_dart_log_enable',
  'sd_dart_log_set_level',
  'sd_dart_log_read',
  'sd_dart_log_dropped',
  'sd_dart_last_error',
];
const _deviceMemorySymbols = [
  'sd_dart_gpu_device_count',
  'sd_dart_gpu_device_memory',
];

// Upstream master-1017's, which v0.3.0-1 first ships.
const _fp8MetalSymbols = ['free_sd_image_generation_result'];

// The root package does not bundle the stable_diffusion runtime, so these
// tests resolve the functions from stand-ins. That each name resolves to the
// runtime's own export is checked against the real runtime by
// example/basic_app/test/image_exit_teardown_e2e_test.dart.
void main() {
  test('binds every sd_dart_ function through the lookup, and resolves '
      'nothing when one is missing', () {
    final requested = <String>[];
    Pointer<NativeType> exported(String name) {
      requested.add(name);
      return Pointer.fromAddress(0x1000 + requested.length);
    }

    expect(StableDiffusionCalls.tryResolve(symbol: exported), isNotNull);
    expect(
      requested,
      unorderedEquals([
        ..._symbols,
        ..._logSymbols,
        ..._deviceMemorySymbols,
        ..._fp8MetalSymbols,
        'sd_dart_new_sd_ctx_intrinsic_tiny_v1',
      ]),
    );
    expect(StableDiffusionCalls.wrapperSymbols, unorderedEquals(_symbols));

    for (final missing in _symbols) {
      expect(
        StableDiffusionCalls.tryResolve(
          symbol: (name) => name == missing
              ? throw ArgumentError("Couldn't resolve native function '$name'")
              : exported(name),
        ),
        isNull,
        reason: missing,
      );
    }
  });

  test('a runtime of v0.2.0-1, without the log and device memory functions, '
      'resolves with both absent', () {
    final calls = StableDiffusionCalls.tryResolve(
      symbol: (name) => _symbols.contains(name)
          ? Pointer.fromAddress(0x1000)
          : throw ArgumentError("Couldn't resolve native function '$name'"),
    );

    expect(calls, isNotNull);
    expect(calls!.log, isNull);
    expect(calls.gpu, isNull);
  });

  test('the log and the GPU queries are each bound only when the runtime '
      'exports all of their functions, one without the other', () {
    expect(StableDiffusionCalls.logSymbols, unorderedEquals(_logSymbols));
    expect(
      StableDiffusionCalls.deviceMemorySymbols,
      unorderedEquals(_deviceMemorySymbols),
    );
    expect(StableDiffusionCalls.optionalNativeRelease, 'v0.2.0-2');

    StableDiffusionCalls without(String missing) =>
        StableDiffusionCalls.tryResolve(
          symbol: (name) => name == missing
              ? throw ArgumentError("Couldn't resolve native function '$name'")
              : Pointer.fromAddress(0x1000),
        )!;

    for (final missing in _logSymbols) {
      final calls = without(missing);
      expect(calls.log, isNull, reason: missing);
      expect(calls.gpu, isNotNull, reason: missing);
    }
    for (final missing in _deviceMemorySymbols) {
      final calls = without(missing);
      expect(calls.gpu, isNull, reason: missing);
      expect(calls.log, isNotNull, reason: missing);
    }
  });

  test(
    'the intrinsic tiny-decoder contract is optional and versioned by its export',
    () {
      final absent = StableDiffusionCalls.tryResolve(
        symbol: (name) => name == 'sd_dart_new_sd_ctx_intrinsic_tiny_v1'
            ? throw ArgumentError('missing')
            : Pointer.fromAddress(0x1000),
      );
      expect(absent, isNotNull);
      expect(absent!.newContextIntrinsicTinyV1, isNull);
      final present = StableDiffusionCalls.tryResolve(
        symbol: (_) => Pointer.fromAddress(0x1000),
      );
      expect(present!.newContextIntrinsicTinyV1, isNotNull);
    },
  );

  group('loadsFp8AsF16OnMetal', () {
    StableDiffusionCalls resolve({
      String? releaseTag,
      Set<String> missing = const {},
    }) {
      Pointer<NativeType> symbol(String name) => missing.contains(name)
          ? throw ArgumentError("Couldn't resolve native function '$name'")
          : Pointer.fromAddress(0x1000);
      return releaseTag == null
          ? StableDiffusionCalls.tryResolve(symbol: symbol)!
          : StableDiffusionCalls.tryResolve(
              symbol: symbol,
              releaseTag: releaseTag,
            )!;
    }

    test('holds for the pinned release when it exports the upstream 1017 '
        'functions', () {
      expect(StableDiffusionCalls.fp8MetalSymbols, _fp8MetalSymbols);
      expect(StableDiffusionCalls.fp8MetalNativeRelease, 'v0.3.0-1');
      expect(resolve().loadsFp8AsF16OnMetal, isTrue);
      for (final tag in ['v0.3.0-1', 'v0.3.0-2', 'v0.3.0-10', 'v0.3.1']) {
        expect(
          resolve(releaseTag: tag).loadsFp8AsF16OnMetal,
          isTrue,
          reason: tag,
        );
      }
      expect(resolve(releaseTag: 'v1.0.0').loadsFp8AsF16OnMetal, isTrue);
    });

    test('fails closed for an older runtime in the process, which still '
        'generates', () {
      final calls = resolve(missing: _fp8MetalSymbols.toSet());

      expect(calls.loadsFp8AsF16OnMetal, isFalse);
      expect(calls.log, isNotNull);
      expect(calls.gpu, isNotNull);
    });

    test('fails closed for a pin older than v0.3.0-1 or not a release tag, '
        'even with the upstream 1017 functions', () {
      for (final tag in [
        'v0.3.0',
        'v0.2.0-4',
        'v0.2.9-9',
        'b1234',
        'latest',
        'v0.3.0-01',
        '',
      ]) {
        expect(
          resolve(releaseTag: tag).loadsFp8AsF16OnMetal,
          isFalse,
          reason: tag,
        );
      }
    });
  });

  test('calls the function exported under the name of each of its '
      'members', () {
    final exports = _RecordingExports();
    addTearDown(exports.close);
    final calls = StableDiffusionCalls.tryResolve(symbol: exports.symbol)!;

    final members = <String, void Function()>{
      'sd_dart_progress_enable': calls.progressEnable,
      'sd_dart_new_sd_ctx': () => calls.newContext(nullptr),
      'sd_dart_new_sd_ctx_intrinsic_tiny_v1': () =>
          calls.newContextIntrinsicTinyV1!(nullptr),
      'sd_dart_generate_image': () =>
          calls.generateImage(nullptr, nullptr, nullptr, nullptr),
      'sd_dart_cancel_generation': () => calls.cancelGeneration(nullptr),
      'sd_dart_exit_free': () => calls.exitFree(nullptr),
      'sd_dart_log_enable': calls.log!.enable,
      'sd_dart_log_set_level': () => calls.log!.setLevel(3),
      'sd_dart_log_read': () =>
          expect(calls.log!.read(41, nullptr, 0, nullptr, nullptr), 42),
      'sd_dart_log_dropped': () => expect(calls.log!.dropped(), 7),
      'sd_dart_last_error': () => expect(calls.log!.lastError(nullptr, 9), 9),
      'sd_dart_gpu_device_count': () => expect(calls.gpu!.deviceCount(), 2),
      'sd_dart_gpu_device_memory': () =>
          expect(calls.gpu!.deviceMemory(1, nullptr), -3),
    };
    for (final MapEntry(key: name, value: call) in members.entries) {
      exports.called.clear();
      call();
      expect(exports.called, [name]);
    }
    expect(exports.cancelMode, sd.sd_cancel_mode_t.SD_CANCEL_ALL.value);
    expect(exports.logLevel, 3);
    expect(exports.deviceIndex, 1);
    expect(calls.exitFreeAddress, exports.symbol('sd_dart_exit_free'));

    // sd_dart_progress_read is a leaf call, which cannot call back into
    // Dart, so memcpy stands in for it: called as
    // (destination, source, length, ignored) it copies and returns its
    // destination.
    using((arena) {
      final source = arena<Uint8>(4)..asTypedList(4).setAll(0, [9, 8, 7, 6]);
      final destination = arena<Uint8>(4);
      expect(
        calls.progressRead(destination.address, source.cast(), 4, nullptr),
        destination.address,
      );
      expect(destination.asTypedList(4), [9, 8, 7, 6]);
    });
  });

  test(
    'resolves nothing from a process without the runtime',
    () {
      expect(StableDiffusionCalls.tryResolve(), isNull);
    },
    skip: probeStableDiffusionRuntime().isAvailable
        ? 'the stable_diffusion runtime is bundled here'
        : false,
  );

  test('the unsupported error names the functions, the release that has them '
      'and the pinned release', () {
    final message = stableDiffusionWrapperUnsupported().message;

    for (final symbol in _symbols) {
      expect(message, contains(symbol));
    }
    for (final symbol in [..._logSymbols, ..._deviceMemorySymbols]) {
      expect(message, isNot(contains(symbol)));
    }
    expect(message, contains('stable-diffusion-native v0.2.0-1 or later'));
    expect(message, contains('pinned release $stableDiffusionReleaseTag'));
  });

  group('generated bindings', () {
    final bindings = File(
      'lib/src/backends/stable_diffusion/stable_diffusion_bindings.dart',
    ).readAsStringSync();

    test('leave out the functions that are not safe from an isolate', () {
      for (final name in const [
        'sd_dart_exit_teardown',
        'sd_dart_exit_call_begin',
        'sd_dart_exit_call_end',
        'sd_dart_exit_track',
        'sd_dart_exit_untrack',
      ]) {
        expect(bindings, isNot(contains(RegExp('$name\\b'))), reason: name);
      }
    });

    // sd_dart_log_read and sd_dart_last_error can wait 100 ms for another
    // thread, and the first device query initializes the GPU backend.
    test('bind only sd_dart_progress_read as a leaf call', () {
      final leaves = RegExp(
        r'isLeaf: true\)\s*external \w[\w<>.]* (\w+)\(',
      ).allMatches(bindings).map((match) => match.group(1));

      expect(leaves, ['sd_dart_progress_read']);
      expect('isLeaf'.allMatches(bindings), hasLength(1));
    });
  });
}

/// A stand-in export for each `sd_dart_` function, which records its name
/// when called.
final class _RecordingExports {
  final List<String> called = <String>[];
  int? cancelMode;
  int? logLevel;
  int? deviceIndex;

  late final Map<String, NativeCallable<Function>> _functions = {
    'sd_dart_progress_enable': NativeCallable<Void Function()>.isolateLocal(
      () => _record('sd_dart_progress_enable', null),
    ),
    'sd_dart_new_sd_ctx':
        NativeCallable<
          Pointer<sd.sd_ctx_t> Function(Pointer<sd.sd_ctx_params_t>)
        >.isolateLocal(
          (Pointer<sd.sd_ctx_params_t> _) =>
              _record('sd_dart_new_sd_ctx', nullptr.cast<sd.sd_ctx_t>()),
        ),
    'sd_dart_new_sd_ctx_intrinsic_tiny_v1':
        NativeCallable<
          Pointer<sd.sd_ctx_t> Function(Pointer<sd.sd_ctx_params_t>)
        >.isolateLocal(
          (Pointer<sd.sd_ctx_params_t> _) => _record(
            'sd_dart_new_sd_ctx_intrinsic_tiny_v1',
            nullptr.cast<sd.sd_ctx_t>(),
          ),
        ),
    'sd_dart_generate_image':
        NativeCallable<
          Bool Function(
            Pointer<sd.sd_ctx_t>,
            Pointer<sd.sd_img_gen_params_t>,
            Pointer<Pointer<sd.sd_image_t>>,
            Pointer<Int>,
          )
        >.isolateLocal(
          (
            Pointer<sd.sd_ctx_t> _,
            Pointer<sd.sd_img_gen_params_t> _,
            Pointer<Pointer<sd.sd_image_t>> _,
            Pointer<Int> _,
          ) => _record('sd_dart_generate_image', false),
          exceptionalReturn: false,
        ),
    'sd_dart_cancel_generation':
        NativeCallable<
          Void Function(Pointer<sd.sd_ctx_t>, UnsignedInt)
        >.isolateLocal((Pointer<sd.sd_ctx_t> _, int mode) {
          cancelMode = mode;
          _record('sd_dart_cancel_generation', null);
        }),
    'sd_dart_exit_free':
        NativeCallable<Void Function(Pointer<Void>)>.isolateLocal(
          (Pointer<Void> _) => _record('sd_dart_exit_free', null),
        ),
    'sd_dart_log_enable': NativeCallable<Void Function()>.isolateLocal(
      () => _record('sd_dart_log_enable', null),
    ),
    'sd_dart_log_set_level': NativeCallable<Void Function(Int32)>.isolateLocal((
      int level,
    ) {
      logLevel = level;
      _record('sd_dart_log_set_level', null);
    }),
    'sd_dart_log_read':
        NativeCallable<
          Uint64 Function(
            Uint64,
            Pointer<Char>,
            Size,
            Pointer<Int32>,
            Pointer<Size>,
          )
        >.isolateLocal(
          (
            int after,
            Pointer<Char> _,
            int _,
            Pointer<Int32> _,
            Pointer<Size> _,
          ) => _record('sd_dart_log_read', after + 1),
          exceptionalReturn: 0,
        ),
    'sd_dart_log_dropped': NativeCallable<Uint64 Function()>.isolateLocal(
      () => _record('sd_dart_log_dropped', 7),
      exceptionalReturn: 0,
    ),
    'sd_dart_last_error':
        NativeCallable<Size Function(Pointer<Char>, Size)>.isolateLocal(
          (Pointer<Char> _, int capacity) =>
              _record('sd_dart_last_error', capacity),
          exceptionalReturn: 0,
        ),
    'sd_dart_gpu_device_count': NativeCallable<Int32 Function()>.isolateLocal(
      () => _record('sd_dart_gpu_device_count', 2),
      exceptionalReturn: 0,
    ),
    'sd_dart_gpu_device_memory':
        NativeCallable<
          Int32 Function(Int32, Pointer<sd.sd_dart_gpu_device_memory_t>)
        >.isolateLocal((int index, Pointer<sd.sd_dart_gpu_device_memory_t> _) {
          deviceIndex = index;
          return _record('sd_dart_gpu_device_memory', -3);
        }, exceptionalReturn: 0),
  };

  T _record<T>(String name, T result) {
    called.add(name);
    return result;
  }

  Pointer<NativeType> symbol(String name) => name == 'sd_dart_progress_read'
      ? _memcpy
      : _functions[name]?.nativeFunction ??
            (throw ArgumentError("Couldn't resolve native function '$name'"));

  void close() {
    for (final function in _functions.values) {
      function.close();
    }
  }
}

final Pointer<NativeType> _memcpy =
    (Platform.isWindows
            ? DynamicLibrary.open('msvcrt.dll')
            : DynamicLibrary.process())
        .lookup('memcpy');
