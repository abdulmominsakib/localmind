import '../../../core/downloads/download_task.dart';
import '../../../core/models/enums.dart';

/// Layout and source of a sherpa-onnx TTS bundle archive. Descriptors are
/// pure metadata: the download service resolves paths, runs the transfer
/// through the shared engine and validates the extracted files against
/// [requiredFileNames] / [requiredDirNames].
abstract class TtsBundleDescriptor {
  EngineId get engine;

  /// Top-level directory the archive extracts into,
  /// `tts_models/<engine>/<bundleDirName>/`.
  String get bundleDirName;

  /// Canonical release URL (never a signed CDN URL) the engine re-resolves
  /// on every resume.
  String get tarballUrl;

  int get totalSizeBytes;

  String get modelFileName;
  String get tokensFileName;

  /// Extra files (lexicon(s), voices.bin) required after extraction.
  List<String> get requiredFileNames;

  /// espeak-ng-data / jieba dict directories required after extraction.
  List<String> get requiredDirNames;

  /// Rule FST file names shipped for date/number normalization. Optional at
  /// runtime: only the files actually present join the `ruleFsts` argument,
  /// so bundle revisions that drop or rename them cannot break synthesis.
  List<String> get ruleFstFileNames;
}

/// UI-facing snapshot of an in-flight `ttsBundle` engine task, bridged from
/// the engine's change stream by [ChineseTtsBundleProgressNotifier].
class TtsBundleTaskProgress {
  final DownloadTaskState state;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  const TtsBundleTaskProgress({
    required this.state,
    required this.receivedBytes,
    required this.totalBytes,
    this.error,
  });

  double get fraction {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isTerminal =>
      state == DownloadTaskState.completed ||
      state == DownloadTaskState.failed ||
      state == DownloadTaskState.canceled;
}
