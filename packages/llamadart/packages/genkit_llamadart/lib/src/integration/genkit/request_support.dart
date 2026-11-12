import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';
import 'converters/genkit_to_llama.dart';

bool _usesTools(genkit.ModelRequest request) =>
    (request.tools?.isNotEmpty ?? false) ||
    request.messages.any(
      (message) => message.content.any(
        (part) => part.isToolRequest || part.isToolResponse,
      ),
    );

void checkDeclaredModelRequest(
  LlamaModelDefinition definition,
  genkit.ModelRequest request,
) {
  if (request.docs?.isNotEmpty ?? false) {
    throw genkit.GenkitException(
      'llamadart model actions do not support `docs` yet.',
      status: genkit.StatusCode.invalidArgument,
    );
  }
  if (!definition.supportsTools && _usesTools(request)) {
    throw genkit.GenkitException(
      'Tool use is disabled for `${definition.name}`.',
      status: genkit.StatusCode.failedPrecondition,
    );
  }
  if (!definition.supportsConstrainedOutput &&
      shouldUseStructuredGeneration(request.output)) {
    throw genkit.GenkitException(
      'Constrained output is disabled for `${definition.name}`.',
      status: genkit.StatusCode.failedPrecondition,
    );
  }
}

void checkRuntimeReady(
  LlamaModelDefinition definition,
  llama.LlamaEngineCapabilities? capabilities,
) {
  if (capabilities != null && !capabilities.isSupported) {
    throw genkit.GenkitException(
      'The active runtime for `${definition.name}` reports no ready model. '
      'Load a supported model before retrying.',
      status: genkit.StatusCode.failedPrecondition,
    );
  }
}

void requireRuntimeCapability(
  LlamaModelDefinition definition, {
  required bool? supported,
  required String feature,
}) {
  if (supported == true) return;
  throw genkit.GenkitException(
    supported == null
        ? 'The custom runtime for `${definition.name}` cannot confirm $feature. '
              'Implement LlamaRuntimeCapabilityProvider to report support '
              'after initialization.'
        : 'The active runtime for `${definition.name}` does not report support '
              'for $feature. Use a model and backend that support it.',
    status: supported == null
        ? genkit.StatusCode.failedPrecondition
        : genkit.StatusCode.unimplemented,
  );
}

void checkRuntimeModelRequest(
  LlamaModelDefinition definition,
  genkit.ModelRequest request,
  List<llama.LlamaChatMessage> messages,
  llama.LlamaEngineCapabilities? capabilities,
) {
  checkRuntimeReady(definition, capabilities);
  void require(bool? supported, String feature) => requireRuntimeCapability(
    definition,
    supported: supported,
    feature: feature,
  );

  if (capabilities?.supportsToolCalling != true && _usesTools(request)) {
    require(capabilities?.supportsToolCalling, 'tool calling');
  }
  if (shouldUseStructuredGeneration(request.output)) {
    require(
      capabilities == null
          ? null
          : capabilities.supportsStructuredOutput &&
                capabilities.supportsGrammar,
      'grammar-constrained structured output',
    );
  }
  if (capabilities?.supportsMultiTurnChat != true) {
    if (messages.any((message) => message.role == llama.LlamaChatRole.system)) {
      require(capabilities?.supportsMultiTurnChat, 'system-message delivery');
    }
    if (messages
        .where((message) => message.role != llama.LlamaChatRole.system)
        .skip(1)
        .isNotEmpty) {
      require(capabilities?.supportsMultiTurnChat, 'multi-turn history');
    }
  }

  // A custom native runtime older than LiteRT-LM v0.18.0 can under-report bundle encoders.
  // Preserve the core runtime's best-effort media validation without
  // advertising support.
  final bestEffortMedia =
      const bool.fromEnvironment('dart.library.io') &&
      capabilities?.runtime == llama.LlamaRuntime.liteRtLm;
  if (bestEffortMedia ||
      (capabilities?.supportsVision == true &&
          capabilities?.supportsAudio == true)) {
    return;
  }
  for (final part in messages.expand((message) => message.parts)) {
    if (part is llama.LlamaImageContent) {
      require(capabilities?.supportsVision, 'image input');
    } else if (part is llama.LlamaAudioContent) {
      require(capabilities?.supportsAudio, 'audio input');
    }
  }
}

void checkRuntimeGenerationConfig(
  LlamaModelDefinition definition,
  genkit.ModelRequest request,
  List<llama.LlamaChatMessage> messages,
  llama.GenerationParams params,
  llama.LlamaEngineCapabilities? capabilities,
) {
  void require(bool? supported, String feature) => requireRuntimeCapability(
    definition,
    supported: supported,
    feature: feature,
  );
  if (params.presencePenalty != 0) {
    require(capabilities?.supportsPresencePenalty, 'presencePenalty');
  }
  if (params.thinkingBudget != null) {
    require(capabilities?.supportsThinkingBudget, 'thinkingBudget');
  }
  if (params.streamBatchTokenThreshold !=
          llama.GenerationParams.defaultStreamBatchTokenThreshold ||
      params.streamBatchByteThreshold !=
          llama.GenerationParams.defaultStreamBatchByteThreshold) {
    require(capabilities?.supportsStreamBatching, 'native stream batching');
  }
  if (!params.reusePromptPrefix) {
    require(
      capabilities == null
          ? null
          : const bool.fromEnvironment('dart.library.io') &&
                capabilities.runtime == llama.LlamaRuntime.llamaCpp,
      'native prompt-prefix reuse control',
    );
  }
  final speculative = params.resolvedSpeculativeDecodingConfig;
  if (speculative != null) {
    for (final strategy in speculative.effectiveStrategies) {
      require(
        capabilities?.speculativeDecodingStrategies.contains(strategy),
        'speculative strategy ${strategy.name}',
      );
    }
  }
  final hasMedia = messages
      .expand((m) => m.parts)
      .any((p) => p is llama.LlamaImageContent || p is llama.LlamaAudioContent);
  if ((hasMedia && (params.thinkingBudget != null || speculative != null)) ||
      (speculative != null &&
          (params.thinkingBudget != null ||
              shouldUseStructuredGeneration(request.output) ||
              ((request.tools?.isNotEmpty ?? false) &&
                  request.toolChoice != genkit.ToolChoice.none)))) {
    throw genkit.GenkitException(
      'Thinking budgets and speculative decoding require text-only input. '
      'Speculative decoding cannot be combined with thinking budgets, constrained JSON or active tools. '
      'Disable speculation or remove the incompatible request options.',
      status: genkit.StatusCode.unimplemented,
    );
  }
}
