import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelSource', () {
    test('path remains local and does not attempt network resolution', () {
      final source = ModelSource.path('/local/model.gguf');

      expect(source.kind, ModelSourceKind.path);
      expect(source.isLocal, isTrue);
      expect(source.isRemote, isFalse);
      expect(source.path, '/local/model.gguf');
      expect(source.resolvedUri, isNull);
      expect(source.fileName, 'model.gguf');
      expect(source.canonicalKey, 'path:/local/model.gguf');
    });

    test('https URI resolves as HTTP with inferred file name', () {
      final source = ModelSource.url(
        Uri.parse('https://host/path/model.gguf?download=true'),
      );

      expect(source.kind, ModelSourceKind.http);
      expect(source.isRemote, isTrue);
      expect(
        source.resolvedUri,
        Uri.parse('https://host/path/model.gguf?download=true'),
      );
      expect(source.fileName, 'model.gguf');
      expect(source.canonicalKey, 'https://host/path/model.gguf?download=true');
      expect(source.metadataSourceKey, isNot(contains('download=true')));
      expect(source.toString(), isNot(contains('download=true')));
    });

    test(
      'explicit URL file names are decoded and included in cache identity',
      () {
        final first = ModelSource.url(
          Uri.parse('https://host/path/model.gguf?download=true'),
          fileName: 'model%2Egguf',
        );
        final second = ModelSource.url(
          Uri.parse('https://host/path/model.gguf?download=true'),
          fileName: 'renamed.gguf',
        );

        expect(first.fileName, 'model.gguf');
        expect(first.canonicalKey, contains('fileName:model.gguf'));
        expect(second.canonicalKey, contains('fileName:renamed.gguf'));
        expect(first.cacheKey, isNot(second.cacheKey));
      },
    );

    test('http URLs require an authority and host', () {
      expect(
        () => ModelSource.url(Uri.parse('https:model.gguf')),
        throwsArgumentError,
      );
      expect(() => ModelSource.parse('https:model.gguf'), throwsArgumentError);
    });

    test('remote explicit file names reject traversal and separators', () {
      final invalidNames = <String>[
        '',
        '.',
        '..',
        '../x.gguf',
        'dir/x.gguf',
        r'dir\\x.gguf',
        '/x.gguf',
        r'\\x.gguf',
        '%2e',
        '%2e%2e',
        '..%2Fx.gguf',
        'dir%2Fx.gguf',
        r'dir%5Cx.gguf',
        'bad<name.gguf',
        'bad>name.gguf',
        'bad:name.gguf',
        'bad%22name.gguf',
        'bad|name.gguf',
        'bad?name.gguf',
        'bad*name.gguf',
        'bad%00name.gguf',
      ];

      for (final fileName in invalidNames) {
        expect(
          () => ModelSource.url(
            Uri.parse('https://host/model.gguf'),
            fileName: fileName,
          ),
          throwsArgumentError,
          reason: 'url fileName=$fileName',
        );
        expect(
          () => ModelSource.huggingFace(
            repoId: 'owner/repo',
            filePath: 'model.gguf',
            fileName: fileName,
          ),
          throwsArgumentError,
          reason: 'hf fileName=$fileName',
        );
      }
    });

    test('inferred URL file names reject encoded traversal and separators', () {
      final invalidUrls = <String>[
        'https://host/',
        'https://host/.',
        'https://host/..',
        'https://host/%2e',
        'https://host/%2e%2e',
        'https://host/dir%2Fx.gguf',
        'https://host/dir%5Cx.gguf',
        'https://host/%2e%2e%2Fx.gguf',
        'https://host/bad:name.gguf',
        'https://host/bad%22name.gguf',
        'https://host/bad%7Cname.gguf',
        'https://host/bad*name.gguf',
      ];

      for (final value in invalidUrls) {
        expect(
          () => ModelSource.url(Uri.parse(value)),
          throwsArgumentError,
          reason: value,
        );
      }
    });

    test('hf URI resolves to Hugging Face main download URL', () {
      final source = ModelSource.parse(
        'hf://unsloth/Qwen3.5-0.8B-GGUF/Qwen3.5-0.8B-Q4_K_M.gguf',
      );

      expect(source.kind, ModelSourceKind.huggingFace);
      expect(source.repoId, 'unsloth/Qwen3.5-0.8B-GGUF');
      expect(source.revision, 'main');
      expect(source.filePath, 'Qwen3.5-0.8B-Q4_K_M.gguf');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf?download=true',
        ),
      );
      expect(source.fileName, 'Qwen3.5-0.8B-Q4_K_M.gguf');
      expect(
        source.canonicalKey,
        'hf://unsloth/Qwen3.5-0.8B-GGUF@main/Qwen3.5-0.8B-Q4_K_M.gguf',
      );
    });

    test('hf URI supports LiteRT-LM bundle file names', () {
      final source = ModelSource.parse(
        'hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm',
      );

      expect(source.kind, ModelSourceKind.huggingFace);
      expect(source.repoId, 'litert-community/gemma-4-E2B-it-litert-lm');
      expect(source.revision, 'main');
      expect(source.filePath, 'gemma-4-E2B-it.litertlm');
      expect(source.fileName, 'gemma-4-E2B-it.litertlm');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true',
        ),
      );
      expect(
        source.canonicalKey,
        'hf://litert-community/gemma-4-E2B-it-litert-lm@main/gemma-4-E2B-it.litertlm',
      );
      expect(source.cacheDirectoryName, startsWith('gemma-4-E2B-it-'));
    });

    test('hf URI resolves explicit revision and nested file path', () {
      final source = ModelSource.parse(
        'hf://owner/repo@rev/sub/dir/model.gguf',
      );

      expect(source.repoId, 'owner/repo');
      expect(source.revision, 'rev');
      expect(source.filePath, 'sub/dir/model.gguf');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/rev/sub/dir/model.gguf?download=true',
        ),
      );
      expect(source.fileName, 'model.gguf');
      expect(source.canonicalKey, 'hf://owner/repo@rev/sub/dir/model.gguf');
    });

    test('hf URI accepts revision query for branch names with slashes', () {
      final source = ModelSource.parse(
        'hf://owner/repo/sub/dir/model.gguf?revision=refs/pr/12',
      );

      expect(source.repoId, 'owner/repo');
      expect(source.revision, 'refs/pr/12');
      expect(source.filePath, 'sub/dir/model.gguf');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/refs%2Fpr%2F12/sub/dir/model.gguf?download=true',
        ),
      );
      expect(source.fileName, 'model.gguf');
      expect(
        source.canonicalKey,
        'hf://owner/repo/sub/dir/model.gguf?revision=refs%2Fpr%2F12',
      );
      expect(source.metadataSourceKey, isNot(contains('refs/pr/12')));
    });

    test('hf URI accepts encoded slash revision query', () {
      final source = ModelSource.parse(
        'hf://owner/repo/model.gguf?revision=refs%2Fpr%2F12',
      );

      expect(source.revision, 'refs/pr/12');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/refs%2Fpr%2F12/model.gguf?download=true',
        ),
      );
    });

    test('factory encodes revision path separators in resolved URL', () {
      final source = ModelSource.huggingFace(
        repoId: 'owner/repo',
        revision: 'refs/pr/12',
        filePath: 'model.gguf',
      );

      expect(source.revision, 'refs/pr/12');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/refs%2Fpr%2F12/model.gguf?download=true',
        ),
      );
      expect(
        source.canonicalKey,
        'hf://owner/repo/model.gguf?revision=refs%2Fpr%2F12',
      );
    });

    test('slash-containing revisions produce unambiguous cache identities', () {
      final queryRevisionSource = ModelSource.parse(
        'hf://owner/repo/model.gguf?revision=a/b',
      );
      final inlineRevisionSource = ModelSource.parse(
        'hf://owner/repo@a/b/model.gguf',
      );

      expect(queryRevisionSource.revision, 'a/b');
      expect(queryRevisionSource.filePath, 'model.gguf');
      expect(
        queryRevisionSource.canonicalKey,
        'hf://owner/repo/model.gguf?revision=a%2Fb',
      );
      expect(inlineRevisionSource.revision, 'a');
      expect(inlineRevisionSource.filePath, 'b/model.gguf');
      expect(
        inlineRevisionSource.canonicalKey,
        'hf://owner/repo@a/b/model.gguf',
      );
      expect(
        queryRevisionSource.canonicalKey,
        isNot(inlineRevisionSource.canonicalKey),
      );
      expect(
        queryRevisionSource.cacheKey,
        isNot(inlineRevisionSource.cacheKey),
      );
    });

    test('delimiter revisions use query-form canonical keys', () {
      final source = ModelSource.huggingFace(
        repoId: 'owner/repo',
        revision: 'release@v1',
        filePath: 'model.gguf',
      );

      expect(source.revision, 'release@v1');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/release%40v1/model.gguf?download=true',
        ),
      );
      expect(
        source.canonicalKey,
        'hf://owner/repo/model.gguf?revision=release%40v1',
      );

      final reparsed = ModelSource.parse(source.canonicalKey);
      expect(reparsed.revision, source.revision);
      expect(reparsed.filePath, source.filePath);
      expect(reparsed.canonicalKey, source.canonicalKey);
    });

    test('delimiter file paths use encoded query-form canonical keys', () {
      final source = ModelSource.parse('hf://owner/repo/nested/model@q4.gguf');

      expect(source.filePath, 'nested/model@q4.gguf');
      expect(
        source.canonicalKey,
        'hf://owner/repo/nested/model%40q4.gguf?revision=main',
      );

      final reparsed = ModelSource.parse(source.canonicalKey);
      expect(reparsed.revision, source.revision);
      expect(reparsed.filePath, source.filePath);
      expect(reparsed.canonicalKey, source.canonicalKey);
    });

    test('hf URI revision query preserves literal plus signs', () {
      final source = ModelSource.parse(
        'hf://owner/repo/model.gguf?revision=release+cuda',
      );

      expect(source.revision, 'release+cuda');
      expect(
        source.resolvedUri,
        Uri.parse(
          'https://huggingface.co/owner/repo/resolve/release%2Bcuda/model.gguf?download=true',
        ),
      );
    });

    test('hf URI rejects ambiguous or unsupported revision query syntax', () {
      final invalidValues = <String>[
        'hf://owner/repo@main/model.gguf?revision=dev',
        'hf://owner/repo/model.gguf?revision=',
        'hf://owner/repo/model.gguf?revision=main&revision=dev',
        'hf://owner/repo/model.gguf?download=true',
        'hf://owner/repo/model.gguf?',
        'hf://owner/repo/model.gguf?revision=bad%ZZ',
        'hf://owner/repo/model.gguf?revision=main%0Ainjected',
        'hf://owner/repo/model.gguf?revision=main%0Dinjected',
        'hf://owner/repo/model.gguf?revision=main%09injected',
        'hf://owner/repo/model.gguf?revision=foo%5Cbar',
        'hf://owner/repo/model.gguf?revision=foo//bar',
        'hf://owner/repo/model.gguf?revision=foo/',
        'hf://owner/repo/model.gguf?revision=foo%20bar',
      ];

      for (final value in invalidValues) {
        expect(
          () => ModelSource.parse(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });

    test('parse accepts local paths as explicit convenience', () {
      final source = ModelSource.parse('/local/model.gguf');

      expect(source.kind, ModelSourceKind.path);
      expect(source.path, '/local/model.gguf');
      expect(source.resolvedUri, isNull);
    });

    test('parse rejects invalid schemes', () {
      expect(
        () => ModelSource.parse('ftp://host/model.gguf'),
        throwsArgumentError,
      );
    });

    test('rejects invalid Hugging Face references', () {
      final invalidValues = <String>[
        'hf://owner/repo',
        'hf://owner',
        'hf://owner//model.gguf',
        'hf://owner/repo/../model.gguf',
        'hf://owner/repo//absolute.gguf',
        'hf://owner/repo/%2e%2e/model.gguf',
        'hf://owner/repo/sub/%2E%2E/model.gguf',
        'hf://owner/repo/dir%2Fx.gguf',
        r'hf://owner/repo/dir%5Cx.gguf',
        'hf://owner/repo/bad%/model.gguf',
        'hf://owner/repo/bad%ZZ/model.gguf',
      ];

      for (final value in invalidValues) {
        expect(
          () => ModelSource.parse(value),
          throwsArgumentError,
          reason: value,
        );
      }
    });

    test('canonical sources produce stable deterministic cache keys', () {
      final source = ModelSource.huggingFace(
        repoId: 'owner/repo',
        filePath: 'sub/model.gguf',
      );
      final equivalent = ModelSource.parse('hf://owner/repo/sub/model.gguf');
      final differentRevision = ModelSource.parse(
        'hf://owner/repo@other/sub/model.gguf',
      );
      final differentPath = ModelSource.parse('hf://owner/repo/other.gguf');

      expect(source.canonicalKey, equivalent.canonicalKey);
      expect(source.cacheKey, equivalent.cacheKey);
      expect(source.cacheDirectoryName, equivalent.cacheDirectoryName);
      expect(source.cacheKey, hasLength(64));
      expect(source.cacheDirectoryName, startsWith('model-'));
      expect(
        source.cacheDirectoryName,
        contains(source.cacheKey.substring(0, 12)),
      );
      expect(source.cacheKey, isNot(differentRevision.cacheKey));
      expect(source.cacheKey, isNot(differentPath.cacheKey));
    });

    test('resolved URI preserves canonical cache identity', () {
      final source = ModelSource.huggingFace(
        repoId: 'owner/repo',
        filePath: 'sub/model.gguf',
      );
      final resolved = source.withResolvedUri(
        Uri.parse('https://cdn.example.com/model.gguf?token=secret'),
      );

      expect(
        resolved.resolvedUri,
        Uri.parse('https://cdn.example.com/model.gguf?token=secret'),
      );
      expect(resolved.fileName, source.fileName);
      expect(resolved.canonicalKey, source.canonicalKey);
      expect(resolved.cacheKey, source.cacheKey);
      expect(resolved.cacheDirectoryName, source.cacheDirectoryName);
    });
  });
}
