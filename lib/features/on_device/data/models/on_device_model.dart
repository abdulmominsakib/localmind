import 'package:flutter_gemma/flutter_gemma.dart';

import '../../../../core/models/enums.dart';

enum OnDeviceModelRuntime { gemma, llamaCpp, mlx }

enum OnDeviceModelFormat { litertlm, task, binary, gguf, mlx }

enum OnDeviceImportedSource { localFile, huggingFace }

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
  final String bestFor;
  final bool supportsFunctionCalling;
  final bool supportsThinking;
  final bool supportsVision;
  final String languagesLabel;
  final String? backendNote;
  final bool isCpuOnly;
  final OnDeviceModelRuntime runtime;
  final OnDeviceModelFormat format;
  final String? localPath;
  final DateTime? importedAt;
  final bool isImported;
  final OnDeviceImportedSource? importedSource;
  final bool requiresHuggingFaceToken;

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
    required this.bestFor,
    this.supportsFunctionCalling = false,
    this.supportsThinking = false,
    this.supportsVision = false,
    required this.languagesLabel,
    this.backendNote,
    this.isCpuOnly = false,
    this.runtime = OnDeviceModelRuntime.gemma,
    this.format = OnDeviceModelFormat.litertlm,
    this.localPath,
    this.importedAt,
    this.isImported = false,
    this.importedSource,
    this.requiresHuggingFaceToken = false,
  });

  String get fileSizeFormatted {
    final gb = fileSizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(2)} GB';
    }
    final mb = fileSizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String get fileName {
    if (localPath != null && localPath!.isNotEmpty) {
      return localPath!.split('/').last;
    }
    return huggingFaceUrl.split('/').last;
  }

  bool get isLlamaCpp => runtime == OnDeviceModelRuntime.llamaCpp;
  bool get isMlx => runtime == OnDeviceModelRuntime.mlx;

  bool get isImportedFromLocalFile =>
      importedSource == OnDeviceImportedSource.localFile;

  bool get isImportedFromHuggingFace =>
      importedSource == OnDeviceImportedSource.huggingFace;

  String? get importedSourceLabel {
    switch (importedSource) {
      case OnDeviceImportedSource.localFile:
        return 'Local file';
      case OnDeviceImportedSource.huggingFace:
        return 'Hugging Face';
      case null:
        return null;
    }
  }

  ModelType get flutterGemmaModelType {
    switch (id) {
      case 'qwen3-0.6b':
        return ModelType.qwen3;
      case 'qwen2.5-1.5b-instruct':
        return ModelType.qwen;
      case 'deepseek-r1-distill-qwen-1.5b':
        return ModelType.deepSeek;
      case 'gemma4-e2b-instruct':
      case 'gemma4-e4b-instruct':
        return ModelType.gemma4;
      case 'phi-4-mini-instruct':
        return ModelType.phi;
      case 'functiongemma-270m':
        return ModelType.functionGemma;
      default:
        return ModelType.general;
    }
  }

  static const List<OnDeviceModel> curatedModels = [
    OnDeviceModel(
      id: 'qwen3-0.6b',
      name: 'Qwen 3 0.6B',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
      fileSizeBytes: 614236160,
      license: 'Apache-2.0',
      description:
          'Compact multilingual chat with function calling and thinking mode.',
      isRecommended: true,
      minRamMb: 2048,
      parameterLabel: '0.6B',
      bestFor: 'Compact multilingual chat with function calling',
      supportsFunctionCalling: true,
      supportsThinking: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'qwen2.5-1.5b-instruct',
      name: 'Qwen 2.5 1.5B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      fileSizeBytes: 1597931520,
      license: 'Apache-2.0',
      description:
          'Strong multilingual chat and instruction following in a compact package.',
      minRamMb: 3072,
      parameterLabel: '1.5B',
      bestFor: 'Strong multilingual chat and instruction following',
      supportsFunctionCalling: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'deepseek-r1-distill-qwen-1.5b',
      name: 'DeepSeek R1 Distill Qwen 1.5B',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv4096.litertlm',
      fileSizeBytes: 1833451520,
      license: 'MIT',
      description:
          'High-performance reasoning and code generation with thinking mode.',
      minRamMb: 3584,
      parameterLabel: '1.5B',
      bestFor: 'High-performance reasoning and code generation',
      supportsFunctionCalling: true,
      supportsThinking: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'gemma4-e2b-instruct',
      name: 'Gemma 4 E2B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
      fileSizeBytes: 2583085056,
      license: 'Apache-2.0',
      description:
          'Next-gen multimodal chat for text, image, and audio-capable workflows.',
      minRamMb: 5120,
      parameterLabel: 'E2B',
      bestFor: 'Next-gen multimodal chat: text, image, audio',
      supportsFunctionCalling: true,
      supportsThinking: true,
      supportsVision: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'gemma4-e4b-instruct',
      name: 'Gemma 4 E4B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm',
      fileSizeBytes: 4617089843,
      license: 'Apache-2.0',
      description:
          'Larger Gemma 4 multimodal model for higher quality local chat.',
      minRamMb: 7168,
      parameterLabel: 'E4B',
      bestFor: 'Next-gen multimodal chat: text, image, audio',
      supportsFunctionCalling: true,
      supportsThinking: true,
      supportsVision: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'gemma3n-e2b-instruct',
      name: 'Gemma3n E2B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm',
      fileSizeBytes: 3221225472,
      license: 'Gemma',
      description: 'On-device multimodal chat and image analysis.',
      requiresHuggingFaceToken: true,
      minRamMb: 5120,
      parameterLabel: 'E2B',
      bestFor: 'On-device multimodal chat and image analysis',
      supportsFunctionCalling: true,
      supportsVision: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'fastvlm-0.5b',
      name: 'FastVLM 0.5B',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/FastVLM-0.5B/resolve/main/FastVLM-0.5B.litertlm',
      fileSizeBytes: 536870912,
      license: 'Apple AMLR',
      description: 'Fast vision-language inference for image understanding.',
      minRamMb: 2048,
      parameterLabel: '0.5B',
      bestFor: 'Fast vision-language inference',
      supportsVision: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'phi-4-mini-instruct',
      name: 'Phi-4 Mini Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/Phi-4-mini-instruct_multi-prefill-seq_q8_ekv4096.litertlm',
      fileSizeBytes: 4187593114,
      license: 'MIT',
      description: 'Advanced reasoning and instruction following.',
      minRamMb: 6144,
      parameterLabel: '3.8B',
      bestFor: 'Advanced reasoning and instruction following',
      supportsFunctionCalling: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'gemma3-1b-it',
      name: 'Gemma 3 1B Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-int4.litertlm',
      fileSizeBytes: 536870912,
      license: 'Gemma',
      description: 'Balanced and efficient text generation.',
      minRamMb: 2048,
      parameterLabel: '1B',
      bestFor: 'Balanced and efficient text generation',
      supportsFunctionCalling: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'gemma3-270m-it',
      name: 'Gemma 3 270M Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.litertlm',
      fileSizeBytes: 322122547,
      license: 'Gemma',
      description: 'Small model suited for fine-tuning with LoRA.',
      minRamMb: 1024,
      parameterLabel: '270M',
      bestFor: 'Fine-tuning for specific tasks',
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'functiongemma-270m',
      name: 'FunctionGemma 270M',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/functiongemma-270m-ft-mobile-actions/resolve/main/mobile_actions_q8_ekv1024.litertlm',
      fileSizeBytes: 297795584,
      license: 'Gemma',
      description: 'Specialized for function calling on-device.',
      minRamMb: 1024,
      parameterLabel: '270M',
      bestFor: 'Specialized on-device function calling',
      supportsFunctionCalling: true,
      languagesLabel: 'Multilingual',
    ),
    OnDeviceModel(
      id: 'smollm2-135m-instruct',
      name: 'SmolLM 135M Instruct',
      huggingFaceUrl:
          'https://huggingface.co/litert-community/SmolLM2-135M-Instruct/resolve/main/SmolLM2_135M_Instruct.litertlm',
      fileSizeBytes: 141557760,
      license: 'Apache-2.0',
      description: 'Ultra-compact chat model for constrained devices.',
      minRamMb: 512,
      parameterLabel: '135M',
      bestFor: 'Ultra-compact resource-constrained devices',
      languagesLabel: 'English',
    ),
    OnDeviceModel(
      id: 'translategemma-4b-it',
      name: 'TranslateGemma 4B',
      huggingFaceUrl:
          'https://huggingface.co/barakplasma/translategemma-4b-it-android-task-quantized/resolve/main/artifacts/int4-generic/translategemma-4b-it-int4-generic.litertlm',
      fileSizeBytes: 4294967296,
      license: 'Gemma',
      description: 'Single-shot translation across 55 languages.',
      minRamMb: 6144,
      parameterLabel: '4B',
      bestFor: 'Single-shot 55-language translation',
      languagesLabel: '55 languages',
      backendNote: 'CPU-only',
      isCpuOnly: true,
    ),
  ];

  static const List<OnDeviceModel> curatedMlxModels = [
    OnDeviceModel(
      id: 'mlx-qwen-2.5-0.5b',
      name: 'Qwen 2.5 0.5B (MLX)',
      huggingFaceUrl:
          'https://huggingface.co/mlx-community/Qwen2.5-0.5B-Instruct-4bit',
      fileSizeBytes: 408944640,
      license: 'Apache-2.0',
      description:
          'High efficiency compact Qwen 2.5 4-bit model running via Apple MLX.',
      isRecommended: true,
      minRamMb: 1536,
      parameterLabel: '0.5B (4-bit)',
      bestFor: 'Compact multilingual chat with tiny footprint',
      languagesLabel: 'Multilingual',
      backendNote: 'Apple MLX',
      runtime: OnDeviceModelRuntime.mlx,
      format: OnDeviceModelFormat.mlx,
    ),
    OnDeviceModel(
      id: 'mlx-llama-3.2-1b',
      name: 'Llama 3.2 1B (MLX)',
      huggingFaceUrl:
          'https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit',
      fileSizeBytes: 786432000,
      license: 'Llama-3.2',
      description:
          'Compact, ultra-fast Llama 3.2 4-bit model powered by Apple MLX Metal kernels.',
      isRecommended: true,
      minRamMb: 2048,
      parameterLabel: '1B (4-bit)',
      bestFor: 'Lightweight high-speed text generation',
      supportsThinking: false,
      languagesLabel: 'Multilingual',
      backendNote: 'Apple MLX',
      runtime: OnDeviceModelRuntime.mlx,
      format: OnDeviceModelFormat.mlx,
    ),
    OnDeviceModel(
      id: 'mlx-gemma-2-2b',
      name: 'Gemma 2 2B (MLX)',
      huggingFaceUrl: 'https://huggingface.co/mlx-community/gemma-2-2b-it-4bit',
      fileSizeBytes: 1530920960,
      license: 'Gemma',
      description:
          'Native Apple MLX 4-bit model running with Metal GPU acceleration.',
      minRamMb: 4096,
      parameterLabel: '2B (4-bit)',
      bestFor: 'Fast chat on Apple Silicon',
      supportsThinking: false,
      languagesLabel: 'Multilingual',
      backendNote: 'Apple MLX',
      runtime: OnDeviceModelRuntime.mlx,
      format: OnDeviceModelFormat.mlx,
    ),
    OnDeviceModel(
      id: 'mlx-smollm2-135m',
      name: 'SmolLM2 135M (MLX)',
      huggingFaceUrl:
          'https://huggingface.co/mlx-community/SmolLM2-135M-Instruct',
      fileSizeBytes: 272629760,
      license: 'Apache-2.0',
      description:
          'Ultra-compact 135M MLX model for near-instant on-device inference.',
      minRamMb: 1024,
      parameterLabel: '135M',
      bestFor: 'Instant local inference and memory efficiency',
      languagesLabel: 'English',
      backendNote: 'Apple MLX',
      runtime: OnDeviceModelRuntime.mlx,
      format: OnDeviceModelFormat.mlx,
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
  final PreferredBackend backend;
  final OnDeviceEngineStatus engineStatus;

  const OnDeviceModelStateInfo({
    required this.modelId,
    this.state = OnDeviceModelState.notDownloaded,
    this.downloadProgress = 0.0,
    this.error,
    this.backend = PreferredBackend.cpu,
    this.engineStatus = OnDeviceEngineStatus.notLoaded,
  });

  OnDeviceModelStateInfo copyWith({
    String? modelId,
    OnDeviceModelState? state,
    double? downloadProgress,
    String? error,
    PreferredBackend? backend,
    OnDeviceEngineStatus? engineStatus,
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
