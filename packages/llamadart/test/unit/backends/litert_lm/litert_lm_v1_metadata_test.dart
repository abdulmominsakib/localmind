@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String libraryPath;
  final missing = <int, DynamicLibrary>{};
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_metadata_$name',
      )(value);
  int get(String name, int index, [DynamicLibrary? selected]) =>
      (selected ?? library)
          .lookupFunction<Int Function(Int), int Function(int)>(
            'fixture_metadata_$name',
          )(index);
  int live([DynamicLibrary? selected]) => (selected ?? library)
      .lookupFunction<Int Function(), int Function()>('fixture_live')();
  String input() => library
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'fixture_metadata_input',
      )()
      .toDartString();
  LiteRtLmV1Runtime runtime([DynamicLibrary? selected, bool load = true]) {
    final result = LiteRtLmV1Runtime(selected ?? library);
    addTearDown(result.dispose);
    if (load) {
      result.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
    }
    return result;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_metadata_');
    for (var i = 0; i <= 17; i++) {
      final output =
          '${directory.path}/$i.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        '-DOMIT_METADATA=$i',
        'test/fixtures/litert_lm/c_api_v1_metadata.c',
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (i == 0) {
        library = DynamicLibrary.open(output);
        libraryPath = output;
      } else {
        missing[i] = DynamicLibrary.open(output);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(
    () => library.lookupFunction<Void Function(), void Function()>(
      'fixture_metadata_reset',
    )(),
  );

  test(
    'file declaration flags map each modality and do not require an engine',
    () {
      final adapter = runtime(null, false);
      for (var bit = 0; bit < 7; bit++) {
        set('flags', 1 << bit);
        final flags = adapter.bundleCapabilities('/secret/other.litertlm');
        expect([
          flags.text,
          flags.vision,
          flags.audio,
          flags.video,
          flags.speculativeDecoding,
          flags.declaredThinking,
          flags.declaredFunctionCalling,
        ], List.generate(7, (index) => bit == index));
        expect(input(), '/secret/other.litertlm');
        expect(live(), 0);
      }
      expect(get('deletes', 0), 7);
      set('flags', 0);
      expect(adapter.bundleCapabilities('/model').declaredThinking, isFalse);
    },
  );
  test('thinking declaration does not admit unproven channel budgets', () {
    final adapter = runtime();
    final sends = library.lookupFunction<Int Function(), int Function()>(
      'fixture_sends',
    );
    final sendsBefore = sends();
    set('flags', 127);
    expect(adapter.bundleCapabilities('/model').declaredThinking, isTrue);
    final conversation = adapter.openConversation();
    try {
      for (final budget in [-1, 0, 16]) {
        expect(
          () => conversation.sendText(
            'think',
            settings: LiteRtLmV1TurnSettings(thinkingTokenBudget: budget),
          ),
          throwsA(
            budget <= 0
                ? isA<LlamaArgumentException>()
                : isA<LlamaUnsupportedException>(),
          ),
        );
      }
    } finally {
      conversation.close();
    }
    expect(sends(), sendsBefore);
  });
  for (var stage = 1; stage <= 5; stage++) {
    test('metadata failed status $stage preserves TLS before file cleanup', () {
      final adapter = runtime();
      set('fail', stage);
      expect(
        () => adapter.bundleCapabilities('/secret/other.litertlm'),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'sanitized immediate diagnostic',
            allOf(
              contains('metadata-stage$stage'),
              isNot(contains('/secret/')),
            ),
          ),
        ),
      );
      expect(live(), 1);
      expect(get('deletes', 0), stage == 1 ? 0 : 1);
      set('fail', 0);
      expect(adapter.bundleCapabilities('/model').text, isFalse);
    });
  }
  test('success without file owner is refused', () {
    final adapter = runtime();
    set('mode', 101);
    expect(
      () => adapter.bundleCapabilities('/model'),
      throwsA(isA<LlamaStateException>()),
    );
    expect(live(), 1);
  });
  for (var omission = 1; omission <= 6; omission++) {
    test(
      'missing metadata export $omission refuses before file allocation',
      () {
        final selected = missing[omission]!;
        final adapter = runtime(selected);
        expect(
          () => adapter.bundleCapabilities('/model'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(get('calls', 1, selected), 0);
        adapter.dispose();
        expect(live(selected), 0);
      },
    );
  }
  test('file invalid paths and disposed adapter never call native create', () {
    final adapter = runtime(null, false);
    for (final path in ['', 'a\u0000b']) {
      expect(
        () => adapter.bundleCapabilities(path),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
    adapter.dispose();
    expect(
      () => adapter.bundleCapabilities('/model'),
      throwsA(isA<LlamaStateException>()),
    );
    expect(get('calls', 1), 0);
  });
  test(
    'render encodes once and copies borrowed UTF8 across subsequent calls',
    () {
      final adapter = runtime();
      final conversation = adapter.openConversation();
      const message = {'role': 'user', 'content': '{"quoted":"世界🙂"}\n'};
      try {
        final first = conversation.renderMessageToString(message);
        expect(jsonDecode(input()), message);
        expect(first, 'render:${jsonEncode(message)}');
        conversation.renderMessageToString({
          'role': 'assistant',
          'content': 'Other',
        });
        expect(first, 'render:${jsonEncode(message)}');
        expect(get('deletes', 0), 0);
        expect(get('deletes', 1), 0);
      } finally {
        conversation.close();
      }
      expect(
        () => conversation.renderMessageToString(message),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test('render validates text/tool subset without entering native', () {
    final adapter = runtime();
    final conversation = adapter.openConversation();
    final cyclic = <String, Object?>{'role': 'user'};
    cyclic['content'] = cyclic;
    try {
      for (final message in <Map<String, Object?>>[
        {},
        cyclic,
        {'role': 'user', 'content': double.nan},
        {
          'role': 'user',
          'content': [
            {'type': 'image', 'path': '/image'},
          ],
        },
        {'role': 'developer', 'content': 'unknown'},
      ]) {
        expect(
          () => conversation.renderMessageToString(message),
          throwsA(isA<LlamaException>()),
        );
      }
      expect(get('calls', 6), 0);
    } finally {
      conversation.close();
    }
  });
  test('missing render export refuses and leaves conversation usable', () {
    final selected = missing[7]!;
    final adapter = runtime(selected);
    final conversation = adapter.openConversation();
    try {
      expect(
        () => conversation.renderMessageToString({
          'role': 'user',
          'content': 'Hi',
        }),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(get('calls', 6, selected), 0);
    } finally {
      conversation.close();
    }
  });
  for (final bad in [6, 106]) {
    test(
      'render status/null failure $bad is typed without freeing borrowed text',
      () {
        final adapter = runtime();
        final conversation = adapter.openConversation();
        try {
          set(bad == 6 ? 'fail' : 'mode', bad);
          expect(
            () => conversation.renderMessageToString({
              'role': 'user',
              'content': 'Hi',
            }),
            throwsA(
              bad == 6
                  ? isA<LlamaModelException>().having(
                      (e) => e.message,
                      'native status',
                      contains('metadata-stage6'),
                    )
                  : isA<LlamaStateException>(),
            ),
          );
          expect(get('deletes', 0), 0);
          expect(get('deletes', 1), 0);
        } finally {
          conversation.close();
        }
      },
    );
  }
  test(
    'metrics sum all turns, use last rates and preserve seconds/wall time',
    () {
      final adapter = runtime();
      final conversation = adapter.openConversation();
      try {
        final metrics = conversation.readMetrics(wallMilliseconds: 4321);
        expect(metrics.toJson(), {
          'inputTokens': 21,
          'outputTokens': 7,
          'timeToFirstTokenSeconds': 0.125,
          'initSeconds': 1.5,
          'prefillTokensPerSecond': 123.25,
          'decodeTokensPerSecond': 45.75,
          'wallMilliseconds': 4321,
        });
        expect(get('calls', 10), 2);
        expect(get('calls', 11), 2);
        expect(get('deletes', 1), 1);
        expect(live(), 2);
        set('mode', 8);
        expect(
          conversation.readMetrics(wallMilliseconds: 0).inputTokens,
          8589934596,
        );
      } finally {
        conversation.close();
      }
    },
  );
  test(
    'empty native history has null rates and native zero timings stay zero',
    () {
      final adapter = runtime();
      final conversation = adapter.openConversation();
      try {
        set('mode', 1);
        final empty = conversation.readMetrics(wallMilliseconds: 0);
        expect(empty.inputTokens, 0);
        expect(empty.outputTokens, 0);
        expect(empty.prefillTokensPerSecond, isNull);
        expect(empty.decodeTokensPerSecond, isNull);
        expect(get('calls', 12), 0);
        expect(get('calls', 13), 0);
        set('mode', 7);
        final zero = conversation.readMetrics(wallMilliseconds: 0);
        expect(zero.prefillTokensPerSecond, 0);
        expect(zero.decodeTokensPerSecond, 0);
        expect(zero.timeToFirstTokenSeconds, 0);
        expect(zero.initSeconds, 0);
      } finally {
        conversation.close();
      }
    },
  );
  for (var stage = 7; stage <= 15; stage++) {
    test('metrics failed status $stage preserves TLS and deletes snapshot', () {
      final adapter = runtime();
      final conversation = adapter.openConversation();
      try {
        set('fail', stage);
        expect(
          () => conversation.readMetrics(wallMilliseconds: 0),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'immediate diagnostic',
              allOf(
                contains('metadata-stage$stage'),
                isNot(contains('/secret/')),
              ),
            ),
          ),
        );
        expect(get('deletes', 1), stage == 7 ? 0 : 1);
        expect(live(), 2);
        set('fail', 0);
        expect(conversation.readMetrics(wallMilliseconds: 0).outputTokens, 7);
      } finally {
        conversation.close();
      }
    });
  }
  for (final mode in [2, 3, 4, 5, 6, 107]) {
    test(
      'invalid metric native result $mode refuses without truncation/leak',
      () {
        final adapter = runtime();
        final conversation = adapter.openConversation();
        try {
          set('mode', mode);
          expect(
            () => conversation.readMetrics(wallMilliseconds: 0),
            throwsA(isA<LlamaStateException>()),
          );
          expect(get('deletes', 1), mode == 107 ? 0 : 1);
          expect(live(), 2);
        } finally {
          conversation.close();
        }
      },
    );
  }
  for (var omission = 8; omission <= 17; omission++) {
    test(
      'missing metric export $omission refuses before snapshot allocation',
      () {
        final selected = missing[omission]!;
        final adapter = runtime(selected);
        final conversation = adapter.openConversation();
        try {
          expect(
            () => conversation.readMetrics(wallMilliseconds: 0),
            throwsA(isA<LlamaUnsupportedException>()),
          );
          expect(get('calls', 7, selected), 0);
        } finally {
          conversation.close();
        }
        adapter.dispose();
        expect(live(selected), 0);
      },
    );
  }
  test(
    'pending/closed lifetime and invalid wall time avoid native inspection',
    () async {
      final adapter = runtime();
      final conversation = adapter.openConversation();
      expect(
        () => conversation.readMetrics(wallMilliseconds: -1),
        throwsA(isA<LlamaArgumentException>()),
      );
      final turn = conversation.sendText('Hi');
      final chunks = turn.chunks.toList();
      try {
        expect(
          () => adapter.bundleCapabilities('/model'),
          throwsA(isA<LlamaStateException>()),
        );
        expect(
          () => conversation.renderMessageToString({
            'role': 'user',
            'content': 'Hi',
          }),
          throwsA(isA<LlamaStateException>()),
        );
        expect(
          () => conversation.readMetrics(wallMilliseconds: 0),
          throwsA(isA<LlamaStateException>()),
        );
        for (final stage in [1, 6, 7]) {
          expect(get('calls', stage), 0);
        }
      } finally {
        library.lookupFunction<Void Function(Int), void Function(int)>(
          'fixture_emit',
        )(2);
        await turn.done;
        await chunks;
        conversation.close();
      }
      expect(
        () => conversation.readMetrics(wallMilliseconds: 0),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test(
    'quarantined family refuses inspection in an isolated process',
    () async {
      final result = await Process.run('dart', [
        'run',
        'test/fixtures/litert_lm_v1_metadata_quarantine.dart',
        libraryPath,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
      expect(result.stdout, contains('metadata quarantine controls passed'));
    },
  );
}
