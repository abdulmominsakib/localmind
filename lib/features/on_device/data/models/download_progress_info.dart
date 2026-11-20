import 'download_status.dart';

class DownloadProgressInfo {
  final String modelId;
  final DownloadStatus status;
  final double progress;
  final String? taskId;
  final String? error;
  final int receivedBytes;
  final int totalBytes;
  final int? bytesPerSecond;
  final int? etaSeconds;
  final bool isResumed;
  final DownloadPauseReason? pauseReason;
  final DownloadErrorCategory? errorCategory;

  const DownloadProgressInfo({
    required this.modelId,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.taskId,
    this.error,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond,
    this.etaSeconds,
    this.isResumed = false,
    this.pauseReason,
    this.errorCategory,
  });

  static const Object _unset = Object();

  DownloadProgressInfo copyWith({
    String? modelId,
    DownloadStatus? status,
    double? progress,
    Object? taskId = _unset,
    Object? error = _unset,
    int? receivedBytes,
    int? totalBytes,
    Object? bytesPerSecond = _unset,
    Object? etaSeconds = _unset,
    bool? isResumed,
    Object? pauseReason = _unset,
    Object? errorCategory = _unset,
  }) {
    return DownloadProgressInfo(
      modelId: modelId ?? this.modelId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      taskId: identical(taskId, _unset) ? this.taskId : taskId as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: identical(bytesPerSecond, _unset)
          ? this.bytesPerSecond
          : bytesPerSecond as int?,
      etaSeconds: identical(etaSeconds, _unset)
          ? this.etaSeconds
          : etaSeconds as int?,
      isResumed: isResumed ?? this.isResumed,
      pauseReason: identical(pauseReason, _unset)
          ? this.pauseReason
          : pauseReason as DownloadPauseReason?,
      errorCategory: identical(errorCategory, _unset)
          ? this.errorCategory
          : errorCategory as DownloadErrorCategory?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'modelId': modelId,
      'status': status.index,
      'progress': progress,
      'taskId': taskId,
      'error': error,
      'receivedBytes': receivedBytes,
      'totalBytes': totalBytes,
      'bytesPerSecond': bytesPerSecond,
      'etaSeconds': etaSeconds,
      'isResumed': isResumed,
      'pauseReason': pauseReason?.index,
      'errorCategory': errorCategory?.index,
    };
  }

  static DownloadStatus _statusFromJson(dynamic value) {
    if (value is int && value >= 0 && value < DownloadStatus.values.length) {
      return DownloadStatus.values[value];
    }
    return DownloadStatus.pending;
  }

  static DownloadPauseReason? _pauseReasonFromJson(dynamic value) {
    if (value is int && value >= 0 && value < DownloadPauseReason.values.length) {
      return DownloadPauseReason.values[value];
    }
    return null;
  }

  static DownloadErrorCategory? _errorCategoryFromJson(dynamic value) {
    if (value is int && value >= 0 && value < DownloadErrorCategory.values.length) {
      return DownloadErrorCategory.values[value];
    }
    return null;
  }

  factory DownloadProgressInfo.fromJson(Map<String, dynamic> json) {
    final rawProgress = (json['progress'] as num?)?.toDouble() ?? 0.0;
    final clampedProgress = rawProgress.clamp(0.0, 1.0);
    final rawReceived = (json['receivedBytes'] as num?)?.toInt() ?? 0;
    final rawTotal = (json['totalBytes'] as num?)?.toInt() ?? 0;
    final receivedBytes = rawReceived < 0 ? 0 : rawReceived;
    final totalBytes = rawTotal < 0 ? 0 : rawTotal;
    final safeTotal = (totalBytes > 0 && receivedBytes > totalBytes)
        ? receivedBytes
        : totalBytes;

    return DownloadProgressInfo(
      modelId: json['modelId'] as String? ?? '',
      status: _statusFromJson(json['status']),
      progress: clampedProgress,
      taskId: json['taskId'] as String?,
      error: json['error'] as String?,
      receivedBytes: receivedBytes,
      totalBytes: safeTotal,
      bytesPerSecond: (json['bytesPerSecond'] as num?)?.toInt(),
      etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
      isResumed: json['isResumed'] as bool? ?? false,
      pauseReason: _pauseReasonFromJson(json['pauseReason']),
      errorCategory: _errorCategoryFromJson(json['errorCategory']),
    );
  }

  String get speedFormatted {
    final bps = bytesPerSecond;
    if (bps == null || bps <= 0) return '—';
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get etaFormatted {
    if (etaSeconds == null) return '—';
    if (etaSeconds! < 60) return '$etaSeconds sec';
    final minutes = etaSeconds! ~/ 60;
    final seconds = etaSeconds! % 60;
    if (minutes < 60) return '$minutes min $seconds sec';
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '$hours hr $remainingMinutes min';
  }

  String get progressFormatted {
    final mb = receivedBytes / (1024 * 1024);
    final totalMb = totalBytes / (1024 * 1024);
    if (totalMb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB / ${(totalMb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(0)} MB / ${totalMb.toStringAsFixed(0)} MB';
  }
}
