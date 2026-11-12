@TestOn('vm && (mac-os || linux)')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String libraryPath;
  final incompatible = <String, DynamicLibrary>{};
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 10));
  LiteRtLmV1Runtime loaded([DynamicLibrary? selected]) {
    final runtime = LiteRtLmV1Runtime(selected ?? library);
    runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
    return runtime;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'litert_v1_conversation_',
    );
    for (final entry in <String, List<String>>{
      'valid': [],
      'old-proxy': ['-DPROXY_ABI=1'],
      'future-proxy': ['-DPROXY_ABI=3'],
      'missing-proxy': ['-DOMIT_PROXY_CREATE'],
      'unmarked-proxy': ['-DOMIT_PROXY_MARKER'],
      'missing-loss-marker': ['-DOMIT_ALLOCATION_FAILURE_MARKER'],
      'missing-loss-getter': ['-DOMIT_ALLOCATION_FAILURE_GETTER'],
      'old-loss': ['-DALLOCATION_FAILURE_ABI=0'],
      'future-loss': ['-DALLOCATION_FAILURE_ABI=2'],
      'unknown-finish': ['-DFINISH_ABI=2'],
      'missing-finish': ['-DOMIT_FINISH_MARKER'],
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        ...entry.value,
        'test/fixtures/litert_lm/c_api_v1_conversation.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final candidate = DynamicLibrary.open(path);
      if (entry.key == 'valid') {
        library = candidate;
        libraryPath = path;
      } else {
        incompatible[entry.key] = candidate;
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    call('fail', 0);
    call('fail_copies', 0);
    expect(count('live'), 0);
    expect(count('copies'), 0);
    expect(count('proxies'), 0);
  });
  tearDown(() {
    expect(count('live'), 0);
    expect(count('copies'), 0);
    expect(count('proxies'), 0);
  });

  for (final name in [
    'old-proxy',
    'future-proxy',
    'missing-proxy',
    'unmarked-proxy',
    'missing-loss-marker',
    'missing-loss-getter',
    'old-loss',
    'future-loss',
  ]) {
    test('$name refuses before conversation allocation or stream dispatch', () {
      final selected = incompatible[name]!;
      final runtime = loaded(selected);
      expect(
        runtime.openConversation,
        throwsA(isA<LlamaUnsupportedException>()),
      );
      for (final counter in [
        'created',
        'sends',
        'proxies',
        'proxy_allocations',
      ]) {
        expect(
          selected.lookupFunction<Int Function(), int Function()>(
            'fixture_$counter',
          )(),
          0,
        );
      }
      expect(
        runtime.generateText('legacy preparation remains usable'),
        'legacy preparation remains usable',
      );
      runtime.dispose();
    });
  }

  test(
    'foreign callbacks copy UTF8 before borrowed chunk storage expires; normal conversation reuse',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final before = count('created');
      final reads = count('loss_reads');
      for (var index = 0; index < 2; index++) {
        final turn = conversation.sendText('Text 世界');
        final chunks = turn.chunks.toList();
        call('emit', 0);
        call('emit', 2);
        expect(await turn.done, LiteRtLmFinishReason.stop);
        expect(await chunks, ['borrowed UTF8 世界']);
        expect(count('copies'), 0);
        expect(count('proxies'), 0);
      }
      expect(count('created'), before);
      expect(count('loss_reads'), reads + 2);
      conversation.close();
      conversation.close();
      runtime.dispose();
    },
  );

  test(
    'live conversation and turn block overlapping operations and engine lifetime changes',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
      final turn = conversation.sendText('active');
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.pending);
      for (final operation in <void Function()>[
        () => conversation.sendText('overlap'),
        conversation.close,
        runtime.dispose,
        () => runtime.load('/new', cacheDir: '/new/cache'),
        () => runtime.generateText('overlap'),
        runtime.openConversation,
      ]) {
        expect(operation, throwsA(isA<LlamaStateException>()));
      }
      call('emit', 2);
      await turn.done;
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
      await turn.chunks.drain<void>();
      conversation.close();
      runtime.dispose();
    },
  );

  test(
    'cancel keeps callback resources through late data then drains deletes and recreates',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('cancel');
      final chunks = turn.chunks.toList();
      var completed = false;
      unawaited(
        turn.done.then((_) {
          completed = true;
        }),
      );
      final cancels = count('cancels');
      turn.cancel();
      turn.cancel();
      expect(count('cancels'), cancels + 1);
      expect(count('proxies'), 1);
      expect(count('live'), 2);
      call('emit', 0);
      await tick();
      expect(completed, isFalse);
      expect(count('copies'), 0);
      call('emit', 2);
      expect(await turn.done, LiteRtLmFinishReason.cancelled);
      expect(await chunks, isEmpty);
      expect(
        () => conversation.sendText('poisoned'),
        throwsA(isA<LlamaStateException>()),
      );
      conversation.close();
      final fresh = runtime.openConversation();
      final next = fresh.sendText('fresh');
      call('emit', 2);
      expect(await next.done, LiteRtLmFinishReason.stop);
      await next.chunks.drain<void>();
      fresh.close();
      runtime.dispose();
    },
  );

  test(
    'cancelling stream subscription requests native cancellation but waits for final',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('cancel subscription');
      final subscription = turn.chunks.listen((_) {});
      await subscription.cancel();
      expect(count('proxies'), 1);
      call('emit', 2);
      expect(await turn.done, LiteRtLmFinishReason.cancelled);
      runtime.dispose();
    },
  );

  test(
    'nonfinal error does not free callback; both copied strings freed on final error',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('error');
      final failure = expectLater(
        turn.done,
        throwsA(
          isA<LlamaModelException>().having(
            (e) => e.message,
            'path redacted',
            allOf(
              isNot(contains('/secret')),
              isNot(contains('token=secret')),
              isNot(contains('user:secret')),
            ),
          ),
        ),
      );
      final chunks = turn.chunks.toList();
      call('emit', 1);
      await tick();
      expect(count('proxies'), 1);
      call('emit', 4);
      await failure;
      expect(await chunks, isEmpty);
      expect(count('proxies'), 0);
      runtime.dispose();
    },
  );

  for (final stage in [4, 5, 6, 13, 14, 15]) {
    test(
      'conversation setup failure $stage releases temporaries and retains engine',
      () {
        final runtime = loaded();
        call('fail', stage);
        expect(runtime.openConversation, throwsA(isA<LlamaException>()));
        expect(count('live'), 1);
        call('fail', 0);
        final conversation = runtime.openConversation();
        conversation.close();
        runtime.dispose();
      },
    );
  }
  for (final stage in [16, 17]) {
    test(
      'stream start failure $stage deletes child and callback before recreate',
      () {
        final runtime = loaded();
        final conversation = runtime.openConversation();
        call('fail', stage);
        expect(
          () => conversation.sendText('failure'),
          throwsA(
            stage == 17
                ? isA<LiteRtLmSendFailureException>()
                : allOf(
                    isA<LlamaException>(),
                    isNot(isA<LiteRtLmSendFailureException>()),
                  ),
          ),
        );
        expect(count('live'), 1);
        expect(count('proxies'), 0);
        call('fail', 0);
        runtime.openConversation().close();
        runtime.dispose();
      },
    );
  }
  test(
    'send failure keeps the native message text and the raising Dart frame',
    () {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      addTearDown(() {
        call('fail', 0);
        conversation.close();
        runtime.dispose();
      });
      call('fail', 17);
      Object? error;
      StackTrace? trace;
      try {
        conversation.sendText('failure');
      } on Object catch (caught, stackTrace) {
        error = caught;
        trace = stackTrace;
      }
      expect(error, isA<LiteRtLmSendFailureException>());
      expect(
        (error! as LiteRtLmSendFailureException).message,
        'conversation_send_message_stream failed: LiteRT-LM reported INTERNAL '
        '(13): stage17 m.litertlm cache secret/dispatch.',
      );
      expect(trace.toString(), contains('LiteRtLmV1Runtime._check'));
    },
  );
  test(
    'cancellation status failure still prevents reuse and retains callback until final',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('cancel failure');
      call('fail', 18);
      expect(turn.cancel, throwsA(isA<LlamaModelException>()));
      expect(count('proxies'), 1);
      call('fail', 0);
      call('emit', 2);
      expect(await turn.done, LiteRtLmFinishReason.cancelled);
      await turn.chunks.drain<void>();
      runtime.dispose();
    },
  );
  test(
    'failed drain quarantines callback child and parent in isolated process',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        'test/fixtures/litert_lm_v1_quarantine.dart',
        libraryPath,
      ]).timeout(const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('quarantine controls passed'));
    },
  );
  test(
    'canonical cancellation error requires native reason and deletes before recreate',
    () async {
      final runtime = loaded();
      final old = runtime.openConversation();
      final turn = old.sendText('cancel');
      turn.cancel();
      call('emit', 3);
      expect(await turn.done, LiteRtLmFinishReason.cancelled);
      await turn.chunks.drain<void>();
      final fresh = runtime.openConversation();
      // Repeated close of the old object must not detach the new child.
      old.close();
      expect(runtime.dispose, throwsA(isA<LlamaStateException>()));
      fresh.close();
      runtime.dispose();
    },
  );
  test(
    'canonical-looking cancellation error without native cancellation remains a failure',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('unconfirmed');
      final failure = expectLater(
        turn.done,
        throwsA(isA<LlamaModelException>()),
      );
      call('emit', 3);
      await failure;
      await turn.chunks.drain<void>();
      runtime.dispose();
    },
  );
  for (final name in ['unknown-finish', 'missing-finish']) {
    test('$name returns unknown without inferring a finish cause', () async {
      final selected = incompatible[name]!;
      final runtime = loaded(selected);
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('unknown reason');
      selected.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_emit',
      )(2);
      expect(await turn.done, LiteRtLmFinishReason.unknown);
      await turn.chunks.drain<void>();
      conversation.close();
      runtime.dispose();
    });
  }
  test(
    'nonfinal stream failure survives a clean final callback and discards the conversation',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('nonfinal failure');
      final failure = expectLater(
        turn.done,
        throwsA(
          allOf(
            isA<LlamaModelException>(),
            isNot(isA<LiteRtLmSendFailureException>()),
          ),
        ),
      );
      call('emit', 1);
      call('emit', 2);
      await failure;
      await turn.chunks.drain<void>();
      expect(
        () => conversation.sendText('reuse failed history'),
        throwsA(isA<LlamaStateException>()),
      );
      runtime.dispose();
    },
  );
  test(
    'malformed copied UTF8 fails with a typed redacted error and releases the failed child',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('invalid copied data');
      final failure = expectLater(
        turn.done,
        throwsA(isA<LlamaModelException>()),
      );
      call('emit', 6);
      await failure;
      await turn.chunks.drain<void>();
      runtime.dispose();
    },
  );
  for (final caseData in [
    (name: 'nonfinal text then clean final', kind: 0, mask: 1, cancel: false),
    (name: 'final text', kind: 9, mask: 1, cancel: false),
    for (final mask in [1, 2, 3]) ...[
      (
        name: 'nonfinal pair loss $mask then clean final',
        kind: 7,
        mask: mask,
        cancel: false,
      ),
      (name: 'final pair loss $mask', kind: 4, mask: mask, cancel: false),
      (name: 'cancelled pair loss $mask', kind: 8, mask: mask, cancel: true),
    ],
  ]) {
    test(
      'copy loss ${caseData.name} fails but settles and discards the child',
      () async {
        final runtime = loaded();
        final conversation = runtime.openConversation();
        final turn = conversation.sendText('lost copy');
        final chunks = turn.chunks.toList();
        final reads = count('loss_reads');
        final failedCopies = count('failed_copies');
        final reason = caseData.cancel
            ? LiteRtLmFinishReason.cancelled
            : caseData.kind == 4
            ? LiteRtLmFinishReason.error
            : LiteRtLmFinishReason.stop;
        final errorDelivered =
            [4, 7, 8].contains(caseData.kind) && caseData.mask == 1;
        final failure = expectLater(
          turn.done,
          throwsA(
            isA<LiteRtLmV1CopyLossException>()
                .having((error) => error.finishReason, 'native reason', reason)
                .having(
                  (error) => error.streamFailure,
                  'copied failure',
                  errorDelivered
                      ? isA<LlamaModelException>().having(
                          (failure) => failure.toString(),
                          'copied failure redacted',
                          allOf(
                            isNot(contains('/secret')),
                            isNot(contains('token=secret')),
                            isNot(contains('user:secret')),
                          ),
                        )
                      : isNull,
                )
                .having(
                  (error) => error.toString(),
                  'redacted',
                  isNot(contains('/secret')),
                ),
          ),
        );
        if (caseData.cancel) turn.cancel();
        call('fail_copies', caseData.mask);
        call('emit', caseData.kind);
        if (caseData.kind == 0 || caseData.kind == 7) {
          await tick();
          expect(
            conversation.nativeSettlement,
            LiteRtLmNativeSettlement.pending,
          );
          expect(count('loss_reads'), reads);
          expect(count('proxies'), 1);
          expect(conversation.close, throwsA(isA<LlamaStateException>()));
          call('fail_copies', 0);
          call('emit', 2);
        }
        await failure;
        expect(
          await chunks,
          !caseData.cancel && caseData.mask == 2
              ? ['borrowed UTF8 世界']
              : isEmpty,
        );
        expect(
          count('failed_copies') - failedCopies,
          caseData.mask == 3 ? 2 : 1,
        );
        expect(count('loss_reads'), reads + 1);
        expect(count('proxies'), 0);
        expect(count('copies'), 0);
        expect(count('live'), 1);
        expect(conversation.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(
          () => conversation.sendText('poisoned'),
          throwsA(isA<LlamaStateException>()),
        );
        // A fresh proxy has no inherited sticky error; the parent remains reusable.
        call('fail_copies', 0);
        final fresh = runtime.openConversation();
        final next = fresh.sendText('clean reuse');
        final nextChunks = next.chunks.toList();
        call('emit', 0);
        call('emit', 2);
        expect(await next.done, LiteRtLmFinishReason.stop);
        expect(await nextChunks, ['borrowed UTF8 世界']);
        fresh.close();
        runtime.dispose();
      },
    );
  }

  test(
    'cancellation status error does not hide subsequent settled copy loss',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText('cancel failed');
      final failure = expectLater(
        turn.done,
        throwsA(
          isA<LiteRtLmV1CopyLossException>().having(
            (error) => error.finishReason,
            'native cause',
            LiteRtLmFinishReason.cancelled,
          ),
        ),
      );
      call('fail', 18);
      expect(turn.cancel, throwsA(isA<LlamaModelException>()));
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.pending);
      call('fail', 0);
      call('fail_copies', 3);
      call('emit', 8);
      await failure;
      await turn.chunks.drain<void>();
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
      expect(count('proxies'), 0);
      runtime.dispose();
    },
  );

  for (final name in ['unknown-finish', 'missing-finish']) {
    test(
      'copy loss with $name preserves unknown native cause and still fails',
      () async {
        final selected = incompatible[name]!;
        void emit(int kind) =>
            selected.lookupFunction<Void Function(Int), void Function(int)>(
              'fixture_emit',
            )(kind);
        void failCopies(int mask) =>
            selected.lookupFunction<Void Function(Int), void Function(int)>(
              'fixture_fail_copies',
            )(mask);
        final runtime = loaded(selected);
        final conversation = runtime.openConversation();
        final turn = conversation.sendText('unknown loss');
        final failure = expectLater(
          turn.done,
          throwsA(
            isA<LiteRtLmV1CopyLossException>().having(
              (error) => error.finishReason,
              'native cause',
              LiteRtLmFinishReason.unknown,
            ),
          ),
        );
        failCopies(1);
        emit(9);
        await failure;
        await turn.chunks.drain<void>();
        failCopies(0);
        expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(
          () => conversation.sendText('closed'),
          throwsA(isA<LlamaStateException>()),
        );
        runtime.dispose();
      },
    );
  }

  test('argument and idle-state refusal avoids native work', () {
    final runtime = LiteRtLmV1Runtime(library);
    expect(runtime.openConversation, throwsA(isA<LlamaStateException>()));
    runtime.load('/model', cacheDir: '/cache');
    expect(
      () => runtime.openConversation(maxOutputTokens: 0),
      throwsA(isA<LlamaArgumentException>()),
    );
    final conversation = runtime.openConversation();
    expect(
      () => conversation.sendText('NUL\u0000text'),
      throwsA(isA<LlamaArgumentException>()),
    );
    conversation.close();
    runtime.dispose();
  });
}
