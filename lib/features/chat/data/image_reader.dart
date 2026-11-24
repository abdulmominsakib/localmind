import 'dart:io';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/logger/app_logger.dart';

/// What could be read from a photo without a vision model: printed text and
/// a few broad labels for what it shows.
class ImageReadout {
  const ImageReadout({this.text = '', this.labels = const []});

  final String text;

  /// Most likely first.
  final List<String> labels;

  bool get isEmpty => text.trim().isEmpty && labels.isEmpty;

  /// Sent when the image couldn't be read at all.
  static const unreadablePromptText =
      'An image was attached, but this model cannot see images and it could '
      'not be read on this device. Tell the user you cannot see it.';

  /// The block sent to a text-only model in place of the image.
  String toPromptText() {
    final lines = <String>[
      'Image read on this device with text and object recognition, because '
          'the model cannot see images. Answer from this description.',
    ];
    if (isEmpty) {
      lines.add('No text or recognizable objects were found in the image.');
      return lines.join('\n');
    }
    if (labels.isNotEmpty) {
      lines.add('Likely shows: ${labels.join(', ')}');
    }
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      lines.add('Text in the image:\n$trimmed');
    }
    return lines.join('\n');
  }
}

/// Reads text and labels from an image file on the device.
abstract class ImageReader {
  /// Returns null when reading isn't available or failed.
  Future<ImageReadout?> read(String path);

  Future<void> close();
}

/// Google ML Kit text recognition (Latin script) and image labeling. Both
/// models ship with the app and run offline.
class MlKitImageReader implements ImageReader {
  MlKitImageReader({this.labelConfidence = 0.6, this.maxLabels = 5});

  final double labelConfidence;
  final int maxLabels;

  TextRecognizer? _recognizer;
  ImageLabeler? _labeler;

  /// Attachments are saved under unique names and never rewritten, so a
  /// path identifies its contents for the life of the app.
  final Map<String, ImageReadout> _cache = {};

  static bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  Future<ImageReadout?> read(String path) async {
    if (!isSupportedPlatform) return null;
    final cached = _cache[path];
    if (cached != null) return cached;
    if (!await File(path).exists()) return null;

    final input = InputImage.fromFilePath(path);
    var text = '';
    var labels = const <String>[];
    var anySucceeded = false;

    try {
      final recognizer = _recognizer ??= TextRecognizer();
      text = (await recognizer.processImage(input)).text;
      anySucceeded = true;
    } catch (e) {
      Log.warning('On-device text recognition failed for $path: $e');
    }

    try {
      final labeler = _labeler ??= ImageLabeler(
        options: ImageLabelerOptions(confidenceThreshold: labelConfidence),
      );
      final found = await labeler.processImage(input)
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
      labels = found
          .take(maxLabels)
          .map((label) => label.label.toLowerCase())
          .toList(growable: false);
      anySucceeded = true;
    } catch (e) {
      Log.warning('On-device image labeling failed for $path: $e');
    }

    if (!anySucceeded) return null;
    final readout = ImageReadout(text: text, labels: labels);
    _cache[path] = readout;
    return readout;
  }

  @override
  Future<void> close() async {
    await _recognizer?.close();
    await _labeler?.close();
    _recognizer = null;
    _labeler = null;
  }
}
