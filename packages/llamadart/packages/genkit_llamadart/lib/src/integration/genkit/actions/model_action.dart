import 'dart:async';
import 'dart:convert';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../../api/generation_config.dart';
import '../../../api/model_definition.dart';
import '../../../api/media_resolver.dart';
import '../../../core/runtime/engine_registry.dart';
import '../../../core/runtime/llama_runtime.dart';
import '../../../core/runtime/operation_usage.dart';
import '../../../core/streaming/completion_accumulator.dart';
import '../action_support.dart';
import '../content_usage.dart';
import '../converters/genkit_to_llama.dart';
import '../converters/constrained_tools.dart';
import '../converters/llama_to_genkit.dart';
import '../converters/remote_media.dart';
import '../request_support.dart';

typedef _ModelActionContext =
    genkit.ActionFnArg<genkit.ModelResponseChunk, genkit.ModelRequest, void>;

genkit.Model<LlamaDartGenerationConfig> buildModelAction({
  required LlamaModelDefinition definition,
  required EngineRegistry registry,
  LlamaDartMediaResolver? mediaResolver,
  void Function(llama.LlamaEngineCapabilities?)? checkCapabilities,
}) {
  final modelInfo = modelInfoFor(definition);
  final actionName = actionNameFor(definition.name);

  final action = genkit.Model<LlamaDartGenerationConfig>(
    name: actionName,
    metadata: actionMetadataFor(definition, modelInfo: modelInfo),
    fn: (request, context) async {
      final total = Stopwatch()..start();
      checkDeclaredModelRequest(definition, request);
      final LlamaDartGenerationConfig config;
      try {
        config = LlamaDartGenerationConfig.fromJson(request.config);
      } on FormatException catch (error) {
        throw genkit.GenkitException(
          error.message,
          status: genkit.StatusCode.invalidArgument,
        );
      }
      final convertedTools = toLlamaTools(request.tools);
      final resolution = resolveLlamaMessages(
        request.messages,
        resolver: mediaResolver,
        cancel: context.cancel,
      );
      final messages = resolution is Future<List<llama.LlamaChatMessage>>
          ? await resolution
          : resolution;
      final capture = OperationUsage();
      return runZoned(() async {
        final response = await registry.withRuntime(definition.name, (
          runtime,
        ) async {
          context.cancel?.throwIfCancelled();
          // Apply entry-point requirements to the same fresh probe used below.
          checkCapabilities?.call(registry.capabilitiesFor(definition.name));
          final unregister = context.cancel?.onCancel(runtime.cancelGeneration);
          try {
            final response = await _runModel(
              definition: definition,
              runtime: runtime,
              capabilities: registry.capabilitiesFor(definition.name),
              request: request,
              messages: messages,
              tools: convertedTools.tools,
              inputSchemas: convertedTools.inputSchemas,
              config: config,
              context: context,
            );
            context.cancel?.throwIfCancelled();
            return response;
          } finally {
            unregister?.call();
          }
        }, beforeInitialize: context.cancel?.throwIfCancelled);
        response.usage ??= toGenkitUsage(capture.usage);
        if (capture.finishReason != null) {
          response.finishReason = mapFinishReason(capture.finishReason);
        }
        final inputParts = messages.expand((message) => message.parts);
        recordContentUsage(
          response,
          inputCharacters: messages.fold(
            0,
            (sum, message) => sum + message.content.length,
          ),
          inputImages: inputParts.whereType<llama.LlamaImageContent>().length,
          inputAudioFiles: inputParts
              .whereType<llama.LlamaAudioContent>()
              .length,
        );
        response.raw = {
          ...?response.raw,
          'queueMs': capture.queueMs,
          'initializationMs': capture.initializationMs,
          'totalLatencyMs': total.elapsedMicroseconds / 1000,
          if (capture.usage != null) 'usage': capture.usage!.toJson(),
        };
        return response;
      }, zoneValues: {operationUsageKey: capture});
    },
  );
  trackCapabilityMetadata(action.metadata, definition, registry);
  return action;
}

Future<genkit.ModelResponse> _runModel({
  required LlamaModelDefinition definition,
  required LlamaRuntime runtime,
  required llama.LlamaEngineCapabilities? capabilities,
  required genkit.ModelRequest request,
  required List<llama.LlamaChatMessage> messages,
  required List<llama.ToolDefinition> tools,
  required Map<String, Map<String, dynamic>> inputSchemas,
  required LlamaDartGenerationConfig config,
  required _ModelActionContext context,
}) async {
  checkRuntimeModelRequest(definition, request, messages, capabilities);
  final params = toGenerationParams(config);
  checkRuntimeGenerationConfig(
    definition,
    request,
    messages,
    params,
    capabilities,
  );
  final toolChoice = toLlamaToolChoice(
    request.toolChoice,
    hasTools: tools.isNotEmpty,
  );
  final activeSchemaTools =
      inputSchemas.isNotEmpty && toolChoice != llama.ToolChoice.none;
  if (activeSchemaTools) {
    requireRuntimeCapability(
      definition,
      supported: capabilities?.supportsGrammar,
      feature: 'grammar-enforced JSON Schema tools (llamadart 0.13+)',
    );
  }
  final started = Stopwatch()..start();

  if (shouldUseStructuredGeneration(request.output)) {
    final activeTools = tools.isNotEmpty && toolChoice != llama.ToolChoice.none;
    if (activeTools &&
        (!const bool.fromEnvironment('dart.library.io') ||
            capabilities?.runtime != llama.LlamaRuntime.llamaCpp)) {
      throw genkit.GenkitException(
        'Constrained output with active tools requires native llama.cpp. '
        'WebGPU, LiteRT-LM and unverified custom runtimes are unsupported.',
        status: genkit.StatusCode.unimplemented,
      );
    }
    if (activeTools && config.parallelToolCalls == true) {
      throw genkit.GenkitException(
        'Constrained tool generation supports one tool call per turn. '
        'Disable parallelToolCalls.',
        status: genkit.StatusCode.unimplemented,
      );
    }
    if (activeTools && config.enableThinking == true) {
      throw genkit.GenkitException(
        'Constrained tool generation currently requires enableThinking: false.',
        status: genkit.StatusCode.unimplemented,
      );
    }

    return _runStructuredModel(
      definition: definition,
      runtime: runtime,
      messages: messages,
      config: config,
      params: params,
      output: request.output,
      tools: tools,
      toolChoice: toolChoice ?? llama.ToolChoice.auto,
      context: context,
      started: started,
    );
  }

  return _runStreamingModel(
    definition: definition,
    runtime: runtime,
    messages: messages,
    tools: tools,
    toolChoice: toolChoice,
    inputSchemas: activeSchemaTools ? inputSchemas : const {},
    config: config,
    params: params,
    context: context,
    started: started,
  );
}

Future<genkit.ModelResponse> _runStreamingModel({
  required LlamaModelDefinition definition,
  required LlamaRuntime runtime,
  required List<llama.LlamaChatMessage> messages,
  required List<llama.ToolDefinition> tools,
  required Map<String, Map<String, dynamic>> inputSchemas,
  required llama.ToolChoice? toolChoice,
  required LlamaDartGenerationConfig config,
  required llama.GenerationParams params,
  required _ModelActionContext context,
  required Stopwatch started,
}) async {
  final accumulator = CompletionAccumulator();

  await for (final chunk in runtime.create(
    messages,
    params: params,
    tools: tools.isEmpty ? null : tools,
    toolChoice: toolChoice,
    parallelToolCalls:
        config.parallelToolCalls ??
        LlamaDartGenerationConfig.defaultParallelToolCalls,
    enableThinking:
        config.enableThinking ??
        LlamaDartGenerationConfig.defaultEnableThinking,
    sourceLangCode: config.sourceLangCode,
    targetLangCode: config.targetLangCode,
    chatTemplateKwargs: config.chatTemplateKwargs,
  )) {
    accumulator.addChunk(chunk);
    if (context.streamingRequested && inputSchemas.isEmpty) {
      final responseChunk = toGenkitChunk(chunk);
      if (responseChunk != null) {
        context.sendChunk(responseChunk);
      }
    }
  }

  final response = toGenkitModelResponse(
    accumulator.toResult(),
    latencyMs: started.elapsedMilliseconds.toDouble(),
    raw: rawResponseMetadata(definition),
    allowToolCalls: tools.isNotEmpty && toolChoice != llama.ToolChoice.none,
  );
  for (final part in response.message!.content) {
    final call = part.toolRequest;
    if (call == null) continue;
    if (inputSchemas.isNotEmpty &&
        !tools.any((tool) => tool.name == call.name)) {
      throw invalidConstrainedOutput();
    }
    final schema = inputSchemas[call.name];
    if (schema != null) await validateConstrainedValue(call.input, schema);
  }
  context.cancel?.throwIfCancelled();
  if (context.streamingRequested && inputSchemas.isNotEmpty) {
    context.sendChunk(
      genkit.ModelResponseChunk(
        role: genkit.Role.model,
        content: response.message!.content,
        aggregated: false,
      ),
    );
  }
  return response;
}

Future<genkit.ModelResponse> _runStructuredModel({
  required LlamaModelDefinition definition,
  required LlamaRuntime runtime,
  required List<llama.LlamaChatMessage> messages,
  required LlamaDartGenerationConfig config,
  required llama.GenerationParams params,
  required genkit.OutputConfig? output,
  required List<llama.ToolDefinition> tools,
  required llama.ToolChoice toolChoice,
  required _ModelActionContext context,
  required Stopwatch started,
}) async {
  final activeTools = tools.isNotEmpty && toolChoice != llama.ToolChoice.none;
  final envelopeSchema = activeTools
      ? constrainedToolSchema(tools, toolChoice, output?.schema)
      : null;
  final responseFormat = envelopeSchema == null
      ? toResponseFormat(output)
      : <String, dynamic>{
          'type': 'json_schema',
          'json_schema': {'schema': envelopeSchema},
        };
  final templateMessages = activeTools
      ? [
          ...messages,
          llama.LlamaChatMessage(
            role: 'system',
            content:
                'For this turn, return one JSON envelope: '
                '{"tool_call":{"name":"tool name","arguments":{...}}} for a tool, '
                'or {"response":<the final value matching the requested output schema>} '
                'for a final answer. Do not wrap the final value in a string unless '
                'the requested schema is a string. Call only a declared tool.',
          ),
        ]
      : messages;
  final template = await runtime.chatTemplate(
    templateMessages,
    addAssistant: true,
    tools: activeTools ? tools : null,
    toolChoice: toolChoice,
    parallelToolCalls: false,
    enableThinking:
        config.enableThinking ??
        LlamaDartGenerationConfig.defaultEnableThinking,
    responseFormat: responseFormat,
    sourceLangCode: config.sourceLangCode,
    targetLangCode: config.targetLangCode,
    includeTokenCount: false,
    chatTemplateKwargs: config.chatTemplateKwargs,
  );

  context.cancel?.throwIfCancelled();
  if (activeTools &&
      (template.grammar == null ||
          template.grammar!.trim().isEmpty ||
          template.format != llama.ChatFormat.generic.index ||
          template.grammarLazy ||
          template.parser != null)) {
    throw genkit.GenkitException(
      'Constrained tools require an eager grammar and the generic JSON envelope '
      'parser from native llama.cpp. The runtime returned an unsupported template.',
      status: genkit.StatusCode.unimplemented,
    );
  }
  final stops = <String>{
    ...template.additionalStops,
    ...params.stopSequences,
  }.toList(growable: false);
  final inputParts = <llama.LlamaContentPart>[];
  for (final message in messages) {
    inputParts.addAll(message.parts);
  }

  final budget = params.thinkingBudget;
  final tags = budget == null
      ? null
      : llama.ChatTemplateEngine.thinkingTagsFor(template.format);
  final resolvedBudget = budget == null
      ? null
      : llama.ThinkingBudget(
          maxTokens: budget.maxTokens,
          startTag: budget.startTag ?? tags!.startTag,
          endTag: budget.endTag ?? tags!.endTag,
          forcedMessage: budget.forcedMessage,
        );
  final rawOutput = StringBuffer();
  await for (final token in runtime.generate(
    template.prompt,
    params: params.copyWith(
      stopSequences: stops,
      grammar: template.grammar,
      thinkingBudget: resolvedBudget,
      grammarLazy: template.grammarLazy,
      grammarTriggers: template.grammarTriggers
          .map((trigger) {
            return llama.GenerationGrammarTrigger.typed(
              type: llama.GrammarTriggerType.fromWireValue(trigger.type),
              value: trigger.value,
              token: trigger.token,
            );
          })
          .toList(growable: false),
      preservedTokens: <String>{
        ...template.preservedTokens,
        ...params.preservedTokens,
      }.toList(growable: false),
    ),
    parts: inputParts,
  )) {
    rawOutput.write(token);
  }

  context.cancel?.throwIfCancelled();
  final generatedText = rawOutput.toString();
  final parsed = llama.ChatTemplateEngine.parseRendered(
    template,
    generatedText,
    parseToolCalls: activeTools,
    tools: activeTools ? tools : null,
  );

  final usage = Zone.current[operationUsageKey] as OperationUsage?;
  if (activeTools && usage?.finishReason == 'length') {
    throw invalidConstrainedOutput();
  }
  var visibleText = parsed.content;
  if (envelopeSchema != null) {
    final raw = llama.ChatTemplateEngine.parseRendered(
      template,
      generatedText,
      parseToolCalls: false,
    );
    final envelope = decodeConstrainedValue(raw.content);
    await validateConstrainedValue(envelope, envelopeSchema);
    final map = envelope as Map;
    if (map.containsKey('response')) {
      visibleText = jsonEncode(map['response']);
    } else if (parsed.toolCalls.length != 1) {
      throw invalidConstrainedOutput();
    }
  } else {
    final value = decodeConstrainedValue(visibleText);
    if (output?.schema != null) {
      await validateConstrainedValue(value, output!.schema!);
    }
  }
  final response = toGenkitModelResponse(
    CompletionResult(
      text: visibleText,
      reasoning: parsed.reasoningContent ?? '',
      toolCalls: parsed.toolCalls,
      finishReason: usage?.finishReason,
    ),
    latencyMs: started.elapsedMilliseconds.toDouble(),
    raw: rawResponseMetadata(definition, structured: true),
    allowToolCalls: activeTools && parsed.toolCalls.isNotEmpty,
  );
  context.cancel?.throwIfCancelled();
  if (context.streamingRequested) {
    context.sendChunk(
      genkit.ModelResponseChunk(
        role: genkit.Role.model,
        content: response.message!.content,
        aggregated: false,
      ),
    );
  }
  return response;
}
