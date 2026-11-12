@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../tool/litert_lm_chat_features_smoke.dart' as smoke;

import '../../support/dart_script_snapshot.dart';

void main() {
  Future<LlamaEngine> engineFor(_SessionSmokeBackend backend) async {
    final directory = await Directory.systemTemp.createTemp('session-smoke-');
    addTearDown(() => directory.delete(recursive: true));
    final model = await File(
      '${directory.path}/model.litertlm',
    ).writeAsString('fixture');
    final engine = await LlamaEngine.load(
      LlamaModel(ModelSource.path(model.path)),
      backend: backend,
    );
    addTearDown(engine.dispose);
    return engine;
  }

  test(
    'session smoke refuses an unsupported request on an admitted backend while supported schema chat succeeds',
    () async {
      final backend = _SessionSmokeBackend()..admitted = true;
      final engine = await engineFor(backend);
      final negative = await smoke.runSessionStructuredOutputScenario(engine);
      expect(negative['unsupportedRequest'], 'object_with_oneOf_property');
      expect(negative['historyAfterRejection'], 0);
      expect(negative['reportedMessages'], 0);
      expect(backend.schemaSends, 0);
      expect(backend.admissions, 0);
      expect(backend.grammarQueries, greaterThan(0));
      expect(backend.nativeMessages, hasLength(1));
      final session = ChatSession(engine);
      final reported = <LlamaChatMessage>[];
      final reply = await session.createStructuredJson(
        [const LlamaTextContent('Reply with {"ok": true}.')],
        output: LlamaStructuredOutput.jsonSchema(
          schema: const {
            'type': 'object',
            'properties': {
              'ok': {'type': 'boolean', 'const': true},
            },
            'required': ['ok'],
            'additionalProperties': false,
          },
          decoder: (json) => json,
        ),
        enableThinking: false,
        onMessageAdded: reported.add,
      );
      expect(reply, {'ok': true});
      expect(backend.schemaSends, 1);
      expect(session.history.map((message) => message.role), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
      ]);
      expect(reported.map((message) => message.role), [
        LlamaChatRole.user,
        LlamaChatRole.assistant,
      ]);
    },
  );

  test(
    'session smoke refuses an unsupported schema before admission and recovers without a rejected native send',
    () async {
      final backend = _SessionSmokeBackend();
      final engine = await engineFor(backend);
      final result = await smoke.runSessionStructuredOutputScenario(engine);
      expect(result['unsupportedRequest'], 'object_with_oneOf_property');
      expect(
        result['rejection'],
        isA<String>().having(
          (message) => message.isNotEmpty,
          'typed refusal message',
          isTrue,
        ),
      );
      expect(backend.admissions, 0);
      expect(backend.grammarQueries, greaterThan(0));
      expect(result['historyAfterRejection'], 0);
      expect(result['reportedMessages'], 0);
      expect(result['rolesAfterNextTurn'], ['user', 'assistant']);
      expect(result['nextReply'], 'Hello');
      expect(backend.schemaSends, 0);
      expect(backend.rawSends, 0);
      expect(backend.nativeMessages, hasLength(1));
      expect(backend.nativeMessages.single, hasLength(1));
      expect(
        backend.nativeMessages.single.single.content,
        'Reply with one short sentence saying hello.',
      );
    },
  );

  for (final failure in [
    LlamaModelException('model failure'),
    LlamaInferenceException('runtime failure'),
    StateError('unexpected state'),
  ]) {
    test(
      'session smoke propagates ${failure.runtimeType} instead of accepting it as unsupported',
      () async {
        final backend = _SessionSmokeBackend();
        final engine = await engineFor(backend);
        backend.probeFailure = failure;
        await expectLater(
          smoke.runSessionStructuredOutputScenario(engine),
          throwsA(same(failure)),
        );
        expect(backend.schemaSends, 0);
        expect(backend.nativeMessages, isEmpty);
      },
    );
  }

  test(
    'session smoke rejects a late refusal even when history rollback and recovery succeed',
    () async {
      final backend = _SessionSmokeBackend();
      final engine = await engineFor(backend);
      backend.grammarSupport = true;
      backend.dropGrammarOnTokenize = true;
      await expectLater(
        smoke.runSessionStructuredOutputScenario(engine),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'contract',
            contains('before recording the turn'),
          ),
        ),
      );
      expect(backend.admissions, 0);
      expect(backend.grammarSupport, isFalse);
      expect(backend.schemaSends, 0);
      expect(backend.nativeMessages.single, hasLength(1));
    },
  );

  test(
    'session smoke fails when the next turn does not recover visible output',
    () async {
      final backend = _SessionSmokeBackend(recoveryReply: '');
      final engine = await engineFor(backend);
      await expectLater(
        smoke.runSessionStructuredOutputScenario(engine),
        throwsA(isA<StateError>()),
      );
      expect(backend.schemaSends, 0);
      expect(backend.nativeMessages, hasLength(1));
    },
  );

  test(
    'fixture selector and artifact gate run before loading a model',
    () async {
      final smoke = await compileDartScript(
        'tool/litert_lm_chat_features_smoke.dart',
      );
      final temp = await Directory.systemTemp.createTemp('qwen-smoke-gate-');
      addTearDown(() => temp.delete(recursive: true));
      final model = await File(
        '${temp.path}/other.litertlm',
      ).writeAsString('other');
      for (final fixture in ['unknown', 'qwen3-0.6b']) {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['--disable-dart-dev', smoke, model.path, 'cpu'],
          environment: {
            'LITERT_LM_TOKENIZER_FIXTURE': fixture,
            'LITERT_LM_AUDIO_PATH': '',
            'LITERT_LM_IMAGE_PATH': '',
          },
        );
        expect(result.exitCode, isNot(0));
        expect(
          result.stderr,
          contains(
            fixture == 'unknown'
                ? 'Unknown tokenizer fixture'
                : 'requires a known Qwen3-0.6B artifact',
          ),
        );
      }
    },
  );

  group('thinkingSupportForTemplate', () {
    const closedAlways =
        '{%- if m.role == "assistant" %}<think>\n\n</think>\n\n{% endif -%}'
        '{%- if add_generation_prompt %}<|im_start|>assistant\n'
        '<think>\n\n</think>\n\n{% endif -%}';
    const honoursSwitch =
        '{%- if add_generation_prompt %}<|im_start|>assistant\n'
        '{%- if enable_thinking is defined and enable_thinking is false %}'
        '<think>\n\n</think>\n\n{%- else %}<think>\n{%- endif %}'
        '{% endif -%}';

    test('reports a template that always closes the think block as N/A', () {
      final support = smoke.thinkingSupportForTemplate(closedAlways);
      expect(support.canProduceThinking, isFalse);
      expect(support.reason, contains('enable_thinking'));
    });

    test('keeps the assertion for a template that reads enable_thinking', () {
      expect(
        smoke.thinkingSupportForTemplate(honoursSwitch).canProduceThinking,
        isTrue,
      );
    });

    test('keeps the assertion when only history closes the think block', () {
      const openInPrompt =
          '{%- if m.role == "assistant" %}<think>\n\n</think>\n\n{% endif -%}'
          '{%- if add_generation_prompt %}<|im_start|>assistant\n<think>\n'
          '{% endif -%}';
      expect(
        smoke.thinkingSupportForTemplate(openInPrompt).canProduceThinking,
        isTrue,
      );
    });

    test('keeps the assertion without a readable or closed-think template', () {
      expect(smoke.thinkingSupportForTemplate(null).canProduceThinking, isTrue);
      expect(
        smoke
            .thinkingSupportForTemplate('<|im_start|>assistant\n<think>\n')
            .canProduceThinking,
        isTrue,
      );
    });
  });

  test('prints usage and exits 64 without a model path', () async {
    final smoke = await compileDartScript(
      'tool/litert_lm_chat_features_smoke.dart',
    );
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '--disable-dart-dev',
      smoke,
      ' ',
    ]);

    expect(result.exitCode, 64, reason: '${result.stderr}');
    expect(
      result.stderr,
      contains(
        'Usage: dart run tool/litert_lm_chat_features_smoke.dart '
        '<model.litertlm>',
      ),
    );
  });
}

class _SessionSmokeBackend
    implements
        LlamaBackend,
        BackendGrammarConstraintsSupport,
        BackendJsonSchemaChatGeneration,
        BackendNativeChatGeneration {
  _SessionSmokeBackend({this.recoveryReply = 'Hello'});
  Object? probeFailure;
  bool grammarSupport = false;
  bool dropGrammarOnTokenize = false;
  int grammarQueries = 0;
  final String recoveryReply;
  bool admitted = false;
  int admissions = 0;
  int schemaSends = 0;
  int rawSends = 0;
  final nativeMessages = <List<LlamaChatMessage>>[];
  @override
  bool get isReady => true;
  @override
  bool get supportsUrlLoading => false;
  @override
  bool get supportsGrammarConstraints {
    grammarQueries++;
    final failure = probeFailure;
    if (failure != null) {
      probeFailure = null;
      throw failure;
    }
    return grammarSupport;
  }

  @override
  bool get supportsJsonSchemaChatGeneration => admitted;
  @override
  bool get supportsNativeChatGeneration => true;
  @override
  Future<void> prepareJsonSchemaChat() async {
    if (admitted) return;
    admissions++;
    admitted = true;
  }

  @override
  Stream<List<int>> generateChatWithJsonSchema(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    required Map<String, dynamic> jsonSchema,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async* {
    schemaSends++;
    yield utf8.encode('{"ok":true}');
  }

  @override
  Stream<List<int>> generateChat(
    int contextHandle,
    List<LlamaChatMessage> messages,
    GenerationParams params, {
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    String? sourceLangCode,
    String? targetLangCode,
    DateTime? templateNow,
  }) async* {
    nativeMessages.add(List.of(messages));
    if (recoveryReply.isNotEmpty) yield utf8.encode(recoveryReply);
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    rawSends++;
    yield utf8.encode(recoveryReply);
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async => 1;
  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;
  @override
  Future<int> getContextSize(int contextHandle) async => 4096;
  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'tokenizer.chat_template': '{{ messages | tojson }}',
  };
  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    if (dropGrammarOnTokenize) grammarSupport = false;
    return [1];
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}
  @override
  Future<void> contextFree(int contextHandle) async {}
  @override
  Future<void> modelFree(int modelHandle) async {}
  @override
  Future<void> dispose() async {}
  @override
  void cancelGeneration() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
