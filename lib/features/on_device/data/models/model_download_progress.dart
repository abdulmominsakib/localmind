class ModelDownloadProgress {
  final int receivedBytes;
  final int totalBytes;
  final double fraction;
  final int bytesPerSecond;
  final int? estimatedSecondsRemaining;
  final bool isResumed;

  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.fraction,
    required this.bytesPerSecond,
    this.estimatedSecondsRemaining,
    required this.isResumed,
  });

  String get speedFormatted {
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get etaFormatted {
    if (estimatedSecondsRemaining == null) return 'Unknown';
    if (estimatedSecondsRemaining! < 60) return '$estimatedSecondsRemaining sec';
    final minutes = estimatedSecondsRemaining! ~/ 60;
    final seconds = estimatedSecondsRemaining! % 60;
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
