import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/kitten_tts_model.dart';
import '../data/kitten_tts_downloader.dart';

/// Provider for the KittenTTS downloader instance.
final kittenTtsDownloaderProvider = Provider<KittenTtsDownloader>((ref) {
  return KittenTtsDownloader();
});

/// Static list of all available KittenTTS models.
final kittenTtsModelsProvider = Provider<List<KittenTtsModel>>((ref) {
  return KittenTtsModel.allModels;
});

/// Async provider for the set of downloaded variants.
final downloadedKittenTtsVariantsProvider =
    FutureProvider<Set<KittenTtsModelVariant>>((ref) async {
  final downloader = ref.read(kittenTtsDownloaderProvider);
  return downloader.getDownloadedVariants();
});

/// Notifier that tracks per-file download progress for KittenTTS models.
final ttsDownloadProgressProvider =
    NotifierProvider<TtsDownloadNotifier, Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>>(
  () => TtsDownloadNotifier(),
);

class TtsDownloadNotifier
    extends Notifier<Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>> {
  final Map<KittenTtsModelVariant, StreamSubscription<KittenTtsFileProgress>>
      _subscriptions = {};

  @override
  Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>> build() {
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
    });
    return {};
  }

  /// Start downloading a model variant.
  Future<void> startDownload(KittenTtsModel model) async {
    final variant = model.variant;

    final currentVariantProgress = Map<String, KittenTtsFileProgress>.from(
      state[variant] ?? {},
    );

    state = {
      ...state,
      variant: currentVariantProgress,
    };

    final downloader = ref.read(kittenTtsDownloaderProvider);

    _subscriptions[variant]?.cancel();
    _subscriptions[variant] = downloader
        .downloadModel(model)
        .listen(
          (progress) {
            final variantMap = Map<String, KittenTtsFileProgress>.from(
              state[variant] ?? {},
            );
            variantMap[progress.fileName] = progress;
            state = {...state, variant: variantMap};
          },
          onDone: () {
            _subscriptions.remove(variant);
            ref.invalidate(downloadedKittenTtsVariantsProvider);
          },
          onError: (e) {
            Log.error('KittenTTS download error for ${variant.displayName}: $e');
            _subscriptions.remove(variant);
          },
        );
  }

  /// Cancel an in-flight download.
  void cancelDownload(KittenTtsModelVariant variant) {
    ref.read(kittenTtsDownloaderProvider).cancelDownload(variant);
    _subscriptions[variant]?.cancel();
    _subscriptions.remove(variant);

    final newState = Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>
        .from(state);
    newState.remove(variant);
    state = newState;
  }

  /// Delete a downloaded variant.
  Future<void> deleteVariant(KittenTtsModelVariant variant) async {
    cancelDownload(variant);
    await ref.read(kittenTtsDownloaderProvider).deleteVariant(variant);

    final newState = Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>
        .from(state);
    newState.remove(variant);
    state = newState;

    ref.invalidate(downloadedKittenTtsVariantsProvider);
  }

  /// Check if a variant is currently being downloaded.
  bool isDownloading(KittenTtsModelVariant variant) {
    final variantProgress = state[variant];
    if (variantProgress == null || variantProgress.isEmpty) return false;
    return !variantProgress.values.every((f) => f.isComplete);
  }

  /// Get overall progress fraction for a variant (0.0–1.0).
  double getOverallFraction(KittenTtsModelVariant variant) {
    final variantProgress = state[variant];
    if (variantProgress == null || variantProgress.isEmpty) return 0.0;
    final total = variantProgress.values
        .map((f) => f.fraction)
        .fold<double>(0.0, (a, b) => a + b);
    return total / variantProgress.length;
  }
}

/// Simple log helper within this file.
class Log {
  static void error(String message) {
    // ignore: avoid_print
    print('[TtsDownloadNotifier] ERROR: $message');
  }
}
