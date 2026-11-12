import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('embedder action rejects models with embeddings disabled', () async {
    final action = testEmbedderAction(
      runtime: FakeRuntime(),
      definition: testModelDefinition(supportsEmbeddings: false),
    );

    expect(
      () => action(
        genkit.EmbedRequest(
          input: <genkit.DocumentData>[
            genkit.DocumentData(
              content: <genkit.Part>[genkit.TextPart(text: 'hello')],
            ),
          ],
        ),
      ),
      throwsA(
        isA<genkit.GenkitException>().having(
          (error) => error.status,
          'status',
          genkit.StatusCode.failedPrecondition,
        ),
      ),
    );
  });
}
