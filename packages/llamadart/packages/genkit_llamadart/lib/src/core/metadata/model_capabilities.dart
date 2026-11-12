import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';

Map<String, dynamic> supportMetadataFor(
  LlamaModelDefinition definition, {
  llama.LlamaEngineCapabilities? capabilities,
  llama.LlamaEmbeddingCapabilities? embeddingCapabilities,
  bool generation = true,
}) {
  final ready = capabilities?.isSupported == true;
  final tools =
      definition.supportsTools && ready && capabilities!.supportsToolCalling;
  return <String, dynamic>{
    'multiturn': ready && capabilities!.supportsMultiTurnChat,
    'media':
        ready &&
        (generation
            ? (capabilities!.supportsVision || capabilities.supportsAudio)
            : (embeddingCapabilities?.image == true ||
                  embeddingCapabilities?.audio == true)),
    'tools': tools,
    'toolChoice': tools,
    'systemRole': ready && capabilities!.supportsMultiTurnChat,
    'constrained':
        definition.supportsConstrainedOutput &&
        ready &&
        capabilities!.supportsStructuredOutput &&
        capabilities.supportsGrammar,
    'constrainedWithTools':
        const bool.fromEnvironment('dart.library.io') &&
        tools &&
        definition.supportsConstrainedOutput &&
        capabilities.runtime == llama.LlamaRuntime.llamaCpp &&
        capabilities.supportsStructuredOutput &&
        capabilities.supportsGrammar,
    'embeddings':
        definition.supportsEmbeddings &&
        ready &&
        (embeddingCapabilities == null
            ? capabilities!.supportsEmbeddings
            : embeddingCapabilities.text ||
                  embeddingCapabilities.image ||
                  embeddingCapabilities.audio),
  };
}
