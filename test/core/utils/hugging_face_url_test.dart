import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/utils/hugging_face_url.dart';

void main() {
  group('canonicalizeHuggingFaceUrl', () {
    test('rewrites blob to resolve', () {
      final uri = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/repo/blob/main/model.gguf',
      );
      expect(uri.toString(), 'https://huggingface.co/org/repo/resolve/main/model.gguf');
    });

    test('drops query and fragment', () {
      final uri = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/repo/resolve/main/model.gguf?download=1#frag',
      );
      expect(uri.toString(), 'https://huggingface.co/org/repo/resolve/main/model.gguf');
    });

    test('strips trailing slash', () {
      final uri = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/repo/resolve/main/model.gguf/',
      );
      expect(uri.toString(), 'https://huggingface.co/org/repo/resolve/main/model.gguf');
    });

    test('normalizes host aliases to huggingface.co', () {
      for (final host in ['www.huggingface.co', 'hf.co']) {
        final uri = canonicalizeHuggingFaceUrl(
          'https://$host/org/repo/resolve/main/model.gguf',
        );
        expect(uri.host, 'huggingface.co');
      }
    });

    test('rejects http scheme', () {
      expect(
        () => canonicalizeHuggingFaceUrl(
          'http://huggingface.co/org/repo/resolve/main/model.gguf',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('adds https scheme when missing', () {
      final uri = canonicalizeHuggingFaceUrl(
        'org/repo/resolve/main/model.gguf',
      );
      expect(uri.toString(), 'https://huggingface.co/org/repo/resolve/main/model.gguf');
    });

    test('percent-decodes segments for stability', () {
      final a = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/my%20repo/resolve/main/my%20model.gguf',
      );
      final b = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/my repo/resolve/main/my model.gguf',
      );
      expect(a, equals(b));
    });

    test('rejects non-huggingface hosts', () {
      expect(
        () => canonicalizeHuggingFaceUrl('https://example.com/model.gguf'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty input', () {
      expect(
        () => canonicalizeHuggingFaceUrl(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('only rewrites blob at action position (segment 3)', () {
      // 'blob' appearing later in the path should not be rewritten.
      final uri = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/repo/resolve/main/blob/model.gguf',
      );
      expect(uri.toString(), 'https://huggingface.co/org/repo/resolve/main/blob/model.gguf');
    });

    test('equivalent forms canonicalize identically', () {
      final a = canonicalizeHuggingFaceUrl(
        'https://huggingface.co/org/repo/blob/main/model.gguf?download=1',
      );
      final b = canonicalizeHuggingFaceUrl(
        'https://hf.co/org/repo/resolve/main/model.gguf',
      );
      expect(a, equals(b));
    });
  });
}
