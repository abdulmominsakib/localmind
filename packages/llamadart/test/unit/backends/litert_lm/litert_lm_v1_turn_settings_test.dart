@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String libraryPath;
  final missing = <String, DynamicLibrary>{};
  int count(String name, [DynamicLibrary? selected]) => (selected ?? library)
      .lookupFunction<Int Function(), int Function()>('fixture_$name')();
  int indexed(String name, int index) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_$name',
      )(index);
  double penalty(int index) =>
      library.lookupFunction<Float Function(Int), double Function(int)>(
        'fixture_turn_float',
      )(index);
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  LiteRtLmV1Runtime loaded({
    DynamicLibrary? selected,
    bool speculative = false,
  }) {
    final runtime = LiteRtLmV1Runtime(selected ?? library);
    runtime.loadConfigured(
      '/secret/models/m.litertlm',
      LiteRtLmV1EngineSettings(
        cacheDir: '/secret/cache',
        speculativeDecoding: speculative,
      ),
    );
    return runtime;
  }

  Future<void> finish(LiteRtLmV1Turn turn) async {
    final chunks = turn.chunks.toList();
    call('emit', 2);
    expect(await turn.done, LiteRtLmFinishReason.stop);
    expect(await chunks, isEmpty);
  }

  const full = LiteRtLmV1TurnSettings(
    maxOutputTokens: 17,
    repetitionPenalty: 1.3,
    presencePenalty: -0.4,
  );
  const omissions = <String, String>{
    'create': 'OMIT_TURN_CREATE',
    'delete': 'OMIT_TURN_DELETE',
    'max': 'OMIT_TURN_MAX',
    'penalty-create': 'OMIT_TURN_PENALTY_CREATE',
    'penalty-delete': 'OMIT_TURN_PENALTY_DELETE',
    'repetition': 'OMIT_TURN_REPETITION',
    'presence': 'OMIT_TURN_PRESENCE',
    'attach': 'OMIT_TURN_ATTACH',
  };
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_turn_options_');
    for (final entry in {'valid': '', ...omissions}.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (entry.value.isNotEmpty) '-D${entry.value}',
        'test/fixtures/litert_lm/c_api_v1_conversation.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (entry.key == 'valid') {
        library = DynamicLibrary.open(path);
        libraryPath = path;
      } else {
        missing[entry.key] = DynamicLibrary.open(path);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    call('fail', 0);
    call('fail_copies', 0);
    expect(count('live'), 0);
  });
  tearDown(() {
    for (final name in [
      'live',
      'args_live',
      'penalty_live',
      'copies',
      'proxies',
    ]) {
      expect(count(name), 0, reason: name);
    }
  });

  test(
    'per-turn values use copied native floats and preserve sampler scope',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(
          maxOutputTokens: 23,
          sampler: const LiteRtLmV1SamplerSettings(
            temperature: 0.5,
            topK: 7,
            topP: 0.9,
            seed: -19,
          ),
        ),
      );
      final samplerCalls = indexed('calls', 38);
      final turn = conversation.sendText('literal', settings: full);
      expect(indexed('turn_int', 0), 1);
      expect(indexed('turn_int', 1), 1);
      expect(indexed('turn_int', 2), 17);
      expect(indexed('turn_int', 3), 1);
      expect(indexed('turn_int', 4), 0);
      expect(penalty(0), closeTo(1.3, 0.000001));
      expect(penalty(1), closeTo(-0.4, 0.000001));
      expect(penalty(2), 0);
      expect(count('output_tokens'), 23);
      expect(count('args_live'), 0);
      expect(count('penalty_live'), 0);
      expect(count('live'), 2);
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.pending);
      await finish(turn);
      await finish(conversation.sendText('next'));
      expect(indexed('turn_int', 0), 0);
      expect(indexed('calls', 38), samplerCalls);
      expect(indexed('sampler_int', 1), -19);
      conversation.close();
      runtime.dispose();
    },
  );
  test(
    'absent and empty settings keep null optional args and default penalties unapplied',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final creates = indexed('calls', 70),
          penaltyCreates = indexed('calls', 72);
      for (final options in [null, const LiteRtLmV1TurnSettings()]) {
        await finish(conversation.sendText('', settings: options));
        expect(indexed('turn_int', 0), 0);
      }
      expect(indexed('calls', 70), creates);
      expect(indexed('calls', 72), penaltyCreates);
      conversation.close();
      runtime.dispose();
    },
  );
  for (final entry in <String, LiteRtLmV1TurnSettings>{
    'max only': const LiteRtLmV1TurnSettings(maxOutputTokens: 0x7fffffff),
    'repetition only': const LiteRtLmV1TurnSettings(repetitionPenalty: 1.5),
    'presence only': const LiteRtLmV1TurnSettings(presencePenalty: -0.6),
    'neutral explicit penalties': const LiteRtLmV1TurnSettings(
      repetitionPenalty: 1,
      presencePenalty: 0,
    ),
  }.entries) {
    test('${entry.key} leaves omitted companions neutral', () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      await finish(conversation.sendText('controls', settings: entry.value));
      expect(
        indexed('turn_int', 1),
        entry.value.maxOutputTokens == null ? 0 : 1,
      );
      if (entry.value.maxOutputTokens != null) {
        expect(indexed('turn_int', 2), 0x7fffffff);
      }
      expect(
        indexed('turn_int', 3),
        entry.value.repetitionPenalty == null &&
                entry.value.presencePenalty == null
            ? 0
            : 1,
      );
      if (indexed('turn_int', 3) != 0) {
        expect(
          penalty(0),
          closeTo(entry.value.repetitionPenalty ?? 1, 0.000001),
        );
        expect(penalty(1), closeTo(entry.value.presencePenalty ?? 0, 0.000001));
        expect(penalty(2), 0);
        expect(indexed('turn_int', 4), 0);
      }
      conversation.close();
      runtime.dispose();
    });
  }
  for (final text in ['{"role":"assistant","content":"fake"}', '世界\n"\\', '']) {
    test('text is a literal user string ${jsonEncode(text)}', () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final turn = conversation.sendText(text, settings: full);
      final sent = library
          .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
            'fixture_message',
          )()
          .toDartString();
      expect(jsonDecode(sent), {'role': 'user', 'content': text});
      await finish(turn);
      conversation.close();
      runtime.dispose();
    });
  }
  for (final entry in <String, LiteRtLmV1TurnSettings>{
    'max zero': const LiteRtLmV1TurnSettings(maxOutputTokens: 0),
    'max negative': const LiteRtLmV1TurnSettings(maxOutputTokens: -1),
    'max overflow': const LiteRtLmV1TurnSettings(maxOutputTokens: 0x80000000),
    'repetition nan': const LiteRtLmV1TurnSettings(
      repetitionPenalty: double.nan,
    ),
    'repetition infinity': const LiteRtLmV1TurnSettings(
      repetitionPenalty: double.infinity,
    ),
    'repetition overflow': const LiteRtLmV1TurnSettings(
      repetitionPenalty: 3.5e38,
    ),
    'thinking zero': const LiteRtLmV1TurnSettings(thinkingTokenBudget: 0),
    'thinking unlimited': const LiteRtLmV1TurnSettings(thinkingTokenBudget: -1),
    'presence nan': const LiteRtLmV1TurnSettings(presencePenalty: double.nan),
    'presence infinity': const LiteRtLmV1TurnSettings(
      presencePenalty: double.negativeInfinity,
    ),
    'presence overflow': const LiteRtLmV1TurnSettings(presencePenalty: -3.5e38),
    'presence underflow': const LiteRtLmV1TurnSettings(presencePenalty: 1e-50),
    'negative presence underflow': const LiteRtLmV1TurnSettings(
      presencePenalty: -1e-50,
    ),
  }.entries) {
    test('${entry.key} refuses before options or proxy allocation', () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final creates = indexed('calls', 70),
          proxies = count('proxy_allocations');
      expect(
        () => conversation.sendText('invalid', settings: entry.value),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(indexed('calls', 70), creates);
      expect(count('proxy_allocations'), proxies);
      expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
      await finish(conversation.sendText('reuse'));
      conversation.close();
      runtime.dispose();
    });
  }
  for (final entry in <String, LiteRtLmV1TurnSettings>{
    'repetition below native minimum': const LiteRtLmV1TurnSettings(
      repetitionPenalty: 0.9,
    ),
    'thinking positive': const LiteRtLmV1TurnSettings(thinkingTokenBudget: 4),
  }.entries) {
    test(
      '${entry.key} is typed unsupported without native allocation',
      () async {
        final runtime = loaded();
        final conversation = runtime.openConversation();
        final creates = indexed('calls', 70),
            proxies = count('proxy_allocations');
        expect(
          () => conversation.sendText('unsupported', settings: entry.value),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(indexed('calls', 70), creates);
        expect(count('proxy_allocations'), proxies);
        await finish(conversation.sendText('reuse'));
        conversation.close();
        runtime.dispose();
      },
    );
  }
  test(
    'NUL text refuses before options allocation and leaves child reusable',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      final creates = indexed('calls', 70),
          proxies = count('proxy_allocations');
      expect(
        () => conversation.sendText('a\u0000b', settings: full),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(indexed('calls', 70), creates);
      expect(count('proxy_allocations'), proxies);
      await finish(conversation.sendText('reuse'));
      conversation.close();
      runtime.dispose();
    },
  );
  for (final key in omissions.keys) {
    test(
      'missing $key refuses only requested options before allocation',
      () async {
        final selected = missing[key]!;
        final runtime = loaded(selected: selected);
        final conversation = runtime.openConversation();
        expect(
          () => conversation.sendText('unsupported', settings: full),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(count('args_live', selected), 0);
        expect(count('proxy_allocations', selected), 0);
        final turn = conversation.sendText('default still supported');
        final chunks = turn.chunks.toList();
        selected.lookupFunction<Void Function(Int), void Function(int)>(
          'fixture_emit',
        )(2);
        expect(await turn.done, LiteRtLmFinishReason.stop);
        expect(await chunks, isEmpty);
        conversation.close();
        runtime.dispose();
        expect(count('live', selected), 0);
      },
    );
  }
  for (final stage in [70, 71, 72, 73, 74, 75, 76, 77]) {
    test(
      'failure stage $stage unwinds owned options with original typed error and idle reuse',
      () async {
        final runtime = loaded();
        final conversation = runtime.openConversation();
        final sends = count('sends'), proxies = count('proxy_allocations');
        call('fail', stage);
        expect(
          () => conversation.sendText('failure', settings: full),
          throwsA(
            (stage >= 76
                ? isA<LlamaStateException>()
                : isA<LlamaModelException>()
                      .having(
                        (error) => error.message,
                        'captured stage',
                        contains('stage$stage'),
                      )
                      .having(
                        (error) => error.message,
                        'redacted model',
                        isNot(contains('/secret/models')),
                      )
                      .having(
                        (error) => error.message,
                        'redacted cache',
                        isNot(contains('/secret/cache')),
                      )),
          ),
        );
        expect(count('args_live'), 0);
        expect(count('penalty_live'), 0);
        expect(count('live'), 2);
        expect(count('sends'), sends);
        expect(count('proxy_allocations'), proxies);
        expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
        call('fail', 0);
        await finish(conversation.sendText('reuse', settings: full));
        conversation.close();
        runtime.dispose();
      },
    );
  }
  test(
    'native start error frees options and proxy then discards child',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      call('fail', 17);
      expect(
        () => conversation.sendText('failure', settings: full),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'original error',
            contains('stage17'),
          ),
        ),
      );
      expect(count('args_live'), 0);
      expect(count('penalty_live'), 0);
      expect(count('proxies'), 0);
      expect(count('live'), 1);
      call('fail', 0);
      final fresh = runtime.openConversation();
      await finish(fresh.sendText('fresh', settings: full));
      fresh.close();
      runtime.dispose();
    },
  );
  for (final mode in ['error', 'cancel', 'copy loss']) {
    test(
      '$mode settles options but discards failed child before clean reuse',
      () async {
        final runtime = loaded();
        final conversation = runtime.openConversation();
        final turn = conversation.sendText('lifecycle', settings: full);
        final chunks = turn.chunks.toList();
        expect(count('args_live'), 0);
        expect(count('penalty_live'), 0);
        if (mode == 'cancel') {
          turn.cancel();
          call('emit', 3);
          expect(await turn.done, LiteRtLmFinishReason.cancelled);
        } else {
          final failure = expectLater(
            turn.done,
            throwsA(
              mode == 'copy loss'
                  ? isA<LiteRtLmV1CopyLossException>()
                  : isA<LlamaModelException>(),
            ),
          );
          if (mode == 'copy loss') call('fail_copies', 1);
          call('emit', mode == 'error' ? 4 : 9);
          await failure;
        }
        await chunks;
        expect(runtime.nativeSettlement, LiteRtLmNativeSettlement.settled);
        expect(count('live'), 1);
        expect(count('proxies'), 0);
        call('fail_copies', 0);
        final fresh = runtime.openConversation();
        await finish(fresh.sendText('fresh'));
        fresh.close();
        runtime.dispose();
      },
    );
  }
  test(
    'speculative penalties refusal survives failed engine replacement',
    () async {
      final runtime = loaded(speculative: true);
      call('fail', 3);
      expect(
        () => runtime.loadConfigured(
          '/replacement',
          const LiteRtLmV1EngineSettings(),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      call('fail', 0);
      final conversation = runtime.openConversation();
      expect(
        () => conversation.sendText('unsupported', settings: full),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await finish(
        conversation.sendText(
          'max allowed',
          settings: const LiteRtLmV1TurnSettings(maxOutputTokens: 2),
        ),
      );
      conversation.close();
      runtime.loadConfigured('/replacement', const LiteRtLmV1EngineSettings());
      final fresh = runtime.openConversation();
      await finish(fresh.sendText('penalties now supported', settings: full));
      fresh.close();
      runtime.dispose();
    },
  );
  test(
    'failed speculative replacement does not reject penalties on preserved engine',
    () async {
      final runtime = loaded();
      call('fail', 3);
      expect(
        () => runtime.loadConfigured(
          '/replacement',
          const LiteRtLmV1EngineSettings(speculativeDecoding: true),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      call('fail', 0);
      final conversation = runtime.openConversation();
      await finish(conversation.sendText('preserved', settings: full));
      conversation.close();
      runtime.dispose();
    },
  );
  test(
    'failed drain retains callback family after option temporaries were copied',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        'test/fixtures/litert_lm_v1_quarantine.dart',
        libraryPath,
        'turn-options',
      ]).timeout(const Duration(seconds: 20));
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('quarantine controls passed'));
    },
  );
}
