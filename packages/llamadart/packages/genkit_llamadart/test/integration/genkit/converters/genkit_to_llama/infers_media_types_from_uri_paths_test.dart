import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  test('toLlamaMessages infers signed remote image URL content types', () {
    const url = 'https://example.com/image.png?token=secret#preview';
    final image = _convertImage(url);

    expect(image.url, url);
  });

  test('toLlamaMessages accepts Windows drive media paths', () {
    for (final path in <String>[
      r'C:\models\image.png',
      'C:/models/image.png',
    ]) {
      final image = _convertImage(path);

      expect(image.path, path);
    }
  });

  test('data URL media preserves decoded binary bytes', () {
    for (final type in ['image/png', 'audio/wav']) {
      for (final payload in [';base64,AP9B', ',%00%FFA']) {
        final converted = toLlamaMessages([
          genkit.Message(
            role: genkit.Role.user,
            content: [
              genkit.MediaPart(media: genkit.Media(url: 'data:$type$payload')),
            ],
          ),
        ]);
        final part = converted.single.parts.single;
        final bytes = part is llama.LlamaImageContent
            ? part.bytes
            : (part as llama.LlamaAudioContent).bytes;
        expect(bytes, [0, 255, 65], reason: '$type$payload');
      }
    }
  });
}

llama.LlamaImageContent _convertImage(String url) {
  final converted = toLlamaMessages(<genkit.Message>[
    genkit.Message(
      role: genkit.Role.user,
      content: <genkit.Part>[genkit.MediaPart(media: genkit.Media(url: url))],
    ),
  ]);

  return converted.single.parts.single as llama.LlamaImageContent;
}
