import 'package:localmind/core/models/enums.dart';

class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? parameterCount;
  final int? contextLength;
  final int? fileSize;
  final String? quantization;
  final String? architecture;
  final ServerType serverType;
  final String serverId;
  final DateTime? modifiedAt;

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
    if (fileSize == null) return null;
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String? get parameterCountDisplay {
    if (parameterCount == null) return null;
    return '${parameterCount}B';
  }
}
