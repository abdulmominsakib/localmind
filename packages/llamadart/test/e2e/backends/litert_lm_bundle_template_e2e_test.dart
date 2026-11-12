@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_cache.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/llama_logger.dart';
import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

const _generationPrompt =
    "{%- if add_generation_prompt -%}{{ '<|im_start|>assistant\\n' }}"
    '{%- endif -%}';

/// ChatML templates that read message content as a string, keyed by how.
const _stringContentTemplates = {
  'interpolating':
      "{%- for message in messages -%}{{ '<|im_start|>' }}{{ message.role }}"
      "{{ '\\n' }}{{ message.content }}{{ '<|im_end|>\\n' }}{%- endfor -%}"
      '$_generationPrompt',
  'concatenating':
      "{%- for message in messages -%}{{ '<|im_start|>' + message.role + '\\n'"
      " + message.content + '<|im_end|>\\n' }}{%- endfor -%}"
      '$_generationPrompt',
  'string-only':
      '{%- for message in messages -%}'
      '{%- if message.content is string -%}{%- set text = message.content -%}'
      "{%- else -%}{%- set text = '' -%}{%- endif -%}"
      "{{ '<|im_start|>' + message.role + '\\n' + text + '<|im_end|>\\n' }}"
      '{%- endfor -%}'
      '$_generationPrompt',
};

/// A ChatML template that reads content parts and strings.
const _partsContentTemplate =
    "{%- for message in messages -%}{{ '<|im_start|>' + message.role + '\\n' }}"
    '{%- if message.content is string -%}{{ message.content }}{%- else -%}'
    "{%- for part in message.content -%}{%- if part.type == 'text' -%}"
    '{{ part.text }}{%- endif -%}{%- endfor -%}{%- endif -%}'
    "{{ '<|im_end|>\\n' }}{%- endfor -%}"
    '$_generationPrompt';

/// Writes every key the service can put on a message.
const _messageKeysTemplate =
    '{%- for message in messages -%}<{{ message.role }}'
    '|reasoning={{ message.reasoning_content }}'
    '|calls={%- for call in message.tool_calls or [] -%}'
    '{{ call.function.name }}({{ call.function.arguments.city }})'
    '{%- endfor -%}'
    '|content={%- if message.content is string -%}{{ message.content }}'
    '{%- else -%}{%- for part in message.content -%}'
    "{%- if part.type == 'tool_response' -%}"
    '{{ part.name }}={{ part.response }}'
    '{%- else -%}{{ part.text }}{%- endif -%}'
    '{%- endfor -%}{%- endif -%}>\n'
    '{% endfor -%}';

const _userTurn = '<|im_start|>user\n';

/// Raw prompts, one already rendered as a ChatML turn.
const _rawPrompts = [
  'hi',
  '\n  The capital of France is',
  '<|im_start|>user\nhi<|im_end|>\n<|im_start|>assistant\n',
];
const _assistantTurn = '<|im_end|>\n<|im_start|>assistant\n';

/// Records what the service asks of the real runtime.
class _RecordingClient extends LiteRtLmRuntimeClient {
  final List<String?> promptTemplates = <String?>[];
  final List<String> sentPrompts = <String>[];

  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    promptTemplates.add(promptTemplate);
    super.createConversation(
      systemMessage: systemMessage,
      promptTemplate: promptTemplate,
      messages: messages,
      tools: tools,
      extraContext: extraContext,
      temperature: temperature,
      topK: topK,
      topP: topP,
      seed: seed,
      npuBackend: npuBackend,
      loraPath: loraPath,
    );
  }

  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) {
    sentPrompts.add(
      renderMessageToString({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': prompt},
        ],
      }),
    );
    return super.generate(
      prompt,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
    );
  }

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
    try {
      sentPrompts.add(
        renderMessageToString(jsonDecode(messageJson) as Map<String, dynamic>),
      );
    } on LlamaModelException catch (error) {
      sentPrompts.add('render failed: ${error.message}');
    }
    return super.generateMessageJson(
      messageJson,
      extraContext: extraContext,
      visualTokenBudget: visualTokenBudget,
      maxOutputTokens: maxOutputTokens,
      repetitionPenalty: repetitionPenalty,
      presencePenalty: presencePenalty,
      thinkingTokenBudget: thinkingTokenBudget,
    );
  }
}

/// Copies the bundle at [model] to [directory] with [template], which the
/// bundle embeds, replaced by [replacement] padded to the same length.
String _bundleWithTemplate(
  String model,
  String template,
  String replacement,
  Directory directory,
) {
  final original = utf8.encode(template);
  final padding = original.length - utf8.encode(replacement).length;
  if (padding < 0) {
    fail('The bundle template is shorter than the replacement.');
  }
  // Spaces inside the first tag do not change what the template renders.
  final padded = replacement.replaceFirst('{%-', '{%-${' ' * padding}');

  final source = File(model).openSync();
  final Uint8List head;
  try {
    head = source.readSync(8 * 1024 * 1024);
  } finally {
    source.closeSync();
  }
  var offset = -1;
  for (var i = 0; i + original.length <= head.length && offset < 0; i++) {
    var matches = true;
    for (var j = 0; j < original.length && matches; j++) {
      matches = head[i + j] == original[j];
    }
    if (matches) offset = i;
  }
  expect(offset, isNonNegative, reason: 'template bytes in the bundle');

  final path = '${directory.path}/${File(model).uri.pathSegments.last}';
  // An APFS clone avoids a second copy of the weights.
  if (!Platform.isMacOS ||
      Process.runSync('cp', ['-c', model, path]).exitCode != 0) {
    File(model).copySync(path);
  }
  // Both copies keep the mode of a read-only cached model.
  if (!Platform.isWindows) {
    expect(Process.runSync('chmod', ['u+w', path]).exitCode, 0);
  }
  final copy = File(path).openSync(mode: FileMode.append);
  try {
    copy.setPositionSync(offset);
    copy.writeFromSync(utf8.encode(padded));
  } finally {
    copy.closeSync();
  }
  expect(readLiteRtLmBundleChatTemplate(path), padded);
  return path;
}

void main() {
  useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_MODEL'];

  setUpAll(() {
    if (model == null || !File(model).existsSync()) {
      fail('Set LITERT_LM_MODEL to an existing .litertlm model.');
    }
  });

  group('the runtime', () {
    late LiteRtLmRuntimeClient client;

    setUpAll(() async {
      client = LiteRtLmRuntimeClient();
      await client.initialize(
        modelPath: model!,
        backend: 'cpu',
        maxTokens: 1024,
        cacheDir: liteRtLmNoCacheDirectory,
        speculativeDecoding: false,
      );
    });

    tearDownAll(() => client.dispose());

    String render(
      String? template, {
      String? systemMessage,
      List<Map<String, dynamic>>? messages,
      Map<String, dynamic> message = liteRtLmContentShapeProbeMessage,
    }) {
      client.createConversation(
        promptTemplate: template,
        systemMessage: systemMessage,
        messages: messages,
      );
      return client.renderMessageToString(message);
    }

    test('renders the bundle template through the adapter', () {
      final bundleTemplate = readLiteRtLmBundleChatTemplate(model!);
      final rendered = render(null);
      if (bundleTemplate == null) {
        // The runtime builds the template of a bundle that embeds none.
        expect(liteRtLmRendersProbeText(rendered), isTrue);
        return;
      }
      const history = [
        {'role': 'user', 'content': 'The code is cedar17.'},
        {'role': 'assistant', 'content': 'Understood.'},
      ];
      final seeded = render(
        null,
        systemMessage: 'Remember the code.',
        messages: history,
      );
      final adapted = render(
        liteRtLmTextContentAdapter(bundleTemplate),
        systemMessage: 'Remember the code.',
        messages: history,
      );

      if (liteRtLmRendersProbeText(rendered) &&
          !liteRtLmRendersProbeText(adapted)) {
        // A template that reads content only as parts, such as Qwen3's, loses
        // the text the adapter gives it as a string. The service adapts only a
        // template that does not render the text, so it keeps this one.
        markTestSkipped('The bundle template reads content only as parts.');
        return;
      }
      // A template that reads content parts and strings renders the same
      // prompt either way; one that interpolates a string differs only in
      // each serialized part list.
      expect(liteRtLmRendersProbeText(adapted), isTrue);
      expect(
        adapted,
        seeded.replaceAllMapped(
          RegExp(r'''\[\{(?:"type": "text", )?"text": "([^"]*)"[^\]]*\}\]'''),
          (match) => match[1]!,
        ),
      );
    });

    for (final MapEntry(key: shape, value: template)
        in _stringContentTemplates.entries) {
      test('renders text for a template $shape content only through the '
          'adapter', () {
        bool rendersText() {
          try {
            return liteRtLmRendersProbeText(render(template));
          } on LlamaModelException {
            return false;
          }
        }

        expect(rendersText(), isFalse);
        expect(
          render(liteRtLmTextContentAdapter(template)),
          '$_userTurn$liteRtLmContentShapeProbeText$_assistantTurn',
        );
      });
    }

    test('renders a template that reads content parts the same through the '
        'adapter', () {
      final rendered = render(_partsContentTemplate);

      expect(
        rendered,
        '$_userTurn$liteRtLmContentShapeProbeText$_assistantTurn',
      );
      expect(
        render(liteRtLmTextContentAdapter(_partsContentTemplate)),
        rendered,
      );
    });

    test('does not reach a template in the single-turn form', () {
      // The runtime gives such a template the message of a turn as `message`,
      // which the adapter does not rebind.
      const template =
          "{#- is_appending_to_prefill -#}{{ '<|im_start|>' }}"
          "{{ message.role }}{{ '\\n' }}{{ message.content }}";

      expect(
        render(template),
        allOf(
          startsWith('<|im_start|>user\n['),
          contains(liteRtLmContentShapeProbeText),
        ),
      );
      expect(
        liteRtLmRendersProbeText(render(liteRtLmTextContentAdapter(template))),
        isFalse,
      );
    });

    test('keeps every other message key through the adapter', () {
      // The message keys and tool result parts the service sends, the only
      // ones the C API 1.0 client accepts.
      const messages = [
        {'role': 'user', 'content': 'Weather?'},
        {
          'role': 'assistant',
          'content': 'Checking.',
          'reasoning_content': 'needs a tool',
          'tool_calls': [
            {
              'type': 'function',
              'function': {
                'name': 'get_weather',
                'arguments': {'city': 'Paris'},
              },
            },
          ],
        },
        {
          'role': 'tool',
          'content': [
            {
              'type': 'tool_response',
              'name': 'get_weather',
              'response': 'sunny',
            },
          ],
        },
      ];
      const message = {'role': 'user', 'content': 'Thanks'};
      final rendered = render(
        _messageKeysTemplate,
        messages: messages,
        message: message,
      );

      for (final value in [
        '|reasoning=needs a tool|',
        '|calls=get_weather(Paris)|content=Checking.>',
        '|content=get_weather=sunny>',
        '|content=Thanks>',
      ]) {
        expect(rendered, contains(value));
      }
      expect(
        render(
          liteRtLmTextContentAdapter(_messageKeysTemplate),
          messages: messages,
          message: message,
        ),
        rendered,
      );
    });

    test('renders a raw prompt unchanged through the raw prompt template', () {
      for (final prompt in _rawPrompts) {
        expect(
          render(
            liteRtLmRawPromptTemplate,
            message: {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
              ],
            },
          ),
          prompt,
        );
      }
    });

    test('keeps how a template handles the whitespace it starts with', () {
      for (final template in [
        '\n  start',
        '  start',
        '  {% if true %}X{% endif %}',
        '  {%- if true %}X{% endif %}',
        "  {{ 'X' }}",
        '\n{% if true %}\nX{% endif %}',
      ]) {
        expect(
          render(liteRtLmTextContentAdapter(template)),
          render(template),
          reason: template,
        );
      }
    });
  });

  group('the service', () {
    late Directory directory;
    final records = <LlamaLogRecord>[];

    setUp(() {
      directory = Directory.systemTemp.createTempSync('litert_bundle_e2e_');
      records.clear();
      LlamaLogger.instance.setLevel(LlamaLogLevel.warn);
      LlamaLogger.instance.setHandler(records.add);
    });

    tearDown(() {
      LlamaLogger.instance.setLevel(LlamaLogLevel.none);
      LlamaLogger.instance.setHandler(null);
      directory.deleteSync(recursive: true);
    });

    test('sends a raw prompt that starts with the start token with one start '
        'token', () async {
      final cache = Directory('${directory.path}/cache')..createSync();
      final client = _RecordingClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final params = ModelParams(
        contextSize: 1024,
        numberOfThreads: 2,
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: cache.path,
      );
      try {
        final handle = await service.loadModel(model!, params);
        final context = service.createContext(handle, params);
        final start = await service.tokenize(handle, '', true);
        if (start.isEmpty) {
          markTestSkipped('The runtime adds no start token for this bundle.');
          return;
        }
        final startText = client.detokenize(start);
        await service
            .generate(
              context,
              '${startText}hi',
              const GenerationParams(maxTokens: 1, temp: 0, seed: 1),
            )
            .drain<void>();

        expect(client.sentPrompts, ['hi']);
        expect(
          service.getPerformanceContext(context)?.promptEvalTokens,
          (await service.tokenize(handle, 'hi', true)).length,
        );
        await expectLater(
          service
              .generate(
                context,
                startText,
                const GenerationParams(maxTokens: 1, temp: 0, seed: 1),
              )
              .drain<void>(),
          throwsA(isA<LlamaArgumentException>()),
        );
      } finally {
        service.dispose();
      }
    });

    test('sends a raw prompt to the model unchanged', () async {
      final cache = Directory('${directory.path}/cache')..createSync();
      final client = _RecordingClient();
      final service = LiteRtLmService(clientFactory: () => client);
      final params = ModelParams(
        contextSize: 1024,
        numberOfThreads: 2,
        liteRtLmBackend: LiteRtLmBackendPreference.cpu,
        liteRtLmCacheDir: cache.path,
      );
      try {
        final handle = await service.loadModel(model!, params);
        final context = service.createContext(handle, params);
        for (final prompt in _rawPrompts) {
          await service
              .generate(
                context,
                prompt,
                const GenerationParams(maxTokens: 1, temp: 0, seed: 1),
              )
              .drain<void>();
          final tokens = await service.tokenize(handle, prompt, true);
          expect(
            service.getPerformanceContext(context)?.promptEvalTokens,
            tokens.length,
            reason: prompt,
          );
        }
        expect(client.promptTemplates, [
          for (final _ in _rawPrompts) liteRtLmRawPromptTemplate,
        ]);
        expect(client.sentPrompts, _rawPrompts);
      } finally {
        service.dispose();
      }
    });

    for (final MapEntry(key: shape, value: template)
        in _stringContentTemplates.entries) {
      test('answers with a bundle whose template is $shape content', () async {
        final bundleTemplate = readLiteRtLmBundleChatTemplate(model!);
        if (bundleTemplate == null) {
          markTestSkipped('The bundle embeds no template to replace.');
          return;
        }
        final path = _bundleWithTemplate(
          model,
          bundleTemplate,
          template,
          directory,
        );
        final embedded = readLiteRtLmBundleChatTemplate(path)!;
        final cache = Directory('${directory.path}/cache')..createSync();
        final client = _RecordingClient();
        final service = LiteRtLmService(clientFactory: () => client);
        final params = ModelParams(
          contextSize: 1024,
          numberOfThreads: 2,
          liteRtLmBackend: LiteRtLmBackendPreference.cpu,
          liteRtLmCacheDir: cache.path,
        );
        try {
          final handle = await service.loadModel(path, params);
          if (service.getMetadata(handle)['tokenizer.chat_template'] !=
              embedded) {
            // Such as Qwen3, whose text chats render a built-in template.
            markTestSkipped(
              'Text chats on this bundle use a built-in template.',
            );
            return;
          }
          final context = service.createContext(handle, params);
          for (var request = 0; request < 2; request++) {
            await service
                .generateChat(
                  context,
                  const [
                    LlamaChatMessage.fromText(
                      role: LlamaChatRole.user,
                      text: 'Hello',
                    ),
                  ],
                  const GenerationParams(maxTokens: 8, temp: 0, seed: 1),
                  enableThinking: false,
                )
                .drain<void>();
          }

          final adapter = liteRtLmTextContentAdapter(embedded);
          expect(client.promptTemplates, [null, adapter, adapter, adapter]);
          expect(client.sentPrompts, [
            '${_userTurn}Hello$_assistantTurn',
            '${_userTurn}Hello$_assistantTurn',
          ]);
          expect(
            records.where((record) => record.message.contains('adapt')),
            isEmpty,
          );
        } finally {
          service.dispose();
        }
      });
    }
  });
}
