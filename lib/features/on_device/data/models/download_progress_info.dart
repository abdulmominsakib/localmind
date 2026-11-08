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
  });

  // Sentinel to distinguish "not provided" from an explicit null in copyWith.
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
    };
  }

  static DownloadStatus _statusFromJson(dynamic value) {
    if (value is int && value >= 0 && value < DownloadStatus.values.length) {
      return DownloadStatus.values[value];
    }
    return DownloadStatus.pending;
  }

  factory DownloadProgressInfo.fromJson(Map<String, dynamic> json) {
    return DownloadProgressInfo(
      modelId: json['modelId'] as String,
      status: _statusFromJson(json['status']),
      progress: (json['progress'] as num).toDouble(),
      taskId: json['taskId'] as String?,
      error: json['error'] as String?,
      receivedBytes: json['receivedBytes'] as int,
      totalBytes: json['totalBytes'] as int,
      bytesPerSecond: json['bytesPerSecond'] as int?,
      etaSeconds: json['etaSeconds'] as int?,
      isResumed: json['isResumed'] as bool? ?? false,
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
