import 'dart:convert';

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/integration/genkit/generation_config_schema.dart';
import 'package:test/test.dart';

void main() {
  test('thinking and worker controls survive a JSON transport round trip', () {
    const config = LlamaDartGenerationConfig(
      presencePenalty: 2,
      thinkingBudget: ThinkingBudget(
        maxTokens: 32,
        startTag: '<think>',
        endTag: '</think>',
        forcedMessage: 'finish',
      ),
      reusePromptPrefix: false,
      streamBatchTokenThreshold: 1,
      streamBatchByteThreshold: 64,
    );
    final map = jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
    expect(map, {
      'presencePenalty': 2.0,
      'thinkingBudget': {
        'maxTokens': 32,
        'startTag': '<think>',
        'endTag': '</think>',
        'forcedMessage': 'finish',
      },
      'reusePromptPrefix': false,
      'streamBatchTokenThreshold': 1,
      'streamBatchByteThreshold': 64,
    });
    expect(LlamaDartGenerationConfig.fromJson(map).toJson(), map);
    expect(const LlamaDartGenerationConfig().toJson(), isEmpty);
  });

  test('every speculative tuning value and source kind round trips', () {
    for (final source in [
      ModelSource.path('/models/draft.gguf', format: ModelFormat.gguf),
      ModelSource.url(
        Uri.parse('https://example.test/model'),
        fileName: 'draft.gguf',
        format: ModelFormat.gguf,
      ),
      ModelSource.huggingFace(
        repoId: 'owner/repo',
        filePath: 'draft.gguf',
        revision: 'refs/pr/12',
      ),
    ]) {
      final config = LlamaDartGenerationConfig(
        speculativeDecoding: false,
        speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
          strategies: [
            SpeculativeDecodingStrategy.draftSimple,
            SpeculativeDecodingStrategy.ngramSimple,
          ],
          draftTokenMax: 8,
          draftTokenMin: 2,
          minProbability: 0.5,
          draftSplitProbability: 0.2,
          draftMicroBatchSize: 64,
          draftModel: source,
          draftModelDownload: ModelLoadOptions(sha256: 'a' * 64),
          ngramSize: 3,
          ngramSizeN: 4,
          ngramSizeM: 5,
          ngramMinHits: 2,
          ngramMatch: 6,
          ngramTokenMin: 1,
          ngramTokenMax: 7,
          ngramCacheStaticPath: '/cache/static',
          ngramCacheDynamicPath: '/cache/dynamic',
        ),
      );
      final map =
          jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>;
      final spec = map['speculativeDecodingConfig'] as Map;
      expect(spec, containsPair('strategies', ['draftSimple', 'ngramSimple']));
      expect(spec['draftTokenMax'], 8);
      expect(spec['draftTokenMin'], 2);
      expect(spec['minProbability'], 0.5);
      expect(spec['draftSplitProbability'], 0.2);
      expect(spec['draftMicroBatchSize'], 64);
      expect(spec['ngramSize'], 3);
      expect(spec['ngramSizeN'], 4);
      expect(spec['ngramSizeM'], 5);
      expect(spec['ngramMinHits'], 2);
      expect(spec['ngramMatch'], 6);
      expect(spec['ngramTokenMin'], 1);
      expect(spec['ngramTokenMax'], 7);
      expect(spec['ngramCacheStaticPath'], '/cache/static');
      expect(spec['ngramCacheDynamicPath'], '/cache/dynamic');
      expect(spec['draftModelDownload'], containsPair('sha256', 'a' * 64));
      final decoded = LlamaDartGenerationConfig.fromJson(map);
      expect(decoded.toJson(), map);
      expect(
        decoded.speculativeDecodingConfig!.draftModel!.canonicalKey,
        source.canonicalKey,
      );
      expect(
        decoded.speculativeDecodingConfig!.draftModel!.fileName,
        source.fileName,
      );
      expect(
        decoded.speculativeDecodingConfig!.draftModel!.format,
        source.format,
      );
    }
  });

  test('speculative codec keys match the published generation schema', () {
    final config = LlamaDartGenerationConfig(
      speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
        strategies: [
          SpeculativeDecodingStrategy.draftSimple,
          SpeculativeDecodingStrategy.ngramSimple,
        ],
        draftTokenMax: 8,
        draftTokenMin: 2,
        minProbability: 0.5,
        draftSplitProbability: 0.2,
        draftMicroBatchSize: 64,
        draftModel: ModelSource.path('/models/draft.gguf'),
        ngramSize: 3,
        ngramSizeN: 4,
        ngramSizeM: 5,
        ngramMinHits: 2,
        ngramMatch: 6,
        ngramTokenMin: 1,
        ngramTokenMax: 7,
        ngramCacheStaticPath: '/cache/static',
        ngramCacheDynamicPath: '/cache/dynamic',
      ),
    );
    final emitted = (config.toJson()['speculativeDecodingConfig'] as Map).keys
        .toSet();
    final schema =
        (generationConfigSchema()['properties']
                as Map)['speculativeDecodingConfig']
            as Map;
    expect((schema['properties'] as Map).keys.toSet(), containsAll(emitted));
    expect(schema['additionalProperties'], false);
  });

  final invalid = <Map<String, dynamic>>[
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftMicroBatchSize': 0,
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftMicroBatchSize': 1.5,
      },
    },
    {'presencePenalty': double.nan},
    {
      'speculativeDecodingConfig': {
        'strategies': ['ngramCache'],
        'ngramCacheStaticPath': '/cache?token=AUDIT_SECRET',
      },
    },
    {'presencePenalty': '2'},
    {'streamBatchTokenThreshold': 0},
    {'streamBatchByteThreshold': 1.5},
    {'reusePromptPrefix': 'false'},
    {'speculativeDecoding': 1},
    {'thinkingBudget': []},
    {
      'thinkingBudget': {'maxTokens': -1},
    },
    {
      'thinkingBudget': {'maxTokens': 2147483648},
    },
    {
      'thinkingBudget': {'maxTokens': 1, 'startTag': ''},
    },
    {
      'thinkingBudget': {'maxTokens': 1, 'token': 'AUDIT_SECRET'},
    },
    {
      'speculativeDecodingConfig': {'strategies': []},
    },
    {
      'speculativeDecodingConfig': {
        'strategies': [null],
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['unknown'],
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['mtp', 'mtp'],
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['backendDefault', 'mtp'],
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['ngramSimple'],
        'minProbability': 2,
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['ngramMod'],
        'ngramTokenMin': 4,
        'ngramTokenMax': 2,
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftModelPath': '/secret',
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftModel': {
          'kind': 'http',
          'url': 'https://host/model?token=AUDIT_SECRET',
        },
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftModel': {'kind': 'path', 'path': '/model?token=AUDIT_SECRET'},
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftModel': {'kind': 'path', 'path': '/model', 'url': 'secret'},
      },
    },
    {
      'speculativeDecodingConfig': {
        'strategies': ['draftSimple'],
        'draftModelDownload': {'bearerToken': 'AUDIT_SECRET'},
      },
    },
  ];
  test('malformed controls fail without echoing request values', () {
    for (final map in invalid) {
      expect(
        () => LlamaDartGenerationConfig.fromJson(map),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('AUDIT_SECRET')),
          ),
        ),
      );
    }
  });

  test('typed credential-bearing draft options cannot enter Genkit traces', () {
    for (final options in [
      ModelLoadOptions(bearerToken: 'AUDIT_SECRET'),
      ModelLoadOptions(headers: {'Authorization': 'AUDIT_SECRET'}),
      ModelLoadOptions(cancelToken: ModelDownloadCancelToken()),
    ]) {
      final config = LlamaDartGenerationConfig(
        speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
          draftModel: ModelSource.path('/models/draft.gguf'),
          draftModelDownload: options,
        ),
      );
      expect(
        config.toJson,
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe error',
            isNot(contains('AUDIT_SECRET')),
          ),
        ),
      );
    }
    final altered = LlamaDartGenerationConfig(
      speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
        draftModel: ModelSource.huggingFace(
          repoId: 'owner/repo',
          filePath: 'draft.gguf',
        ).withResolvedUri(Uri.parse('https://host/model?token=AUDIT_SECRET')),
      ),
    );
    expect(
      altered.toJson,
      throwsA(
        isA<FormatException>().having(
          (e) => e.toString(),
          'safe error',
          isNot(contains('AUDIT_SECRET')),
        ),
      ),
    );
    final signed = LlamaDartGenerationConfig(
      speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
        draftModel: ModelSource.url(
          Uri.parse('https://host/model?token=AUDIT_SECRET'),
        ),
      ),
    );
    expect(
      signed.toJson,
      throwsA(
        isA<FormatException>().having(
          (e) => e.toString(),
          'safe error',
          isNot(contains('AUDIT_SECRET')),
        ),
      ),
    );
  });
}
