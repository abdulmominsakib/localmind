enum DownloadStatus {
  pending,
  running,
  paused,
  canceled,
  failed,
  complete,
  undefined,
}

class DownloadStatusUpdate {
  final String modelId;
  final String taskId;
  final DownloadStatus status;
  final int progress; // 0-100

  DownloadStatusUpdate({
    required this.modelId,
    required this.taskId,
    required this.status,
    required this.progress,
  });
}
