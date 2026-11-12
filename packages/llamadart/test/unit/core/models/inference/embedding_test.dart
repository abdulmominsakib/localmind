import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('embedding input snapshots ordered parts and kinds', () {
    final parts = <LlamaContentPart>[
      const LlamaTextContent('before'),
      const LlamaImageContent(path: 'private.png'),
      const LlamaAudioContent(path: 'private.wav'),
      const LlamaTextContent('after'),
    ];
    final input = LlamaEmbeddingInput(parts);
    parts.clear();
    expect(input.parts, hasLength(4));
    expect(input.partKinds, [
      LlamaEmbeddingModality.text,
      LlamaEmbeddingModality.image,
      LlamaEmbeddingModality.audio,
      LlamaEmbeddingModality.text,
    ]);
    expect(() => input.parts.clear(), throwsUnsupportedError);
    expect(() => input.partKinds.clear(), throwsUnsupportedError);
  });

  test('empty content is rejected but empty text remains valid', () {
    expect(
      () => LlamaEmbeddingInput([]),
      throwsA(isA<LlamaArgumentException>()),
    );
    expect(
      LlamaEmbeddingInput([const LlamaTextContent('')]).parts,
      hasLength(1),
    );
  });

  test('video and chat-only parts fail without serializing their payload', () {
    for (final part in <LlamaContentPart>[
      LlamaVideoContent(path: 'secret.mp4'),
      const LlamaThinkingContent('secret'),
      const LlamaToolCallContent(
        name: 'secret',
        arguments: {},
        rawJson: 'secret',
      ),
      const LlamaToolResultContent(name: 'secret', result: 'secret'),
    ]) {
      expect(
        () => LlamaEmbeddingInput([part]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'redaction',
            isNot(contains('secret')),
          ),
        ),
      );
    }
  });
}
