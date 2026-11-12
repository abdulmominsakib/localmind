import 'package:llamadart/llamadart.dart' as llama;

Map<String, dynamic> generationConfigSchema() {
  Map<String, dynamic> integer({int minimum = 0}) => {
    'type': ['integer', 'null'],
    'minimum': minimum,
    'maximum': 2147483647,
  };
  const string = {
    'type': ['string', 'null'],
  };
  const boolean = {
    'type': ['boolean', 'null'],
  };
  const number = {
    'type': ['number', 'null'],
  };
  Map<String, dynamic> sourceSchema(
    String kind,
    List<String> required,
    List<String> fields,
  ) => {
    'type': 'object',
    'additionalProperties': false,
    'required': ['kind', ...required],
    'properties': {
      'kind': {'const': kind},
      'format': {
        'enum': [null, ...llama.ModelFormat.values.map((v) => v.name)],
      },
      for (final key in fields) key: {'type': 'string', 'minLength': 1},
    },
  };
  return {
    'type': 'object',
    'properties': {
      for (final key in [
        'temperature',
        'topP',
        'minP',
        'penalty',
        'presencePenalty',
      ])
        key: number,
      for (final key in ['topK', 'maxTokens', 'seed'])
        key: {
          'type': ['integer', 'null'],
        },
      'stop': {
        'type': ['array', 'null'],
        'items': {'type': 'string'},
      },
      for (final key in [
        'enableThinking',
        'parallelToolCalls',
        'speculativeDecoding',
        'reusePromptPrefix',
      ])
        key: boolean,
      for (final key in ['sourceLangCode', 'targetLangCode']) key: string,
      'chatTemplateKwargs': {
        'type': ['object', 'null'],
      },
      for (final key in [
        'streamBatchTokenThreshold',
        'streamBatchByteThreshold',
      ])
        key: integer(minimum: 1),
      'thinkingBudget': {
        'type': ['object', 'null'],
        'additionalProperties': false,
        'required': ['maxTokens'],
        'properties': {
          'maxTokens': {...integer(), 'type': 'integer'},
          for (final key in ['startTag', 'endTag', 'forcedMessage'])
            key: string,
        },
      },
      'speculativeDecodingConfig': {
        'type': ['object', 'null'],
        'additionalProperties': false,
        'required': ['strategies'],
        'properties': {
          'strategies': {
            'type': 'array',
            'minItems': 1,
            'uniqueItems': true,
            'items': {
              'enum': llama.SpeculativeDecodingStrategy.values
                  .map((v) => v.name)
                  .toList(),
            },
          },
          for (final key in [
            'draftTokenMax',
            'draftTokenMin',
            'ngramTokenMin',
            'ngramTokenMax',
          ])
            key: integer(),
          for (final key in [
            'ngramSize',
            'ngramSizeN',
            'ngramSizeM',
            'ngramMinHits',
            'ngramMatch',
            'draftMicroBatchSize',
          ])
            key: integer(minimum: 1),
          for (final key in ['minProbability', 'draftSplitProbability'])
            key: {...number, 'minimum': 0, 'maximum': 1},
          for (final key in ['ngramCacheStaticPath', 'ngramCacheDynamicPath'])
            key: string,
          'draftModel': {
            'oneOf': [
              sourceSchema('path', ['path'], ['path']),
              sourceSchema('http', ['url'], ['url', 'fileName']),
              sourceSchema(
                'huggingFace',
                ['repoId', 'filePath'],
                ['repoId', 'filePath', 'revision', 'fileName'],
              ),
              {'type': 'null'},
            ],
          },
          'draftModelDownload': {
            'type': ['object', 'null'],
            'additionalProperties': false,
            'properties': {
              'cachePolicy': {
                'enum': [null, 'preferCached', 'cacheOnly'],
              },
              'cacheDirectory': string,
              'sha256': string,
              'resume': boolean,
              'maxRetries': integer(),
            },
          },
        },
      },
    },
  };
}
