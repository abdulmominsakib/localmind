import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('hasPersistentCacheSensitiveUrlParts', () {
    test('allows regular model URLs and benign catalog query keys', () {
      expect(
        hasPersistentCacheSensitiveUrlParts(
          'https://example.com/model.gguf?download=true',
        ),
        isFalse,
      );
      expect(
        hasPersistentCacheSensitiveUrlParts(
          'https://example.com/model.litertlm?DOWNLOAD=true',
        ),
        isFalse,
      );
    });

    test('blocks user info, fragments, and credential-like query keys', () {
      const sensitiveUrls = <String>[
        'https://user:pass@example.com/model.gguf',
        'https://example.com/model.gguf#signed-fragment',
        'https://example.com/model.gguf?access_token=secret',
        'https://example.com/model.gguf?apiKey=secret',
        'https://example.com/model.gguf?token=secret',
        'https://example.com/model.gguf?X-Amz-Signature=secret',
        'https://example.com/model.gguf?credential=secret',
        'https://example.com/model.gguf?key-pair-id=secret',
        'https://example.com/model.gguf?session_id=secret',
      ];

      for (final url in sensitiveUrls) {
        expect(hasPersistentCacheSensitiveUrlParts(url), isTrue, reason: url);
      }
    });

    test('allows benign query keys that contain sensitive substrings', () {
      const benignUrls = <String>[
        'https://example.com/model.gguf?design=compact',
        'https://example.com/model.gguf?author=maintainer',
        'https://example.com/model.gguf?monkey=banana',
      ];

      for (final url in benignUrls) {
        expect(hasPersistentCacheSensitiveUrlParts(url), isFalse, reason: url);
      }
    });

    test('ignores non-remote values', () {
      expect(hasPersistentCacheSensitiveUrlParts('/local/model.gguf'), isFalse);
      expect(hasPersistentCacheSensitiveUrlParts('not a url'), isFalse);
    });
  });
}
