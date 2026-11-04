import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty
      ? args[0]
      : Platform.environment['GGUF_MODEL'];
  if (modelPath == null || modelPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/gguf_chat_features_smoke.dart '
      '<model.gguf> [auto|cpu|metal|vulkan|cuda|opencl|hip|blas] '
      '[mmproj.gguf] [image-path]',
    );
    exitCode = 64;
    return;
  }

  final backend = args.length > 1 ? _parseBackend(args[1]) : GpuBackend.auto;
  final mmprojPath = _nonEmptyTrimmed(
    args.length > 2 ? args[2] : Platform.environment['GGUF_MMPROJ'],
  );
  final imagePath = _nonEmptyTrimmed(
    args.length > 3 ? args[3] : Platform.environment['GGUF_IMAGE'],
  );
  if (imagePath != null && mmprojPath == null) {
    stderr.writeln('GGUF_IMAGE/image-path requires GGUF_MMPROJ/mmproj path.');
    exitCode = 64;
    return;
  }

  final engine = LlamaEngine(LlamaBackend());
  try {
    engine.setLogLevel(LlamaLogLevel.warn);
    await engine.loadModel(
      modelPath,
      modelParams: ModelParams(
        contextSize: 2048,
        preferredBackend: backend,
        gpuLayers: backend == GpuBackend.cpu ? 0 : ModelParams.maxGpuLayers,
        numberOfThreads: 4,
        numberOfThreadsBatch: 4,
      ),
    );
    if (mmprojPath != null) {
      await engine.loadMultimodalProjector(mmprojPath);
    }

    final template = await engine.chatTemplate(
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Reply with one word.',
        ),
      ],
      addAssistant: true,
      enableThinking: false,
    );

    final noThinking = await _runScenario(
      engine: engine,
      name: 'noThinking',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'Answer directly. Do not include reasoning tags.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is 2 + 2? Reply with only the number.',
        ),
      ],
      tools: const [],
      enableThinking: false,
      maxTokens: 384,
    );

    final thinking = await _runScenario(
      engine: engine,
      name: 'thinking',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text:
              'Think briefly if the model supports a thinking channel, then answer directly.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is 3 + 5? Reply with only the final number.',
        ),
      ],
      tools: const [],
      enableThinking: true,
      maxTokens: 384,
    );

    final toolCallNoThinking = await _runScenario(
      engine: engine,
      name: 'toolCallNoThinking',
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
      tools: [_weatherTool],
      enableThinking: false,
      maxTokens: 160,
      toolChoice: ToolChoice.required,
    );

    final toolCallWithThinking = await _runScenario(
      engine: engine,
      name: 'toolCallWithThinking',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text:
              'Think briefly if the model supports a thinking channel, then call get_weather. Return only the tool call.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Call get_weather with location Seoul.',
        ),
      ],
      tools: [_weatherTool],
      enableThinking: true,
      maxTokens: 240,
      toolChoice: ToolChoice.required,
    );

    final toolCallWithThinkingBudget = await _runScenario(
      engine: engine,
      name: 'toolCallWithThinkingBudget',
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text:
              'Think briefly if the model supports a thinking channel, then call get_weather. Return only the tool call.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Call get_weather with location Seoul.',
        ),
      ],
      tools: [_weatherTool],
      enableThinking: true,
      maxTokens: 160,
      thinkingBudget: const ThinkingBudget(maxTokens: 4),
      toolChoice: ToolChoice.required,
    );

    final toolCallWithZeroThinkingBudget = await _runScenario(
      engine: engine,
      name: 'toolCallWithZeroThinkingBudget',
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
      tools: [_weatherTool],
      enableThinking: true,
      maxTokens: 160,
      thinkingBudget: const ThinkingBudget(maxTokens: 0),
      toolChoice: ToolChoice.required,
    );

    final multimodal = mmprojPath != null && imagePath != null
        ? await _runScenario(
            engine: engine,
            name: 'multimodal',
            messages: [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [
                  const LlamaTextContent(
                    'Describe this image in one short sentence.',
                  ),
                  LlamaImageContent(path: imagePath),
                ],
              ),
            ],
            tools: const [],
            enableThinking: false,
            maxTokens: 120,
          )
        : null;

    _verifyNoThinking(noThinking);
    _verifyThinkingSeparation(thinking);
    _verifyNoThinking(toolCallNoThinking);
    _verifyThinkingSeparation(toolCallWithThinking);
    _verifyToolCall(toolCallNoThinking);
    _verifyToolCall(toolCallWithThinking);
    _verifyThinkingSeparation(toolCallWithThinkingBudget);
    _verifyToolCall(toolCallWithThinkingBudget);
    _verifyThinkingSuppressedByZeroBudget(toolCallWithZeroThinkingBudget);
    _verifyToolCall(toolCallWithZeroThinkingBudget);
    if (multimodal != null) {
      _verifyHasOutput(multimodal);
      _verifyNoThinking(multimodal);
    }

    final result = {
      'backendName': await engine.getBackendName(),
      'requestedBackend': backend.name,
      'format': template.format,
      'noThinking': noThinking.toJson(),
      'thinking': thinking.toJson(),
      'toolCallNoThinking': toolCallNoThinking.toJson(),
      'toolCallWithThinking': toolCallWithThinking.toJson(),
      'toolCallWithThinkingBudget': toolCallWithThinkingBudget.toJson(),
      'toolCallWithZeroThinkingBudget': toolCallWithZeroThinkingBudget.toJson(),
      if (multimodal != null) 'multimodal': multimodal.toJson(),
    };
    print('RESULT gguf_chat_features ${jsonEncode(result)}');
  } finally {
    await engine.dispose();
  }
}

String? _nonEmptyTrimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Future<_ScenarioResult> _runScenario({
  required LlamaEngine engine,
  required String name,
  required List<LlamaChatMessage> messages,
  required List<ToolDefinition> tools,
  required bool enableThinking,
  required int maxTokens,
  ThinkingBudget? thinkingBudget,
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
    params: GenerationParams(
      maxTokens: maxTokens,
      temp: 0.0,
      seed: 1,
      thinkingBudget: thinkingBudget,
    ),
  )) {
    chunks++;
    final choice = chunk.choices.first;
    finishReason = choice.finishReason ?? finishReason;
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
    name: name,
    chunks: chunks,
    finishReason: finishReason,
    content: content.toString(),
    thinking: thinking.toString(),
    toolCalls: toolCalls,
  );
}

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('location', description: 'City name')],
  handler: (_) async => 'Sunny',
);

void _verifyHasOutput(_ScenarioResult result) {
  if (result.content.trim().isEmpty &&
      result.thinking.trim().isEmpty &&
      result.toolCalls.isEmpty) {
    throw StateError('${result.name} scenario produced no output.');
  }
}

void _verifyNoThinking(_ScenarioResult result) {
  _verifyHasOutput(result);
  if (result.thinking.trim().isNotEmpty) {
    throw StateError(
      '${result.name} scenario leaked thinking while enableThinking=false.',
    );
  }
  _verifyNoThinkingMarkers(result);
}

void _verifyThinkingSuppressedByZeroBudget(_ScenarioResult result) {
  _verifyHasOutput(result);
  if (result.thinking.trim().isNotEmpty) {
    throw StateError(
      '${result.name} scenario emitted thinking despite thinkingBudget.maxTokens=0.',
    );
  }
  _verifyNoThinkingMarkers(result);
}

void _verifyThinkingSeparation(_ScenarioResult result) {
  _verifyHasOutput(result);
  _verifyNoThinkingMarkers(result);
}

void _verifyNoThinkingMarkers(_ScenarioResult result) {
  final leakedMarkers = const [
    '<think>',
    '</think>',
    '<|channel>thought',
    '<channel|>',
  ].where(result.content.contains).toList(growable: false);
  if (leakedMarkers.isNotEmpty) {
    throw StateError(
      '${result.name} scenario leaked thinking markers in content: '
      '$leakedMarkers',
    );
  }
}

void _verifyToolCall(_ScenarioResult result) {
  if (result.finishReason != 'tool_calls') {
    throw StateError(
      '${result.name} scenario finished with ${result.finishReason}; '
      'content=${_tail(result.content)}',
    );
  }
  if (result.content.trim().isNotEmpty) {
    throw StateError(
      '${result.name} scenario leaked content: ${_tail(result.content)}',
    );
  }
  if (result.toolCalls.length != 1) {
    throw StateError(
      '${result.name} expected 1 tool call, got ${result.toolCalls.length}.',
    );
  }

  final function = result.toolCalls.first['function'];
  if (function is! Map || function['name'] != 'get_weather') {
    throw StateError(
      '${result.name} scenario did not call get_weather: '
      '${result.toolCalls.first}',
    );
  }
  final arguments = function['arguments'];
  if (arguments is! String) {
    throw StateError(
      '${result.name} tool call has no string arguments: $function',
    );
  }
  final decoded = jsonDecode(arguments);
  final location = decoded is Map ? decoded['location'] : null;
  if (location is! String || !location.toLowerCase().contains('seoul')) {
    throw StateError('${result.name} unexpected tool arguments: $arguments');
  }
}

GpuBackend _parseBackend(String value) {
  switch (value.trim().toLowerCase()) {
    case 'auto':
      return GpuBackend.auto;
    case 'cpu':
      return GpuBackend.cpu;
    case 'metal':
      return GpuBackend.metal;
    case 'vulkan':
    case 'vk':
      return GpuBackend.vulkan;
    case 'cuda':
      return GpuBackend.cuda;
    case 'opencl':
    case 'open-cl':
    case 'ocl':
      return GpuBackend.opencl;
    case 'hip':
      return GpuBackend.hip;
    case 'blas':
      return GpuBackend.blas;
    default:
      throw ArgumentError.value(
        value,
        'backend',
        'Expected auto, cpu, metal, vulkan, cuda, opencl, hip, or blas.',
      );
  }
}

class _ScenarioResult {
  const _ScenarioResult({
    required this.name,
    required this.chunks,
    required this.finishReason,
    required this.content,
    required this.thinking,
    required this.toolCalls,
  });

  final String name;
  final int chunks;
  final String finishReason;
  final String content;
  final String thinking;
  final List<Map<String, Object?>> toolCalls;

  Map<String, Object?> toJson() => {
    'name': name,
    'chunks': chunks,
    'finishReason': finishReason,
    'contentLength': content.length,
    'contentTail': _tail(content),
    'thinkingLength': thinking.length,
    'thinkingTail': _tail(thinking),
    'thinkingObserved': thinking.trim().isNotEmpty,
    'toolCallCount': toolCalls.length,
    'toolCalls': toolCalls,
  };
}

String _tail(String value) {
  if (value.length <= 240) {
    return value;
  }
  return value.substring(value.length - 240);
}
