import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty
      ? args[0]
      : Platform.environment['LITERT_LM_MODEL'];
  if (modelPath == null || modelPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/litert_lm_chat_features_smoke.dart '
      '<model.litertlm> [cpu|gpu|npu|auto] [image-path]\n'
      'Optional env: LITERT_LM_IMAGE_PATH=<local image file>',
    );
    exitCode = 64;
    return;
  }

  final backend = args.length > 1 ? _parseBackend(args[1]) : _defaultBackend();
  final imagePath = _optionalImagePath(args.length > 2 ? args[2] : null);
  final engine = LlamaEngine(LlamaBackend());
  try {
    await engine.loadModel(
      modelPath,
      modelParams: ModelParams(contextSize: 2048, liteRtLmBackend: backend),
    );

    final thinking = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text:
              'A farmer has 17 sheep. All but 9 run away. Think step by step, '
              'then state how many sheep remain.',
        ),
      ],
      tools: const [],
      enableThinking: true,
      maxTokens: 256,
    );

    final toolCall = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'You must call get_weather. Return only a tool call.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Call get_weather with location Seoul.',
        ),
      ],
      tools: [
        ToolDefinition(
          name: 'get_weather',
          description: 'Returns current weather for a city.',
          parameters: [ToolParam.string('location', description: 'City name')],
          handler: (_) async => 'Sunny',
        ),
      ],
      enableThinking: false,
      maxTokens: 160,
      toolChoice: ToolChoice.required,
    );

    final nativeToolHistory = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text:
              'For weather questions, call get_weather with the requested '
              'city. Do not answer weather questions in text.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Remember this city: Seoul.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'I will remember Seoul.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is the weather in the remembered city? Use the tool.',
        ),
      ],
      tools: [
        ToolDefinition(
          name: 'get_weather',
          description: 'Returns current weather for a city.',
          parameters: [ToolParam.string('location', description: 'City name')],
          handler: (_) async => 'Sunny',
        ),
      ],
      enableThinking: false,
      maxTokens: 160,
      toolChoice: ToolChoice.auto,
    );

    final nativeMediaRender = imagePath == null
        ? null
        : await _renderNativeMediaPrompt(
            modelPath: modelPath,
            backend: backend,
            imagePath: imagePath,
          );
    final multimodal = imagePath == null
        ? null
        : await _runScenario(
            engine: engine,
            messages: [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [
                  const LlamaTextContent(
                    'Describe the image in one short sentence.',
                  ),
                  LlamaImageContent(path: imagePath),
                ],
              ),
            ],
            tools: const [],
            enableThinking: false,
            maxTokens: 96,
          );

    final result = {
      'backendName': await engine.getBackendName(),
      'requestedLiteRtLmBackend': backend.name,
      'thinking': thinking.toJson(),
      'toolCall': toolCall.toJson(),
      'nativeToolHistory': nativeToolHistory.toJson(),
      if (nativeMediaRender != null)
        'nativeMediaRender': nativeMediaRender.toJson(),
      if (multimodal != null) 'multimodal': multimodal.toJson(),
    };
    _verifyResult(
      thinking: thinking,
      toolCall: toolCall,
      nativeToolHistory: nativeToolHistory,
      multimodal: multimodal,
    );
    print('RESULT litert_lm_chat_features ${jsonEncode(result)}');
  } finally {
    await engine.dispose();
  }
}

void _verifyResult({
  required _ScenarioResult thinking,
  required _ScenarioResult toolCall,
  required _ScenarioResult nativeToolHistory,
  _ScenarioResult? multimodal,
}) {
  if (thinking.thinking.trim().isEmpty) {
    throw StateError('Gemma 4 thinking scenario produced no thinking delta.');
  }
  _verifyWeatherToolCall(
    toolCall,
    scenarioName: 'Gemma 4 required tool scenario',
  );
  if (nativeToolHistory.content.trim().isNotEmpty) {
    throw StateError(
      'Gemma 4 native tool/history scenario streamed content: '
      '${nativeToolHistory.content}',
    );
  }
  _verifyWeatherToolCall(
    nativeToolHistory,
    scenarioName: 'Gemma 4 native tool/history scenario',
  );
  if (multimodal != null && multimodal.content.trim().isEmpty) {
    throw StateError('Gemma 4 multimodal scenario produced no content.');
  }
}

void _verifyWeatherToolCall(
  _ScenarioResult scenario, {
  required String scenarioName,
}) {
  if (scenario.finishReason != 'tool_calls') {
    throw StateError('$scenarioName finished with ${scenario.finishReason}.');
  }
  if (scenario.toolCalls.length != 1) {
    throw StateError(
      '$scenarioName produced ${scenario.toolCalls.length} calls.',
    );
  }
  final function = scenario.toolCalls.first['function'];
  if (function is! Map || function['name'] != 'get_weather') {
    throw StateError('$scenarioName did not call get_weather.');
  }
  final arguments = function['arguments'];
  if (arguments is! String || !arguments.contains('"location":"Seoul"')) {
    throw StateError('$scenarioName did not pass the expected location.');
  }
}

Future<_ScenarioResult> _runScenario({
  required LlamaEngine engine,
  required List<LlamaChatMessage> messages,
  required List<ToolDefinition> tools,
  required bool enableThinking,
  required int maxTokens,
  ToolChoice toolChoice = ToolChoice.auto,
}) async {
  final content = StringBuffer();
  final thinking = StringBuffer();
  final toolCalls = <Map<String, Object?>>[];
  var chunks = 0;
  var finishReason = '';

  await for (final chunk in engine.create(
    messages,
    tools: tools.isEmpty ? null : tools,
    toolChoice: toolChoice,
    enableThinking: enableThinking,
    params: GenerationParams(maxTokens: maxTokens, temp: 0.0, seed: 1),
  )) {
    chunks++;
    final choice = chunk.choices.first;
    finishReason = choice.finishReason ?? '';
    final delta = choice.delta;
    if (delta.content != null) {
      content.write(delta.content);
    }
    if (delta.thinking != null) {
      thinking.write(delta.thinking);
    }
    for (final call
        in delta.toolCalls ?? const <LlamaCompletionChunkToolCall>[]) {
      toolCalls.add(call.toJson());
    }
  }

  return _ScenarioResult(
    chunks: chunks,
    finishReason: finishReason,
    content: content.toString(),
    thinking: thinking.toString(),
    toolCalls: toolCalls,
  );
}

Future<_NativeMediaRenderResult> _renderNativeMediaPrompt({
  required String modelPath,
  required LiteRtLmBackendPreference backend,
  required String imagePath,
}) async {
  final client = LiteRtLmRuntimeClient();
  try {
    await client.initialize(
      modelPath: modelPath,
      backend: _runtimeBackendName(backend),
      maxTokens: 2048,
      outputTokens: 32,
      maxNumImages: 1,
      speculativeDecoding: false,
    );
    client.createConversation(temperature: 0, topK: 1, topP: 1, seed: 1);
    final rendered = client.renderMessageToString({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Describe the image in one short sentence.'},
        {'type': 'image', 'path': imagePath},
      ],
    });
    final marker = _firstMediaMarker(rendered);
    if (marker == null) {
      throw StateError(
        'Native Gemma 4 render did not include an image marker. Rendered tail: '
        '${_tail(rendered)}',
      );
    }
    return _NativeMediaRenderResult(
      marker: marker,
      renderedLength: rendered.length,
      renderedTail: _tail(rendered),
    );
  } finally {
    client.dispose();
  }
}

String _runtimeBackendName(LiteRtLmBackendPreference backend) {
  final nativeName = backend.nativeName;
  if (nativeName != null) {
    return nativeName;
  }
  return Platform.isAndroid || Platform.isMacOS ? 'gpu' : 'cpu';
}

String? _firstMediaMarker(String rendered) {
  for (final marker in const [
    '<|image|>',
    '<start_of_image>',
    '<image_soft_token>',
  ]) {
    if (rendered.contains(marker)) {
      return marker;
    }
  }
  return null;
}

LiteRtLmBackendPreference _defaultBackend() {
  if (Platform.isAndroid || Platform.isMacOS) {
    return LiteRtLmBackendPreference.gpu;
  }
  return LiteRtLmBackendPreference.cpu;
}

String? _optionalImagePath(String? argValue) {
  final value = argValue ?? Platform.environment['LITERT_LM_IMAGE_PATH'];
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final image = File(value);
  if (!image.existsSync()) {
    throw ArgumentError('LiteRT-LM smoke image does not exist: $value');
  }
  return image.path;
}

LiteRtLmBackendPreference _parseBackend(String value) {
  switch (value.trim().toLowerCase()) {
    case 'auto':
      return LiteRtLmBackendPreference.auto;
    case 'cpu':
      return LiteRtLmBackendPreference.cpu;
    case 'gpu':
      return LiteRtLmBackendPreference.gpu;
    case 'npu':
      return LiteRtLmBackendPreference.npu;
    default:
      throw ArgumentError.value(
        value,
        'backend',
        'Expected auto, cpu, gpu, or npu.',
      );
  }
}

class _ScenarioResult {
  const _ScenarioResult({
    required this.chunks,
    required this.finishReason,
    required this.content,
    required this.thinking,
    required this.toolCalls,
  });

  final int chunks;
  final String finishReason;
  final String content;
  final String thinking;
  final List<Map<String, Object?>> toolCalls;

  Map<String, Object?> toJson() => {
    'chunks': chunks,
    'finishReason': finishReason,
    'contentLength': content.length,
    'contentTail': _tail(content),
    'thinkingLength': thinking.length,
    'thinkingTail': _tail(thinking),
    'toolCallCount': toolCalls.length,
    'toolCalls': toolCalls,
  };
}

class _NativeMediaRenderResult {
  const _NativeMediaRenderResult({
    required this.marker,
    required this.renderedLength,
    required this.renderedTail,
  });

  final String marker;
  final int renderedLength;
  final String renderedTail;

  Map<String, Object?> toJson() => {
    'marker': marker,
    'renderedLength': renderedLength,
    'renderedTail': renderedTail,
  };
}

String _tail(String value) {
  if (value.length <= 240) {
    return value;
  }
  return value.substring(value.length - 240);
}
