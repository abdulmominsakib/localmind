import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/model_downloader.dart';
import '../data/kitten_tts_model.dart';
import '../data/kitten_tts_downloader.dart';
import '../data/piper_tts_model.dart';
import '../data/piper_tts_downloader.dart';

/// Provider for the KittenTTS downloader instance.
final kittenTtsDownloaderProvider = Provider<KittenTtsDownloader>((ref) {
  return KittenTtsDownloader();
});

/// Provider for the Piper TTS downloader instance.
final piperTtsDownloaderProvider = Provider<PiperTtsDownloader>((ref) {
  return PiperTtsDownloader();
});

final modelDownloaderProvider = Provider<ModelDownloader>((ref) {
  return ModelDownloader();
});

/// Static list of all available KittenTTS models.
final kittenTtsModelsProvider = Provider<List<KittenTtsModel>>((ref) {
  return KittenTtsModel.allModels;
});

/// Async provider for the set of downloaded KittenTTS variants.
final downloadedKittenTtsVariantsProvider =
    FutureProvider<Set<KittenTtsModelVariant>>((ref) async {
      final downloader = ref.read(kittenTtsDownloaderProvider);
      return downloader.getDownloadedVariants();
    });

/// Async provider for the set of downloaded Piper variants.
final downloadedPiperTtsVariantsProvider =
    FutureProvider<Set<PiperTtsModelVariant>>((ref) async {
      final downloader = ref.read(piperTtsDownloaderProvider);
      return downloader.getDownloadedVariants();
    });

// ── KittenTTS Download Progress ──

/// Notifier that tracks per-file download progress for KittenTTS models.
final ttsDownloadProgressProvider =
    NotifierProvider<
      TtsDownloadNotifier,
      Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>
    >(() => TtsDownloadNotifier());

class TtsDownloadNotifier
    extends
        Notifier<
          Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>
        > {
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
    final completer = Completer<void>();

    final currentVariantProgress = Map<String, KittenTtsFileProgress>.from(
      state[variant] ?? {},
    );

    state = {...state, variant: currentVariantProgress};

    final downloader = ref.read(kittenTtsDownloaderProvider);

    _subscriptions[variant]?.cancel();
    _subscriptions[variant] = downloader
        .downloadModel(model)
        .listen(
          (progress) {
            if (!ref.mounted) return;
            final variantMap = Map<String, KittenTtsFileProgress>.from(
              state[variant] ?? {},
            );
            variantMap[progress.fileName] = progress;
            state = {...state, variant: variantMap};
          },
          onDone: () {
            _subscriptions.remove(variant);
            if (ref.mounted) {
              ref.invalidate(downloadedKittenTtsVariantsProvider);
            }
            if (!completer.isCompleted) completer.complete();
          },
          onError: (e) {
            _ModelLog.error(
              'KittenTTS download error for ${variant.displayName}: $e',
            );
            _subscriptions.remove(variant);
            if (!completer.isCompleted) completer.complete();
          },
        );
    return completer.future;
  }

  /// Cancel an in-flight download.
  void cancelDownload(KittenTtsModelVariant variant) {
    if (!ref.mounted) return;
    ref.read(kittenTtsDownloaderProvider).cancelDownload(variant);
    _subscriptions[variant]?.cancel();
    _subscriptions.remove(variant);

    final newState =
        Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>.from(
          state,
        );
    newState.remove(variant);
    state = newState;
  }

  /// Delete a downloaded variant.
  Future<void> deleteVariant(KittenTtsModelVariant variant) async {
    if (!ref.mounted) return;
    cancelDownload(variant);
    await ref.read(kittenTtsDownloaderProvider).deleteVariant(variant);
    if (!ref.mounted) return;

    final newState =
        Map<KittenTtsModelVariant, Map<String, KittenTtsFileProgress>>.from(
          state,
        );
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

// ── Piper TTS Download Progress ──

/// Notifier that tracks per-file download progress for Piper TTS models.
final piperTtsDownloadProgressProvider =
    NotifierProvider<
      PiperTtsDownloadNotifier,
      Map<PiperTtsModelVariant, Map<String, PiperTtsFileProgress>>
    >(() => PiperTtsDownloadNotifier());

class PiperTtsDownloadNotifier
    extends
        Notifier<Map<PiperTtsModelVariant, Map<String, PiperTtsFileProgress>>> {
  final Map<PiperTtsModelVariant, StreamSubscription<PiperTtsFileProgress>>
  _subscriptions = {};
  final Map<PiperTtsModelVariant, Completer<void>> _completers = {};

  @override
  Map<PiperTtsModelVariant, Map<String, PiperTtsFileProgress>> build() {
    ref.onDispose(() {
      for (final sub in _subscriptions.values) {
        sub.cancel();
      }
      _subscriptions.clear();
      _completers.clear();
    });
    return {};
  }

  Future<void> startDownload(PiperTtsModelVariant variant) async {
    final completer = Completer<void>();
    _completers[variant] = completer;
    final currentVariantProgress = Map<String, PiperTtsFileProgress>.from(
      state[variant] ?? {},
    );

    state = {...state, variant: currentVariantProgress};

    final downloader = ref.read(piperTtsDownloaderProvider);

    _subscriptions[variant]?.cancel();
    _subscriptions[variant] = downloader
        .downloadModel(variant)
        .listen(
          (progress) {
            if (!ref.mounted) return;
            final variantMap = Map<String, PiperTtsFileProgress>.from(
              state[variant] ?? {},
            );
            variantMap[progress.fileName] = progress;
            state = {...state, variant: variantMap};
          },
          onDone: () {
            _subscriptions.remove(variant);
            _completers.remove(variant);
            if (ref.mounted) {
              ref.invalidate(downloadedPiperTtsVariantsProvider);
            }
            if (!completer.isCompleted) completer.complete();
          },
          onError: (e) {
            _ModelLog.error(
              'Piper TTS download error for ${variant.displayName}: $e',
            );
            _subscriptions.remove(variant);
            _completers.remove(variant);
            if (!completer.isCompleted) completer.complete();
          },
        );
    return completer.future;
  }

  void cancelDownload(PiperTtsModelVariant variant) {
    if (!ref.mounted) return;
    ref.read(piperTtsDownloaderProvider).cancelDownload(variant);
    _subscriptions[variant]?.cancel();
    _subscriptions.remove(variant);
    final completer = _completers.remove(variant);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    final newState =
        Map<PiperTtsModelVariant, Map<String, PiperTtsFileProgress>>.from(
          state,
        );
    newState.remove(variant);
    state = newState;
  }

  Future<void> deleteVariant(PiperTtsModelVariant variant) async {
    if (!ref.mounted) return;
    cancelDownload(variant);
    await ref.read(piperTtsDownloaderProvider).deleteVariant(variant);
    if (!ref.mounted) return;

    final newState =
        Map<PiperTtsModelVariant, Map<String, PiperTtsFileProgress>>.from(
          state,
        );
    newState.remove(variant);
    state = newState;

    ref.invalidate(downloadedPiperTtsVariantsProvider);
  }

  bool isDownloading(PiperTtsModelVariant variant) {
    final variantProgress = state[variant];
    if (variantProgress == null || variantProgress.isEmpty) return false;
    return !variantProgress.values.every((f) => f.isComplete);
  }

  double getOverallFraction(PiperTtsModelVariant variant) {
    final variantProgress = state[variant];
    if (variantProgress == null || variantProgress.isEmpty) return 0.0;
    final total = variantProgress.values
        .map((f) => f.fraction)
        .fold<double>(0.0, (a, b) => a + b);
    return total / variantProgress.length;
  }
}

class _ModelLog {
  static void error(String message) {
    debugPrint('[TtsModel] ERROR: $message');
  }
}
