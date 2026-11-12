import 'dart:convert';
import 'dart:io';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';

import 'audio_chat_smoke_support.dart';
import 'litert_lm_tokenizer_fixture.dart';

Future<void> main(List<String> args) async {
  final modelPath = args.isNotEmpty
      ? args[0]
      : Platform.environment['LITERT_LM_MODEL'];
  if (modelPath == null || modelPath.trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/litert_lm_chat_features_smoke.dart '
      '<model.litertlm> [cpu|gpu|npu|auto] [image-path]\n'
      'Optional env:\n'
      '  LITERT_LM_TOKENIZER_FIXTURE=qwen3-0.6b (known artifacts only)\n'
      '  LITERT_LM_IMAGE_PATH=<local image file>\n'
      '  LITERT_LM_AUDIO_PATH=<local encoded audio file>\n'
      '  LITERT_LM_AUDIO_EXPECTED_TEXT=<expected answer; required with audio>',
    );
    exitCode = 64;
    return;
  }

  final backend = args.length > 1 ? _parseBackend(args[1]) : _defaultBackend();
  final imagePath = _optionalImagePath(args.length > 2 ? args[2] : null);
  final audioPath = optionalAudioChatSmokePath(
    environmentName: 'LITERT_LM_AUDIO_PATH',
    smokeName: 'LiteRT-LM smoke',
  );
  final audioExpectedText = optionalAudioChatExpectedText(
    audioPath: audioPath,
    environmentName: 'LITERT_LM_AUDIO_EXPECTED_TEXT',
    audioEnvironmentName: 'LITERT_LM_AUDIO_PATH',
  );
  final audioFixture = audioPath == null
      ? null
      : await readAudioChatSmokeFixture(audioPath);
  final tokenizerFixture = selectLiteRtLmTokenizerFixture(
    Platform.environment['LITERT_LM_TOKENIZER_FIXTURE'],
  );
  final tokenizerArtifactSha256 = tokenizerFixture == null
      ? null
      : await verifyQwen3TokenizerArtifact(File(modelPath));
  final engine = LlamaEngine(LlamaBackend());
  try {
    await engine.loadModel(
      modelPath,
      modelParams: ModelParams(contextSize: 2048, liteRtLmBackend: backend),
    );

    final tokenizer = tokenizerFixture == null
        ? null
        : await checkQwen3Tokenizer(engine);

    final plain = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Reply with one short sentence saying hello.',
        ),
      ],
      tools: const [],
      enableThinking: false,
      maxTokens: 64,
    );

    final cutoff = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Count from 1 to 100, separated by commas.',
        ),
      ],
      tools: const [],
      enableThinking: false,
      maxTokens: 3,
    );
    final toolLoopCutoff = await _runToolLoopCutoffScenario(engine);

    final thinkingSupport = thinkingSupportForTemplate(
      readLiteRtLmBundleChatTemplate(modelPath),
    );
    final thinking = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is 2+2? Think briefly, then answer with the number.',
        ),
      ],
      tools: const [],
      enableThinking: true,
      // Greedy Qwen3-0.6B needs about 300 tokens on deterministic CPU kernels;
      // headroom keeps small numerics changes from truncating the answer.
      maxTokens: 1024,
    );

    final textHistory = await _runScenario(
      engine: engine,
      messages: const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: 'Answer briefly and accurately.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'Remember this code: PINE.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.assistant,
          text: 'I will remember PINE.',
        ),
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'What is the code? Answer only with the code.',
        ),
      ],
      tools: const [],
      enableThinking: false,
      maxTokens: 64,
    );

    final sessionStructuredOutput = await runSessionStructuredOutputScenario(
      engine,
    );

    final requiredTemplate = await engine.chatTemplate(
      _requiredToolMessages,
      tools: [_weatherTool],
      toolChoice: ToolChoice.required,
      enableThinking: false,
      includeTokenCount: false,
    );
    final requiredUnsupportedExpected =
        requiredTemplate.format == ChatFormat.hermes.index;
    final toolCall = await _runRequiredToolScenario(
      engine: engine,
      expectUnsupported: requiredUnsupportedExpected,
    );

    final nativeToolHistory = requiredUnsupportedExpected
        ? null
        : await _runScenario(
            engine: engine,
            messages: const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.system,
                text:
                    'For weather questions, call get_weather with the '
                    'requested city. Do not answer weather questions in text.',
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
                text:
                    'What is the weather in the remembered city? Use the tool.',
              ),
            ],
            tools: [_weatherTool],
            enableThinking: false,
            maxTokens: 160,
            toolChoice: ToolChoice.auto,
          );

    final nativeMediaRender = imagePath == null
        ? null
        : await renderLiteRtLmNativeMediaPrompt(
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
    final audioChat = audioFixture == null
        ? null
        : await _runScenario(
            engine: engine,
            messages: [
              LlamaChatMessage.withContent(
                role: LlamaChatRole.user,
                content: [
                  LlamaAudioContent(bytes: audioFixture.bytes),
                  const LlamaTextContent(audioChatQuestionPrompt),
                ],
              ),
            ],
            tools: const [],
            enableThinking: false,
            maxTokens: 64,
          );

    final result = {
      'backendName': await engine.getBackendName(),
      'requestedLiteRtLmBackend': backend.name,
      'format': requiredTemplate.format,
      if (tokenizer != null)
        'tokenizer': {
          'fixture': tokenizerFixture,
          'artifactSha256': tokenizerArtifactSha256,
          ...tokenizer,
        },
      'plain': plain.toJson(),
      'cutoff': cutoff.toJson(),
      'toolLoopCutoff': toolLoopCutoff,
      'thinking': {
        if (!thinkingSupport.canProduceThinking) ...{
          'status': 'not_applicable',
          'reason': thinkingSupport.reason,
        },
        ...thinking.toJson(),
      },
      'textHistory': textHistory.toJson(),
      'sessionStructuredOutput': sessionStructuredOutput,
      'toolCall': toolCall.toJson(),
      'nativeToolHistory':
          nativeToolHistory?.toJson() ??
          const {
            'status': 'not_applicable',
            'reason':
                'Hermes/Qwen auto tool calls are best-effort and are not '
                'asserted by this smoke',
          },
      if (nativeMediaRender != null)
        'nativeMediaRender': nativeMediaRender.toJson(),
      if (multimodal != null) 'multimodal': multimodal.toJson(),
      if (audioChat != null) ...{
        'audioInput': audioFixture!.toJson(),
        'audioChat': audioChat.toJson(),
      },
    };
    print('DIAGNOSTIC litert_lm_chat_features ${jsonEncode(result)}');
    _verifyResult(
      plain: plain,
      cutoff: cutoff,
      thinking: thinking,
      thinkingSupport: thinkingSupport,
      textHistory: textHistory,
      toolCall: toolCall,
      requiredUnsupportedExpected: requiredUnsupportedExpected,
      nativeToolHistory: nativeToolHistory,
      multimodal: multimodal,
      audioChat: audioChat,
      audioExpectedText: audioExpectedText,
    );
    print('RESULT litert_lm_chat_features ${jsonEncode(result)}');
  } finally {
    await engine.dispose();
  }
}

/// Checks refusal of a `oneOf` schema outside LiteRT-LM's schema contract.
/// Even an admitted provider must refuse before edits and leave the next turn usable.
Future<Map<String, Object?>> runSessionStructuredOutputScenario(
  LlamaEngine engine,
) async {
  final session = ChatSession(engine);
  final reported = <LlamaChatMessage>[];
  String? rejection;
  try {
    await session.createStructuredJson(
      [const LlamaTextContent('Reply with {"values": "ok"}.')],
      output: LlamaStructuredOutput.jsonSchema(
        schema: const {
          'type': 'object',
          'properties': {
            'values': {
              'oneOf': [
                {'type': 'string'},
                {'type': 'integer'},
              ],
            },
          },
          'required': ['values'],
          'additionalProperties': false,
        },
        decoder: (json) => json,
      ),
      enableThinking: false,
      onMessageAdded: reported.add,
    );
  } on LlamaUnsupportedException catch (error) {
    rejection = error.message;
  }
  final historyAfterRejection = session.history.length;
  final reply = StringBuffer();
  await for (final chunk in session.create(
    [const LlamaTextContent('Reply with one short sentence saying hello.')],
    params: const GenerationParams(maxTokens: 64),
    enableThinking: false,
  )) {
    reply.write(chunk.choices.firstOrNull?.delta.content ?? '');
  }
  final roles = [for (final message in session.history) message.role.name];
  final result = <String, Object?>{
    'unsupportedRequest': 'object_with_oneOf_property',
    'rejection': rejection,
    'historyAfterRejection': historyAfterRejection,
    'reportedMessages': reported.length,
    'rolesAfterNextTurn': roles,
    'nextReply': reply.toString(),
  };
  print('DIAGNOSTIC litert_lm_session_structured_output ${jsonEncode(result)}');
  if (rejection == null ||
      historyAfterRejection != 0 ||
      reported.isNotEmpty ||
      roles.join(',') != 'user,assistant' ||
      reply.toString().trim().isEmpty) {
    throw StateError(
      'LiteRT-LM ChatSession did not reject the unsupported schema request before '
      'recording the turn, or did not recover on the next turn.',
    );
  }
  return result;
}

/// Whether the chat template a loaded bundle renders can produce thinking.
class ThinkingSupport {
  const ThinkingSupport.supported() : canProduceThinking = true, reason = null;

  const ThinkingSupport.unsupported(String this.reason)
    : canProduceThinking = false;

  final bool canProduceThinking;
  final String? reason;
}

final RegExp _closedThinkBlock = RegExp(r'<think>\s*</think>');

/// Judges [template], the chat template embedded in a loaded bundle.
///
/// A heuristic for the known always-closed shape: a template that never
/// mentions `enable_thinking` and closes an empty think block in its generation
/// prompt is treated as unable to think. Any other template, or an unreadable
/// one, keeps the thinking assertion.
ThinkingSupport thinkingSupportForTemplate(String? template) {
  final generationStart = template?.lastIndexOf('add_generation_prompt') ?? -1;
  if (template == null ||
      generationStart < 0 ||
      template.contains('enable_thinking') ||
      !_closedThinkBlock.hasMatch(template.substring(generationStart))) {
    return const ThinkingSupport.supported();
  }
  return const ThinkingSupport.unsupported(
    'the bundle chat template never reads enable_thinking and its generation '
    'prompt always closes an empty <think></think> block, so it cannot '
    'produce thinking',
  );
}

void _verifyResult({
  required _ScenarioResult plain,
  required _ScenarioResult cutoff,
  required _ScenarioResult thinking,
  required ThinkingSupport thinkingSupport,
  required _ScenarioResult textHistory,
  required _RequiredToolScenarioResult toolCall,
  required bool requiredUnsupportedExpected,
  required _ScenarioResult? nativeToolHistory,
  _ScenarioResult? multimodal,
  _ScenarioResult? audioChat,
  String? audioExpectedText,
}) {
  if (plain.content.trim().isEmpty) {
    throw StateError('LiteRT-LM plain chat produced no visible content.');
  }
  if (plain.thinking.trim().isNotEmpty) {
    throw StateError(
      'LiteRT-LM plain chat produced an unexpected thinking delta.',
    );
  }
  if (plain.toolCalls.isNotEmpty) {
    throw StateError('LiteRT-LM plain chat produced an unexpected tool call.');
  }
  if (plain.finishReason != 'stop') {
    throw StateError(
      'LiteRT-LM plain chat finished with ${plain.finishReason}, not stop.',
    );
  }
  if (cutoff.finishReason != 'length') {
    throw StateError(
      'LiteRT-LM chat cut off at maxTokens finished with '
      '${cutoff.finishReason}, not length.',
    );
  }
  if (thinkingSupport.canProduceThinking) {
    if (thinking.thinking.trim().isEmpty) {
      throw StateError(
        'LiteRT-LM thinking scenario produced no thinking delta.',
      );
    }
    if (thinking.content.trim().isEmpty) {
      throw StateError(
        'LiteRT-LM thinking scenario produced no visible answer.',
      );
    }
  } else {
    if (thinking.thinking.trim().isNotEmpty) {
      throw StateError(
        'LiteRT-LM thinking scenario produced a thinking delta although its '
        'template cannot think.',
      );
    }
    if (thinking.content.trim().isEmpty) {
      throw StateError(
        'LiteRT-LM thinking scenario produced no visible answer.',
      );
    }
    stdout.writeln(
      'N/A litert_lm_chat_features thinking: ${thinkingSupport.reason}',
    );
  }
  if (!textHistory.content.contains('PINE') ||
      textHistory.thinking.isNotEmpty ||
      textHistory.toolCalls.isNotEmpty) {
    throw StateError(
      'LiteRT-LM system/history chat did not preserve the remembered code.',
    );
  }
  if (requiredUnsupportedExpected) {
    if (!toolCall.isUnsupported) {
      throw StateError(
        'Hermes/Qwen required tool choice did not fail explicitly unsupported.',
      );
    }
  } else {
    _verifyWeatherToolCall(
      toolCall.scenario!,
      scenarioName: 'LiteRT-LM required tool scenario',
    );
  }
  if (nativeToolHistory != null) {
    if (nativeToolHistory.content.trim().isNotEmpty) {
      throw StateError(
        'LiteRT-LM native tool/history scenario streamed content: '
        '${nativeToolHistory.content}',
      );
    }
    _verifyWeatherToolCall(
      nativeToolHistory,
      scenarioName: 'LiteRT-LM native tool/history scenario',
    );
  }
  if (multimodal != null && multimodal.content.trim().isEmpty) {
    throw StateError('LiteRT-LM multimodal scenario produced no content.');
  }
  if (audioChat != null) {
    verifyExactAudioChatAnswer(
      scenarioName: 'Gemma 4 audio chat',
      actualText: audioChat.content,
      expectedText: audioExpectedText!,
    );
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
  if (arguments is! String) {
    throw StateError('$scenarioName did not provide JSON string arguments.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(arguments);
  } catch (_) {
    throw StateError('$scenarioName produced invalid JSON arguments.');
  }
  if (decoded is! Map ||
      decoded.length != 1 ||
      decoded['location'] != 'Seoul') {
    throw StateError('$scenarioName did not pass the expected location.');
  }
}

/// An automatic tool loop whose reply is cut off at `maxTokens` must stop
/// truncated, run no tool and roll the turn back.
Future<Map<String, Object?>> _runToolLoopCutoffScenario(
  LlamaEngine engine,
) async {
  var toolRuns = 0;
  final session = ChatSession(engine);
  final result = await session.completeWithTools(
    const [LlamaTextContent('What is the weather in Seoul? Use the tool.')],
    tools: [
      ToolDefinition(
        name: _weatherTool.name,
        description: _weatherTool.description,
        parameters: _weatherTool.parameters,
        handler: (_) async {
          toolRuns++;
          return 'Sunny';
        },
      ),
    ],
    params: const GenerationParams(maxTokens: 3, temp: 0.0, seed: 1),
    enableThinking: false,
  );
  final summary = <String, Object?>{
    'stopReason': result.stopReason.name,
    'finishReason': result.completion.finishReason?.name,
    'rolledBack': result.rolledBack,
    'historyLength': session.history.length,
    'toolRuns': toolRuns,
  };
  if (result.stopReason != LlamaToolLoopStopReason.truncated ||
      result.completion.finishReason != LlamaFinishReason.length ||
      !result.rolledBack ||
      session.history.isNotEmpty ||
      toolRuns != 0) {
    throw StateError(
      'LiteRT-LM automatic tool loop did not stop truncated at maxTokens '
      'without running tools: ${jsonEncode(summary)}',
    );
  }
  return summary;
}

Future<_RequiredToolScenarioResult> _runRequiredToolScenario({
  required LlamaEngine engine,
  required bool expectUnsupported,
}) async {
  try {
    final scenario = await _runScenario(
      engine: engine,
      messages: _requiredToolMessages,
      tools: [_weatherTool],
      enableThinking: false,
      maxTokens: 160,
      toolChoice: ToolChoice.required,
    );
    if (expectUnsupported) {
      throw StateError(
        'Hermes/Qwen required tool choice reached generation instead of '
        'failing explicitly unsupported.',
      );
    }
    return _RequiredToolScenarioResult.success(scenario);
  } on LlamaUnsupportedException catch (error) {
    if (!expectUnsupported) {
      rethrow;
    }
    if (!error.message.contains('ToolChoice.required') ||
        !error.message.contains('Hermes/Qwen') ||
        !error.message.contains('grammar-constrained decoding')) {
      throw StateError(
        'Hermes/Qwen required tool choice produced a non-actionable '
        'unsupported error.',
      );
    }
    return _RequiredToolScenarioResult.unsupported(error.message);
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

/// Renders an encoded image through the smoke tool's native runtime client.
///
/// Shared by the CLI and local qualification test to check the same encoder
/// configuration. This tool helper is not exported by the package.
Future<LiteRtLmNativeMediaRenderResult> renderLiteRtLmNativeMediaPrompt({
  required String modelPath,
  required LiteRtLmBackendPreference backend,
  required String imagePath,
}) async {
  final client = LiteRtLmRuntimeClient();
  try {
    await client.initialize(
      modelPath: modelPath,
      backend: _runtimeBackendName(backend),
      visionBackend: _runtimeBackendName(backend),
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
    return LiteRtLmNativeMediaRenderResult(
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

class _RequiredToolScenarioResult {
  const _RequiredToolScenarioResult.success(this.scenario)
    : unsupportedMessage = null;

  const _RequiredToolScenarioResult.unsupported(this.unsupportedMessage)
    : scenario = null;

  final _ScenarioResult? scenario;
  final String? unsupportedMessage;

  bool get isUnsupported => unsupportedMessage != null;

  Map<String, Object?> toJson() =>
      scenario?.toJson() ??
      {'status': 'unsupported', 'message': unsupportedMessage};
}

/// Native image-render diagnostics shared by the smoke tool and its test.
class LiteRtLmNativeMediaRenderResult {
  /// Creates diagnostics for a prompt containing a recognized image marker.
  const LiteRtLmNativeMediaRenderResult({
    required this.marker,
    required this.renderedLength,
    required this.renderedTail,
  });

  /// Recognized native image marker in the rendered prompt.
  final String marker;

  /// Number of characters in the rendered prompt.
  final int renderedLength;

  /// Final characters of the rendered prompt for bounded diagnostics.
  final String renderedTail;

  /// Serializes the bounded native rendering diagnostics.
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

const List<LlamaChatMessage> _requiredToolMessages = [
  LlamaChatMessage.fromText(
    role: LlamaChatRole.system,
    text: 'You must call get_weather. Return only a tool call.',
  ),
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Call get_weather with location Seoul.',
  ),
];

final ToolDefinition _weatherTool = ToolDefinition(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  parameters: [ToolParam.string('location', description: 'City name')],
  handler: (_) async => 'Sunny',
);
