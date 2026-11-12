@TestOn('vm && (mac-os || linux)')
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

import '../../../support/dart_script_snapshot.dart';

Uint8List _protoField(int field, List<int> value) =>
    Uint8List.fromList([(field << 3) | 2, ..._varint(value.length), ...value]);

List<int> _varint(int value) {
  final bytes = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    bytes.add((rest & 0x7f) | 0x80);
    rest >>= 7;
  }
  return bytes..add(rest);
}

/// The `LlmMetadata` protobuf of a bundle whose template is [template].
Uint8List _metadata(String? template) => Uint8List.fromList([
  // start_token, a nested message, then max_num_tokens, a varint.
  ..._protoField(1, [0x0a, 0x01, 0x41]),
  0x28, 0x80, 0x20,
  if (template != null) ..._protoField(7, utf8.encode(template)),
]);

/// A `.litertlm` file with [sections] laid out after a FlatBuffers header
/// that [headerPadding] unused bytes follow.
Uint8List _bundle(
  List<({int type, Uint8List data})> sections, {
  int headerPadding = 0,
}) {
  const headerStart = 32;
  // Root offset, root vtable and table, section-metadata vtable and table,
  // then the vector of section objects.
  final objectsStart = 44 + 4 * sections.length;
  final headerEnd =
      headerStart + objectsStart + 36 * sections.length + headerPadding;
  var dataOffset = headerEnd + 16;

  final header = ByteData(headerEnd - headerStart - headerPadding);
  header.setUint32(0, 12, Endian.little);
  header.setUint16(4, 8, Endian.little);
  header.setUint16(6, 12, Endian.little);
  header.setUint16(10, 8, Endian.little);
  header.setInt32(12, 8, Endian.little);
  header.setUint32(20, 12, Endian.little);
  header.setUint16(24, 6, Endian.little);
  header.setUint16(26, 8, Endian.little);
  header.setUint16(28, 4, Endian.little);
  header.setInt32(32, 8, Endian.little);
  header.setUint32(36, 4, Endian.little);
  header.setUint32(40, sections.length, Endian.little);

  final body = BytesBuilder();
  for (var i = 0; i < sections.length; i++) {
    final vtable = objectsStart + 36 * i;
    final table = vtable + 12;
    final slot = 44 + 4 * i;
    header.setUint32(slot, table - slot, Endian.little);
    header.setUint16(vtable, 12, Endian.little);
    header.setUint16(vtable + 2, 24, Endian.little);
    header.setUint16(vtable + 6, 8, Endian.little);
    header.setUint16(vtable + 8, 16, Endian.little);
    header.setUint16(vtable + 10, 4, Endian.little);
    header.setInt32(table, 12, Endian.little);
    header.setUint8(table + 4, sections[i].type);
    header.setUint64(table + 8, dataOffset, Endian.little);
    dataOffset += sections[i].data.length;
    header.setUint64(table + 16, dataOffset, Endian.little);
    body.add(sections[i].data);
  }

  final prefix = ByteData(headerStart);
  prefix.buffer.asUint8List().setAll(0, ascii.encode('LITERTLM'));
  prefix.setUint32(8, 1, Endian.little);
  prefix.setUint32(12, 7, Endian.little);
  prefix.setUint64(24, headerEnd, Endian.little);
  return (BytesBuilder()
        ..add(prefix.buffer.asUint8List())
        ..add(header.buffer.asUint8List())
        ..add(Uint8List(headerPadding + 16))
        ..add(body.takeBytes()))
      .takeBytes();
}

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String libraryPath;
  late String retentionScript;
  final variants = <String, DynamicLibrary>{};
  var nextModel = 0;
  int count(String name, [DynamicLibrary? selected]) => (selected ?? library)
      .lookupFunction<Int Function(), int Function()>('fixture_$name')();
  int calls(int stage) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_calls',
      )(stage);
  void set(String name, int value, [DynamicLibrary? selected]) =>
      (selected ?? library)
          .lookupFunction<Void Function(Int), void Function(int)>(
            'fixture_$name',
          )(value);
  List<int> channel({
    String name = 'thought',
    String? start = '<think>',
    String? end = '</think>',
    int? reasoning = 1,
  }) => [
    ..._protoField(1, utf8.encode(name)),
    if (start != null) ..._protoField(2, utf8.encode(start)),
    if (end != null) ..._protoField(3, utf8.encode(end)),
    if (reasoning != null) 0x20,
    ?reasoning,
  ];
  File model({List<List<int>>? channels}) =>
      File('${directory.path}/thinking${nextModel++}.litertlm')
        ..writeAsBytesSync(
          _bundle([
            (
              type: 5,
              data: Uint8List.fromList([
                ..._metadata(null),
                for (final item in channels ?? [channel()])
                  ..._protoField(8, item),
              ]),
            ),
          ]),
        );
  void emit(String? json, {int reason = 1, DynamicLibrary? selected}) {
    final text = json?.toNativeUtf8(allocator: calloc) ?? nullptr;
    try {
      (selected ?? library).lookupFunction<
        Void Function(Pointer<Utf8>, Bool, Int),
        void Function(Pointer<Utf8>, bool, int)
      >('fixture_client_emit')(text, true, reason);
    } finally {
      if (text != nullptr) calloc.free(text);
    }
  }

  Future<LiteRtLmV1RuntimeClient> client({
    File? input,
    DynamicLibrary? selected,
    bool speculative = false,
  }) async {
    final result = LiteRtLmV1RuntimeClient(selected ?? library);
    addTearDown(() async {
      if (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
        result.cancel();
        emit(null, reason: 4, selected: selected);
        while (result.nativeSettlement == LiteRtLmNativeSettlement.pending) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      result.dispose();
    });
    await result.initialize(
      modelPath: (input ?? model()).path,
      backend: 'cpu',
      speculativeDecoding: speculative,
      numberOfThreads: 2,
    );
    return result;
  }

  Future<void> complete(
    Stream<String> stream, {
    DynamicLibrary? selected,
  }) async {
    final output = stream.toList();
    emit(
      '{"role":"assistant","content":[{"type":"text","text":"ok"}]}',
      selected: selected,
    );
    expect((await output).join(), 'ok');
  }

  Stream<String> budget(
    LiteRtLmV1RuntimeClient client, {
    int? value = 4,
    Map<String, dynamic>? extraContext,
    String? jsonSchema,
  }) => client.generateMessageJson(
    '{"role":"user","content":"reason"}',
    thinkingTokenBudget: value,
    extraContext: extraContext,
    jsonSchema: jsonSchema,
  );

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_thinking_');
    for (final entry in {
      'full': '',
      'create': 'OMIT_THINK_CREATE',
      'delete': 'OMIT_THINK_DELETE',
      'enable': 'OMIT_THINK_ENABLE',
      'budget': 'OMIT_THINK_BUDGET',
      'attach': 'OMIT_THINK_ARGS',
      'args-create': 'OMIT_THINK_ARGS_CREATE',
      'args-delete': 'OMIT_TURN_DELETE',
      'tokenize': 'OMIT_TOKENIZE',
      'token-delete': 'OMIT_TOKEN_DELETE',
      'token-array': 'OMIT_TOKEN_ARRAY',
      'token-count': 'OMIT_TOKEN_COUNT',
      'detokenize': 'OMIT_DETOKENIZE',
      'detoken-delete': 'OMIT_DETOKEN_DELETE',
      'detoken-string': 'OMIT_DETOKEN_STRING',
      'start-token': 'OMIT_TOKEN_START',
      'union-delete': 'OMIT_TOKEN_UNION_DELETE',
      'union-type': 'OMIT_TOKEN_TYPE',
      'union-string': 'OMIT_TOKEN_STRING',
      'union-ids': 'OMIT_TOKEN_IDS',
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (entry.value.isNotEmpty) '-D${entry.value}',
        'test/fixtures/litert_lm/c_api_v1_thinking.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      variants[entry.key] = DynamicLibrary.open(path);
      if (entry.key == 'full') libraryPath = path;
    }
    library = variants['full']!;
    retentionScript = await compileDartScript(
      'test/fixtures/litert_lm_v1_thinking_retention.dart',
    );
  });
  setUp(() {
    set('fail', 0);
    set('token_fail', 0);
    set('thinking_mode', 0);
    set('thinking_token_mode', 0);
  });
  tearDown(() {
    for (final selected in variants.values) {
      expect(count('live', selected), 0);
      expect(count('proxies', selected), 0);
      expect(count('args_live', selected), 0);
      expect(count('thinking_live', selected), 0);
    }
  });
  tearDownAll(() => directory.delete(recursive: true));

  test(
    'runtime capability is allocation-free and missing each required export is false',
    () {
      for (final entry in variants.entries) {
        final probe = LiteRtLmV1RuntimeClient(entry.value);
        expect(
          probe.supportsThinkingBudget,
          entry.key == 'full',
          reason: entry.key,
        );
        expect(count('live', entry.value), 0);
        probe.dispose();
        expect(probe.supportsThinkingBudget, isFalse);
      }
    },
  );
  test(
    'positive thinking budget and enable cross native ABI by value with owned cleanup',
    () async {
      final adapter = await client();
      adapter.createConversation(extraContext: {'enable_thinking': true});
      final before = calls(91);
      final stream = budget(adapter, value: 0x7fffffff);
      expect(count('thinking_present'), 1);
      expect(count('thinking_enabled'), 1);
      expect(count('thinking_budget'), 0x7fffffff);
      expect(count('thinking_live'), 0);
      expect(count('args_live'), 0);
      expect(calls(91), before + 1);
      expect(
        library.lookupFunction<Int Function(Int), int Function(int)>(
          'fixture_token_calls',
        )(4),
        0,
      );
      await complete(stream);
    },
  );
  test(
    'native send failure deletes thinking options before an ordinary retry',
    () async {
      final adapter = await client();
      adapter.createConversation();
      set('fail', 17);
      expect(() => budget(adapter), throwsA(isA<LlamaModelException>()));
      expect(count('thinking_live'), 0);
      expect(count('args_live'), 0);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      set('fail', 0);
      adapter.createConversation();
      await complete(budget(adapter, value: null));
      expect(count('thinking_present'), 0);
    },
  );
  test('unknown effective thinking values refuse before send', () async {
    final adapter = await client();
    adapter.createConversation();
    final before = count('sends');
    for (final value in <Object?>[null, 0, 'true']) {
      expect(
        () => budget(adapter, extraContext: {'enable_thinking': value}),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    }
    expect(count('sends'), before);
  });
  test('no budget sets no thinking override after a bounded turn', () async {
    final adapter = await client();
    adapter.createConversation();
    await complete(budget(adapter));
    final before = calls(91);
    await complete(budget(adapter, value: null));
    expect(count('thinking_present'), 0);
    expect(calls(91), before);
  });
  test(
    'unknown optional thinking exports do not disable ordinary unbounded text',
    () async {
      final selected = variants['budget']!;
      final adapter = await client(selected: selected);
      adapter.createConversation();
      expect(adapter.supportsThinkingBudget, isFalse);
      expect(() => budget(adapter), throwsA(isA<LlamaUnsupportedException>()));
      await complete(budget(adapter, value: null), selected: selected);
    },
  );
  test('partial thinking owner is deleted after copied native error', () async {
    final adapter = await client();
    adapter.createConversation();
    final before = count('live');
    set('thinking_mode', 1);
    expect(
      () => budget(adapter),
      throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'copied error',
          contains('thinking-partial'),
        ),
      ),
    );
    expect(count('live'), before);
    expect(count('thinking_live'), 0);
    expect(count('args_live'), 0);
  });
  test(
    'partial optional args owner is deleted after copied native error',
    () async {
      final adapter = await client();
      adapter.createConversation();
      final before = count('live');
      set('thinking_mode', 3);
      expect(
        () => budget(adapter),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'copied error',
            contains('args-partial'),
          ),
        ),
      );
      expect(count('live'), before);
      expect(count('args_live'), 0);
    },
  );
  for (final stage in [70, 91, 92, 97, 94]) {
    test(
      'thinking status failure $stage preserves error and cleans pre-send owners',
      () async {
        final adapter = await client();
        adapter.createConversation();
        final before = count('live');
        set('fail', stage);
        expect(
          () => budget(adapter),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'status',
              contains('stage$stage'),
            ),
          ),
        );
        expect(count('live'), before);
        expect(count('thinking_live'), 0);
        expect(count('args_live'), 0);
        set('fail', 0);
        await complete(budget(adapter));
      },
    );
  }
  test(
    'success with null thinking config refuses without native send or leak',
    () async {
      final adapter = await client();
      adapter.createConversation();
      final before = count('sends');
      set('thinking_mode', 2);
      expect(() => budget(adapter), throwsA(isA<LlamaStateException>()));
      expect(count('sends'), before);
      expect(count('thinking_live'), 0);
      expect(count('args_live'), 0);
    },
  );
  for (final value in [0, -1, 0x80000000]) {
    test(
      'thinking budget $value is refused before optional args allocation',
      () async {
        final adapter = await client();
        adapter.createConversation();
        final before = calls(70);
        expect(
          () => budget(adapter, value: value),
          throwsA(isA<LlamaArgumentException>()),
        );
        expect(calls(70), before);
      },
    );
  }
  for (final (index, data) in [
    <List<int>>[],
    [channel(name: 'answer', reasoning: 0), channel()],
    [channel(reasoning: 0)],
    [channel(name: 'unknown', reasoning: null)],
    [channel(start: null)],
    [channel(end: '')],
    [channel(start: 'same', end: 'same')],
    [channel(start: 'bad\u0000marker')],
    [channel(name: 'bad\u0000name')],
    [channel(reasoning: 2)],
  ].indexed) {
    test('missing or wrong first-channel proof case $index refuses', () async {
      final adapter = await client(input: model(channels: data));
      adapter.createConversation();
      final before = calls(70);
      expect(() => budget(adapter), throwsA(isA<LlamaUnsupportedException>()));
      expect(calls(70), before);
    });
  }
  test(
    'legacy name fallback and explicit arbitrary reasoning name remain admitted',
    () async {
      for (final data in [
        channel(reasoning: null),
        channel(name: 'custom', reasoning: 1),
        channel(start: '思考：', end: '終了。'),
      ]) {
        final adapter = await client(input: model(channels: [data]));
        adapter.createConversation();
        await complete(budget(adapter));
        adapter.dispose();
      }
    },
  );
  for (final mode in [1, 2, 3, 4, 5, 6]) {
    test(
      'bad native boundary tokenization $mode refuses before thinking allocation',
      () async {
        final adapter = await client();
        adapter.createConversation();
        final before = calls(91);
        set('thinking_token_mode', mode);
        expect(
          () => budget(adapter),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(calls(91), before);
        expect(count('thinking_live'), 0);
      },
    );
  }
  test(
    'native tokenizer failure copies status before result cleanup',
    () async {
      final adapter = await client();
      adapter.createConversation();
      set('token_fail', 1);
      expect(
        () => budget(adapter),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'token status',
            contains('token-stage1'),
          ),
        ),
      );
      expect(count('thinking_live'), 0);
      expect(count('args_live'), 0);
    },
  );
  test(
    'effective send context overrides immutable conversation context only for this turn',
    () async {
      final context = <String, dynamic>{'enable_thinking': false};
      final adapter = await client();
      adapter.createConversation(extraContext: context);
      context['enable_thinking'] = true;
      expect(() => budget(adapter), throwsA(isA<LlamaUnsupportedException>()));
      await complete(budget(adapter, extraContext: {'enable_thinking': true}));
      expect(() => budget(adapter), throwsA(isA<LlamaUnsupportedException>()));
      adapter.createConversation(extraContext: {'enable_thinking': true});
      expect(
        () => budget(adapter, extraContext: {'enable_thinking': false}),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      await complete(budget(adapter));
    },
  );
  test(
    'an already-open reasoning prefix does not disable the admitted budget',
    () async {
      final adapter = await client();
      adapter.createConversation(
        promptTemplate: '<think>',
        extraContext: {'enable_thinking': true},
      );
      await complete(budget(adapter));
      expect(count('thinking_budget'), 4);
    },
  );
  test(
    'schema and speculative decoding cannot silently override thinking intent',
    () async {
      final adapter = await client();
      adapter.createConversation(jsonSchemaConstraints: true);
      expect(() => budget(adapter), throwsA(isA<LlamaUnsupportedException>()));
      await complete(budget(adapter, value: null, jsonSchema: '{}'));
      expect(count('thinking_enabled'), 0);
      adapter.dispose();
      final speculative = await client(speculative: true);
      speculative.createConversation();
      expect(
        () => budget(speculative),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'a cancelled bounded send recreates an ordinary unbounded conversation',
    () async {
      final adapter = await client();
      adapter.createConversation();
      final output = budget(adapter).toList();
      adapter.cancel();
      emit(null, reason: 4);
      await output;
      expect(adapter.lastFinishReason, LiteRtLmFinishReason.cancelled);
      expect(adapter.nativeSettlement, LiteRtLmNativeSettlement.settled);
      adapter.createConversation();
      await complete(budget(adapter, value: null));
      expect(count('thinking_present'), 0);
    },
  );
  test(
    'detailed marker decoding leaves the legacy first-channel record unchanged',
    () {
      final input = model(
        channels: [
          [
            ..._protoField(1, utf8.encode('thought')),
            ..._protoField(2, [0xff]),
            ..._protoField(3, utf8.encode('</think>')),
            0x20,
            1,
          ],
        ],
      );
      expect(readLiteRtLmBundleFirstChannel(input.path), (
        name: 'thought',
        isReasoning: true,
      ));
      expect(readLiteRtLmBundleFirstChannelDetails(input.path), isNull);
    },
  );

  test(
    'service preserves disabled-thinking semantics and refuses invalid controls before send',
    () async {
      final input = model();
      final service = LiteRtLmService(
        runtimeClientFactory: () => LiteRtLmV1RuntimeClient(library),
        readBundleCapabilities: (_) =>
            (vision: false, audio: false, speculativeDecoding: false),
        readBundleChatTemplate: (_) => null,
        useTempCacheDir: false,
      );
      addTearDown(service.dispose);
      final handle = await service.loadModel(
        input.path,
        const ModelParams(liteRtLmBackend: LiteRtLmBackendPreference.cpu),
      );
      final context = service.createContext(handle, const ModelParams());
      const messages = [
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'reason'),
      ];
      for (final invalid in [
        const ThinkingBudget(maxTokens: 0),
        const ThinkingBudget(maxTokens: 4, forcedMessage: 'stop'),
      ]) {
        final before = count('sends');
        await expectLater(
          service.generateChat(
            context,
            messages,
            GenerationParams(thinkingBudget: invalid),
          ),
          emitsError(isA<LlamaUnsupportedException>()),
        );
        expect(count('sends'), before);
      }
      final output = service
          .generateChat(
            context,
            messages,
            const GenerationParams(
              thinkingBudget: ThinkingBudget(maxTokens: 4),
            ),
            enableThinking: false,
          )
          .toList();
      while (count('proxies') == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(count('thinking_present'), 0);
      emit('{"role":"assistant","content":[{"type":"text","text":"ok"}]}');
      expect(
        (await output).expand((bytes) => bytes).toList(),
        utf8.encode('ok'),
      );
    },
  );
  for (final mode in ['failed-drain', 'missing-final']) {
    test(
      '$mode bounded turn retains its native family in an owned child',
      () async {
        final process = await Process.start(Platform.resolvedExecutable, [
          retentionScript,
          libraryPath,
          mode,
          model().path,
        ]);
        final output = process.stdout.transform(utf8.decoder).join();
        final errors = process.stderr.transform(utf8.decoder).join();
        try {
          final code = await process.exitCode.timeout(
            const Duration(seconds: 15),
          );
          expect(code, 0, reason: '${await output} ${await errors}');
          expect(
            await output,
            contains('$mode thinking lifetime controls passed'),
          );
        } finally {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          await output;
          await errors;
        }
      },
    );
  }
}
