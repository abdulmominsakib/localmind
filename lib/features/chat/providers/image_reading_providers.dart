import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';

import '../data/image_reader.dart';

final imageReaderProvider = Provider<ImageReader>((ref) {
  final reader = MlKitImageReader();
  ref.onDispose(reader.close);
  return reader;
});

/// Whether photos must be read on the device before a request to [server].
///
/// Only on-device models qualify: their vision support is known for sure.
/// Remote servers often don't report it, so a "no vision" flag there may
/// just mean "unknown", and replacing the image would hide it from a model
/// that could have seen it.
Future<bool> needsOnDeviceImageReading(Ref ref, Server server) async {
  if (!server.isOnDevice) return false;
  if (!ref.read(settingsProvider).readImagesOnDevice) return false;
  if (!MlKitImageReader.isSupportedPlatform &&
      ref.read(imageReaderProvider) is MlKitImageReader) {
    return false;
  }
  final runtime = ref.read(onDeviceEngineProvider).loadedRuntime;
  final acceptsImages = switch (runtime) {
    OnDeviceModelRuntime.llamaCpp =>
      await ref.read(onDeviceLlamaServiceProvider).supportsVision,
    // MLX chat is text-only.
    OnDeviceModelRuntime.mlx => false,
    OnDeviceModelRuntime.gemma ||
    null => ref.read(onDeviceGemmaServiceProvider).currentModelSupportsVision,
  };
  return !acceptsImages;
}
