import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceMemoryInfo {
  final int totalMemoryMb;
  final int availableMemoryMb;

  const DeviceMemoryInfo({
    required this.totalMemoryMb,
    required this.availableMemoryMb,
  });

  bool hasEnoughRam(int requiredMb) => availableMemoryMb >= requiredMb;
  bool isOversized(int minRamMb) => totalMemoryMb < minRamMb;

  String get totalMemoryFormatted => _formatMb(totalMemoryMb);
  String get availableMemoryFormatted => _formatMb(availableMemoryMb);

  String _formatMb(int mb) {
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '$mb MB';
  }
}

class DeviceMemoryService {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<DeviceMemoryInfo> getMemoryInfo() async {
    int totalMb = 0;
    int availableMb = 0;

    if (Platform.isAndroid) {
      try {
        final androidInfo = await _deviceInfo.androidInfo;
        totalMb = androidInfo.physicalRamSize; // In MB
      } catch (_) {}

      try {
        final file = File('/proc/meminfo');
        if (await file.exists()) {
          final memInfo = await file.readAsLines();
          for (final line in memInfo) {
            if (line.startsWith('MemAvailable:')) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 2) {
                final kb = int.tryParse(parts[1]) ?? 0;
                availableMb = kb ~/ 1024;
              }
              break;
            }
          }
        }
      } catch (_) {
        // Fallback or ignore
      }
    } else if (Platform.isMacOS || Platform.isLinux) {
      // Optional: Add support for desktop if needed for testing
    }

    return DeviceMemoryInfo(
      totalMemoryMb: totalMb,
      availableMemoryMb: availableMb,
    );
  }
}
