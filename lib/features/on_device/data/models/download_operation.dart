/// Write-ahead intent record for an in-flight download/update operation.
///
/// The registry is NOT a source of truth — metadata (repositories) and the
/// background_downloader DB remain authoritative. The registry only records
/// *intent* so recovery after process death is possible.
enum DownloadOperationType { download, update }

enum DownloadOperationPhase { started, downloading, finalizing, cancelRequested }

class DownloadOperation {
  final String operationId;
  final String modelId;
  final DownloadOperationType type;
  final String taskId; // modelId or '$modelId-update'
  final String? baseRevision; // metadata.revision at start
  final String? targetRevision; // metadata.latestRevision at start
  final DownloadOperationPhase phase;
  final DateTime startedAt;
  final DateTime updatedAt;

  const DownloadOperation({
    required this.operationId,
    required this.modelId,
    required this.type,
    required this.taskId,
    this.baseRevision,
    this.targetRevision,
    this.phase = DownloadOperationPhase.started,
    required this.startedAt,
    required this.updatedAt,
  });

  DownloadOperation copyWith({
    String? operationId,
    String? modelId,
    DownloadOperationType? type,
    String? taskId,
    Object? baseRevision = _unset,
    Object? targetRevision = _unset,
    DownloadOperationPhase? phase,
    DateTime? startedAt,
    DateTime? updatedAt,
  }) {
    return DownloadOperation(
      operationId: operationId ?? this.operationId,
      modelId: modelId ?? this.modelId,
      type: type ?? this.type,
      taskId: taskId ?? this.taskId,
      baseRevision: identical(baseRevision, _unset)
          ? this.baseRevision
          : baseRevision as String?,
      targetRevision: identical(targetRevision, _unset)
          ? this.targetRevision
          : targetRevision as String?,
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static const Object _unset = Object();

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'modelId': modelId,
        'type': type.index,
        'taskId': taskId,
        'baseRevision': baseRevision,
        'targetRevision': targetRevision,
        'phase': phase.index,
        'startedAt': startedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DownloadOperation.fromJson(Map<String, dynamic> json) {
    final typeIdx = (json['type'] as num?)?.toInt() ?? 0;
    final phaseIdx = (json['phase'] as num?)?.toInt() ?? 0;
    return DownloadOperation(
      operationId: json['operationId'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      type: typeIdx >= 0 && typeIdx < DownloadOperationType.values.length
          ? DownloadOperationType.values[typeIdx]
          : DownloadOperationType.download,
      taskId: json['taskId'] as String? ?? '',
      baseRevision: json['baseRevision'] as String?,
      targetRevision: json['targetRevision'] as String?,
      phase: phaseIdx >= 0 && phaseIdx < DownloadOperationPhase.values.length
          ? DownloadOperationPhase.values[phaseIdx]
          : DownloadOperationPhase.started,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
