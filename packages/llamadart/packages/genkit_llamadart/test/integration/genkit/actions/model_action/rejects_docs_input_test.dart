import 'package:genkit/genkit.dart' as genkit;
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';
import '../test_support/action_harness.dart';

void main() {
  test('model action rejects docs input', () async {
    final action = testModelAction(runtime: FakeRuntime());

    expect(
      () => action(
        genkit.ModelRequest(
          messages: <genkit.Message>[
            genkit.Message(
              role: genkit.Role.user,
              content: <genkit.Part>[genkit.TextPart(text: 'Hi')],
            ),
          ],
          docs: <genkit.DocumentData>[
            genkit.DocumentData(
              content: <genkit.Part>[genkit.TextPart(text: 'doc')],
            ),
          ],
        ),
      ),
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
