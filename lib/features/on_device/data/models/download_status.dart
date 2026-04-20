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
  final int receivedBytes;
  final int totalBytes;
  final int bytesPerSecond;
  final int? etaSeconds;
  final bool isResumed;

  DownloadStatusUpdate({
    required this.modelId,
    required this.taskId,
    required this.status,
    required this.progress,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.etaSeconds,
    this.isResumed = false,
  });
}
