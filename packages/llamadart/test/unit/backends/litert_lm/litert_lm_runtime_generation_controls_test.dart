@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:test/test.dart';

Future<String> _compileFixture(
  Directory dir,
  String name,
  List<String> defines,
) async {
  final library = '${dir.path}/$name.${Platform.isMacOS ? 'dylib' : 'so'}';
  final result = await Process.run('cc', [
    '-shared',
    '-fPIC',
    ...defines,
    'test/fixtures/litert_lm/generation_controls.c',
    '-o',
    library,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return library;
}

/// What the last send of test/fixtures/litert_lm/generation_controls.c
/// received through its optional args.
class _Fixture {
  _Fixture(String path) : _library = DynamicLibrary.open(path);

  final DynamicLibrary _library;

  late final int Function() sends = _int('fixture_sends');
  late final bool Function() hasPenalty = _bool('fixture_has_penalty');
  late final double Function() repetitionPenalty = _float(
    'fixture_repetition_penalty',
  );
  late final double Function() presencePenalty = _float(
    'fixture_presence_penalty',
  );
  late final bool Function() hasThinking = _bool('fixture_has_thinking');
  late final bool Function() enableThinking = _bool('fixture_enable_thinking');
  late final int Function() thinkingBudget = _int('fixture_thinking_budget');
  late final int Function() maxOutputTokens = _int('fixture_max_output_tokens');
  late final int Function() liveObjects = _int('fixture_live_objects');

  int Function() _int(String symbol) =>
      _library.lookupFunction<Int32 Function(), int Function()>(symbol);

  bool Function() _bool(String symbol) =>
      _library.lookupFunction<Bool Function(), bool Function()>(symbol);

  double Function() _float(String symbol) =>
      _library.lookupFunction<Float Function(), double Function()>(symbol);
}

void main() {
  late Directory dir;
  late String blocking;
  late String streaming;
  late String noPenalties;
  late String noPresence;
  late String noThinking;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('litert_generation_controls_');
    blocking = await _compileFixture(dir, 'blocking', []);
    streaming = await _compileFixture(dir, 'streaming', [
      '-DWITH_STREAM_PROXY',
    ]);
    noPenalties = await _compileFixture(dir, 'no_penalties', [
      '-DOMIT_PENALTIES',
    ]);
    noPresence = await _compileFixture(dir, 'no_presence', ['-DOMIT_PRESENCE']);
    noThinking = await _compileFixture(dir, 'no_thinking', ['-DOMIT_THINKING']);
  });

  tearDownAll(() => dir.delete(recursive: true));

  Future<LiteRtLmRuntimeClient> open(String library) async {
    final client = LiteRtLmRuntimeClient(libraryPath: library);
    addTearDown(client.dispose);
    await client.initialize(
      modelPath: '${dir.path}/model.litertlm',
      backend: 'cpu',
    );
    client.createConversation(npuBackend: true);
    return client;
  }

  const message = '{"role":"user","content":[{"type":"text","text":"Hello"}]}';

  // The pre-1.0 C API schema group always disables thinking, so native schema
  // chat must not admit a reasoning channel on it.
  test('a legacy runtime never advertises schema thinking', () async {
    final client = await open(blocking);
    expect(client.supportsJsonSchemaThinking, isFalse);
  });

  for (final (name, library) in [
    ('blocking', () => blocking),
    ('streaming', () => streaming),
  ]) {
    group('$name send', () {
      test('passes penalties and a thinking budget to the native '
          'setters', () async {
        final fixture = _Fixture(library());
        final client = await open(library());

        final text = await client
            .generateMessageJson(
              message,
              maxOutputTokens: 64,
              repetitionPenalty: 1.25,
              presencePenalty: -0.5,
              thinkingTokenBudget: 7,
            )
            .join();

        expect(text, 'ok');
        expect(fixture.hasPenalty(), isTrue);
        expect(fixture.repetitionPenalty(), 1.25);
        expect(fixture.presencePenalty(), -0.5);
        expect(fixture.hasThinking(), isTrue);
        expect(fixture.enableThinking(), isTrue);
        expect(fixture.thinkingBudget(), 7);
        expect(fixture.maxOutputTokens(), 64);
        expect(fixture.liveObjects(), 0);
      });

      test('fills an unset penalty with its neutral value', () async {
        final fixture = _Fixture(library());
        final client = await open(library());

        await client.generate('Hi', presencePenalty: 0.75).drain<void>();

        expect(fixture.hasPenalty(), isTrue);
        expect(fixture.repetitionPenalty(), 1.0);
        expect(fixture.presencePenalty(), 0.75);
        expect(fixture.hasThinking(), isFalse);

        await client.generate('Hi', repetitionPenalty: 1.4).drain<void>();

        expect(fixture.hasPenalty(), isTrue);
        expect(fixture.repetitionPenalty(), closeTo(1.4, 1e-6));
        expect(fixture.presencePenalty(), 0.0);
      });

      test('scopes controls to the send that sets them', () async {
        final fixture = _Fixture(library());
        final client = await open(library());

        await client
            .generateMessageJson(
              message,
              repetitionPenalty: 1.5,
              thinkingTokenBudget: 3,
            )
            .drain<void>();
        final sendsBefore = fixture.sends();
        await client.generateMessageJson(message).drain<void>();

        expect(fixture.sends(), sendsBefore + 1);
        expect(fixture.hasPenalty(), isFalse);
        expect(fixture.hasThinking(), isFalse);
        expect(fixture.liveObjects(), 0);
      });

      test('applies controls on a send after a cancelled one', () async {
        final fixture = _Fixture(library());
        final client = await open(library());

        final sendsBefore = fixture.sends();
        final cancelled = client
            .generateMessageJson(message, repetitionPenalty: 1.1)
            .listen(null);
        await cancelled.cancel();
        // A blocking send keeps running in its isolate after cancellation.
        for (var i = 0; i < 200 && fixture.sends() == sendsBefore; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(fixture.sends(), sendsBefore + 1);
        await client
            .generateMessageJson(message, presencePenalty: 0.25)
            .drain<void>();

        expect(fixture.hasPenalty(), isTrue);
        expect(fixture.repetitionPenalty(), 1.0);
        expect(fixture.presencePenalty(), 0.25);
        expect(fixture.liveObjects(), 0);
      });
    });
  }

  test('reports the controls a runtime exports', () {
    for (final (library, penalties, thinking) in [
      (blocking, true, true),
      (noPenalties, false, true),
      (noPresence, false, true),
      (noThinking, true, false),
    ]) {
      final client = LiteRtLmRuntimeClient(libraryPath: library);
      expect(client.supportsSamplingPenalties, penalties, reason: library);
      expect(client.supportsThinkingBudget, thinking, reason: library);
    }
  });

  test('a runtime that fails to load reports no controls', () {
    final client = LiteRtLmRuntimeClient(
      libraryPath: '${Directory.systemTemp.path}/missing_litert_lm.dylib',
    );

    expect(client.supportsSamplingPenalties, isFalse);
    expect(client.supportsThinkingBudget, isFalse);
  });

  for (final (name, library, controls, symbol) in [
    (
      'penalties without the penalty API',
      () => noPenalties,
      (LiteRtLmRuntimeClient client) =>
          client.generateMessageJson(message, repetitionPenalty: 1.2),
      'litert_lm_repetition_penalty_config_create',
    ),
    (
      'penalties without the presence setter',
      () => noPresence,
      (LiteRtLmRuntimeClient client) =>
          client.generateMessageJson(message, presencePenalty: 0.5),
      'litert_lm_repetition_penalty_config_set_presence_penalty',
    ),
    (
      'a thinking budget without the thinking API',
      () => noThinking,
      (LiteRtLmRuntimeClient client) =>
          client.generateMessageJson(message, thinkingTokenBudget: 4),
      'litert_lm_thinking_config_set_thinking_token_budget',
    ),
  ]) {
    test('refuses $name before sending', () async {
      final fixture = _Fixture(library());
      final client = await open(library());
      final sendsBefore = fixture.sends();

      expect(
        () => controls(client),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(contains(symbol), contains('v0.18.0 or newer')),
          ),
        ),
      );
      expect(fixture.sends(), sendsBefore);
      expect(fixture.liveObjects(), 0);
    });
  }

  test('rejects control values the runtime would clamp', () async {
    final client = await open(blocking);

    for (final call in <void Function()>[
      () => client.generateMessageJson(message, repetitionPenalty: 0.9),
      () => client.generateMessageJson(message, repetitionPenalty: double.nan),
      () =>
          client.generateMessageJson(message, presencePenalty: double.infinity),
      () => client.generateMessageJson(message, thinkingTokenBudget: 0),
    ]) {
      expect(call, throwsArgumentError);
    }
  });
}
