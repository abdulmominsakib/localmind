import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test('toLlamaMessages rejects query-bearing file URLs cleanly', () {
    expect(
      () => toLlamaMessages(<genkit.Message>[
        genkit.Message(
          role: genkit.Role.user,
          content: <genkit.Part>[
            genkit.MediaPart(
              media: genkit.Media(url: 'file:///tmp/image.png?token=local'),
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
