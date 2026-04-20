import 'download_status.dart';

class DownloadProgressInfo {
  final String modelId;
  final DownloadStatus status;
  final double progress;
  final String? taskId;
  final String? error;
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;
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
    this.bytesPerSecond = 0,
    this.etaSeconds,
    this.isResumed = false,
  });

  DownloadProgressInfo copyWith({
    String? modelId,
    DownloadStatus? status,
    double? progress,
    String? taskId,
    String? error,
    int? receivedBytes,
    int? totalBytes,
    int? bytesPerSecond,
    int? etaSeconds,
    bool? isResumed,
  }) {
    return DownloadProgressInfo(
      modelId: modelId ?? this.modelId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      taskId: taskId ?? this.taskId,
      error: error ?? this.error,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      etaSeconds: etaSeconds ?? this.etaSeconds,
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

  factory DownloadProgressInfo.fromJson(Map<String, dynamic> json) {
    return DownloadProgressInfo(
      modelId: json['modelId'] as String,
      status: DownloadStatus.values[json['status'] as int],
      progress: (json['progress'] as num).toDouble(),
      taskId: json['taskId'] as String?,
      error: json['error'] as String?,
      receivedBytes: json['receivedBytes'] as int,
      totalBytes: json['totalBytes'] as int,
      bytesPerSecond: json['bytesPerSecond'] as int,
      etaSeconds: json['etaSeconds'] as int?,
      isResumed: json['isResumed'] as bool? ?? false,
    );
  }

  String get speedFormatted {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get etaFormatted {
    if (etaSeconds == null) return 'Unknown';
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
