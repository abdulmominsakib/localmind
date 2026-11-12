@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:test/test.dart';

import '../../support/litert_lm_thinking_input_observer.dart';
import '../../support/litert_lm_v1_thinking_owner.dart';
import '../../support/litert_lm_v1_thinking_qualification.dart';

final class _Client implements LiteRtLmRuntimeClientContract {
  final calls = <String>[];
  bool failCreate = false;
  String? sent;
  Map<String, Object?>? options;
  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = .8,
    int topK = 40,
    double topP = .95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    if (failCreate) throw StateError('native status');
    calls.add('created');
  }

  @override
  String renderMessageToString(Map<String, dynamic> message) {
    calls.add('rendered');
    return '<turn>${(message['content'] as List).single['text']}';
  }

  @override
  List<int> tokenize(String text, {bool addSpecial = true}) => [
    ...(addSpecial ? [2] : <int>[]),
    ...utf8.encode(text),
  ];
  @override
  Stream<String> generateMessageJson(
    String messageJson, {
    Map<String, dynamic>? extraContext,
    int? visualTokenBudget,
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
    int? thinkingTokenBudget,
    String? jsonSchema,
  }) {
    calls.add('send');
    sent = messageJson;
    options = {
      'cap': maxOutputTokens,
      'budget': thinkingTokenBudget,
      'repetition': repetitionPenalty,
      'presence': presencePenalty,
      'extra': extraContext,
      'schema': jsonSchema,
      'visual': visualTokenBudget,
    };
    return Stream.value('answer');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'prospective first baseline requires exact legacy native input bytes and hash',
    () {
      final bytes = utf8.encode(thinkingLegacyBaselineRender);
      final accepted = <String, Object?>{
        'rendered_prompt': thinkingLegacyBaselineRender,
        'rendered_prompt_utf8_hex': bytes
            .map((v) => v.toRadixString(16).padLeft(2, '0'))
            .join(),
        'rendered_prompt_sha256': sha256.convert(bytes).toString(),
      };
      requireThinkingBaselineInput(accepted);
      for (final key in accepted.keys) {
        expect(
          () => requireThinkingBaselineInput({...accepted, key: 'changed'}),
          throwsStateError,
        );
      }
      expect(() => requireThinkingBaselineInput({}), throwsStateError);
    },
  );
  test(
    'mismatched actual render refuses before delegate starts generation',
    () {
      final client = _Client();
      final observed = ThinkingInputObserver(
        client,
        requireThinkingBaselineInput,
      );
      observed.createConversation(temperature: 0);
      final message = jsonEncode({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': thinkingPrompt},
        ],
      });
      expect(
        () => observed.generateMessageJson(
          message,
          maxOutputTokens: thinkingOutputCap,
        ),
        throwsStateError,
      );
      expect(client.calls, ['created', 'rendered']);
      expect(client.sent, isNull);
    },
  );

  test(
    'actual render/tokenizer evidence precedes unchanged send and snapshots successful config',
    () async {
      final client = _Client();
      Map<String, Object?>? input;
      final observed = ThinkingInputObserver(client, (value) {
        client.calls.add('observed');
        input = value;
      });
      final extra = <String, dynamic>{'enable_thinking': true};
      observed.createConversation(
        extraContext: extra,
        temperature: 0,
        topK: 40,
        topP: .9,
        seed: 1,
      );
      extra['enable_thinking'] = false;
      final message = jsonEncode({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '考える\n🙂'},
        ],
      });
      expect(
        await observed
            .generateMessageJson(
              message,
              maxOutputTokens: thinkingOutputCap,
              thinkingTokenBudget: 12,
            )
            .toList(),
        ['answer'],
      );
      expect(client.calls, ['created', 'rendered', 'observed', 'send']);
      expect(client.sent, message);
      expect(client.options, {
        'cap': 1536,
        'budget': 12,
        'repetition': null,
        'presence': null,
        'extra': null,
        'schema': null,
        'visual': null,
      });
      expect(input!['message_json'], message);
      final config =
          input!['conversation_after_successful_status_checks'] as Map;
      expect(config['extra_context'], {'enable_thinking': true});
      expect(config['top_k'], 1);
      expect(config['top_p'], .9);
      final bytes = utf8.encode('<turn>考える\n🙂');
      expect(
        input!['rendered_prompt_sha256'],
        sha256.convert(bytes).toString(),
      );
      expect(
        input!['rendered_prompt_utf8_hex'],
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      );
      expect(
        input!['rendered_prompt_native_token_ids_without_added_start'],
        bytes,
      );
      expect(input!['rendered_prompt_native_token_ids_with_start'], [
        2,
        ...bytes,
      ]);
    },
  );
  test(
    'native configuration failure emits no successful-setting observation',
    () {
      final client = _Client()..failCreate = true;
      final observed = ThinkingInputObserver(
        client,
        (_) => fail('No successful config.'),
      );
      expect(observed.createConversation, throwsStateError);
      expect(client.calls, isEmpty);
    },
  );
  test(
    'compiled native renderer runs on actual settled conversation before send',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thinking_input_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path =
          '${directory.path}/input.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compiled = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        'test/fixtures/litert_lm/c_api_v1_thinking.c',
        '-o',
        path,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final library = DynamicLibrary.open(path);
      final native = createTrackedThinkingClient(
        library,
        ThinkingOwnerTracker(),
      );
      addTearDown(native.dispose);
      final inputs = <Map<String, Object?>>[];
      final observed = ThinkingInputObserver(native, inputs.add);
      await observed.initialize(
        modelPath: '/fixture/model.litertlm',
        backend: 'cpu',
        numberOfThreads: 2,
        speculativeDecoding: false,
      );
      observed.createConversation(
        temperature: 0,
        topP: .9,
        extraContext: {'enable_thinking': true},
      );
      final message = jsonEncode({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'hello'},
        ],
      });
      final stream = observed.generateMessageJson(
        message,
        maxOutputTokens: thinkingOutputCap,
      );
      expect(inputs.single['rendered_prompt'], 'render:$message');
      expect(inputs.single['requested_max_output_tokens'], 1536);
      expect(
        (inputs.single['engine_after_successful_status_checks']
            as Map)['threads'],
        2,
      );
      expect(
        (inputs.single['engine_after_successful_status_checks']
            as Map)['speculation'],
        false,
      );
      final result = stream.toList();
      final text = jsonEncode({
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'answer'},
        ],
      }).toNativeUtf8(allocator: calloc);
      try {
        library.lookupFunction<
          Void Function(Pointer<Utf8>, Bool, Int),
          void Function(Pointer<Utf8>, bool, int)
        >('fixture_client_emit')(text, true, 1);
      } finally {
        calloc.free(text);
      }
      expect((await result).join(), 'answer');
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_metadata_fail',
      )(6);
      expect(
        () => observed.generateMessageJson(message),
        throwsA(isA<Exception>()),
      );
      expect(inputs.length, 1);
    },
  );
}
