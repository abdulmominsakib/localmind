import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';
import '../../core/metadata/model_capabilities.dart';
import '../../core/runtime/engine_registry.dart';
import 'generation_config_schema.dart';

const String llamaDartPluginName = 'llamadart';

String actionNameFor(String modelName) => '$llamaDartPluginName/$modelName';

Map<String, dynamic> actionMetadataFor(
  LlamaModelDefinition definition, {
  required genkit.ModelInfo modelInfo,
  bool generation = true,
}) {
  return <String, dynamic>{
    'label': definition.name,
    'description': definition.name,
    'model': {
      ...modelInfo.toJson(),
      if (generation && modelInfo.configSchema != null)
        'customOptions': modelInfo.configSchema,
    },
  };
}

genkit.ModelInfo modelInfoFor(
  LlamaModelDefinition definition, {
  llama.LlamaEngineCapabilities? capabilities,
  bool generation = true,
}) {
  final provided = definition.modelInfo;
  return genkit.ModelInfo(
    versions: provided?.versions,
    label: provided?.label ?? definition.name,
    configSchema:
        provided?.configSchema ??
        (generation ? generationConfigSchema() : null),
    supports: <String, dynamic>{
      ...?provided?.supports,
      ...supportMetadataFor(
        definition,
        capabilities: capabilities,
        generation: generation,
      ),
    },
    stage: provided?.stage,
  );
}

void trackCapabilityMetadata(
  Map<String, dynamic> metadata,
  LlamaModelDefinition definition,
  EngineRegistry registry, {
  bool generation = true,
}) {
  void refresh() {
    final model = metadata['model'] as Map<String, dynamic>;
    model['supports'] = <String, dynamic>{
      ...?model['supports'] as Map<String, dynamic>?,
      ...?definition.modelInfo?.supports,
      ...supportMetadataFor(
        definition,
        capabilities: registry.capabilitiesFor(definition.name),
        embeddingCapabilities: registry.embeddingCapabilitiesFor(
          definition.name,
        ),
        generation: generation,
      ),
    };
    metadata['llamadartCapabilities'] = capabilityMetadataFor(
      definition,
      registry,
    );
  }

  refresh();
  registry.onCapabilitiesChanged(definition.name, refresh);
}

Map<String, dynamic> capabilityMetadataFor(
  LlamaModelDefinition definition,
  EngineRegistry registry,
) {
  final snapshot = registry.capabilitiesFor(definition.name);
  final capabilities = snapshot?.isSupported == true ? snapshot : null;
  return {
    'state': registry.capabilityStateFor(definition.name),
    'ready': capabilities != null,
    'embedding': {
      'text':
          capabilities != null &&
          (registry.embeddingCapabilitiesFor(definition.name)?.text ??
              capabilities.supportsEmbeddings),
      'image':
          capabilities != null &&
          registry.embeddingCapabilitiesFor(definition.name)?.image == true,
      'audio':
          capabilities != null &&
          registry.embeddingCapabilitiesFor(definition.name)?.audio == true,
    },
    'generation': {
      'penalty': capabilities?.supportsPenalty == true,
      'minP': capabilities?.supportsMinP == true,
      'presencePenalty': capabilities?.supportsPresencePenalty == true,
      'thinkingBudget': capabilities?.supportsThinkingBudget == true,
      'streamBatching': capabilities?.supportsStreamBatching == true,
      'promptPrefixControl':
          const bool.fromEnvironment('dart.library.io') &&
          capabilities?.runtime == llama.LlamaRuntime.llamaCpp,
      'speculativeDecodingStrategies':
          capabilities?.speculativeDecodingStrategies
              .map((s) => s.name)
              .toList() ??
          <String>[],
    },
    'declared': {
      'tools': definition.supportsTools,
      'constrained': definition.supportsConstrainedOutput,
      'embeddings': definition.supportsEmbeddings,
    },
  };
}

Map<String, dynamic> rawResponseMetadata(
  LlamaModelDefinition definition, {
  bool structured = false,
}) {
  return <String, dynamic>{
    'provider': llamaDartPluginName,
    'model': definition.name,
    if (structured) 'structured': true,
  };
}
