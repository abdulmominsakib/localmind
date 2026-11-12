import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('embedder action returns embeddings and preserves metadata', () async {
    final runtime = FakeRuntime()
      ..embeddings = <List<double>>[
        <double>[1, 2, 3],
      ];
    final action = testEmbedderAction(runtime: runtime);

    final response = await action(
      genkit.EmbedRequest(
        input: <genkit.DocumentData>[
          genkit.DocumentData(
            content: <genkit.Part>[genkit.TextPart(text: 'hello world')],
            metadata: <String, dynamic>{'id': 'doc-1'},
          ),
        ],
        options: <String, dynamic>{'normalize': false},
      ),
    );

    expect(runtime.embedBatchCallCount, 1);
    expect(runtime.lastNormalize, false);
    expect(response.embeddings.single.embedding, <double>[1, 2, 3]);
    expect(response.embeddings.single.metadata, <String, dynamic>{
      'id': 'doc-1',
    });
  });
}
