@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/backends/llama_cpp/vulkan_device_probe.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

const _llamadartWrapperAssetId = 'package:llamadart/llamadart_wrapper';
const _llamadartPrimaryAssetId = 'package:llamadart/llamadart';

const _genericSpeculativeSymbols = [
  'llama_dart_speculative_init',
  'llama_dart_speculative_free',
  'llama_dart_speculative_get_draft_context',
  'llama_dart_speculative_need_embd_nextn',
  'llama_dart_speculative_begin',
  'llama_dart_speculative_process_batch',
  'llama_dart_speculative_draft',
  'llama_dart_speculative_accept',
  'llama_dart_sampler_sample_and_accept_n',
];

const _b10514BindingSymbols = [
  'ggml_rope_set_offset',
  'mtmd_bitmap_set_mergeable',
  'mtmd_input_chunk_get_placeholder',
];

const _b10514MtmdSymbols = [
  'mtmd_bitmap_set_mergeable',
  'mtmd_input_chunk_get_placeholder',
];

const _mtmdChunkEvalSymbols = [
  'mtmd_input_chunks_size',
  'mtmd_input_chunks_get',
  'mtmd_input_chunk_get_type',
  'mtmd_input_chunk_get_n_tokens',
  'mtmd_decode_use_non_causal',
  'mtmd_helper_eval_chunk_single',
  'mtmd_encode_chunk',
  'mtmd_get_output_embd',
  'mtmd_helper_decode_image_chunk',
];

const _ttsCancelSymbols = [
  'llama_dart_tts_eval_callback',
  'llama_dart_tts_set_cancel_flag',
];

const _exitTeardownSymbols = [
  'llama_dart_exit_track',
  'llama_dart_exit_untrack',
  'llama_dart_exit_free',
  'llama_dart_model_load_from_file',
  'llama_dart_init_from_model',
  'llama_dart_mtmd_init_from_file',
  'llama_dart_decode',
  'llama_dart_encode',
  'llama_dart_synchronize',
  'llama_dart_sampler_sample',
  'llama_dart_state_save_file',
  'llama_dart_state_load_file',
  'llama_dart_state_seq_get_size_ext',
  'llama_dart_state_seq_get_data_ext',
  'llama_dart_state_seq_set_data_ext',
  'llama_dart_adapter_lora_init',
  'llama_dart_mtmd_tokenize',
  'llama_dart_mtmd_encode_chunk',
  'llama_dart_mtmd_helper_eval_chunks',
  'llama_dart_mtmd_helper_eval_chunk_single',
  'llama_dart_mtmd_helper_decode_image_chunk',
];

const _barrierSymbols = [
  'llama_dart_last_error',
  'llama_dart_clear_last_error',
  'llama_dart_sampler_accept',
  'llama_dart_sampler_init_grammar_lazy_patterns',
  'llama_dart_tokenize',
  'llama_dart_token_to_piece',
  'llama_dart_memory_clear',
  'llama_dart_mtmd_bitmap_init_from_audio',
  'llama_dart_mtmd_bitmap_init_from_buf',
  'llama_dart_mtmd_bitmap_init_from_file',
  'llama_dart_ggml_backend_dev_init',
  'llama_dart_ggml_backend_dev_memory',
  'llama_dart_ggml_backend_dev_get_props',
  'llama_dart_ggml_backend_alloc_ctx_tensors',
  'llama_dart_ggml_backend_tensor_set',
  'llama_dart_ggml_backend_tensor_get',
  'llama_dart_ggml_backend_sched_alloc_graph',
  'llama_dart_ggml_backend_sched_synchronize',
];

const _vulkanDeviceSymbols = [
  'llama_dart_vulkan_get_device_count',
  'llama_dart_vulkan_get_device_info',
];

// Returns an enum, so ffigen binds it under a private name behind a wrapper.
const _exitTeardownGraphComputeSymbol =
    'llama_dart_ggml_backend_sched_graph_compute';

// Not kill-safe from Dart, so the bindings must not offer them.
const _unboundExitTeardownSymbols = [
  'llama_dart_exit_call_begin',
  'llama_dart_exit_call_end',
  'llama_dart_exit_teardown',
];

const _aloraMetadataSymbols = [
  'llama_adapter_get_alora_n_invocation_tokens',
  'llama_adapter_get_alora_invocation_tokens',
];

const _transparentPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

typedef _MtmdHelperBitmapInitFromBufNative =
    mtmd_helper_bitmap_wrapper Function(
      ffi.Pointer<mtmd_context>,
      ffi.Pointer<ffi.UnsignedChar>,
      ffi.Size,
      ffi.Bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdHelperBitmapInitFromBufDart =
    mtmd_helper_bitmap_wrapper Function(
      ffi.Pointer<mtmd_context>,
      ffi.Pointer<ffi.UnsignedChar>,
      int,
      bool,
      mtmd_helper_init_opt,
    );
typedef _MtmdBitmapFreeNative = ffi.Void Function(ffi.Pointer<mtmd_bitmap>);
typedef _MtmdBitmapFreeDart = void Function(ffi.Pointer<mtmd_bitmap>);

File? _llamadartWrapperLibraryFileOrNull() {
  if (Platform.isWindows) {
    try {
      return _windowsMtpWrapperLibraryFile();
    } catch (_) {
      return null;
    }
  }

  final nativeAssetPath =
      _nativeAssetFilePath(_llamadartWrapperAssetId) ??
      _nativeAssetFilePath(_llamadartPrimaryAssetId);
  if (nativeAssetPath == null) {
    return null;
  }
  final file = File(nativeAssetPath);
  return file.existsSync() ? file : null;
}

File? _llamadartPrimaryLibraryFileOrNull() {
  final nativeAssetPath = _nativeAssetFilePath(_llamadartPrimaryAssetId);
  if (nativeAssetPath == null) {
    return null;
  }
  final file = File(nativeAssetPath);
  return file.existsSync() ? file : null;
}

File _windowsMtpWrapperLibraryFile() {
  final dartToolLibPath = [
    Directory.current.path,
    '.dart_tool',
    'lib',
  ].join(Platform.pathSeparator);
  final dartToolLibDir = Directory(dartToolLibPath);
  final candidates = <String>[
    ?_nativeAssetFilePath(_llamadartWrapperAssetId),
    ?_nativeAssetFilePath(_llamadartPrimaryAssetId),
    ..._matchingWindowsLibraryPaths(
      dartToolLibDir,
      RegExp(r'^llamadart(?:[-_][^.\\/]+)*\.dll$'),
    ),
    [dartToolLibPath, 'llamadart_wrapper.dll'].join(Platform.pathSeparator),
    [dartToolLibPath, 'llamadart.dll'].join(Platform.pathSeparator),
    'llamadart_wrapper.dll',
    'llamadart.dll',
  ];

  final tried = <String>{};
  for (final candidate in candidates) {
    if (!tried.add(candidate)) {
      continue;
    }

    final file = File(candidate);
    if (file.existsSync()) {
      return file;
    }
  }

  throw StateError(
    'Unable to find Windows llama.cpp MTP wrapper library. '
    'Tried: ${tried.join(', ')}.',
  );
}

File? _mtmdFallbackLibraryFile() {
  final fileNamePattern = _mtmdFallbackLibraryPattern();
  if (fileNamePattern == null) {
    return null;
  }

  final dartToolLibPath = [
    Directory.current.path,
    '.dart_tool',
    'lib',
  ].join(Platform.pathSeparator);
  final directories = <Directory>[];
  final nativeAssetPath =
      _nativeAssetFilePath(_llamadartWrapperAssetId) ??
      _nativeAssetFilePath(_llamadartPrimaryAssetId);
  if (nativeAssetPath != null) {
    directories.add(File(nativeAssetPath).parent);
  }
  directories.add(Directory(dartToolLibPath));
  directories.add(Directory.current);

  final tried = <String>{};
  for (final directory in directories) {
    final directoryPath = directory.path;
    if (!tried.add(directoryPath)) {
      continue;
    }

    final matches = _matchingLibraryPaths(directory, fileNamePattern);
    if (matches.isNotEmpty) {
      return File(matches.first);
    }
  }

  return null;
}

RegExp? _mtmdFallbackLibraryPattern() {
  if (Platform.isWindows) {
    return RegExp(r'^mtmd(?:[-_][^.\\/]+)*\.dll$');
  }
  if (Platform.isLinux || Platform.isAndroid) {
    return RegExp(r'^libmtmd(?:[-_][^.\\/]+)*\.so$');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return RegExp(r'^libmtmd(?:[-_][^.\\/]+)*\.dylib$');
  }
  return null;
}

bool _fileContainsAscii(File file, String text) {
  final bytes = file.readAsBytesSync();
  final pattern = ascii.encode(text);
  if (pattern.isEmpty || bytes.length < pattern.length) {
    return false;
  }

  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var matched = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return true;
    }
  }
  return false;
}

void _expectDynamicLibraryExports(File libraryFile, Iterable<String> symbols) {
  final library = ffi.DynamicLibrary.open(libraryFile.path);
  for (final symbol in symbols) {
    expect(
      library.lookup<ffi.NativeFunction<ffi.Void Function()>>(symbol).address,
      isNot(0),
      reason: symbol,
    );
  }
}

String? _nativeAssetFilePath(String assetId) {
  final configFile = File('.dart_tool/native_assets.yaml');
  if (!configFile.existsSync()) {
    return null;
  }

  final source = configFile
      .readAsLinesSync()
      .where((line) => !line.trimLeft().startsWith('#'))
      .join('\n');
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }

  final nativeAssets = decoded['native-assets'];
  if (nativeAssets is! Map) {
    return null;
  }

  for (final platformAssets in nativeAssets.values) {
    if (platformAssets is! Map) {
      continue;
    }
    final entry = platformAssets[assetId];
    if (entry is List && entry.length >= 2 && entry[0] == 'absolute') {
      final filePath = entry[1];
      if (filePath is String && filePath.isNotEmpty) {
        return filePath;
      }
    }
  }

  return null;
}

List<String> _matchingWindowsLibraryPaths(Directory directory, RegExp regex) {
  return _matchingLibraryPaths(directory, regex);
}

List<String> _matchingLibraryPaths(Directory directory, RegExp regex) {
  try {
    return directory
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .where((filePath) {
          final separatorIndex = filePath.lastIndexOf(Platform.pathSeparator);
          final name = separatorIndex == -1
              ? filePath
              : filePath.substring(separatorIndex + 1);
          return regex.hasMatch(name);
        })
        .toList(growable: false);
  } catch (_) {
    return const <String>[];
  }
}

/// The source of the library defined in [libraryPath], its parts included.
String _librarySource(String libraryPath) {
  final source = File(libraryPath).readAsStringSync();
  final directory = File(libraryPath).parent.path;
  return [
    source,
    for (final part in RegExp(
      r"^part '([^']+)';$",
      multiLine: true,
    ).allMatches(source))
      File('$directory/${part.group(1)}').readAsStringSync(),
  ].join('\n');
}

String _sourceSection(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNot(-1), reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNot(-1), reason: endMarker);
  return source.substring(start, end);
}

String _sourceBracedDeclaration(String source, String marker) {
  final start = source.indexOf(marker);
  expect(start, isNot(-1), reason: marker);

  final openingBrace = source.indexOf('{', start);
  expect(openingBrace, isNot(-1), reason: marker);

  var depth = 0;
  for (var index = openingBrace; index < source.length; index++) {
    switch (source[index]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) {
          return source.substring(start, index + 1);
        }
    }
  }

  fail('Unterminated declaration: $marker');
}

void _expectBitmapHelperDecodesTransparentPng(
  _MtmdHelperBitmapInitFromBufDart helper,
  _MtmdBitmapFreeDart bitmapFree,
  mtmd_helper_init_opt Function() defaultOptions,
) {
  final data = malloc<ffi.UnsignedChar>(_transparentPngBytes.length);
  ffi.Pointer<mtmd_bitmap> bitmap = ffi.nullptr;

  try {
    data
        .cast<ffi.Uint8>()
        .asTypedList(_transparentPngBytes.length)
        .setAll(0, _transparentPngBytes);
    final result = helper(
      ffi.nullptr.cast<mtmd_context>(),
      data,
      _transparentPngBytes.length,
      false,
      defaultOptions(),
    );
    bitmap = result.bitmap;

    expect(bitmap.address, isNot(0));
    expect(result.video_ctx.address, 0);
  } finally {
    if (bitmap.address != 0) {
      bitmapFree(bitmap);
    }
    malloc.free(data);
  }
}

void _expectB10545MtmdContextDefaults(mtmd_context_params params) {
  expect(params.use_gpu, isTrue);
  expect(params.device.address, 0);
  expect(params.print_timings, isTrue);
  expect(params.n_threads, 4);
}

void main() {
  group('Native Symbol Availability', () {
    test(
      'grammar barrier accepts tokens through the platform wrapper asset',
      () {
        final barrier = NativeBarrierApi.tryResolve(
          isWindows: Platform.isWindows,
        );
        expect(barrier, isNotNull);
        final sampler = llama_sampler_init_penalties(256, 64, 2, 0, 0);
        expect(sampler, isNot(ffi.nullptr));
        final data = calloc<llama_token_data>();
        final candidates = calloc<llama_token_data_array>();
        try {
          candidates.ref
            ..data = data
            ..size = 1
            ..selected = -1
            ..sorted = false;
          data.ref
            ..id = 42
            ..logit = 10
            ..p = 0;
          llama_sampler_apply(sampler, candidates);
          expect(data.ref.logit, 10);
          expect(barrier!.samplerAccept(sampler, 42), isTrue);
          data.ref.logit = 10;
          llama_sampler_apply(sampler, candidates);
          expect(data.ref.logit, 5);
          expect(barrier.caughtException(), isNull);
        } finally {
          llama_sampler_free(sampler);
          calloc.free(candidates);
          calloc.free(data);
        }
      },
    );

    test('context batch constants match the pinned llama.cpp defaults', () {
      final params = llama_context_default_params();

      expect(params.n_batch, ModelParams.defaultBatchSize);
      expect(params.n_ubatch, ModelParams.defaultMicroBatchSize);
    });

    test('v0.7.0 context defaults preserve fields around the expert cache', () {
      // Qualified 64-bit C headers: the expert cache and graph counters grow
      // both structs passed by value across the FFI boundary.
      expect(ffi.sizeOf<llama_context_params>(), 168);
      expect(ffi.sizeOf<llama_perf_context_data>(), 56);
      final params = llama_context_default_params();

      expect(params.type_k, ggml_type.GGML_TYPE_F16);
      expect(params.type_v, ggml_type.GGML_TYPE_F16);
      expect(params.moe_cache_size, 0);
      expect(params.abort_callback, ffi.nullptr);
      expect(params.abort_callback_data, ffi.nullptr);
      expect(params.embeddings, isFalse);
      expect(params.offload_kqv, isTrue);
    });

    test('v0.7.0-1 processing wrappers are declared and exported', () {
      final source = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();
      const symbols = ['llama_dart_process', 'llama_dart_batch_ext_init'];
      for (final symbol in symbols) {
        expect(
          _declaresExternalFunction(source, symbol),
          isTrue,
          reason: symbol,
        );
      }
      final wrapper = _llamadartWrapperLibraryFileOrNull();
      expect(
        wrapper,
        isNotNull,
        reason: 'Expected the llama.cpp wrapper library.',
      );
      // Resolved through the package first: a raw open of the wrapper cannot
      // find its sibling DLLs on Windows until the runtime is loaded.
      expect(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows),
        isNotNull,
      );
      _expectDynamicLibraryExports(wrapper!, symbols);
    });

    test('processing wrapper enum wire values match the published header', () {
      expect(llama_dart_process_type.LLAMA_DART_PROCESS_TYPE_DECODE.value, 1);
      expect(
        llama_dart_process_type.fromValue(1),
        llama_dart_process_type.LLAMA_DART_PROCESS_TYPE_DECODE,
      );
      expect(() => llama_dart_process_type.fromValue(0), throwsArgumentError);
      expect(
        llama_dart_process_status
            .LLAMA_DART_PROCESS_STATUS_UNSUPPORTED_TYPE
            .value,
        -1,
      );
      expect(
        llama_dart_process_status.LLAMA_DART_PROCESS_STATUS_UNSUPPORTED.value,
        -4,
      );
      expect(
        llama_dart_process_status.fromValue(-1),
        llama_dart_process_status.LLAMA_DART_PROCESS_STATUS_UNSUPPORTED_TYPE,
      );
      expect(
        llama_dart_process_status.fromValue(-4),
        llama_dart_process_status.LLAMA_DART_PROCESS_STATUS_UNSUPPORTED,
      );
      expect(() => llama_dart_process_status.fromValue(0), throwsArgumentError);
    });

    test('v0.7.0 scheduler callbacks are declared and exported', () {
      final source = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();
      const symbols = [
        'ggml_backend_sched_set_copy_callback',
        'ggml_backend_sched_set_realloc_callback',
      ];
      for (final symbol in symbols) {
        expect(
          _declaresExternalFunction(source, symbol),
          isTrue,
          reason: symbol,
        );
      }
      final primary = _llamadartPrimaryLibraryFileOrNull();
      expect(primary, isNotNull);
      final library = Platform.isWindows
          ? File('${primary!.parent.path}/ggml-base.dll')
          : primary!;
      _expectDynamicLibraryExports(library, symbols);
    });

    test('pinned runtime exposes the signed automatic load mode', () {
      expect(
        llama_model_default_params().load_mode,
        llama_load_mode.LLAMA_LOAD_MODE_AUTO,
      );
    });

    test('published image-token capability binding preserves the invalid '
        'projector error barrier', () {
      final barrier = NativeBarrierApi.tryResolve(
        isWindows: Platform.isWindows,
      )!;
      addTearDown(barrier.clearLastError);
      barrier.clearLastError();
      final probe = Platform.isWindows
          ? ffi.DynamicLibrary.open(
              _llamadartWrapperLibraryFileOrNull()!.path,
            ).lookupFunction<
              ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Int32),
              int Function(ffi.Pointer<ffi.Char>, int)
            >('llama_dart_mtmd_supports_image_token_limit')
          : llama_dart_mtmd_supports_image_token_limit;

      expect(probe(ffi.nullptr, 1), -1);
      expect(
        barrier.lastError().cast<Utf8>().toDartString(),
        contains('image token limit needs a projector and a positive limit'),
      );
    });

    test('v0.4.0 by-value defaults match regenerated model layout', () {
      final params = llama_model_default_params();
      expect(params.lazy_mode, llama_lazy_mode.LLAMA_LAZY_MODE_AUTO);
      expect(params.main_gpu, 0);
      expect(params.vocab_only, isFalse);
      expect(
        llama_model_quantize_default_params().max_buf_size,
        8 * 1024 * 1024 * 1024,
      );
      expect(LLAMA_SESSION_VERSION, 11);
      expect(LLAMA_STATE_SEQ_VERSION, 4);
    });

    test('Verify speculative symbols are declared in generated bindings', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();

      for (final symbol in [..._genericSpeculativeSymbols]) {
        expect(
          _declaresExternalFunction(bindingsSource, symbol),
          isTrue,
          reason: symbol,
        );
      }
    });

    test('Verify b10514 symbols are declared in generated bindings', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();

      for (final symbol in _b10514BindingSymbols) {
        expect(
          _declaresExternalFunction(bindingsSource, symbol),
          isTrue,
          reason: symbol,
        );
      }
    });

    test('Verify aLoRA metadata symbols are declared in bindings', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();

      for (final symbol in _aloraMetadataSymbols) {
        expect(
          _declaresExternalFunction(bindingsSource, symbol),
          isTrue,
          reason: symbol,
        );
      }
    });

    test('Verify exit-teardown symbols are declared in generated bindings, '
        'except the ones that are unsafe from Dart', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();

      for (final symbol in _exitTeardownSymbols) {
        expect(
          _declaresExternalFunction(bindingsSource, symbol),
          isTrue,
          reason: symbol,
        );
      }
      expect(
        bindingsSource,
        contains("symbol: '$_exitTeardownGraphComputeSymbol'"),
      );
      for (final symbol in _unboundExitTeardownSymbols) {
        expect(bindingsSource, isNot(contains(symbol)), reason: symbol);
      }
    });

    test('Verify the pinned wrapper exports the exit-teardown API the service '
        'resolves', () {
      final wrapper = _llamadartWrapperLibraryFileOrNull();
      expect(
        wrapper,
        isNotNull,
        reason: 'Expected the llama.cpp wrapper library.',
      );
      // Resolved through the package first: a raw open of the wrapper cannot
      // find its sibling DLLs on Windows until the runtime is loaded.
      expect(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows),
        isNotNull,
      );
      _expectDynamicLibraryExports(wrapper!, [
        ..._exitTeardownSymbols,
        _exitTeardownGraphComputeSymbol,
      ]);
      // Each name resolves to the wrapper's own export of that name, not to
      // another function with the same signature.
      final library = ffi.DynamicLibrary.open(wrapper.path);
      for (final symbol in [
        ..._exitTeardownSymbols,
        _exitTeardownGraphComputeSymbol,
      ]) {
        expect(
          ExitTeardownApi.symbolAddress(
            symbol,
            isWindows: Platform.isWindows,
          ).address,
          library.lookup<ffi.Void>(symbol).address,
          reason: symbol,
        );
      }
    });

    test('Verify the pinned wrapper exports the exception barrier and the '
        'Vulkan device facts the service resolves', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();
      for (final symbol in [..._barrierSymbols, ..._vulkanDeviceSymbols]) {
        expect(
          _declaresExternalFunction(bindingsSource, symbol),
          isTrue,
          reason: symbol,
        );
      }

      final wrapper = _llamadartWrapperLibraryFileOrNull();
      expect(
        wrapper,
        isNotNull,
        reason: 'Expected the llama.cpp wrapper library.',
      );
      // Resolved through the package first: a raw open of the wrapper cannot
      // find its sibling DLLs on Windows until the runtime is loaded.
      expect(
        NativeBarrierApi.tryResolve(isWindows: Platform.isWindows),
        isNotNull,
      );
      expect(
        VulkanDeviceInfoApi.tryResolve(isWindows: Platform.isWindows),
        isNotNull,
      );
      _expectDynamicLibraryExports(wrapper!, [
        ..._barrierSymbols,
        ..._vulkanDeviceSymbols,
      ]);
      // Each name resolves to the wrapper's own export of that name, not to
      // another function with the same signature.
      final library = ffi.DynamicLibrary.open(wrapper.path);
      for (final symbol in _barrierSymbols) {
        expect(
          NativeBarrierApi.symbolAddress(
            symbol,
            isWindows: Platform.isWindows,
          ).address,
          library.lookup<ffi.Void>(symbol).address,
          reason: symbol,
        );
      }
      for (final symbol in _vulkanDeviceSymbols) {
        expect(
          VulkanDeviceInfoApi.symbolAddress(
            symbol,
            isWindows: Platform.isWindows,
          ).address,
          library.lookup<ffi.Void>(symbol).address,
          reason: symbol,
        );
      }
    });

    test('Verify pinned mtmd context parameter layout in bindings', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();
      final section = _sourceBracedDeclaration(
        bindingsSource,
        'final class mtmd_context_params extends ffi.Struct {',
      );

      final useGpuIndex = section.indexOf('external bool use_gpu;');
      final deviceIndex = section.indexOf(
        'external ggml_backend_dev_t device;',
      );
      final printTimingsIndex = section.indexOf('external bool print_timings;');

      expect(useGpuIndex, isNot(-1));
      expect(deviceIndex, greaterThan(useGpuIndex));
      expect(printTimingsIndex, greaterThan(deviceIndex));
    });

    test('Verify generic speculative symbols are resolvable when exported', () {
      final wrapper = _llamadartWrapperLibraryFileOrNull();
      if (wrapper == null) {
        markTestSkipped('Unable to locate the llama.cpp wrapper library.');
        return;
      }

      final missing = _genericSpeculativeSymbols
          .where((symbol) => !_fileContainsAscii(wrapper, symbol))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        markTestSkipped(
          'Current native bundle does not export generic speculative wrapper '
          'symbols: ${missing.join(', ')}.',
        );
        return;
      }
      if (Platform.isWindows) {
        _expectDynamicLibraryExports(wrapper, _genericSpeculativeSymbols);
        return;
      }

      final nullSpeculative = ffi.nullptr.cast<llama_dart_speculative>();
      final nullModel = ffi.nullptr.cast<llama_model>();
      final nullContext = ffi.nullptr.cast<llama_context>();
      final nullTokenArray = ffi.nullptr.cast<ffi.Int32>();
      final nullParams = ffi.nullptr.cast<llama_dart_speculative_params>();
      final nullSampler = ffi.nullptr.cast<llama_sampler>();
      final ctxParams = llama_context_default_params();

      expect(
        llama_dart_sampler_sample_and_accept_n(
          nullSampler,
          nullContext,
          nullTokenArray,
          0,
          nullTokenArray,
          0,
          nullTokenArray,
          0,
        ),
        -1,
      );
      expect(
        llama_dart_speculative_init(
          nullModel,
          nullModel,
          nullContext,
          ctxParams,
          nullParams,
        ).address,
        0,
      );
      expect(
        () => llama_dart_speculative_free(nullSpeculative),
        returnsNormally,
      );
      expect(
        llama_dart_speculative_get_draft_context(nullSpeculative).address,
        0,
      );
      expect(llama_dart_speculative_need_embd_nextn(nullSpeculative), isFalse);
      expect(
        llama_dart_speculative_begin(nullSpeculative, 0, nullTokenArray, 0),
        isFalse,
      );
      expect(
        llama_dart_speculative_draft(
          nullSpeculative,
          0,
          0,
          0,
          nullTokenArray,
          0,
          1,
          nullTokenArray,
          0,
        ),
        -1,
      );
      expect(
        () => llama_dart_speculative_accept(nullSpeculative, 0, 0),
        returnsNormally,
      );

      final batch = llama_batch_init(1, 0, 1);
      try {
        expect(
          llama_dart_speculative_process_batch(nullSpeculative, batch),
          isFalse,
        );
      } finally {
        llama_batch_free(batch);
      }
    });

    test('Verify multimodal symbols are resolvable', () {
      // Some bundles export mtmd via the primary llama asset while others ship
      // it as a dedicated mtmd shared library loaded via runtime fallback.
      // So direct primary-asset lookup may legitimately fail.
      if (Platform.isWindows || Platform.isLinux || Platform.isAndroid) {
        try {
          _expectB10545MtmdContextDefaults(mtmd_context_params_default());
        } on ArgumentError {
          // The service resolves the dedicated mtmd shared library instead.
        }
        return;
      }

      _expectB10545MtmdContextDefaults(mtmd_context_params_default());
    });

    test('Verify mtmd fallback bitmap helper ABI mirrors bindings', () {
      final serviceSource = _librarySource(
        'lib/src/backends/llama_cpp/llama_cpp_service.dart',
      );

      final fileNative = _sourceSection(
        serviceSource,
        'typedef _MtmdHelperBitmapInitFromFileNative =',
        'typedef _MtmdHelperBitmapInitFromFileDart =',
      );
      expect(fileNative, contains('mtmd_helper_bitmap_wrapper Function('));
      expect(fileNative, contains('Pointer<mtmd_context>,'));
      expect(fileNative, contains('Pointer<Char>,'));
      expect(fileNative, contains('Bool,'));
      expect(fileNative, contains('mtmd_helper_init_opt,'));
      expect(fileNative, isNot(contains('Pointer<mtmd_bitmap> Function(')));

      final fileDart = _sourceSection(
        serviceSource,
        'typedef _MtmdHelperBitmapInitFromFileDart =',
        'typedef _MtmdHelperBitmapInitFromBufNative =',
      );
      expect(fileDart, contains('mtmd_helper_bitmap_wrapper Function('));
      expect(fileDart, contains('Pointer<mtmd_context>,'));
      expect(fileDart, contains('Pointer<Char>,'));
      expect(fileDart, contains('bool,'));
      expect(fileDart, contains('mtmd_helper_init_opt,'));

      final bufNative = _sourceSection(
        serviceSource,
        'typedef _MtmdHelperBitmapInitFromBufNative =',
        'typedef _MtmdHelperBitmapInitFromBufDart =',
      );
      expect(bufNative, contains('mtmd_helper_bitmap_wrapper Function('));
      expect(bufNative, contains('Pointer<mtmd_context>,'));
      expect(bufNative, contains('Pointer<UnsignedChar>,'));
      expect(bufNative, contains('Size,'));
      expect(bufNative, contains('Bool,'));
      expect(bufNative, contains('mtmd_helper_init_opt,'));
      expect(bufNative, isNot(contains('Pointer<mtmd_bitmap> Function(')));

      final bufDart = _sourceSection(
        serviceSource,
        'typedef _MtmdHelperBitmapInitFromBufDart =',
        'typedef _MtmdBitmapInitFromAudioNative =',
      );
      expect(bufDart, contains('mtmd_helper_bitmap_wrapper Function('));
      expect(bufDart, contains('Pointer<mtmd_context>,'));
      expect(bufDart, contains('Pointer<UnsignedChar>,'));
      expect(bufDart, contains('int,'));
      expect(bufDart, contains('bool,'));
      expect(bufDart, contains('mtmd_helper_init_opt,'));

      // Bind each assertion to its production function: deleting/bypassing one
      // call must fail even when the other helper still passes defaults.
      final fileBody = _sourceSection(
        serviceSource,
        '  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromFile(',
        '  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromBuf(',
      ).replaceAll(RegExp(r'\s+'), '');
      final bufBody = _sourceSection(
        serviceSource,
        '  Pointer<mtmd_bitmap> _mtmdHelperBitmapInitFromBuf(',
        '  Pointer<mtmd_bitmap> _mtmdBitmapInitFromAudio(',
      ).replaceAll(RegExp(r'\s+'), '');
      expect(
        fileBody,
        contains(
          'returnmtmd_helper_bitmap_init_from_file(ctx,pathPtr,false,mtmd_helper_init_opt_default(),).bitmap;',
        ),
      );
      expect(
        fileBody,
        contains(
          'returnfallback.helperBitmapInitFromFile(ctx,pathPtr,false,fallback.helperInitOptDefault(),).bitmap;',
        ),
      );
      expect(
        bufBody,
        contains(
          'returnmtmd_helper_bitmap_init_from_buf(ctx,data,size,false,mtmd_helper_init_opt_default(),).bitmap;',
        ),
      );
      expect(
        bufBody,
        contains(
          'returnfallback.helperBitmapInitFromBuf(ctx,data,size,false,fallback.helperInitOptDefault(),).bitmap;',
        ),
      );
      final fallback = serviceSource
          .substring(serviceSource.indexOf('class _MtmdApi {'))
          .replaceAll(RegExp(r'\s+'), '');
      expect(
        fallback,
        contains(
          "helperInitOptDefault:library.lookupFunction<_MtmdHelperInitOptDefaultNative,_MtmdHelperInitOptDefaultDart>('mtmd_helper_init_opt_default')",
        ),
      );
      expect(fallback, contains('catch(_){returnnull;}'));
    });

    test('Verify mtmd bitmap helper ABI is callable', () {
      final libraryFile = _mtmdFallbackLibraryFile();
      if (libraryFile == null) {
        if (Platform.isLinux || Platform.isAndroid || Platform.isWindows) {
          fail('Expected a split mtmd fallback library for this platform.');
        }
        _expectBitmapHelperDecodesTransparentPng(
          (ctx, data, len, placeholder, options) =>
              mtmd_helper_bitmap_init_from_buf(
                ctx,
                data,
                len,
                placeholder,
                options,
              ),
          (bitmap) => mtmd_bitmap_free(bitmap),
          mtmd_helper_init_opt_default,
        );
        return;
      }

      final library = ffi.DynamicLibrary.open(libraryFile.path);
      final helper = library
          .lookupFunction<
            _MtmdHelperBitmapInitFromBufNative,
            _MtmdHelperBitmapInitFromBufDart
          >('mtmd_helper_bitmap_init_from_buf');
      final bitmapFree = library
          .lookupFunction<_MtmdBitmapFreeNative, _MtmdBitmapFreeDart>(
            'mtmd_bitmap_free',
          );
      final defaultOptions = library
          .lookupFunction<
            mtmd_helper_init_opt Function(),
            mtmd_helper_init_opt Function()
          >('mtmd_helper_init_opt_default');
      _expectBitmapHelperDecodesTransparentPng(
        helper,
        bitmapFree,
        defaultOptions,
      );
    });

    test('Verify b10514 mtmd symbols are resolvable', () {
      final libraryFile =
          _mtmdFallbackLibraryFile() ?? _llamadartWrapperLibraryFileOrNull();
      expect(
        libraryFile,
        isNotNull,
        reason: 'Expected a native library exporting mtmd symbols.',
      );
      _expectDynamicLibraryExports(libraryFile!, _b10514MtmdSymbols);
    });

    test('Verify mtmd chunk-level eval symbols are resolvable', () {
      final libraryFile =
          _mtmdFallbackLibraryFile() ?? _llamadartWrapperLibraryFileOrNull();
      expect(
        libraryFile,
        isNotNull,
        reason: 'Expected a native library exporting mtmd symbols.',
      );
      _expectDynamicLibraryExports(libraryFile!, _mtmdChunkEvalSymbols);
      expect(
        LlamaCppService.debugMtmdFallbackHasChunkEvalForTesting(
          ffi.DynamicLibrary.open(libraryFile.path),
        ),
        isTrue,
      );
    });

    test('the TTS API has both cancel exports and mtmd contexts get its eval '
        'callback', () {
      final wrapper = _llamadartWrapperLibraryFileOrNull();
      expect(
        wrapper,
        isNotNull,
        reason: 'Expected the llama.cpp wrapper library.',
      );
      final service = LlamaCppService();
      final exports = service.debugTtsCancelExportsForTesting();
      final address = service.debugMtmdEvalCallbackAddressForTesting();
      expect(service.getStartupDiagnostics(), isEmpty);

      if (!_fileContainsAscii(wrapper!, 'llama_dart_tts_step')) {
        expect(exports, isNull);
        expect(address, 0);
        return;
      }
      expect(
        _ttsCancelSymbols
            .where((symbol) => _fileContainsAscii(wrapper, symbol))
            .toList(),
        _ttsCancelSymbols,
      );
      expect(exports, (evalCallback: true, setCancelFlag: true));
      expect(
        address,
        ffi.DynamicLibrary.open(
          wrapper.path,
        ).lookup<ffi.Void>('llama_dart_tts_eval_callback').address,
      );
    });

    test('Verify core llama symbols are resolvable', () {
      expect(() => llama_backend_init(), returnsNormally);
      expect(llama_version().cast<Utf8>().toDartString(), isNotEmpty);
      expect(() => llama_time_us(), returnsNormally);
      expect(() => llama_max_devices(), returnsNormally);
      expect(() => llama_supports_mmap(), returnsNormally);
      expect(() => llama_supports_mlock(), returnsNormally);
      expect(() => llama_supports_gpu_offload(), returnsNormally);
      expect(() => llama_supports_rpc(), returnsNormally);
      expect(() => llama_model_default_params(), returnsNormally);
      expect(() => llama_context_default_params(), returnsNormally);
      expect(() => llama_sampler_chain_default_params(), returnsNormally);
      expect(() => llama_model_quantize_default_params(), returnsNormally);
      expect(
        () => llama_numa_init(ggml_numa_strategy.GGML_NUMA_STRATEGY_DISABLED),
        returnsNormally,
      );
    });

    test('Verify pinned primary runtime exports aLoRA metadata ABI', () {
      final libraryFile = _llamadartPrimaryLibraryFileOrNull();
      expect(
        libraryFile,
        isNotNull,
        reason: 'Expected a native library exporting llama.cpp symbols.',
      );
      _expectDynamicLibraryExports(libraryFile!, _aloraMetadataSymbols);
    });
  });
}

bool _declaresExternalFunction(String source, String symbol) => RegExp(
  r'external\s+[^;]*\b' + RegExp.escape(symbol) + r'\s*\(',
).hasMatch(source);
