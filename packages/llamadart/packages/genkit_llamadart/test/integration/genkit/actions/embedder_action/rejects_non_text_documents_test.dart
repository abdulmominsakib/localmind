import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('legacy runtime rejects media without an embedding provider', () async {
    final action = testEmbedderAction(runtime: FakeRuntime());

    expect(
      () => action(
        genkit.EmbedRequest(
          input: <genkit.DocumentData>[
            genkit.DocumentData(
              content: <genkit.Part>[
                genkit.MediaPart(
                  media: genkit.Media(
                    url: 'file:///tmp/example.png',
                    contentType: 'image/png',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      throwsA(
        isA<genkit.GenkitException>().having(
          (error) => error.status,
          'status',
          genkit.StatusCode.unimplemented,
        ),
      ),
    );
  });
}
