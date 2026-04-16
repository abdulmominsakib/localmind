import '../../../../core/models/enums.dart';

class OnDeviceModel {
  final String id;
  final String name;
  final String huggingFaceUrl;
  final int fileSizeBytes;
  final String license;
  final String description;
  final bool isRecommended;
  final int minRamMb;
  final String parameterLabel;

  const OnDeviceModel({
    required this.id,
    required this.name,
    required this.huggingFaceUrl,
    required this.fileSizeBytes,
    required this.license,
    required this.description,
    this.isRecommended = false,
    required this.minRamMb,
    required this.parameterLabel,
  });

  String get fileSizeFormatted {
    final gb = fileSizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get fileName => '$id.litertlm';

  static const List<OnDeviceModel> curatedModels = [
    OnDeviceModel(
      id: 'qwen3-0.6b',
      name: 'Qwen 3 0.6B',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      fileSizeBytes: 614236160,
      license: 'Apache-2.0',
      description:
          'Smallest general-purpose chat model. Fast responses, low memory usage.',
      isRecommended: true,
      minRamMb: 2048,
      parameterLabel: '0.6B',
    ),
    OnDeviceModel(
      id: 'qwen2.5-1.5b-instruct',
      name: 'Qwen 2.5 1.5B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      fileSizeBytes: 1597931520,
      license: 'Apache-2.0',
      description: 'Balanced quality and size. Good for general conversation.',
      minRamMb: 3072,
      parameterLabel: '1.5B',
    ),
    OnDeviceModel(
      id: 'deepseek-r1-distill-qwen-1.5b',
      name: 'DeepSeek R1 Distill Qwen 1.5B',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      fileSizeBytes: 1833451520,
      license: 'MIT',
      description:
          'Reasoning and chain-of-thought model. Best for logical tasks.',
      minRamMb: 3584,
      parameterLabel: '1.5B',
    ),
    OnDeviceModel(
      id: 'gemma4-e2b-instruct',
      name: 'Gemma 4 E2B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      fileSizeBytes: 2583085056,
      license: 'Apache-2.0',
      description: 'Google flagship model. Highest quality, requires more RAM.',
      minRamMb: 5120,
      parameterLabel: '2B',
    ),
  ];
}

class DownloadedModel {
  final String modelId;
  final String filePath;
  final DateTime downloadedAt;

  const DownloadedModel({
    required this.modelId,
    required this.filePath,
    required this.downloadedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'modelId': modelId,
      'filePath': filePath,
      'downloadedAt': downloadedAt.toIso8601String(),
    };
  }

  factory DownloadedModel.fromMap(Map<String, dynamic> map) {
    return DownloadedModel(
      modelId: map['modelId'] as String,
      filePath: map['filePath'] as String,
      downloadedAt: DateTime.parse(map['downloadedAt'] as String),
    );
  }
}

class OnDeviceModelStateInfo {
  final String modelId;
  final OnDeviceModelState state;
  final double downloadProgress;
  final String? error;
  final LiteLmBackendType backend;
  final EngineStatus engineStatus;

  const OnDeviceModelStateInfo({
    required this.modelId,
    this.state = OnDeviceModelState.notDownloaded,
    this.downloadProgress = 0.0,
    this.error,
    this.backend = LiteLmBackendType.cpu,
    this.engineStatus = EngineStatus.notLoaded,
  });

  OnDeviceModelStateInfo copyWith({
    String? modelId,
    OnDeviceModelState? state,
    double? downloadProgress,
    String? error,
    LiteLmBackendType? backend,
    EngineStatus? engineStatus,
  }) {
    return OnDeviceModelStateInfo(
      modelId: modelId ?? this.modelId,
      state: state ?? this.state,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      error: error ?? this.error,
      backend: backend ?? this.backend,
      engineStatus: engineStatus ?? this.engineStatus,
    );
  }
}
