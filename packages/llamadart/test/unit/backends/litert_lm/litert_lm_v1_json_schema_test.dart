@TestOn('vm && (mac-os || linux)')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  final missing = <String, DynamicLibrary>{};
  const omissions = [
    'PROVIDER',
    'CREATE',
    'DELETE',
    'ENABLE',
    'CONFIG',
    'ARGS',
    'CONSTRAINT',
  ];
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  LiteRtLmV1Runtime loaded([DynamicLibrary? selected]) {
    final runtime = LiteRtLmV1Runtime(selected ?? library);
    runtime.loadConfigured(
      '/secret/model.litertlm',
      const LiteRtLmV1EngineSettings(),
    );
    return runtime;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_schema_');
    for (final name in ['full', ...omissions]) {
      final path =
          '${directory.path}/$name.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (name != 'full') '-DOMIT_SCHEMA_$name',
        'test/fixtures/litert_lm/c_api_v1_json_schema.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (name == 'full') {
        library = DynamicLibrary.open(path);
      } else {
        missing[name] = DynamicLibrary.open(path);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() => call('fail', 0));
  tearDown(() {
    expect(count('live'), 0);
    expect(count('args_live'), 0);
    expect(count('proxies'), 0);
  });
  test(
    'provider enum and schema type cross the v1 ABI by value with thinking disabled',
    () async {
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(jsonSchemaConstraints: true),
      );
      expect(count('constrained'), 0);
      expect(count('schema_provider'), 1);
      expect(count('config_thinking'), 0);
      const schema = '{"type":"object","properties":{"café":{"const":"日本"}}}';
      final turn = conversation.sendText(
        'reply',
        settings: const LiteRtLmV1TurnSettings(jsonSchema: schema),
      );
      final chunks = turn.chunks.toList();
      expect(count('schema_kind'), 2);
      expect(count('args_thinking'), 0);
      expect(
        library
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              'fixture_schema_text',
            )()
            .toDartString(),
        schema,
      );
      call('emit', 2);
      await turn.done;
      await chunks;
      conversation.close();
      runtime.dispose();
    },
  );
  for (final enabled in [true, false]) {
    test(
      'schema thinking follows the conversation context: $enabled',
      () async {
        final runtime = loaded();
        final conversation = runtime.openConfiguredConversation(
          LiteRtLmV1ConversationSettings(
            jsonSchemaConstraints: true,
            extraContext: {'enable_thinking': enabled},
          ),
        );
        expect(count('config_thinking'), enabled ? 1 : 0);
        final turn = conversation.sendText(
          'reply',
          settings: const LiteRtLmV1TurnSettings(
            jsonSchema: '{"type":"object"}',
          ),
        );
        final chunks = turn.chunks.toList();
        expect(count('args_thinking'), enabled ? 1 : 0);
        call('emit', 2);
        await turn.done;
        await chunks;
        conversation.close();
        runtime.dispose();
      },
    );
  }
  test(
    'client forwards schemas and stops advertising capability after disposal',
    () async {
      final client = LiteRtLmV1RuntimeClient(library);
      expect(client.supportsJsonSchemaConstraints, isTrue);
      expect(client.supportsJsonSchemaThinking, isTrue);
      await client.initialize(
        modelPath: '/secret/model.litertlm',
        backend: 'cpu',
        speculativeDecoding: false,
      );
      client.createConversation(jsonSchemaConstraints: true);
      final output = client
          .generateMessageJson(
            '{"role":"user","content":"reply"}',
            jsonSchema: '{"type":"object"}',
          )
          .toList();
      expect(count('schema_kind'), 2);
      final text =
          '{"role":"assistant","content":[{"type":"text","text":"{}"}]}'
              .toNativeUtf8();
      try {
        library.lookupFunction<
          Void Function(Pointer<Utf8>, Bool, Int),
          void Function(Pointer<Utf8>, bool, int)
        >('fixture_client_emit')(text, true, 1);
      } finally {
        calloc.free(text);
      }
      expect((await output).join(), '{}');
      client.dispose();
      expect(client.supportsJsonSchemaConstraints, isFalse);
      expect(client.supportsJsonSchemaThinking, isFalse);
    },
  );
  for (final stage in [90, 91, 92, 93, 96]) {
    test('config failure $stage releases every temporary owner', () {
      final runtime = loaded();
      call('fail', stage);
      expect(
        () => runtime.openConfiguredConversation(
          LiteRtLmV1ConversationSettings(jsonSchemaConstraints: true),
        ),
        throwsA(isA<LlamaException>()),
      );
      runtime.dispose();
    });
  }
  for (final stage in [91, 92, 94, 95, 96]) {
    test('turn failure $stage prevents send and releases optional owners', () {
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(jsonSchemaConstraints: true),
      );
      final sends = count('sends');
      call('fail', stage);
      expect(
        () => conversation.sendText(
          'reply',
          settings: const LiteRtLmV1TurnSettings(jsonSchema: '{}'),
        ),
        throwsA(isA<LlamaException>()),
      );
      expect(count('sends'), sends);
      expect(count('args_live'), 0);
      conversation.close();
      runtime.dispose();
    });
  }
  for (final name in omissions) {
    test('missing $name refuses the complete optional group', () {
      final runtime = loaded(missing[name]);
      expect(
        () => runtime.openConfiguredConversation(
          LiteRtLmV1ConversationSettings(jsonSchemaConstraints: true),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      final text = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(),
      );
      text.close();
      runtime.dispose();
    });
  }
  test('schema requires an opted-in conversation', () {
    final runtime = loaded();
    final conversation = runtime.openConfiguredConversation(
      LiteRtLmV1ConversationSettings(),
    );
    expect(
      () => conversation.sendText(
        'reply',
        settings: const LiteRtLmV1TurnSettings(jsonSchema: '{}'),
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    conversation.close();
    runtime.dispose();
  });
  for (final schema in ['', '{', '[]', 'null', '{}\u0000ignored']) {
    test('invalid schema is rejected before native send: ${schema.length}', () {
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(jsonSchemaConstraints: true),
      );
      final sends = count('sends');
      expect(
        () => conversation.sendText(
          'reply',
          settings: LiteRtLmV1TurnSettings(jsonSchema: schema),
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(count('sends'), sends);
      conversation.close();
      runtime.dispose();
    });
  }
}
