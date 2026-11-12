import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:test/test.dart';

void main() {
  final cases = <String, genkit.Media>{
    'signed audio': genkit.Media(
      url:
          'https://USER_SENTINEL:PASS_SENTINEL@example.invalid/PATH_SENTINEL.wav?signature=QUERY_SENTINEL#FRAGMENT_SENTINEL',
      contentType: 'audio/wav',
    ),
    'unknown type': genkit.Media(
      url: 'https://example.invalid/PATH_SENTINEL?signature=QUERY_SENTINEL',
    ),
    'unsupported MIME': genkit.Media(
      url: 'https://example.invalid/PATH_SENTINEL',
      contentType: 'application/TYPE_SENTINEL',
    ),
    'malformed URI': genkit.Media(
      url: 'https://[PATH_SENTINEL?secret=QUERY_SENTINEL',
      contentType: 'image/png',
    ),
    'malformed data payload': genkit.Media(
      url: 'data:image/png;base64,PAYLOAD_SENTINEL!',
    ),
    'local file query': genkit.Media(
      url: 'file:///PATH_SENTINEL.wav?secret=QUERY_SENTINEL',
      contentType: 'audio/wav',
    ),
    'invalid local file': genkit.Media(
      url: 'file://USER_SENTINEL:PASS_SENTINEL@host/PATH_SENTINEL.png',
      contentType: 'image/png',
    ),
    'unsupported scheme': genkit.Media(
      url: 'ftp://USER_SENTINEL:PASS_SENTINEL@host/PATH_SENTINEL.wav',
      contentType: 'audio/wav',
    ),
  };
  for (final entry in cases.entries) {
    test('${entry.key} returns an actionable redacted error', () {
      expect(
        () => toLlamaMessages([
          genkit.Message(
            role: genkit.Role.user,
            content: [genkit.MediaPart(media: entry.value)],
          ),
        ]),
        throwsA(
          isA<genkit.GenkitException>()
              .having(
                (e) => e.status,
                'status',
                genkit.StatusCode.invalidArgument,
              )
              .having(
                (e) => e.toString(),
                'redacted diagnostic',
                isNot(contains('SENTINEL')),
              )
              .having(
                (e) => e.message,
                'actionable diagnostic',
                contains('media'),
              ),
        ),
      );
    });
  }
}
