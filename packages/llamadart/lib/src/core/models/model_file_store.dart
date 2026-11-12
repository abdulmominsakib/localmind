import 'download/model_download_manager.dart';
import 'model_resolver.dart';

/// Where an engine finds and keeps model files: the resolver that maps a
/// `ModelSource` to a load target, and the download manager that fetches
/// and caches remote files.
///
/// Pass one as `store:` to replace the defaults, for example to keep weights
/// in a directory the app chooses:
///
/// ```dart
/// final store = ModelFileStore(
///   downloadManager: DefaultModelDownloadManager.appPrivate(
///     cacheDirectory: modelsDirectory,
///   ),
/// );
/// ```
class ModelFileStore {
  /// Resolves sources to local or remote load targets.
  final ModelResolver resolver;

  /// Downloads and caches remote files, and checks local ones.
  final ModelDownloadManager downloadManager;

  /// Creates a store; each part left out uses its default:
  /// [DefaultModelResolver] and [DefaultModelDownloadManager].
  ModelFileStore({
    ModelResolver? resolver,
    ModelDownloadManager? downloadManager,
  }) : resolver = resolver ?? const DefaultModelResolver(),
       downloadManager = downloadManager ?? DefaultModelDownloadManager();
}
