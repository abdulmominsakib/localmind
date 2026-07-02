import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Resize/compress images so LM Studio requests stay under payload limits.
class ImageUploadUtils {
  ImageUploadUtils._();

  static const maxPayloadBytes = 750000;
  static const maxBase64Chars = 1000000;

  static Future<Uint8List> prepareImageBytes(File file) async {
    var bytes = await file.readAsBytes();
    if (_isSmallEnough(bytes)) return bytes;

    for (final dimension in [1536, 1280, 1024, 768, 512]) {
      final resized = await _resizeToPng(bytes, dimension);
      if (_isSmallEnough(resized)) return resized;
      bytes = resized;
    }
    return bytes;
  }

  static Future<File> prepareImageFile(File source) async {
    final bytes = await prepareImageBytes(source);
    final original = source.path.split(Platform.pathSeparator).last;
    final dot = original.lastIndexOf('.');
    final base = dot > 0 ? original.substring(0, dot) : original;
    final outPath =
        '${source.parent.path}${Platform.pathSeparator}upload_${DateTime.now().millisecondsSinceEpoch}_$base.png';
    final out = File(outPath);
    await out.writeAsBytes(bytes);
    return out;
  }

  static bool _isSmallEnough(Uint8List bytes) {
    if (bytes.length <= maxPayloadBytes) return true;
    return false;
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
