import 'package:genkit/genkit.dart' show ModelInfo;
import 'package:llamadart/llamadart.dart' show ModelParams;

/// Static configuration for one `llamadart` model exposed through Genkit.
///
/// Use one definition per local model you want to register. The same
/// definition controls the model name, native loading parameters, optional
/// multimodal projector path, and which Genkit capabilities are permitted.
///
/// Genkit retains generated reasoning in conversation history, but incoming
/// `ReasoningPart` values are omitted from model-facing messages in every role.
/// Visible text and tool history are preserved. There is no reasoning replay
/// option: it requires separate model/template qualification. This policy does
/// not disable newly generated reasoning or the request's thinking controls.
///
/// ```dart
/// const chatModel = LlamaModelDefinition(
///   name: 'local-chat',
///   modelPath: '/models/chat.gguf',
///   modelParams: ModelParams(contextSize: 8192),
///   supportsEmbeddings: false,
///   supportsTools: true,
///   supportsConstrainedOutput: true,
/// );
/// ```
class LlamaModelDefinition {
  /// Creates a model definition for a local model file.
  const LlamaModelDefinition({
    required this.name,
    required this.modelPath,
    this.modelParams = const ModelParams(),
    this.mmprojPath,
    this.supportsEmbeddings = true,
    this.supportsTools = true,
    this.supportsConstrainedOutput = true,
    this.modelInfo,
  }) : assert(name != ''),
       assert(modelPath != '');

  /// Unique model name used in Genkit refs like `llamadart/<name>`.
  final String name;

  /// Filesystem path to a model file supported by `llamadart`.
  ///
  /// This can be a GGUF file or a `.litertlm` LiteRT-LM bundle on supported
  /// `llamadart` platforms.
  final String modelPath;

  /// Native engine parameters used while loading the model.
  final ModelParams modelParams;

  /// Optional path to a multimodal projector file.
  final String? mmprojPath;

  /// Whether this definition should register a Genkit embedder action.
  ///
  /// The loaded runtime must also report embedding support to accept requests.
  /// Image/audio documents additionally require embedding-specific modality
  /// probes; chat vision/audio support alone is insufficient. Native LiteRT-LM
  /// needs an explicit CPU `LiteRtLmModelParams(embeddingEngine: true)` configuration.
  final bool supportsEmbeddings;

  /// Whether this definition permits Genkit tool requests and tool history.
  ///
  /// The loaded runtime must also report tool-calling support.
  ///
  /// Enabled tools must use object-shaped input schemas and arguments because
  /// `llamadart` represents tool arguments as `Map<String, dynamic>`. Local
  /// `$ref` wrappers emitted for named Schemantic object schemas are resolved
  /// before conversion. Simple primitive types, string enums, nested objects,
  /// required fields and typed arrays retain their existing runtime support.
  /// Nullable/type alternatives, scalar enums/const, `anyOf`, length bounds
  /// and restrictive `additionalProperties` policies use owned JSON Schemas
  /// and require grammar support plus a supported template. These responses
  /// are buffered until final argument validation. Numeric bounds, patterns,
  /// formats, `oneOf`/`allOf` and non-object roots fail with `INVALID_ARGUMENT`.
  /// See the tool input schema guide for backend restrictions and size limits.
  ///
  /// Tool results may contain text parts, joined with newlines for the model;
  /// structured output remains in Genkit history. Missing or empty parts use
  /// the output representation. Non-text result parts are unsupported.
  final bool supportsTools;

  /// Whether this definition permits constrained JSON output requests.
  ///
  /// The loaded runtime must also report structured output and grammar support.
  ///
  /// With active tools, native llama.cpp supports one call per turn and requires
  /// thinking/parallel calls disabled. Constrained content is buffered until
  /// complete parsing and validation. Browser/LiteRT combinations are unsupported.
  ///
  /// Disable this for `.litertlm` LiteRT-LM bundles until `llamadart` exposes
  /// grammar constraints for that backend.
  final bool supportsConstrainedOutput;

  /// Optional Genkit model metadata override.
  ///
  /// Custom keys in `modelInfo.supports` are preserved. Standard support keys
  /// are derived from the loaded runtime and the definition's permission flags;
  /// supplied values cannot override unknown or unsupported capabilities.
  final ModelInfo? modelInfo;
}
