import 'download_status.dart';

class DownloadProgressInfo {
  final String modelId;
  final DownloadStatus status;
  final double progress;
  final String? taskId;
  final String? error;

  const DownloadProgressInfo({
    required this.modelId,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.taskId,
    this.error,
  });

  DownloadProgressInfo copyWith({
    String? modelId,
    DownloadStatus? status,
    double? progress,
    String? taskId,
    String? error,
  }) {
    return DownloadProgressInfo(
      modelId: modelId ?? this.modelId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      taskId: taskId ?? this.taskId,
      error: error ?? this.error,
    );
  }
}
