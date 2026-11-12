import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelFormat.fromHeader', () {
    test('recognizes the GGUF and LiteRT-LM magic', () {
      expect(
        ModelFormat.fromHeader('GGUF\x03\x00\x00\x00'.codeUnits),
        ModelFormat.gguf,
      );
      expect(
        ModelFormat.fromHeader('LITERTLM\x01\x00'.codeUnits),
        ModelFormat.liteRtLm,
      );
    });

    test('returns null for short, empty or unknown headers', () {
      expect(ModelFormat.fromHeader(const []), isNull);
      expect(ModelFormat.fromHeader('GGU'.codeUnits), isNull);
      expect(ModelFormat.fromHeader('LITERT'.codeUnits), isNull);
      expect(ModelFormat.fromHeader('PK\x03\x04TFL3'.codeUnits), isNull);
      expect(ModelFormat.fromHeader('gguf'.codeUnits), isNull);
    });

    test('headerLength covers the longest magic', () {
      expect(ModelFormat.headerLength, 'LITERTLM'.length);
    });
  });

  group('ModelFormat.fromPath', () {
    test('reads model extensions case-insensitively', () {
      expect(ModelFormat.fromPath('/models/a.gguf'), ModelFormat.gguf);
      expect(ModelFormat.fromPath('/models/A.LITERTLM'), ModelFormat.liteRtLm);
      expect(
        ModelFormat.fromPath(r'C:\models\a.litertlm'),
        ModelFormat.liteRtLm,
      );
    });

    test('returns null without a model extension', () {
      expect(ModelFormat.fromPath('/models/download'), isNull);
      expect(ModelFormat.fromPath('/models/model.bin'), isNull);
      expect(ModelFormat.fromPath('https://host/download?id=42'), isNull);
    });

    test('ignores a URL query and fragment', () {
      expect(
        ModelFormat.fromPath('https://host/m.litertlm?download=true#x'),
        ModelFormat.liteRtLm,
      );
      expect(ModelFormat.fromPath('https://host/download?f=m.gguf'), isNull);
      expect(
        ModelFormat.fromPath('blob:https://host/m.gguf'),
        ModelFormat.gguf,
      );
    });

    test('reads a local path literally', () {
      expect(ModelFormat.fromPath('/models/a#b/c.gguf'), ModelFormat.gguf);
      expect(
        ModelFormat.fromPath('/models/100%#?.litertlm'),
        ModelFormat.liteRtLm,
      );
    });

    test('ignores the query of a relative URL', () {
      expect(
        ModelFormat.fromPath('models/a.litertlm?download=true'),
        ModelFormat.liteRtLm,
      );
    });
  });

  test('maps each format to its runtime', () {
    expect(ModelFormat.gguf.runtime, LlamaRuntime.llamaCpp);
    expect(ModelFormat.liteRtLm.runtime, LlamaRuntime.liteRtLm);
    expect(ModelFormat.liteRtLm.extension, '.litertlm');
  });
}
