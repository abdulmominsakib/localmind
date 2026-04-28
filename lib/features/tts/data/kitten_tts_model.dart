import 'package:flutter/material.dart';

/// Available KittenTTS model variants downloadable from HuggingFace.
///
/// Each variant has a different parameter count and quality trade-off.
enum KittenTtsModelVariant {
  /// 15M parameters, ~56 MB total, high quality.
  nano,

  /// 15M parameters, ~25 MB total, int8 quantized. Best for most devices.
  nanoInt8,

  /// 40M parameters, ~41 MB total, higher quality.
  micro,

  /// 80M parameters, ~80 MB total, best quality.
  mini;

  String get displayName {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 'Kitten TTS Nano';
      case KittenTtsModelVariant.nanoInt8:
        return 'Kitten TTS Nano (Int8)';
      case KittenTtsModelVariant.micro:
        return 'Kitten TTS Micro';
      case KittenTtsModelVariant.mini:
        return 'Kitten TTS Mini';
    }
  }

  /// Short label shown in badges (e.g. "15M", "80M").
  String get parameterLabel {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return '15M';
      case KittenTtsModelVariant.nanoInt8:
        return '15M';
      case KittenTtsModelVariant.micro:
        return '40M';
      case KittenTtsModelVariant.mini:
        return '80M';
    }
  }

  /// Approximate total size in bytes for all 3 files combined.
  int get totalSizeBytes {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 56 * 1024 * 1024;
      case KittenTtsModelVariant.nanoInt8:
        return 25 * 1024 * 1024;
      case KittenTtsModelVariant.micro:
        return 41 * 1024 * 1024;
      case KittenTtsModelVariant.mini:
        return 80 * 1024 * 1024;
    }
  }

  String get description {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 'Balanced quality and size. Good for most devices.';
      case KittenTtsModelVariant.nanoInt8:
        return 'Smallest model with excellent quality. Recommended for most devices.';
      case KittenTtsModelVariant.micro:
        return 'Higher quality with more parameters. Requires more RAM.';
      case KittenTtsModelVariant.mini:
        return 'Highest quality, largest size. Best for high-end devices.';
    }
  }

  /// Whether this variant is recommended as the default.
  bool get isRecommended => this == KittenTtsModelVariant.nanoInt8;

  /// HuggingFace repository ID for this variant.
  String get huggingFaceRepoId {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 'KittenML/kitten-tts-nano-0.8-fp32';
      case KittenTtsModelVariant.nanoInt8:
        return 'KittenML/kitten-tts-nano-0.8-int8';
      case KittenTtsModelVariant.micro:
        return 'KittenML/kitten-tts-micro-0.8';
      case KittenTtsModelVariant.mini:
        return 'KittenML/kitten-tts-mini-0.8';
    }
  }

  /// The ONNX model file name inside the HF repo.
  String get modelFileName {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 'kitten_tts_nano_v0_8.onnx';
      case KittenTtsModelVariant.nanoInt8:
        return 'kitten_tts_nano_v0_8.onnx';
      case KittenTtsModelVariant.micro:
        return 'kitten_tts_micro_v0_8.onnx';
      case KittenTtsModelVariant.mini:
        return 'kitten_tts_mini_v0_8.onnx';
    }
  }

  /// The 3 files required for this variant.
  List<KittenTtsModelFile> get files {
    return [
      KittenTtsModelFile(
        fileName: 'config.json',
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/config.json',
        sizeBytes: 2 * 1024,
      ),
      KittenTtsModelFile(
        fileName: modelFileName,
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/$modelFileName',
        sizeBytes: _modelFileSizeBytes,
      ),
      KittenTtsModelFile(
        fileName: 'voices.npz',
        downloadUrl:
            'https://huggingface.co/$huggingFaceRepoId/resolve/main/voices.npz',
        sizeBytes: 3 * 1024 * 1024,
      ),
    ];
  }

  int get _modelFileSizeBytes {
    switch (this) {
      case KittenTtsModelVariant.nano:
        return 52 * 1024 * 1024;
      case KittenTtsModelVariant.nanoInt8:
        return 21 * 1024 * 1024;
      case KittenTtsModelVariant.micro:
        return 37 * 1024 * 1024;
      case KittenTtsModelVariant.mini:
        return 76 * 1024 * 1024;
    }
  }

  /// Storage directory name for this variant.
  String get dirName => name;
}

/// Metadata for a single file within a KittenTTS model variant.
@immutable
class KittenTtsModelFile {
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;

  const KittenTtsModelFile({
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
  });
}

/// A fully-specified KittenTTS model with its variant and files.
@immutable
class KittenTtsModel {
  final KittenTtsModelVariant variant;
  final List<KittenTtsModelFile> files;
  final int totalSizeBytes;

  const KittenTtsModel({
    required this.variant,
    required this.files,
    required this.totalSizeBytes,
  });

  static final List<KittenTtsModel> allModels = [
    KittenTtsModel(
      variant: KittenTtsModelVariant.nano,
      files: KittenTtsModelVariant.nano.files,
      totalSizeBytes: KittenTtsModelVariant.nano.totalSizeBytes,
    ),
    KittenTtsModel(
      variant: KittenTtsModelVariant.nanoInt8,
      files: KittenTtsModelVariant.nanoInt8.files,
      totalSizeBytes: KittenTtsModelVariant.nanoInt8.totalSizeBytes,
    ),
    KittenTtsModel(
      variant: KittenTtsModelVariant.micro,
      files: KittenTtsModelVariant.micro.files,
      totalSizeBytes: KittenTtsModelVariant.micro.totalSizeBytes,
    ),
    KittenTtsModel(
      variant: KittenTtsModelVariant.mini,
      files: KittenTtsModelVariant.mini.files,
      totalSizeBytes: KittenTtsModelVariant.mini.totalSizeBytes,
    ),
  ];

  String get displayName => variant.displayName;

  String get parameterLabel => variant.parameterLabel;

  String get description => variant.description;

  bool get isRecommended => variant.isRecommended;
}

/// Progress for downloading a single file of a model variant.
@immutable
class KittenTtsFileProgress {
  final String fileName;
  final KittenTtsModelVariant variant;
  final int receivedBytes;
  final int totalBytes;
  final bool isComplete;

  const KittenTtsFileProgress({
    required this.fileName,
    required this.variant,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.isComplete = false,
  });

  double get fraction =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// Overall download progress for a variant (all 3 files).
@immutable
class KittenTtsVariantProgress {
  final KittenTtsModelVariant variant;
  final Map<String, KittenTtsFileProgress> fileProgress;

  const KittenTtsVariantProgress({
    required this.variant,
    this.fileProgress = const {},
  });

  double get overallFraction {
    if (fileProgress.isEmpty) return 0.0;
    final total = fileProgress.values
        .map((f) => f.fraction)
        .fold<double>(0.0, (a, b) => a + b);
    return total / fileProgress.length;
  }

  bool get isComplete =>
      fileProgress.isNotEmpty &&
      fileProgress.values.every((f) => f.isComplete);
}
