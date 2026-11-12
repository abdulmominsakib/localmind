import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test('toLlamaMessages rejects unsupported remote audio URLs', () {
    expect(
      () => toLlamaMessages(<genkit.Message>[
        genkit.Message(
          role: genkit.Role.user,
          content: <genkit.Part>[
            genkit.MediaPart(
              media: genkit.Media(
                url: 'https://example.com/audio.mp3',
                contentType: 'audio/mpeg',
              ),
            ),
          ],
        ),
      ]),
      throwsA(
        isA<genkit.GenkitException>().having(
          (error) => error.status,
          'status',
          genkit.StatusCode.invalidArgument,
        ),
      ),
    );
  });
}
