import '../model_load_options.dart';
import '../model_source.dart';

/// Configuration for a LoRA (Low-Rank Adaptation) adapter.
class LoraAdapterConfig {
  final String? _path;

  /// Where the adapter file comes from: a local path, an HTTP(S) URL or a
  /// Hugging Face file.
  ///
  /// `LlamaEngine` loads it as `LlamaEngine.setLoraSource` does. Null for a
  /// configuration made with the deprecated path constructor.
  final ModelSource? source;

  /// Download options for [source] in `ModelParams.loras`: cache policy and
  /// directory, authentication, checksum, resume, retries and cancel token.
  ///
  /// When null, a remote [source] takes only the non-secret options of the
  /// model load: its cache policy and directory, resume, retries and cancel
  /// token, and a local one only its cancel token. The model load's bearer
  /// token, headers and checksum never apply to an adapter, since the
  /// adapter's host may differ from the model's. When set, they apply as
  /// given, and the model load's cancel token also cancels the download.
  final ModelLoadOptions? download;

  /// The strength of the adapter (typically 0.0 to 1.0).
  final double scale;

  /// Creates a LoRA adapter configuration from a local file [path], or a URL
  /// on WebGPU, that backends load as written.
  @Deprecated(
    'Use LoraAdapterConfig.source(ModelSource.path(path)), or another '
    'ModelSource to download the adapter. This constructor will be removed '
    'in a future release.',
  )
  const LoraAdapterConfig({required String path, this.scale = 1.0})
    : _path = path,
      source = null,
      download = null;

  const LoraAdapterConfig._resolved(String path, this.scale)
    : _path = path,
      source = null,
      download = null;

  /// Creates a LoRA adapter configuration for the adapter at [source].
  const LoraAdapterConfig.source(
    ModelSource this.source, {
    this.scale = 1.0,
    this.download,
  }) : _path = null;

  /// The adapter file that backends load: the path given to the deprecated
  /// constructor, the path of a local [source], or the URL of a remote one.
  ///
  /// A remote [source] becomes a file only when `LlamaEngine` downloads it, so
  /// pass a configuration with a remote [source] through `LlamaEngine`, not
  /// straight to a native backend.
  String get path => _path ?? source!.path ?? source!.url.toString();
}

/// A configuration for the adapter file at [path], already resolved from a
/// [LoraAdapterConfig.source], that backends load as written and
/// `LlamaEngine` does not resolve again.
LoraAdapterConfig resolvedLoraAdapterConfig(String path, double scale) =>
    LoraAdapterConfig._resolved(path, scale);
