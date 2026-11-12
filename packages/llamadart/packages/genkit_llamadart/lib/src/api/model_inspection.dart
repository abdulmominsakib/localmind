import 'package:llamadart/llamadart.dart' as llama;

/// Read-only information about a model loaded by this plugin.
///
/// Measurements describe the active runtime, not requested load settings.
/// Missing diagnostics remain null. No model paths, raw metadata or performance
/// counters are included. Capabilities describe runtime support; they do not
/// guarantee model quality or every combination of generation options. Definition
/// permissions can restrict these capabilities further.
class LlamaModelInspection {
  /// Creates an inspection snapshot, copying capability strategy collections.
  LlamaModelInspection({
    llama.LlamaEngineCapabilities? capabilities,
    llama.LlamaEmbeddingCapabilities? embeddingCapabilities,
    this.contextSize,
  }) : capabilities = capabilities == null
           ? null
           : _copyCapabilities(capabilities),
       embeddingCapabilities = embeddingCapabilities == null
           ? null
           : llama.LlamaEmbeddingCapabilities(
               text: embeddingCapabilities.text,
               image: embeddingCapabilities.image,
               audio: embeddingCapabilities.audio,
             );

  /// Embedding-specific modalities, independent of chat vision/audio support.
  ///
  /// Null for custom runtimes without `LlamaRuntimeEmbeddingProvider`. The
  /// snapshot omits backend diagnostic reasons and input paths. Available
  /// modalities do not guarantee every codec, model or input size is supported.
  final llama.LlamaEmbeddingCapabilities? embeddingCapabilities;

  /// Loaded runtime capabilities, or null for an unverified custom runtime.
  ///
  /// Includes recognized backend identity and supported sampling/speculation
  /// controls. Unknown backend labels are omitted to avoid exposing arbitrary
  /// runtime diagnostics. Unsupported reasons use a neutral message.
  final llama.LlamaEngineCapabilities? capabilities;

  /// Actual loaded context capacity in tokens, or null when unavailable.
  ///
  /// This is not a chat budget: templates, tools and media consume capacity too.
  final int? contextSize;
}

llama.LlamaEngineCapabilities _copyCapabilities(
  llama.LlamaEngineCapabilities value,
) {
  return llama.LlamaEngineCapabilities(
    isSupported: value.isSupported,
    unsupportedReason: value.isSupported
        ? null
        : 'The loaded runtime is unavailable.',
    backendName: _safeBackendName(value.backendName),
    runtime: value.runtime,
    supportsVision: value.supportsVision,
    supportsAudio: value.supportsAudio,
    supportsEmbeddings: value.supportsEmbeddings,
    supportsNextTokenScoring: value.supportsNextTokenScoring,
    supportsMultiTurnChat: value.supportsMultiTurnChat,
    supportsToolCalling: value.supportsToolCalling,
    supportsStructuredOutput: value.supportsStructuredOutput,
    supportsGrammar: value.supportsGrammar,
    supportsLazyGrammar: value.supportsLazyGrammar,
    supportsPenalty: value.supportsPenalty,
    supportsPresencePenalty: value.supportsPresencePenalty,
    supportsMinP: value.supportsMinP,
    supportsThinkingBudget: value.supportsThinkingBudget,
    supportsStreamBatching: value.supportsStreamBatching,
    speculativeDecodingStrategies: Set.unmodifiable(
      value.speculativeDecodingStrategies,
    ),
  );
}

String? _safeBackendName(String? name) {
  if (name == null) return null;
  const labels = <String>[
    'CPU',
    'Metal',
    'Vulkan',
    'CUDA',
    'OpenCL',
    'HIP',
    'BLAS',
    'WebGPU',
    'WebGPU (Web)',
    'WASM',
    'WASM (CPU)',
    'LiteRT-LM CPU',
    'LiteRT-LM GPU',
    'LiteRT-LM TPU',
    'LiteRT-LM NPU',
    'LiteRT-LM Web CPU',
    'LiteRT-LM Web GPU',
    'LiteRT-LM Web auto',
  ];
  for (final label in labels) {
    if (name.toLowerCase() == label.toLowerCase()) return label;
  }
  return null;
}
