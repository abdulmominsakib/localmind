import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:schemantic/schemantic.dart';

import '../../../api/media_model.dart';

Map<String, dynamic> mediaConfigSchema(LlamaDartMediaModel model) {
  Map<String, dynamic> integer(int min, int max) => {
    'type': 'integer',
    'minimum': min,
    'maximum': max,
  };
  Map<String, dynamic> number(num min, num max) => {
    'type': 'number',
    'minimum': min,
    'maximum': max,
  };
  const string = {'type': 'string', 'minLength': 1, 'maxLength': 16384};
  return {
    'type': 'object',
    'additionalProperties': false,
    'properties': switch (model) {
      LlamaDartSpeechToTextModel() => {
        'contextPrompt': string,
        'languageHint': string,
        'maxOutputTokens': integer(1, 16384),
      },
      LlamaDartTextToSpeechModel() => {
        'language': string,
        'maxFrames': integer(1, 8192),
        'promptBatchSize': integer(1, 8192),
        'topK': integer(1, 100000),
        'topP': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 1},
        'minP': number(0, 1),
        'temperature': number(0, 10),
        'seed': integer(0, 0xffffffff),
      },
      LlamaDartImageModel() => {
        'negativePrompt': {'type': 'string', 'maxLength': 16384},
        'width': {...integer(64, 2048), 'multipleOf': 8},
        'height': {...integer(64, 2048), 'multipleOf': 8},
        'steps': integer(1, 150),
        'guidanceScale': number(0, 30),
        'seed': integer(0, 0x7fffffff),
        'count': integer(1, 16),
        'sampler': {
          'type': 'string',
          'enum': [
            for (final value in llama.ImageGenerationSampler.values) value.name,
          ],
        },
        'scheduler': {
          'type': 'string',
          'enum': [
            for (final value in llama.ImageGenerationScheduler.values)
              value.name,
          ],
        },
        'flowShift': {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 100},
      },
    },
  };
}

Future<Map<String, dynamic>> validateMediaConfig(
  LlamaDartMediaModel model,
  Map<String, dynamic>? config,
) async {
  final values = config ?? <String, dynamic>{};
  final definition = mediaConfigSchema(model);
  final properties = definition['properties'] as Map;
  final schema = SchemanticType.from(
    jsonSchema: definition,
    parse: (value) => value,
  );
  if (values.entries.any(
        (entry) =>
            properties[entry.key]?['type'] == 'integer' && entry.value is! int,
      ) ||
      values.values.any((value) => value is num && !value.isFinite) ||
      (await schema.validate(values)).isNotEmpty) {
    throw genkit.GenkitException(
      'Invalid media model configuration. Use only the documented options and ranges.',
      status: genkit.StatusCode.invalidArgument,
    );
  }
  return values;
}
