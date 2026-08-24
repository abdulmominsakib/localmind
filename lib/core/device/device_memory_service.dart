import 'dart:io';

import 'package:flutter/services.dart';
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
  static const MethodChannel _memoryChannel = MethodChannel(
    'localmind/device_memory',
  );

  Future<DeviceMemoryInfo> getMemoryInfo() async {
    int totalMb = 0;
    int availableMb = 0;

    if (Platform.isAndroid) {
      try {
        final memory = await _memoryChannel.invokeMapMethod<String, dynamic>(
          'getMemoryInfo',
        );
        if (memory != null) {
          totalMb = (memory['totalMemoryMb'] as num?)?.toInt() ?? 0;
          availableMb = (memory['availableMemoryMb'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}

      try {
        final androidInfo = await _deviceInfo.androidInfo;
        if (totalMb == 0) {
          // physicalRamSize is in bytes for device_info_plus 4.0.0+
          totalMb = androidInfo.physicalRamSize ~/ (1024 * 1024);
        }
      } catch (_) {}

      if (availableMb == 0) {
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
