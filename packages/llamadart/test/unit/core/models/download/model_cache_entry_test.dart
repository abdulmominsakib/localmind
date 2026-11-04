import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelDownloadProgress', () {
    test('fraction is null when total bytes is null or zero', () {
      expect(
        const ModelDownloadProgress(
          receivedBytes: 10,
          totalBytes: null,
        ).fraction,
        isNull,
      );
      expect(
        const ModelDownloadProgress(receivedBytes: 10, totalBytes: 0).fraction,
        isNull,
      );
    });

    test('fraction clamps to zero through one', () {
      expect(
        const ModelDownloadProgress(
          receivedBytes: -10,
          totalBytes: 100,
        ).fraction,
        0,
      );
      expect(
        const ModelDownloadProgress(
          receivedBytes: 50,
          totalBytes: 100,
        ).fraction,
        0.5,
      );
      expect(
        const ModelDownloadProgress(
          receivedBytes: 150,
          totalBytes: 100,
        ).fraction,
        1,
      );
      expect(const ModelDownloadProgress.fraction(-0.5).fraction, 0);
      expect(const ModelDownloadProgress.fraction(0.25).fraction, 0.25);
      expect(const ModelDownloadProgress.fraction(2).fraction, 1);
    });
  });

  group('ModelCacheEntry', () {
    test('toJson and fromJson round-trip all fields', () {
      final entry = ModelCacheEntry(
        sourceCanonicalKey: 'hf://owner/repo@main/model.gguf',
        cacheKey: 'abc123',
        fileName: 'model.gguf',
        filePath: '/cache/model.gguf',
        bytes: 1234,
        sha256: 'def456',
        etag: 'etag-value',
        lastModified: 'Wed, 21 Oct 2015 07:28:00 GMT',
        createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
        updatedAt: DateTime.utc(2026, 1, 3, 3, 4, 5),
        expiresAt: DateTime.utc(2026, 2, 3, 3, 4, 5),
      );

      final decoded = ModelCacheEntry.fromJson(entry.toJson());

      expect(decoded.sourceCanonicalKey, entry.sourceCanonicalKey);
      expect(decoded.cacheKey, entry.cacheKey);
      expect(decoded.fileName, entry.fileName);
      expect(decoded.filePath, entry.filePath);
      expect(decoded.bytes, entry.bytes);
      expect(decoded.sha256, entry.sha256);
      expect(decoded.etag, entry.etag);
      expect(decoded.lastModified, entry.lastModified);
      expect(decoded.createdAt, entry.createdAt);
      expect(decoded.updatedAt, entry.updatedAt);
      expect(decoded.expiresAt, entry.expiresAt);
      expect(decoded.toJson(), entry.toJson());
    });

    test('missing optional JSON fields do not crash parsing', () {
      final decoded = ModelCacheEntry.fromJson(const <String, Object?>{
        'source_canonical_key': 'path:/models/model.gguf',
        'cache_key': 'abc123',
        'file_name': 'model.gguf',
        'file_path': '/models/model.gguf',
        'created_at': '2026-01-02T03:04:05.000Z',
        'updated_at': '2026-01-03T03:04:05.000Z',
      });

      expect(decoded.bytes, isNull);
      expect(decoded.sha256, isNull);
      expect(decoded.etag, isNull);
      expect(decoded.lastModified, isNull);
      expect(decoded.expiresAt, isNull);
    });

    test('toJson redacts credential-bearing URL source keys', () {
      final source = ModelSource.url(
        Uri.parse(
          'https://user:secret@host/model.gguf?token=secret&download=1',
        ),
      );
      final entry = ModelCacheEntry(
        sourceCanonicalKey: source.canonicalKey,
        cacheKey: source.cacheKey,
        fileName: source.fileName,
        filePath: '/cache/model.gguf',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final encoded = jsonEncode(entry.toJson());

      expect(encoded, isNot(contains('secret')));
      expect(encoded, isNot(contains('user:secret')));
      expect(encoded, isNot(contains('token=secret')));
      expect(encoded, isNot(contains(source.canonicalKey)));
      expect(entry.sourceCanonicalKey, source.metadataSourceKey);
      expect(entry.cacheKey, source.cacheKey);
    });

    test('toJson redacts url-prefixed credential-bearing source keys', () {
      final entry = ModelCacheEntry(
        sourceCanonicalKey:
            'url:https://user:secret@host/model.gguf?token=secret#fragment',
        cacheKey: 'abc123',
        fileName: 'model.gguf',
        filePath: '/cache/model.gguf',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final encoded = jsonEncode(entry.toJson());

      expect(encoded, isNot(contains('secret')));
      expect(encoded, isNot(contains('token=secret')));
      expect(
        entry.sourceCanonicalKey,
        'url:https://host/model.gguf#cacheKey=abc123',
      );
    });

    test('toJson redacts url canonical keys with explicit file names', () {
      final entry = ModelCacheEntry(
        sourceCanonicalKey:
            'url:https://user:secret@host/model.gguf?token=secret\nfileName:model.gguf',
        cacheKey: 'abc123',
        fileName: 'model.gguf',
        filePath: '/cache/model.gguf',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      final encoded = jsonEncode(entry.toJson());

      expect(encoded, isNot(contains('secret')));
      expect(encoded, isNot(contains('token=secret')));
      expect(encoded, isNot(contains('fileName:model.gguf')));
      expect(
        entry.sourceCanonicalKey,
        'url:https://host/model.gguf#cacheKey=abc123',
      );
    });

    test('normalizes percent-encoded cache file names and paths', () {
      final entry = ModelCacheEntry(
        sourceCanonicalKey: 'path:/models/model.gguf',
        cacheKey: 'abc123',
        fileName: 'model%2Egguf',
        filePath: r'C:\cache\model%2Egguf',
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 2),
      );

      expect(entry.fileName, 'model.gguf');
      expect(entry.filePath, r'C:\cache\model.gguf');
    });

    test('rejects unsafe cache file names and traversal paths', () {
      for (final fileName in <String>[
        '',
        '.',
        '..',
        '../model.gguf',
        'dir/model.gguf',
        r'dir\model.gguf',
        '%2e%2e',
        '..%2Fmodel.gguf',
        '%',
      ]) {
        expect(
          () => ModelCacheEntry(
            sourceCanonicalKey: 'path:/models/model.gguf',
            cacheKey: 'abc123',
            fileName: fileName,
            filePath: '/cache/model.gguf',
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
          throwsArgumentError,
          reason: fileName,
        );
      }

      for (final filePath in <String>[
        '',
        '/cache/../model.gguf',
        '/cache/%2e%2e/model.gguf',
        '/cache/%2e%2e%2fmodel.gguf',
        '/cache/%/model.gguf',
        r'C:\cache\..\model.gguf',
      ]) {
        expect(
          () => ModelCacheEntry(
            sourceCanonicalKey: 'path:/models/model.gguf',
            cacheKey: 'abc123',
            fileName: 'model.gguf',
            filePath: filePath,
            createdAt: DateTime.utc(2026, 1, 2),
            updatedAt: DateTime.utc(2026, 1, 2),
          ),
          throwsArgumentError,
          reason: filePath,
        );
      }
    });
  });

  group('ModelDownloadCancelToken', () {
    test('cancel is idempotent and reports cancellation', () {
      final token = ModelDownloadCancelToken();

      expect(token.isCancelled, isFalse);
      token.cancel();
      token.cancel();

      expect(token.isCancelled, isTrue);
    });
  });
}
