@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:test/test.dart';

import '../../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart_qwen_media_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // The real service behind the real backend and engine, in this isolate,
  // with only the native runtime client replaced. Synthetic encoder flags
  // isolate this boundary; litert_lm_v1_media_test.dart checks real processor
  // admission, including unsupported Qwen processors.
  Future<({LlamaEngine engine, List<_RuntimeClient> clients})> load(
    String bundle, {
    required bool encoders,
    required bool rendersMessages,
  }) async {
    final clients = <_RuntimeClient>[];
    final handshake = ReceivePort();
    runLiteRtLmWorkerForTesting(
      handshake.sendPort,
      LiteRtLmService(
        runtimeClientFactory: () {
          final client = _RuntimeClient(
            failConversation: !encoders,
            rendersMessages: rendersMessages,
          );
          clients.add(client);
          return client;
        },
      ),
      exitOnDispose: false,
    );
    final engine = LlamaEngine(
      LiteRtLmBackend(initialSendPort: await handshake.first as SendPort),
    );
    final modelFile = File('${tempDir.path}/$bundle');
    await modelFile.writeAsString('fake model');
    await engine.loadModel(modelFile.path);
    return (engine: engine, clients: clients);
  }

  LlamaChatMessage user(LlamaContentPart media) => LlamaChatMessage.withContent(
    role: LlamaChatRole.user,
    content: [const LlamaTextContent('Describe this.'), media],
  );

  for (final rendersMessages in [false, true]) {
    final renderer = rendersMessages ? 'native renderer' : 'no native renderer';
    group(renderer, () {
      void expectMediaConversation(_RuntimeClient client) {
        expect(client.promptTemplates, rendersMessages ? [null, null] : [null]);
        expect(
          client.events,
          rendersMessages
              ? ['create', 'render', 'create', 'send']
              : ['create', 'send'],
        );
        expect(
          client.renderedMessages,
          rendersMessages ? [liteRtLmContentShapeProbeMessage] : isEmpty,
        );
        expect(
          client.conversationInputs,
          everyElement({'systemMessage': null, 'messages': null}),
          reason: 'Rendering probes must stay out of user conversations.',
        );
      }

      for (final bundle in [
        'Qwen3-0.6B.litertlm',
        'Qwen3.5-0.8B_int8.litertlm',
        'qwen-3-vl.litertlm',
      ]) {
        for (final kind in ['image', 'audio']) {
          final bytes = kind == 'image' ? [1, 2, 3] : [4, 5, 6];
          LlamaContentPart media() => kind == 'image'
              ? LlamaImageContent(bytes: Uint8List.fromList(bytes))
              : LlamaAudioContent(bytes: Uint8List.fromList(bytes));

          test(
            '$bundle renders the $kind marker in the Dart template',
            () async {
              final loaded = await load(
                bundle,
                encoders: true,
                rendersMessages: rendersMessages,
              );
              try {
                final rendered = await loaded.engine.chatTemplate(
                  [user(media())],
                  tools: [
                    ToolDefinition(
                      name: 'lookup',
                      description: 'Lookup',
                      parameters: const [],
                      handler: (_) async => 'unused',
                    ),
                  ],
                  includeTokenCount: false,
                );
                expect(
                  rendered.prompt,
                  endsWith(
                    '<|im_start|>user\nDescribe this.<__media__><|im_end|>\n'
                    '<|im_start|>assistant\n',
                  ),
                );
                expect(rendered.format, ChatFormat.hermes.index);
                expect(rendered.grammarTriggers.single.value, '<tool_call>');
                expect(rendered.preservedTokens, [
                  '<tool_call>',
                  '</tool_call>',
                ]);
              } finally {
                await loaded.engine.dispose();
              }
            },
          );

          test(
            '$bundle $kind request fails at the native media boundary when the '
            'bundle has no $kind encoder',
            () async {
              final loaded = await load(
                bundle,
                encoders: false,
                rendersMessages: rendersMessages,
              );
              try {
                await expectLater(
                  loaded.engine.create([user(media())]).drain<void>(),
                  throwsA(
                    isA<LlamaUnsupportedException>().having(
                      (error) => error.message,
                      'message',
                      allOf(
                        contains('declares no $kind encoder'),
                        contains('conversation create failed'),
                      ),
                    ),
                  ),
                );
                // Failure diagnostics may create a fresh metadata-only client.
                final client = loaded.clients.singleWhere(
                  (client) => client.conversations > 0,
                );
                expect(client.conversations, 1);
                expect(client.events, ['create']);
                expect(
                  loaded.clients.map((client) => client.messageJson),
                  everyElement(isNull),
                );
                expect(
                  loaded.clients.expand((client) => client.renderedMessages),
                  isEmpty,
                );
              } finally {
                await loaded.engine.dispose();
              }
            },
          );

          test('$bundle $kind request reaches the native conversation with the '
              'bundle template', () async {
            final loaded = await load(
              bundle,
              encoders: true,
              rendersMessages: rendersMessages,
            );
            try {
              expect(
                await loaded.engine.create([user(media())]).text(),
                'A cat.',
              );
              final client = loaded.clients.last;
              expectMediaConversation(client);
              expect(jsonDecode(client.messageJson!), {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': 'Describe this.'},
                  {'type': kind, 'blob': base64Encode(bytes)},
                ],
              });
            } finally {
              await loaded.engine.dispose();
            }
          });

          test('$bundle ChatSession $kind turn reaches the native '
              'conversation', () async {
            final loaded = await load(
              bundle,
              encoders: true,
              rendersMessages: rendersMessages,
            );
            try {
              final session = ChatSession(loaded.engine);
              expect(
                await session.create(user(media()).parts).text(),
                'A cat.',
              );
              expectMediaConversation(loaded.clients.last);
              expect(session.history.map((message) => message.role), [
                LlamaChatRole.user,
                LlamaChatRole.assistant,
              ]);
            } finally {
              await loaded.engine.dispose();
            }
          });
        }
      }

      test('a video part gets the typed video error, not a template error, '
          'through ChatSession', () async {
        final loaded = await load(
          'Qwen3-0.6B.litertlm',
          encoders: true,
          rendersMessages: rendersMessages,
        );
        try {
          final video = LlamaVideoContent(bytes: Uint8List.fromList([7, 8, 9]));
          final rendered = await loaded.engine.chatTemplate([
            user(video),
          ], includeTokenCount: false);
          expect(
            rendered.prompt,
            '<|im_start|>user\nDescribe this.<__media__><|im_end|>\n'
            '<|im_start|>assistant\n',
          );
          await expectLater(
            ChatSession(loaded.engine).create(user(video).parts).drain<void>(),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'message',
                contains('Video input is not consumable'),
              ),
            ),
          );
          expect(
            loaded.clients.every((client) => client.conversations == 0),
            true,
          );
        } finally {
          await loaded.engine.dispose();
        }
      });

      test('a text-only turn on a Qwen 3 bundle still gets the built-in '
          'template as the native override', () async {
        final loaded = await load(
          'Qwen3-0.6B.litertlm',
          encoders: true,
          rendersMessages: rendersMessages,
        );
        try {
          expect(
            await loaded.engine.create(const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'Hello',
              ),
            ]).text(),
            'A cat.',
          );
          final client = loaded.clients.last;
          expect(
            client.promptTemplates.single,
            (await loaded.engine.getMetadata())['tokenizer.chat_template'],
          );
          expect(client.events, ['create', 'send']);
          expect(client.renderedMessages, isEmpty);
        } finally {
          await loaded.engine.dispose();
        }
      });
    });
  }
}

class _RuntimeClient implements LiteRtLmRuntimeClientContract {
  _RuntimeClient({
    required this.failConversation,
    required this.rendersMessages,
  });

  final bool failConversation;
  final bool rendersMessages;
  final List<String> events = <String>[];
  final List<Map<String, dynamic>> renderedMessages = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> conversationInputs =
      <Map<String, dynamic>>[];
  final List<String?> promptTemplates = <String?>[];
  String? messageJson;
  int conversations = 0;

  @override
  bool get supportsAsrBridge => false;

  @override
  bool get supportsSamplingPenalties => false;

  @override
  bool get supportsThinkingBudget => false;

  @override
  bool get supportsFinishReasons => false;

  @override
  bool get supportsJsonSchemaConstraints => false;

  @override
  bool get supportsJsonSchemaThinking => false;

  @override
  bool get supportsMessageRendering => rendersMessages;

  @override
  LiteRtLmFinishReason? get lastFinishReason => null;

  @override
  LiteRtLmNativeSettlement get nativeSettlement =>
      LiteRtLmNativeSettlement.settled;

  @override
  void configureResponseThinkingTags({
    required String startTag,
    required String endTag,
  }) {}

  @override
  int? resolveDefaultVisualTokenBudget(int preferredBudget) => null;

  @override
  ({bool vision, bool audio, bool speculativeDecoding})? bundleCapabilities(
    String modelPath,
  ) => (
    vision: !failConversation,
    audio: !failConversation,
    speculativeDecoding: false,
  );

  @override
  LiteRtLmAsrRuntimeSession createAsrSession(LiteRtLmAsrRuntimeConfig config) =>
      throw UnsupportedError('This media fake has no ASR engine.');

  @override
  Future<LiteRtLmEmbeddingRuntimeSession> createEmbeddingSession({
    required String modelPath,
    required String backend,
    required String cacheDir,
    required int maxInputLength,
    required int numberOfThreads,
  }) => throw UnsupportedError('This media fake has no embedding engine.');

  @override
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  }) async {}

  @override
  void setMinLogLevel(int level) {}

  @override
  List<int> tokenize(String text, {bool addSpecial = true}) => text.codeUnits;

  @override
  String detokenize(List<int> tokens) => String.fromCharCodes(tokens);

  @override
  String renderMessageToString(Map<String, dynamic> message) {
    if (!rendersMessages || promptTemplates.isEmpty) {
      throw StateError('No renderable conversation.');
    }
    events.add('render');
    renderedMessages.add(
      jsonDecode(jsonEncode(message)) as Map<String, dynamic>,
    );
    final text = (message['content'] as List)
        .cast<Map<String, dynamic>>()
        .where((part) => part['type'] == 'text')
        .map((part) => part['text'] as String)
        .join();
    return '<|im_start|>${message['role']}\n$text<|im_end|>\n';
  }

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
    events.add('create');
    conversations += 1;
    if (failConversation) throw StateError('conversation create failed');
    promptTemplates.add(promptTemplate);
    final input = {'systemMessage': systemMessage, 'messages': messages};
    conversationInputs.add(
      jsonDecode(jsonEncode(input)) as Map<String, dynamic>,
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
    events.add('send');
    this.messageJson = messageJson;
    return Stream.value('A cat.');
  }

  @override
  Stream<String> generate(
    String prompt, {
    int? maxOutputTokens,
    double? repetitionPenalty,
    double? presencePenalty,
  }) => throw UnsupportedError('Media turns must use structured message JSON.');

  @override
  Future<LiteRtLmRuntimeResult> run({
    required String prompt,
    int warmupRuns = 1,
    int measuredRuns = 3,
  }) => throw UnsupportedError('This media fake has no benchmark engine.');

  @override
  LiteRtLmRuntimeMetrics readMetrics({required int wallMilliseconds}) =>
      LiteRtLmRuntimeMetrics(
        inputTokens: 0,
        outputTokens: 0,
        timeToFirstTokenSeconds: null,
        initSeconds: null,
        prefillTokensPerSecond: null,
        decodeTokensPerSecond: null,
        wallMilliseconds: wallMilliseconds,
      );

  @override
  void cancel() {}

  @override
  void dispose() {}
}
