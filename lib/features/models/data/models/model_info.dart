import '../../../../core/models/enums.dart';
import '../../../on_device/data/models/on_device_model.dart';

class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final double? parameterCount;
  final int? contextLength;
  final int? fileSize;
  final String? quantization;
  final String? architecture;
  final ServerType serverType;
  final String serverId;
  final DateTime? modifiedAt;
  final ModelStatus status;
  final OnDeviceModelRuntime? onDeviceRuntime;
  final OnDeviceModelFormat? onDeviceFormat;
  final String? localPath;
  final bool supportsVision;
  final bool supportsReasoning;
  final bool supportsToolUse;
  /// Effort strings the model advertises for reasoning (OpenRouter
  /// `reasoning.supported_efforts`), e.g. `["minimal","low","medium","high"]`.
  /// Null for providers that don't expose per-model efforts.
  final List<String>? supportedReasoningEfforts;
  /// The model's default reasoning effort (OpenRouter
  /// `reasoning.default_effort`), e.g. `"medium"`.
  final String? defaultReasoningEffort;
  /// When true the model cannot run without reasoning (OpenRouter
  /// `reasoning.mandatory`); the "Off" toggle should be hidden.
  final bool reasoningMandatory;
  /// Input token price in USD per 1M tokens (OpenRouter `pricing.prompt`).
  final double? inputPricePerMillion;
  /// Output token price in USD per 1M tokens (OpenRouter `pricing.completion`).
  final double? outputPricePerMillion;

  ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.parameterCount,
    this.contextLength,
    this.fileSize,
    this.quantization,
    this.architecture,
    required this.serverType,
    required this.serverId,
    this.modifiedAt,
    this.status = ModelStatus.unloaded,
    this.onDeviceRuntime,
    this.onDeviceFormat,
    this.localPath,
    this.supportsVision = false,
    this.supportsReasoning = false,
    this.supportsToolUse = false,
    this.supportedReasoningEfforts,
    this.defaultReasoningEffort,
    this.reasoningMandatory = false,
    this.inputPricePerMillion,
    this.outputPricePerMillion,
  });

  String get displayName {
    if (name.isNotEmpty) return name;
    return id
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '',
        )
        .join(' ');
  }

  String? get formattedSize {
    if (fileSize == null || fileSize == 0) return null;
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String? get parameterCountDisplay {
    if (parameterCount == null) return null;
    final formatted = parameterCount!.toStringAsFixed(2);
    if (formatted.endsWith('.00')) {
      return '${parameterCount!.toInt()}B';
    } else if (formatted.endsWith('0')) {
      return '${parameterCount!.toStringAsFixed(1)}B';
    }
    return '${parameterCount!.toStringAsFixed(2)}B';
  }

  /// True when both prices are known and are zero (a genuinely free model).
  bool get isPricingFree =>
      inputPricePerMillion != null &&
      outputPricePerMillion != null &&
      inputPricePerMillion == 0 &&
      outputPricePerMillion == 0;

  /// Compact chip label for API pricing, e.g. `$2.50/$10.00`. Returns
  /// `Free` for zero-cost models and null when no pricing is known.
  String? get pricingLabel {
    if (inputPricePerMillion == null && outputPricePerMillion == null) {
      return null;
    }
    if (isPricingFree) return 'Free';
    return [
      if (inputPricePerMillion != null)
        '\$${_formatPriceValue(inputPricePerMillion!)}',
      if (outputPricePerMillion != null)
        '\$${_formatPriceValue(outputPricePerMillion!)}',
    ].join('/');
  }

  /// Formatted input price (e.g. `$2.50`) or null when unknown.
  String? get formattedInputPrice => inputPricePerMillion == null
      ? null
      : '\$${_formatPriceValue(inputPricePerMillion!)}';

  /// Formatted output price (e.g. `$10.00`) or null when unknown.
  String? get formattedOutputPrice => outputPricePerMillion == null
      ? null
      : '\$${_formatPriceValue(outputPricePerMillion!)}';

  static String _formatPriceValue(double value) {
    if (value >= 100) return value.round().toString();
    if (value >= 0.01) return value.toStringAsFixed(2);
    var s = value.toStringAsFixed(6);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  ModelInfo copyWith({
    String? id,
    String? name,
    String? description,
    double? parameterCount,
    int? contextLength,
    int? fileSize,
    String? quantization,
    String? architecture,
    ServerType? serverType,
    String? serverId,
    DateTime? modifiedAt,
    ModelStatus? status,
    OnDeviceModelRuntime? onDeviceRuntime,
    OnDeviceModelFormat? onDeviceFormat,
    String? localPath,
    bool? supportsVision,
    bool? supportsReasoning,
    bool? supportsToolUse,
    List<String>? supportedReasoningEfforts,
    String? defaultReasoningEffort,
    bool? reasoningMandatory,
    double? inputPricePerMillion,
    double? outputPricePerMillion,
  }) {
    return ModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parameterCount: parameterCount ?? this.parameterCount,
      contextLength: contextLength ?? this.contextLength,
      fileSize: fileSize ?? this.fileSize,
      quantization: quantization ?? this.quantization,
      architecture: architecture ?? this.architecture,
      serverType: serverType ?? this.serverType,
      serverId: serverId ?? this.serverId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      status: status ?? this.status,
      onDeviceRuntime: onDeviceRuntime ?? this.onDeviceRuntime,
      onDeviceFormat: onDeviceFormat ?? this.onDeviceFormat,
      localPath: localPath ?? this.localPath,
      supportsVision: supportsVision ?? this.supportsVision,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
      supportsToolUse: supportsToolUse ?? this.supportsToolUse,
      supportedReasoningEfforts:
          supportedReasoningEfforts ?? this.supportedReasoningEfforts,
      defaultReasoningEffort:
          defaultReasoningEffort ?? this.defaultReasoningEffort,
      reasoningMandatory: reasoningMandatory ?? this.reasoningMandatory,
      inputPricePerMillion:
          inputPricePerMillion ?? this.inputPricePerMillion,
      outputPricePerMillion:
          outputPricePerMillion ?? this.outputPricePerMillion,
    );
  }
}
