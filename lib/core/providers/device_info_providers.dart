import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../device/device_memory_service.dart';

final deviceMemoryServiceProvider = Provider<DeviceMemoryService>((ref) {
  return DeviceMemoryService();
});

final deviceMemoryProvider = FutureProvider<DeviceMemoryInfo>((ref) async {
  final service = ref.watch(deviceMemoryServiceProvider);
  return service.getMemoryInfo();
});
