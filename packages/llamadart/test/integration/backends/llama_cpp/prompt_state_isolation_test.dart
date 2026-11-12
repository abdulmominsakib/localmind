@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../test_helper.dart';

const _p1 = 'Once upon a time there was a little girl named Lily.';
const _p2 =
    'Once upon a time there was a little dog named Max who liked to run fast '
    'and chase red balls in the big green park.';
const _p3 = '$_p1 She';

final _decodeFailure = isA<Exception>().having(
  (error) => '$error',
  'message',
  contains('Initial decode failed'),
);

const _greedy = GenerationParams(
  maxTokens: 24,
  temp: 0,
  topK: 1,
  penalty: 1,
  seed: 1,
);

void main() {
  late String modelPath;

  setUpAll(() async {
    modelPath = (await TestHelper.getTestModel()).path;
  });

  // https://github.com/leehack/llamadart/issues/601
  group('a failed prompt decode', () {
    late _Session session;
    late String fresh;

    setUp(() async {
      final reference = _Session.open(modelPath);
      try {
        fresh = await reference.generate(_p3, _greedy);
      } finally {
        reference.dispose();
      }
      session = _Session.open(modelPath);
      addTearDown(session.dispose);
    });

    test('on the suffix path does not leave the prefix cache stale', () async {
      await session.generate(_p1, _greedy);
      await expectLater(
        session.withAbortedDecodes(() => session.generate(_p2, _greedy)),
        throwsA(_decodeFailure),
      );
      expect(await session.generate(_p3, _greedy), fresh);
    });

    test(
      'on the full-prompt path does not leave the prefix cache stale',
      () async {
        await session.generate(_p1, _greedy);
        await expectLater(
          session.withAbortedDecodes(() => session.generate(_p1, _greedy)),
          throwsA(_decodeFailure),
        );
        expect(await session.generate(_p3, _greedy), fresh);
      },
    );
  });

  // https://github.com/leehack/llamadart/issues/603
  // On the tracked calls the service evaluates media through its
  // ExitTeardownApi, on the upstream ones through libmtmd.
  for (final tracked in [true, false]) {
    final calls = tracked ? 'tracked' : 'upstream';

    test('a media prompt does not seed the repeat penalty from stale memory '
        '($calls calls)', () async {
      final media = _MediaSession.open(
        modelPath,
        _p1,
        tracked: tracked,
        contextSize: 4096,
      );
      addTearDown(media.dispose);
      final session = media.session;
      const params = GenerationParams(maxTokens: 16, temp: 0, penalty: 2);
      final clean = await session.generate(
        '<__media__>',
        params,
        parts: media.mtmd.parts,
      );
      // The next generate() can get this request's freed prompt buffer, which
      // holds the media reply's own ids. On macOS a 1 KB buffer (context 256)
      // came back zeroed; this 16 KB one keeps the ids from index 4.
      await session.generate(clean, params.copyWith(maxTokens: 1));

      expect(
        await session.generate('<__media__>', params, parts: media.mtmd.parts),
        clean,
      );
      expect(media.mtmd.evaluations, 2);
      expect(
        media.mtmd.calls.where((call) => call.contains('eval')),
        hasLength(tracked ? 0 : 2),
      );
    });

    test('a text prompt still seeds the repeat penalty with its own ids '
        '($calls calls)', () async {
      final media = _MediaSession.open(modelPath, _p1, tracked: tracked);
      addTearDown(media.dispose);
      final session = media.session;
      const params = GenerationParams(maxTokens: 16, temp: 0, penalty: 2);
      final unprimed = await session.generate(
        '<__media__>',
        params,
        parts: media.mtmd.parts,
      );
      // Same KV, but the text path primes the penalty with the prompt ids.
      expect(await session.generate(_p1, params), isNot(unprimed));
    });
  }
}

/// A session whose model has a fake projector: one media part that evaluates
/// the tokens of a text.
final class _MediaSession {
  _MediaSession._(this.session, this.mtmd, this._directory);

  factory _MediaSession.open(
    String modelPath,
    String mediaText, {
    required bool tracked,
    int contextSize = 256,
  }) {
    final real = ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!;
    late final FakeMtmd mtmd;
    final session = _Session.open(
      modelPath,
      contextSize: contextSize,
      calls: tracked
          ? LlamaCppObjectCalls.tracked(
              RecordingExitTeardown(
                real,
                evalMedia: (context, nPast, nBatch, newNPast) =>
                    mtmd.evalMedia(context, nPast, nBatch, newNPast),
              ).api,
            )
          : LlamaCppObjectCalls.upstream,
    );
    mtmd = FakeMtmd.install(
      session.service,
      tokens: session.tokenize(mediaText),
      chunkEval: true,
      decode: tracked ? real.decode : llama_decode,
    );
    final directory = Directory.systemTemp.createTempSync('llamadart_mmproj_');
    final projector = File('${directory.path}/mmproj.gguf')
      ..writeAsStringSync('GGUF');
    session.service.createMultimodalContext(
      session.modelHandle,
      projector.path,
    );
    return _MediaSession._(session, mtmd, directory);
  }

  final _Session session;
  final FakeMtmd mtmd;
  final Directory _directory;

  void dispose() {
    session.dispose();
    mtmd.dispose();
    _directory.deleteSync(recursive: true);
  }
}

final class _Session {
  _Session._(this.service, this.modelHandle, this.contextHandle);

  factory _Session.open(
    String modelPath, {
    int contextSize = 256,
    LlamaCppObjectCalls? calls,
  }) {
    final params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: contextSize,
      batchSize: 8,
      microBatchSize: 8,
      gpuLayers: 0,
    );
    final service = LlamaCppService(objectCalls: calls)..initializeBackend();
    final modelHandle = service.loadModel(modelPath, params);
    return _Session._(
      service,
      modelHandle,
      service.createContext(modelHandle, params),
    );
  }

  final LlamaCppService service;
  final int modelHandle;
  final int contextHandle;

  Pointer<llama_context> get context =>
      (_private(service, '_contexts') as Map)[contextHandle].pointer
          as Pointer<llama_context>;

  List<int> tokenize(String text, {bool addSpecial = true}) =>
      service.tokenize(modelHandle, text, addSpecial);

  Future<String> generate(
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async {
    final cancel = calloc<Int8>();
    try {
      final bytes = <int>[];
      await for (final chunk in service.generate(
        contextHandle,
        prompt,
        params,
        cancel.address,
        parts: parts,
      )) {
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      calloc.free(cancel);
    }
  }

  /// Runs [action] while every CPU graph compute on the context aborts, so the
  /// first prompt `llama_decode` fails after generate() changed the KV.
  Future<void> withAbortedDecodes(Future<void> Function() action) async {
    // strlen("x") returns 1, which the ggml abort check reads as true.
    final strlen = DynamicLibrary.process()
        .lookup<NativeFunction<Bool Function(Pointer<Void>)>>('strlen');
    final data = 'x'.toNativeUtf8();
    llama_set_abort_callback(context, strlen, data.cast());
    try {
      await action();
    } finally {
      llama_set_abort_callback(context, nullptr, nullptr);
      malloc.free(data);
    }
  }

  void dispose() => service.dispose();
}

Object? _private(LlamaCppService service, String field) {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  return reflect(
    service,
  ).getField(MirrorSystem.getSymbol(field, owner)).reflectee;
}
