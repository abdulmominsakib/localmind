import 'package:llamadart/llamadart.dart';

// No noSuchMethod: a new required public member must fail this legacy contract.
final class LegacyChatSession implements ChatSession {
  LegacyChatSession(this.inner);

  final ChatSession inner;

  @override
  LlamaEngine get engine => inner.engine;
  @override
  List<LlamaChatMessage> get history => inner.history;
  @override
  bool get lastRequestFitContext => inner.lastRequestFitContext;
  @override
  int? get maxContextTokens => inner.maxContextTokens;
  @override
  set maxContextTokens(int? value) => inner.maxContextTokens = value;
  @override
  String? get systemPrompt => inner.systemPrompt;
  @override
  set systemPrompt(String? value) => inner.systemPrompt = value;
  @override
  void addMessage(LlamaChatMessage message) => inner.addMessage(message);
  @override
  void reset({bool keepSystemPrompt = true}) =>
      inner.reset(keepSystemPrompt: keepSystemPrompt);

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaContentPart> parts, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
    bool continuesPreviousTurn = false,
  }) => inner.create(
    parts,
    params: params,
    tools: tools,
    toolChoice: toolChoice,
    parallelToolCalls: parallelToolCalls,
    enableThinking: enableThinking,
    responseFormat: responseFormat,
    chatTemplateKwargs: chatTemplateKwargs,
    onMessageAdded: onMessageAdded,
    continuesPreviousTurn: continuesPreviousTurn,
  );

  @override
  Future<T> createStructuredJson<T>(
    List<LlamaContentPart> parts, {
    required LlamaStructuredOutput<T> output,
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? chatTemplateKwargs,
    void Function(LlamaChatMessage message)? onMessageAdded,
    bool continuesPreviousTurn = false,
  }) => inner.createStructuredJson(
    parts,
    output: output,
    params: params,
    tools: tools,
    toolChoice: toolChoice,
    parallelToolCalls: parallelToolCalls,
    enableThinking: enableThinking,
    chatTemplateKwargs: chatTemplateKwargs,
    onMessageAdded: onMessageAdded,
    continuesPreviousTurn: continuesPreviousTurn,
  );
}
