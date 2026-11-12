import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../../api/embed_config.dart';
import '../../../api/model_definition.dart';
import '../../../api/media_resolver.dart';
import '../../../core/runtime/engine_registry.dart';
import '../../../core/runtime/llama_runtime.dart';
import '../action_support.dart';
import '../converters/genkit_to_llama.dart';
import '../converters/embedding_input.dart';
import '../converters/remote_media.dart';
import '../request_support.dart';

genkit.Embedder<LlamaDartEmbedConfig> buildEmbedderAction({
  required LlamaModelDefinition definition,
  required EngineRegistry registry,
  LlamaDartMediaResolver? mediaResolver,
}) {
  final actionName = actionNameFor(definition.name);

  final action = genkit.Embedder<LlamaDartEmbedConfig>(
    name: actionName,
    metadata: actionMetadataFor(
      definition,
      modelInfo: modelInfoFor(definition, generation: false),
      generation: false,
    ),
    fn: (request, context) async {
      context.cancel?.throwIfCancelled();
      if (!definition.supportsEmbeddings) {
        throw genkit.GenkitException(
          'Embeddings are disabled for `${definition.name}`.',
          status: genkit.StatusCode.failedPrecondition,
        );
      }

      final config = LlamaDartEmbedConfig.fromJson(request.options);
      final modalities = embeddingModalities(request.input);
      final documents = snapshotEmbeddingDocuments(request.input);
      final hasMedia = modalities.any(
        (m) => m != llama.LlamaEmbeddingModality.text,
      );

      final embeddings = await registry.withRuntime(definition.name, (
        runtime,
      ) async {
        context.cancel?.throwIfCancelled();
        final capabilities = registry.capabilitiesFor(definition.name);
        checkRuntimeReady(definition, capabilities);
        if (hasMedia || runtime is LlamaRuntimeEmbeddingProvider) {
          if (runtime is! LlamaRuntimeEmbeddingProvider) {
            throw genkit.GenkitException(
              'This runtime does not implement LlamaRuntimeEmbeddingProvider '
              'for image and audio embeddings.',
              status: genkit.StatusCode.unimplemented,
            );
          }
          final provider = runtime as LlamaRuntimeEmbeddingProvider;
          final supported = (await registry.probeEmbeddingCapabilities(
            definition.name,
            runtime,
          ))!;
          context.cancel?.throwIfCancelled();
          for (final modality in modalities) {
            requireRuntimeCapability(
              definition,
              supported: supported.supports(modality),
              feature: '${modality.name} embeddings',
            );
          }
          final messages = await resolveLlamaMessages(
            embeddingMessages(documents),
            resolver: mediaResolver,
            cancel: context.cancel,
          );
          context.cancel?.throwIfCancelled();
          final inputs = [
            for (final message in messages)
              llama.LlamaEmbeddingInput(message.parts),
          ];
          final unregister = context.cancel?.onCancel(runtime.cancelGeneration);
          try {
            return await provider.embedContentBatch(
              inputs,
              normalize:
                  config.normalize ?? LlamaDartEmbedConfig.defaultNormalize,
            );
          } finally {
            unregister?.call();
            context.cancel?.throwIfCancelled();
          }
        }
        requireRuntimeCapability(
          definition,
          supported: capabilities?.supportsEmbeddings,
          feature: 'embeddings',
        );
        try {
          return await runtime.embedBatch(
            documents.map(documentToPlainText).toList(growable: false),
            normalize:
                config.normalize ?? LlamaDartEmbedConfig.defaultNormalize,
          );
        } finally {
          context.cancel?.throwIfCancelled();
        }
      }, beforeInitialize: context.cancel?.throwIfCancelled);

      if (embeddings.length != documents.length) {
        throw genkit.GenkitException(
          'Embedding runtime returned an unexpected vector count.',
          status: genkit.StatusCode.internal,
        );
      }

      return genkit.EmbedResponse(
        embeddings: embeddings
            .asMap()
            .entries
            .map((entry) {
              return genkit.Embedding(
                embedding: entry.value,
                metadata: documents[entry.key].metadata,
              );
            })
            .toList(growable: false),
      );
    },
  );
  trackCapabilityMetadata(
    action.metadata,
    definition,
    registry,
    generation: false,
  );
  return action;
}
