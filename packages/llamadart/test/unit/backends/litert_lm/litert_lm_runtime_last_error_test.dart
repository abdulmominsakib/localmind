@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

// Operations of test/fixtures/litert_lm/last_error.c.
const _settings = 1;
const _engine = 2;
const _conversation = 3;
const _send = 4;

Future<String> _compileFixture(
  Directory dir,
  String name,
  List<String> defines, {
  String source = 'test/fixtures/litert_lm/last_error.c',
}) async {
  final library = '${dir.path}/$name.${Platform.isMacOS ? 'dylib' : 'so'}';
  final result = await Process.run('cc', [
    '-shared',
    '-fPIC',
    ...defines,
    '-pthread',
    source,
    '-o',
    library,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return library;
}

void _configure(
  String library,
  int op, {
  int code = 0,
  String? message,
  bool stale = false,
}) {
  final configure = DynamicLibrary.open(library)
      .lookupFunction<
        Void Function(Int32, Int32, Pointer<Utf8>, Bool),
        void Function(int, int, Pointer<Utf8>, bool)
      >('fixture_configure');
  final messagePtr = message?.toNativeUtf8() ?? nullptr;
  try {
    configure(op, code, messagePtr, stale);
  } finally {
    if (messagePtr != nullptr) malloc.free(messagePtr);
  }
}

typedef _Trigger =
    Future<void> Function(LiteRtLmRuntimeClient client, void Function() arm);

void main() {
  late Directory dir;
  late String blocking;
  late String streaming;
  late String legacy;
  late String modelPath;
  late String delayed;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('litert_last_error_');
    blocking = await _compileFixture(dir, 'blocking', []);
    streaming = await _compileFixture(dir, 'streaming', [
      '-DWITH_STREAM_PROXY',
    ]);
    legacy = await _compileFixture(dir, 'legacy', ['-DOMIT_LAST_ERROR']);
    delayed = await _compileFixture(
      dir,
      'delayed',
      [],
      source: 'test/fixtures/litert_lm/legacy_stream.c',
    );
    modelPath = '${dir.path}/secret_models/model.litertlm';
  });

  tearDownAll(() => dir.delete(recursive: true));

  Future<void> initialize(LiteRtLmRuntimeClient client) =>
      client.initialize(modelPath: modelPath, backend: 'cpu');

  Future<void> send(LiteRtLmRuntimeClient client, void Function() arm) async {
    await initialize(client);
    client.createConversation(npuBackend: true);
    arm();
    await client.generate('Hi').drain<void>();
  }

  for (final finalError in [false, true]) {
    test(
      'legacy nonfinal error retains callbacks until actual final: $finalError',
      () async {
        final client = LiteRtLmRuntimeClient(libraryPath: delayed);
        final library = DynamicLibrary.open(delayed);
        int count(String name) => library
            .lookupFunction<Int Function(), int Function()>('fixture_$name')();
        void emit(int kind) =>
            library.lookupFunction<Void Function(Int), void Function(int)>(
              'fixture_emit',
            )(kind);
        await initialize(client);
        client.createConversation(npuBackend: true);
        final deleted = count('conversations_deleted');
        final output = <String>[];
        final done = Completer<void>();
        Object? failure;
        final subscription = client
            .generate('Hi')
            .listen(
              output.add,
              onError: (Object error) {
                failure = error;
              },
              onDone: done.complete,
            );
        emit(
          1,
        ); // Both owned fields must be freed, without freeing their proxy.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.pending);
        expect(done.isCompleted, isFalse);
        expect(count('copied_strings'), 0);
        expect(count('proxies'), 1);
        expect(count('conversations_deleted'), deleted);
        expect(client.dispose, throwsA(isA<LlamaStateException>()));
        emit(0); // Data after the error is copied/freed, then suppressed.
        emit(finalError ? 3 : 2);
        await done.future;
        await subscription.cancel();
        expect(output, isEmpty);
        expect(
          failure,
          isA<StateError>().having(
            (error) => error.message,
            'original failure',
            'INTERNAL: original native failure',
          ),
        );
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('copied_strings'), 0);
        expect(count('proxies'), 0);
        client.createConversation(npuBackend: true);
        final next = client.generate('reuse after drained error').toList();
        emit(0);
        emit(2);
        expect(await next, ['late']);
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('copied_strings'), 0);
        expect(count('proxies'), 0);
        client.dispose();
        expect(count('conversations_deleted'), deleted + 2);
      },
    );
  }

  for (final stage in [5, _send]) {
    test(
      'blocking failure $stage returns only after the native scope unwinds',
      () async {
        final client = LiteRtLmRuntimeClient(libraryPath: blocking);
        _configure(blocking, 0);
        final library = DynamicLibrary.open(blocking);
        int count(String name) => library
            .lookupFunction<Int Function(), int Function()>('fixture_$name')();
        await initialize(client);
        client.createConversation(npuBackend: true);
        final deleted = count('optional_args_deleted');
        final sends = count('send_calls');
        _configure(
          blocking,
          stage,
          code: 7,
          message: 'PERMISSION_DENIED: $modelPath',
        );
        final stream = client.generate('Hi');
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.pending);
        await expectLater(
          stream.drain<void>(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'redacted native error',
              allOf(
                stage == _send
                    ? contains('PERMISSION_DENIED')
                    : contains('optional_args_create returned null'),
                isNot(contains('secret_models')),
              ),
            ),
          ),
        );
        expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('send_calls') - sends, stage == _send ? 1 : 0);
        expect(
          count('optional_args_deleted') - deleted,
          stage == _send ? 1 : 0,
        );
        client.dispose();
      },
    );
  }

  final scenarios = <(String, int, bool, String, _Trigger)>[
    (
      'engine settings creation',
      _settings,
      false,
      'litert_lm_engine_settings_create returned null',
      (client, arm) async {
        arm();
        await initialize(client);
      },
    ),
    (
      'engine creation',
      _engine,
      false,
      'LiteRT-LM engine creation failed for backend "cpu" and model '
          '"model.litertlm".',
      (client, arm) async {
        arm();
        await initialize(client);
      },
    ),
    (
      'conversation creation',
      _conversation,
      false,
      'litert_lm_conversation_create returned null',
      (client, arm) async {
        await initialize(client);
        arm();
        client.createConversation(npuBackend: true);
      },
    ),
    (
      'streaming send',
      _send,
      true,
      'litert_lm_conversation_send_message_stream rc=-1',
      send,
    ),
    (
      'blocking send',
      _send,
      false,
      'litert_lm_conversation_send_message returned null',
      send,
    ),
  ];

  Future<String> failure(
    String library,
    int op,
    _Trigger trigger, {
    int code = 0,
    String? message,
    bool stale = false,
  }) async {
    final client = LiteRtLmRuntimeClient(libraryPath: library);
    _configure(library, 0);
    try {
      await trigger(
        client,
        () =>
            _configure(library, op, code: code, message: message, stale: stale),
      );
    } on StateError catch (error) {
      return error.message;
    } finally {
      client.dispose();
    }
    fail('No error was thrown.');
  }

  for (final (name, op, streams, base, trigger) in scenarios) {
    String library() => streams ? streaming : blocking;

    test('a failed $name carries the native error', () async {
      final message = await failure(
        library(),
        op,
        trigger,
        code: 7,
        message: 'PERMISSION_DENIED: cannot open $modelPath\n  for reading:',
      );

      expect(message, startsWith(base));
      expect(
        message,
        contains(
          'LiteRT-LM reported PERMISSION_DENIED (7): cannot open '
          'model.litertlm for reading.',
        ),
      );
      expect(message, isNot(contains('secret_models')));
    });

    test('a failed $name reports no error recorded before it', () async {
      final message = await failure(library(), op, trigger, stale: true);

      expect(message, startsWith(base));
      expect(message, isNot(contains('LiteRT-LM reported')));
    });

    if (!streams) {
      test('a failed $name on a runtime without the last-error API keeps '
          'its message', () async {
        final message = await failure(
          legacy,
          op,
          trigger,
          code: 7,
          message: 'PERMISSION_DENIED: cannot open the model',
        );

        expect(message, startsWith(base));
        expect(message, isNot(contains('LiteRT-LM reported')));
      });
    }
  }
}
