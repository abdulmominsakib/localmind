import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

class _IdleBackend implements LlamaBackend {
  @override
  void cancelGeneration() {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

typedef ScriptedReply = Stream<LlamaCompletionChunk> Function();

/// Answers each [create] call with the next scripted reply and records the
/// messages and tool choice it was given.
///
/// [onRequest] sees each request first; an error it throws fails that
/// request's stream, as a template that rejects the messages would.
class ScriptedChatEngine extends LlamaEngine {
  ScriptedChatEngine() : super(_IdleBackend());

  final List<ScriptedReply> replies = [];
  final List<List<LlamaChatMessage>> requests = [];
  final List<ToolChoice?> toolChoices = [];

  /// The `enableThinking` and `chatTemplateKwargs` of each [create] call.
  final List<(bool, Map<String, dynamic>?)> createOptions = [];

  /// The `enableThinking` and `chatTemplateKwargs` of each [chatTemplate]
  /// call.
  final List<(bool, Map<String, dynamic>?)> templateOptions = [];

  /// The `templateNow` of each [create] call.
  final List<DateTime?> createTemplateNows = [];

  /// The `templateNow` of each [chatTemplate] call.
  final List<DateTime?> templateTemplateNows = [];
  int promptTokens = 0;

  /// The prompt token count of a request; [promptTokens] when unset.
  int Function(List<LlamaChatMessage> messages)? countFor;
  void Function(List<LlamaChatMessage> messages, List<ToolDefinition>? tools)?
  onRequest;

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    requests.add(List.of(messages));
    toolChoices.add(toolChoice);
    createOptions.add((enableThinking, chatTemplateKwargs));
    createTemplateNows.add(templateNow);
    try {
      onRequest?.call(messages, tools);
    } catch (error, stackTrace) {
      return Stream.error(error, stackTrace);
    }
    if (replies.isEmpty) fail('unexpected request ${requests.length}');
    return replies.removeAt(0)();
  }

  @override
  Future<LlamaChatTemplateResult> chatTemplate(
    List<LlamaChatMessage> messages, {
    bool addAssistant = true,
    @Deprecated('Use responseFormat.') Map<String, dynamic>? jsonSchema,
    List<ToolDefinition>? tools,
    ToolChoice toolChoice = ToolChoice.auto,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? customTemplate,
    String? sourceLangCode,
    String? targetLangCode,
    bool includeTokenCount = true,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) async {
    templateOptions.add((enableThinking, chatTemplateKwargs));
    templateTemplateNows.add(templateNow);
    return LlamaChatTemplateResult(
      prompt: '',
      tokenCount: countFor?.call(messages) ?? promptTokens,
    );
  }
}

LlamaCompletionChunk scriptedChunk({
  String? content,
  List<LlamaCompletionChunkToolCall>? toolCalls,
  String? finishReason,
}) => LlamaCompletionChunk(
  id: 'c',
  object: 'chat.completion.chunk',
  created: 1,
  model: 'm',
  choices: [
    LlamaCompletionChunkChoice(
      index: 0,
      delta: LlamaCompletionChunkDelta(content: content, toolCalls: toolCalls),
      finishReason: finishReason,
    ),
  ],
);

ScriptedReply scriptedAnswer(String text) =>
    () => Stream.fromIterable([
      scriptedChunk(content: text, finishReason: 'stop'),
    ]);

/// A reply that [GenerationParams.maxTokens] cut off after [text].
ScriptedReply scriptedTruncated(String text) =>
    () => Stream.fromIterable([
      scriptedChunk(content: text, finishReason: 'length'),
    ]);

ScriptedReply scriptedCalls(
  List<(String id, String name, String arguments)> calls,
) =>
    () => Stream.fromIterable([
      scriptedChunk(
        toolCalls: [
          for (final (index, (id, name, arguments)) in calls.indexed)
            LlamaCompletionChunkToolCall(
              index: index,
              id: id,
              type: 'function',
              function: LlamaCompletionChunkFunction(
                name: name,
                arguments: arguments,
              ),
            ),
        ],
        finishReason: 'tool_calls',
      ),
    ]);
