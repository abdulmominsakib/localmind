import '../data/catalog_models.dart';

MemoryCompatibility estimateMemoryCompatibility({
  required int? modelSizeBytes,
  int? availableRamGb,
  int? availableVramGb,
}) {
  if (modelSizeBytes == null || modelSizeBytes <= 0) {
    return MemoryCompatibility.unknown;
  }

  final ramBytes = availableRamGb != null && availableRamGb > 0
      ? availableRamGb * 1024 * 1024 * 1024
      : null;
  final vramBytes = availableVramGb != null && availableVramGb > 0
      ? availableVramGb * 1024 * 1024 * 1024
      : null;

  if (ramBytes == null && vramBytes == null) {
    return MemoryCompatibility.unknown;
  }

  // Reserve ~15% for runtime overhead (KV cache, context, OS).
  const overheadFactor = 0.85;

  if (vramBytes != null &&
      modelSizeBytes <= (vramBytes * overheadFactor).round()) {
    return MemoryCompatibility.fullGpuOffload;
  }

  if (ramBytes != null &&
      modelSizeBytes <= (ramBytes * overheadFactor).round()) {
    return MemoryCompatibility.partialGpuOffload;
  }

  return MemoryCompatibility.likelyTooLarge;
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 2)} ${units[unitIndex]}';
}

String formatSpeed(int? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond <= 0) return '';
  final mbPerSecond = bytesPerSecond / (1024 * 1024);
  if (mbPerSecond < 0.1) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${mbPerSecond.toStringAsFixed(1)} MB/s';
}

String formatRelativeTime(DateTime? dateTime) {
  if (dateTime == null) return '';
  final diff = DateTime.now().difference(dateTime);
  if (diff.inDays >= 365) {
    return '${diff.inDays ~/ 365}y ago';
  }
  if (diff.inDays >= 30) {
    return '${diff.inDays ~/ 30}mo ago';
  }
  if (diff.inDays >= 1) {
    return '${diff.inDays}d ago';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours}h ago';
  }
  if (diff.inMinutes >= 1) {
    return '${diff.inMinutes}m ago';
  }
  return 'just now';
}
