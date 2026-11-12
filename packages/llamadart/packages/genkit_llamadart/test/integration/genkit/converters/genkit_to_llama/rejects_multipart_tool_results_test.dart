import 'package:genkit/plugin.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  test('non-text tool results fail with redacted errors for every role', () {
    for (final role in [Role.tool, Role.user]) {
      expect(
        () => toLlamaMessages([
          Message(
            role: role,
            content: [
              ToolResponsePart(
                toolResponse: ToolResponse(
                  name: 'lookup',
                  output: 'ok',
                  content: [
                    {'text': 'supported'},
                    {
                      'media': {
                        'url':
                            'https://USER_SENTINEL:SECRET_SENTINEL@host/PATH_SENTINEL?token=TOKEN_SENTINEL',
                        'contentType': 'image/png',
                      },
                    },
                  ],
                ),
              ),
            ],
          ),
        ]),
        throwsA(
          isA<GenkitException>()
              .having((e) => e.status, 'status', StatusCode.unimplemented)
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('SENTINEL')),
              ),
        ),
      );
    }
  });
}
