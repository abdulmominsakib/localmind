import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:llamadart/llamadart.dart';

class MockLlamaBackend implements LlamaBackend, BackendAvailability {
  bool _isReady = false;
  final List<String> prompts = [];
  final List<GenerationParams> paramsList = [];

  final _generateQueuedTokens = <List<String>>[];
  int _generateCallCount = 0;

  @override
  bool get isReady => _isReady;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    _isReady = true;
    return 1;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    Function(double progress)? onProgress,
  }) async {
    _isReady = true;
    return 1;
  }

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 1;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 2048;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    prompts.add(prompt);
    paramsList.add(params);

    if (_generateCallCount < _generateQueuedTokens.length) {
      final tokens = _generateQueuedTokens[_generateCallCount];
      _generateCallCount++;
      for (final t in tokens) {
        yield utf8.encode(t);
      }
    }
  }

  void queueResponse(List<String> tokens) {
    _generateQueuedTokens.add(tokens);
  }

  @override
  void cancelGeneration() {}

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => [1, 2, 3];

  @override
  Future<String> detokenize(
    int modelHandle,
    List<int> tokens, {
    bool special = false,
  }) async => 'decoded';

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => {
    'general.architecture': 'llama',
    'tokenizer.chat_template':
        "{% if tools %}<|im_start|>system\\n{{ tools | tojson }}<|im_end|>\\n{% endif %}{% for message in messages %}<|im_start|>{{ message.role }}\\n{{ message.content }}<|im_end|>\\n{% endfor %}{% if add_generation_prompt %}<|im_start|>assistant\\n{% endif %}",
  };

  @override
  Future<void> setLoraAdapter(
    int contextHandle,
    String path,
    double scale,
  ) async {}

  @override
  Future<void> removeLoraAdapter(int contextHandle, String path) async {}

  @override
  Future<void> clearLoraAdapters(int contextHandle) async {}

  @override
  Future<String> getBackendName() async => 'Mock';

  @override
  Future<String> getAvailableBackends() async => 'Mock';

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<bool> isGpuSupported() async => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<void> dispose() async {
    _isReady = false;
  }

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => null;

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;

  @override
  Future<bool> supportsAudio(int mmContextHandle) async => false;

  @override
  Future<({int total, int free})> getVramInfo() async =>
      (total: 8192, free: 4096);

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    // Basic mock implementation that just joins messages
    return messages.map((m) => "${m['role']}: ${m['content']}").join('\n');
  }
}

void main() {
  late MockLlamaBackend backend;
  late LlamaEngine engine;
  late List<ToolDefinition> tools;

  setUp(() async {
    backend = MockLlamaBackend();
    engine = LlamaEngine(backend);
    await engine.loadModel('qwen-test.gguf');

    tools = [
      ToolDefinition(
        name: 'get_weather',
        description: 'Get weather',
        parameters: [
          ToolParam.string(
            'location',
            description: 'City name',
            required: true,
          ),
        ],
        handler: (params) async =>
            'Sunny in ${params.getRequiredString("location")}',
      ),
    ];
  });

  group('ToolDefinition', () {
    test('toJsonSchema includes tool definitions', () {
      final tool = tools.first;
      final schema = tool.toJsonSchema();
      expect(schema['properties'], containsPair('location', isA<Map>()));
    });

    test('invoke handles valid tool call', () async {
      final tool = tools.first;
      final result = await tool.invoke({'location': 'London'});
      expect(result, 'Sunny in London');
    });
  });

  group('ChatSession with Tools', () {
    test('tools are passed to engine.create', () async {
      final session = ChatSession(engine);

      backend.queueResponse(['Checking the weather for you']);

      await session.create([
        const LlamaTextContent('What is the weather?'),
      ], tools: tools).drain();

      // Verify tool definitions were injected into prompt
      expect(backend.prompts.first, contains('get_weather'));
      expect(backend.prompts.first, contains('Get weather'));
      expect(backend.prompts.first, contains('<|im_start|>system'));
      // Check for the tools JSON injection
      expect(backend.prompts.first, contains('"name":"get_weather"'));
    });

    test('response with tool call can be parsed by caller', () async {
      final session = ChatSession(engine);

      backend.queueResponse([
        '<tool_call>{"name": "get_weather", "arguments": {"location": "London"}}</tool_call>',
      ]);

      final responseChunks = await session.create([
        const LlamaTextContent('Weather?'),
      ], tools: tools).toList();

      final toolCalls = responseChunks
          .expand((c) => c.choices.first.delta.toolCalls ?? [])
          .toList();
      final assistantText = responseChunks
          .map((c) => c.choices.first.delta.content ?? '')
          .join();

      String? name;
      Map<String, dynamic> params;
      if (toolCalls.isNotEmpty) {
        name = toolCalls.first.function?.name;
        final argumentsStr = toolCalls.first.function?.arguments ?? '{}';
        params = jsonDecode(argumentsStr) as Map<String, dynamic>;
      } else {
        final match = RegExp(
          r'<tool_call>\s*(\{[\s\S]*?\})\s*</tool_call>',
        ).firstMatch(assistantText);
        expect(match, isNotNull);
        final payload = jsonDecode(match!.group(1)!) as Map<String, dynamic>;
        name = payload['name'] as String?;
        final arguments = payload['arguments'];
        if (arguments is String) {
          params = jsonDecode(arguments) as Map<String, dynamic>;
        } else if (arguments is Map<String, dynamic>) {
          params = arguments;
        } else {
          params = <String, dynamic>{};
        }
      }

      expect(name, 'get_weather');
      expect(params, containsPair('location', 'London'));
      final toolName = name!;
      final tool = tools.firstWhere((t) => t.name == toolName);
      final toolResult = await tool.invoke(params);
      expect(toolResult, contains('London'));

      // Caller adds tool result and continues
      session.addMessage(
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [LlamaToolResultContent(name: toolName, result: toolResult)],
        ),
      );

      backend.queueResponse(['The weather in London is sunny.']);
      final finalResponse = await session
          .create([])
          .map((c) => c.choices.first.delta.content ?? '')
          .join();
      expect(finalResponse, contains('sunny'));
    });

    test('engine.create accepts tools directly', () async {
      backend.queueResponse(['Direct engine response']);

      final messages = [
        const LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is the weather?',
        ),
      ];

      final result = await engine
          .create(messages, tools: tools)
          .map((c) => c.choices.first.delta.content ?? '')
          .join();

      expect(result, 'Direct engine response');
      // Should contain tool info in system prompt
      expect(backend.prompts.first, contains('get_weather'));
      expect(backend.prompts.first, contains('<|im_start|>system'));
    });
  });
}
