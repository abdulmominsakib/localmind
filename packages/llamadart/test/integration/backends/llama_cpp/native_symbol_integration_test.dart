@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

const _llamadartWrapperAssetId = 'package:llamadart/llamadart_wrapper';
const _llamadartPrimaryAssetId = 'package:llamadart/llamadart';

const _mtpSymbols = [
  'llama_dart_mtp_init',
  'llama_dart_mtp_init_with_draft_model',
  'llama_dart_mtp_free',
  'llama_dart_mtp_get_draft_context',
  'llama_dart_mtp_begin',
  'llama_dart_mtp_process_batch',
  'llama_dart_mtp_draft',
  'llama_dart_mtp_accept',
  'llama_dart_sampler_sample_and_accept_n',
];

const _ngramSymbols = [
  'llama_dart_ngram_simple_init',
  'llama_dart_ngram_free',
  'llama_dart_ngram_begin',
  'llama_dart_ngram_process_batch',
  'llama_dart_ngram_draft',
  'llama_dart_ngram_accept',
];

const _genericSpeculativeSymbols = [
  'llama_dart_speculative_init',
  'llama_dart_speculative_free',
  'llama_dart_speculative_get_draft_context',
  'llama_dart_speculative_need_embd',
  'llama_dart_speculative_need_embd_nextn',
  'llama_dart_speculative_begin',
  'llama_dart_speculative_process_batch',
  'llama_dart_speculative_draft',
  'llama_dart_speculative_accept',
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
    );
typedef _MtmdHelperBitmapInitFromBufDart =
    mtmd_helper_bitmap_wrapper Function(
      ffi.Pointer<mtmd_context>,
      ffi.Pointer<ffi.UnsignedChar>,
      int,
      bool,
    );
typedef _MtmdBitmapFreeNative = ffi.Void Function(ffi.Pointer<mtmd_bitmap>);
typedef _MtmdBitmapFreeDart = void Function(ffi.Pointer<mtmd_bitmap>);

@ffi.Native<ffi.Void Function(ffi.Pointer<llama_dart_mtp>)>(
  assetId: _llamadartWrapperAssetId,
  symbol: 'llama_dart_mtp_free',
)
external void _windowsMtpFree(ffi.Pointer<llama_dart_mtp> mtp);

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

String _sourceSection(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, isNot(-1), reason: startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNot(-1), reason: endMarker);
  return source.substring(start, end);
}

void _expectBitmapHelperDecodesTransparentPng(
  _MtmdHelperBitmapInitFromBufDart helper,
  _MtmdBitmapFreeDart bitmapFree,
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

void main() {
  group('Native Symbol Availability', () {
    test('context batch constants match the pinned llama.cpp defaults', () {
      final params = llama_context_default_params();

      expect(params.n_batch, ModelParams.defaultBatchSize);
      expect(params.n_ubatch, ModelParams.defaultMicroBatchSize);
    });

    test('Verify speculative symbols are declared in generated bindings', () {
      final bindingsSource = File(
        'lib/src/backends/llama_cpp/bindings.dart',
      ).readAsStringSync();

      for (final symbol in [
        ..._mtpSymbols,
        ..._ngramSymbols,
        ..._genericSpeculativeSymbols,
      ]) {
        expect(
          bindingsSource,
          matches(RegExp(r'external\s+[\s\S]*?\b' + RegExp.escape(symbol))),
          reason: symbol,
        );
      }
    });

    test('Verify MTP wrapper symbols are resolvable', () {
      if (Platform.isWindows) {
        expect(() => llama_context_default_params(), returnsNormally);
        expect(
          () => _windowsMtpFree(ffi.nullptr.cast<llama_dart_mtp>()),
          returnsNormally,
        );
        final wrapper = _windowsMtpWrapperLibraryFile();
        for (final symbol in _mtpSymbols) {
          expect(_fileContainsAscii(wrapper, symbol), isTrue, reason: symbol);
        }
        return;
      }

      final nullMtp = ffi.nullptr.cast<llama_dart_mtp>();
      final nullModel = ffi.nullptr.cast<llama_model>();
      final nullContext = ffi.nullptr.cast<llama_context>();
      final nullSampler = ffi.nullptr.cast<llama_sampler>();
      final nullTokenArray = ffi.nullptr.cast<ffi.Int32>();
      final ctxParams = llama_context_default_params();

      expect(
        llama_dart_mtp_init(
          nullModel,
          nullContext,
          ctxParams,
          1,
          0,
          0.0,
          true,
        ).address,
        0,
      );
      expect(
        llama_dart_mtp_init_with_draft_model(
          nullModel,
          nullContext,
          ctxParams,
          1,
          0,
          0.0,
          true,
        ).address,
        0,
      );
      expect(() => llama_dart_mtp_free(nullMtp), returnsNormally);
      expect(llama_dart_mtp_get_draft_context(nullMtp).address, 0);
      expect(llama_dart_mtp_begin(nullMtp, 0, nullTokenArray, 0), isFalse);
      expect(
        llama_dart_mtp_draft(
          nullMtp,
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
      expect(() => llama_dart_mtp_accept(nullMtp, 0, 0), returnsNormally);
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

      final batch = llama_batch_init(1, 0, 1);
      try {
        expect(llama_dart_mtp_process_batch(nullMtp, batch), isFalse);
      } finally {
        llama_batch_free(batch);
      }
    });

    test('Verify ngram wrapper symbols are resolvable when exported', () {
      final wrapper = _llamadartWrapperLibraryFileOrNull();
      if (wrapper == null) {
        markTestSkipped('Unable to locate the llama.cpp wrapper library.');
        return;
      }

      final missing = _ngramSymbols
          .where((symbol) => !_fileContainsAscii(wrapper, symbol))
          .toList(growable: false);
      if (missing.isNotEmpty) {
        markTestSkipped(
          'Current native bundle does not export ngram wrapper symbols: '
          '${missing.join(', ')}.',
        );
        return;
      }
      if (Platform.isWindows) {
        _expectDynamicLibraryExports(wrapper, _ngramSymbols);
        return;
      }

      final nullNgram = ffi.nullptr.cast<llama_dart_ngram>();
      final nullTokenArray = ffi.nullptr.cast<ffi.Int32>();
      final session = llama_dart_ngram_simple_init(1, 1);
      expect(session.address, isNot(0));

      try {
        expect(() => llama_dart_ngram_free(nullNgram), returnsNormally);
        expect(
          llama_dart_ngram_begin(nullNgram, 0, nullTokenArray, 0),
          isFalse,
        );
        expect(llama_dart_ngram_begin(session, 1, nullTokenArray, 0), isFalse);
        expect(
          llama_dart_ngram_draft(
            nullNgram,
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
          llama_dart_ngram_draft(
            session,
            1,
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
        expect(() => llama_dart_ngram_accept(nullNgram, 0, 0), returnsNormally);
        expect(() => llama_dart_ngram_accept(session, 0, 0), returnsNormally);

        final batch = llama_batch_init(1, 0, 1);
        try {
          expect(llama_dart_ngram_process_batch(nullNgram, batch), isFalse);
        } finally {
          llama_batch_free(batch);
        }
      } finally {
        llama_dart_ngram_free(session);
      }
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
      final ctxParams = llama_context_default_params();

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
      expect(llama_dart_speculative_need_embd(nullSpeculative), isFalse);
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
        expect(
          () => mtmd_context_params_default(),
          anyOf(returnsNormally, throwsA(isA<ArgumentError>())),
        );
        return;
      }

      expect(() => mtmd_context_params_default(), returnsNormally);
    });

    test('Verify mtmd fallback bitmap helper ABI mirrors bindings', () {
      final serviceSource = File(
        'lib/src/backends/llama_cpp/llama_cpp_service.dart',
      ).readAsStringSync();

      final fileNative = _sourceSection(
        serviceSource,
        'typedef _MtmdHelperBitmapInitFromFileNative =',
        'typedef _MtmdHelperBitmapInitFromFileDart =',
      );
      expect(fileNative, contains('mtmd_helper_bitmap_wrapper Function('));
      expect(fileNative, contains('Pointer<mtmd_context>,'));
      expect(fileNative, contains('Pointer<Char>,'));
      expect(fileNative, contains('Bool,'));
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

      expect(
        serviceSource,
        contains(
          'mtmd_helper_bitmap_init_from_file(ctx, pathPtr, false).bitmap',
        ),
      );
      expect(
        serviceSource,
        contains(
          'mtmd_helper_bitmap_init_from_buf(ctx, data, size, false)'
          '.bitmap',
        ),
      );
    });

    test('Verify mtmd bitmap helper ABI is callable', () {
      final libraryFile = _mtmdFallbackLibraryFile();
      if (libraryFile == null) {
        if (Platform.isLinux || Platform.isAndroid || Platform.isWindows) {
          fail('Expected a split mtmd fallback library for this platform.');
        }
        _expectBitmapHelperDecodesTransparentPng(
          (ctx, data, len, placeholder) =>
              mtmd_helper_bitmap_init_from_buf(ctx, data, len, placeholder),
          (bitmap) => mtmd_bitmap_free(bitmap),
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
      _expectBitmapHelperDecodesTransparentPng(helper, bitmapFree);
    });

    test('Verify core llama symbols are resolvable', () {
      expect(() => llama_backend_init(), returnsNormally);
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
  });
}
