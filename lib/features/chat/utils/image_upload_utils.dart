import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

enum ImageCompressionLevel { low, medium, high }

class _CompressionConfig {
  const _CompressionConfig(this.maxPayloadBytes, this.dimensions);

  final int maxPayloadBytes;
  final List<int> dimensions;
}

/// Resize/compress images so LM Studio requests stay under payload limits.
class ImageUploadUtils {
  ImageUploadUtils._();

  /// Kept for callers that don't care about the configured level.
  static const maxPayloadBytes = 750000;
  static const maxBase64Chars = 1000000;

  static const Map<ImageCompressionLevel, _CompressionConfig> _configs = {
    ImageCompressionLevel.low:
        _CompressionConfig(1500000, [1920, 1536, 1280, 1024]),
    ImageCompressionLevel.medium:
        _CompressionConfig(750000, [1536, 1280, 1024, 768, 512]),
    ImageCompressionLevel.high:
        _CompressionConfig(400000, [1024, 768, 512, 384, 256]),
  };

  static Future<Uint8List> prepareImageBytes(
    File file, {
    bool enabled = true,
    ImageCompressionLevel level = ImageCompressionLevel.medium,
  }) async {
    var bytes = await file.readAsBytes();
    if (!enabled) return bytes;

    final config = _configs[level]!;
    if (bytes.length <= config.maxPayloadBytes) return bytes;

    for (final dimension in config.dimensions) {
      final resized = await _resizeToPng(bytes, dimension);
      if (resized.length <= config.maxPayloadBytes) return resized;
      bytes = resized;
    }
    return bytes;
  }

  static Future<File> prepareImageFile(
    File source, {
    bool enabled = true,
    ImageCompressionLevel level = ImageCompressionLevel.medium,
  }) async {
    final bytes = await prepareImageBytes(
      source,
      enabled: enabled,
      level: level,
    );
    final original = source.path.split(Platform.pathSeparator).last;
    final dot = original.lastIndexOf('.');
    final base = dot > 0 ? original.substring(0, dot) : original;
    final outPath =
        '${source.parent.path}${Platform.pathSeparator}upload_${DateTime.now().millisecondsSinceEpoch}_$base.png';
    final out = File(outPath);
    await out.writeAsBytes(bytes);
    return out;
  }

  static Future<Uint8List> _resizeToPng(
    Uint8List bytes,
    int maxDimension,
  ) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxDimension,
      targetHeight: maxDimension,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    return data?.buffer.asUint8List() ?? bytes;
  }
}
