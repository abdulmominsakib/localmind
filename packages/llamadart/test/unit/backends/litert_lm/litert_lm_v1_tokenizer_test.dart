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
  final missing = <String, DynamicLibrary>{};
  const omissions = <String, String>{
    'tokenize': 'OMIT_TOKENIZE',
    'count': 'OMIT_TOKEN_COUNT',
    'array': 'OMIT_TOKEN_ARRAY',
    'delete': 'OMIT_TOKEN_DELETE',
    'start': 'OMIT_TOKEN_START',
    'type': 'OMIT_TOKEN_TYPE',
    'ids': 'OMIT_TOKEN_IDS',
    'string': 'OMIT_TOKEN_STRING',
    'union-delete': 'OMIT_TOKEN_UNION_DELETE',
    'detokenize': 'OMIT_DETOKENIZE',
    'detoken-string': 'OMIT_DETOKEN_STRING',
    'detoken-delete': 'OMIT_DETOKEN_DELETE',
  };
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_token_$name',
      )(value);
  int get(String name, int index, [DynamicLibrary? selected]) =>
      (selected ?? library)
          .lookupFunction<Int Function(Int), int Function(int)>(
            'fixture_token_$name',
          )(index);
  int live([DynamicLibrary? selected]) => (selected ?? library)
      .lookupFunction<Int Function(), int Function()>('fixture_live')();
  LiteRtLmV1Runtime loaded([DynamicLibrary? selected]) {
    final runtime = LiteRtLmV1Runtime(selected ?? library);
    runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
    addTearDown(runtime.dispose);
    return runtime;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_tokenizer_');
    for (final entry in {'valid': '', ...omissions}.entries) {
      final output =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (entry.value.isNotEmpty) '-D${entry.value}',
        'test/fixtures/litert_lm/c_api_v1_tokenizer.c',
        '-o',
        output,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (entry.key == 'valid') {
        library = DynamicLibrary.open(output);
        libraryPath = output;
      } else {
        missing[entry.key] = DynamicLibrary.open(output);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(
    () => library.lookupFunction<Void Function(), void Function()>(
      'fixture_token_reset',
    )(),
  );

  List<int> raw(String value) {
    final bytes = utf8.encode(value);
    return bytes.isEmpty ? [] : [bytes.length, bytes.first, bytes.last];
  }

  test('UTF8 token arrays are copied before result deletion', () {
    final runtime = loaded();
    final first = runtime.tokenize('A世界🙂', addSpecial: false);
    expect(first, raw('A世界🙂'));
    expect(runtime.tokenize('Other', addSpecial: false), raw('Other'));
    expect(first, raw('A世界🙂'));
    expect(get('deletes', 0), 2);
    expect(get('calls', 4), 0);
    expect(live(), 1);
    runtime.dispose();
    expect(live(), 0);
  });
  for (final mode in [0, 1, 2, 3, 4]) {
    test('addSpecial prepends configured BOS variant $mode', () {
      final runtime = loaded();
      set('mode', mode);
      expect(runtime.tokenize('Hi'), [
        if (mode == 1) ...[11, 22],
        if (mode == 2) ...[900, 901],
        ...raw('Hi'),
      ]);
      expect(get('calls', 4), 1);
      expect(get('deletes', 1), mode == 0 ? 0 : 1);
      expect(get('calls', 1), mode == 2 ? 2 : 1);
      expect(live(), 1);
      runtime.dispose();
      expect(live(), 0);
    });
  }
  test('empty raw text still receives configured BOS', () {
    final runtime = loaded();
    set('mode', 1);
    expect(runtime.tokenize(''), [11, 22]);
    expect(runtime.tokenize('', addSpecial: false), isEmpty);
    runtime.dispose();
    expect(live(), 0);
  });
  test(
    'BOS string is tokenized after raw text with no recursive BOS lookup',
    () {
      final runtime = loaded();
      set('mode', 2);
      expect(runtime.tokenize('Hi'), [900, 901, ...raw('Hi')]);
      final text = library
          .lookupFunction<
            Pointer<Utf8> Function(Int),
            Pointer<Utf8> Function(int)
          >('fixture_token_text');
      expect(text(1).toDartString(), 'Hi');
      expect(text(0).toDartString(), 'BOS');
      expect(get('calls', 4), 1);
      runtime.dispose();
      expect(live(), 0);
    },
  );
  for (final stage in [1, 2, 3, 4, 5, 6, 7]) {
    test(
      'tokenizer status failure $stage copies TLS diagnostic before cleanup',
      () {
        final runtime = loaded();
        set('mode', stage == 7 ? 2 : 1);
        set('fail', stage);
        expect(
          () => runtime.tokenize('Hi'),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'immediate diagnostic',
              allOf(
                contains('token-stage$stage'),
                isNot(contains('cleanup')),
                isNot(contains('/secret')),
              ),
            ),
          ),
        );
        expect(live(), 1);
        set('fail', 0);
        expect(runtime.tokenize('Hi'), [
          if (stage == 7) ...[900, 901] else ...[11, 22],
          ...raw('Hi'),
        ]);
        runtime.dispose();
        expect(live(), 0);
      },
    );
  }
  for (final mode in [5, 6, 7, 8, 100, 102, 104]) {
    test('invalid native tokenizer result $mode fails without leaking', () {
      final runtime = loaded();
      set('mode', mode);
      expect(() => runtime.tokenize('Hi'), throwsA(isA<LlamaException>()));
      expect(live(), 1);
      set('mode', 0);
      expect(runtime.tokenize('Hi'), raw('Hi'));
      runtime.dispose();
      expect(live(), 0);
    });
  }
  test('zero size_t count permits null borrowed array', () {
    final runtime = loaded();
    set('mode', 103);
    expect(runtime.tokenize('Hi'), isEmpty);
    runtime.dispose();
    expect(live(), 0);
  });
  test('detokenize copies UTF8 and passes signed C ints and size_t count', () {
    final runtime = loaded();
    const tokens = [-0x80000000, -1, 0, 42, 0x7fffffff];
    expect(runtime.detokenize(tokens), 'decoded 世界🙂');
    expect(
      library.lookupFunction<Size Function(), int Function()>(
        'fixture_token_input_count',
      )(),
      tokens.length,
    );
    expect(List.generate(tokens.length, (i) => get('input', i)), tokens);
    expect(get('deletes', 2), 1);
    expect(live(), 1);
    set('mode', 105);
    expect(runtime.detokenize([3]), '');
    runtime.dispose();
    expect(live(), 0);
  });
  test('empty detokenize returns empty without entering native tokenizer', () {
    final runtime = loaded();
    expect(runtime.detokenize([]), '');
    expect(get('calls', 8), 0);
    runtime.dispose();
    expect(live(), 0);
  });
  for (final stage in [8, 9]) {
    test(
      'detokenizer status failure $stage preserves error and frees owners',
      () {
        final runtime = loaded();
        set('fail', stage);
        expect(
          () => runtime.detokenize([1]),
          throwsA(
            isA<LlamaModelException>().having(
              (e) => e.message,
              'status before cleanup',
              contains('token-stage$stage'),
            ),
          ),
        );
        expect(live(), 1);
        set('fail', 0);
        expect(runtime.detokenize([1]), 'decoded 世界🙂');
        runtime.dispose();
        expect(live(), 0);
      },
    );
  }
  for (final mode in [101, 106]) {
    test('null detokenizer result $mode is refused and cleanup succeeds', () {
      final runtime = loaded();
      set('mode', mode);
      expect(
        () => runtime.detokenize([1]),
        throwsA(isA<LlamaStateException>()),
      );
      expect(live(), 1);
      runtime.dispose();
      expect(live(), 0);
    });
  }
  for (final name in omissions.keys) {
    test(
      'missing $name refuses complete tokenizer group before native calls',
      () {
        final selected = missing[name]!;
        final runtime = loaded(selected);
        expect(
          () => runtime.tokenize('Hi'),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          () => runtime.detokenize([1]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(get('calls', 1, selected), 0);
        expect(get('calls', 8, selected), 0);
        runtime.dispose();
        expect(live(selected), 0);
      },
    );
  }
  test(
    'unloaded/disposed and invalid input requests avoid native operations',
    () {
      final runtime = LiteRtLmV1Runtime(library);
      addTearDown(runtime.dispose);
      expect(() => runtime.tokenize('Hi'), throwsA(isA<LlamaStateException>()));
      expect(() => runtime.detokenize([]), throwsA(isA<LlamaStateException>()));
      runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
      expect(
        () => runtime.tokenize('A\u0000B'),
        throwsA(isA<LlamaArgumentException>()),
      );
      for (final token in [-0x80000001, 0x80000000]) {
        expect(
          () => runtime.detokenize([token]),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      expect(get('calls', 1), 0);
      expect(get('calls', 8), 0);
      runtime.dispose();
      expect(() => runtime.tokenize('Hi'), throwsA(isA<LlamaStateException>()));
      expect(() => runtime.detokenize([]), throwsA(isA<LlamaStateException>()));
      expect(live(), 0);
    },
  );
  test(
    'idle conversation permits tokenizer access; pending native turn refuses',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConversation();
      expect(runtime.tokenize('Hi'), raw('Hi'));
      expect(runtime.detokenize([1]), 'decoded 世界🙂');
      final turn = conversation.sendText('Hi');
      final chunks = turn.chunks.toList();
      try {
        final before = get('calls', 1);
        expect(
          () => runtime.tokenize('Hi'),
          throwsA(isA<LlamaStateException>()),
        );
        expect(
          () => runtime.detokenize([1]),
          throwsA(isA<LlamaStateException>()),
        );
        expect(get('calls', 1), before);
      } finally {
        library.lookupFunction<Void Function(Int), void Function(int)>(
          'fixture_emit',
        )(2);
        await turn.done;
        await chunks;
        conversation.close();
        runtime.dispose();
      }
      expect(live(), 0);
    },
  );
  test(
    'quarantined native work refuses tokenizer access in an isolated process',
    () async {
      final result = await Process.run('dart', [
        'run',
        'test/fixtures/litert_lm_v1_tokenizer_quarantine.dart',
        libraryPath,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
      expect(result.stdout, contains('tokenizer quarantine controls passed'));
    },
  );
}
