@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DynamicLibrary library;
  final missing = <String, DynamicLibrary>{};
  int count(String field) => library
      .lookupFunction<Int Function(), int Function()>('fixture_$field')();
  int calls(int stage) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_calls',
      )(stage);
  int samplerInt(int index) =>
      library.lookupFunction<Int Function(Int), int Function(int)>(
        'fixture_sampler_int',
      )(index);
  double samplerFloat(int index) =>
      library.lookupFunction<Float Function(Int), double Function(int)>(
        'fixture_sampler_float',
      )(index);
  String preface(int index) => library
      .lookupFunction<Pointer<Utf8> Function(Int), Pointer<Utf8> Function(int)>(
        'fixture_preface',
      )(index)
      .toDartString();
  void fail(int stage) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_fail',
      )(stage);
  LiteRtLmV1Runtime loaded([ComputeDevice device = ComputeDevice.cpu]) {
    final runtime = LiteRtLmV1Runtime(library);
    runtime.loadConfigured(
      '/secret/models/m.litertlm',
      LiteRtLmV1EngineSettings(backend: device, cacheDir: '/secret/cache'),
    );
    return runtime;
  }

  const selected = LiteRtLmV1SamplerSettings(
    temperature: 0.3,
    topK: 7,
    topP: 0.4,
    seed: 19,
  );
  Map<String, Object?> tool() => {
    'type': 'function',
    'function': {
      'name': 'weather',
      'description': 'Weather 世界',
      'parameters': {
        'type': 'object',
        'properties': {
          'city': {'type': 'string'},
        },
        'required': ['city'],
        'additionalProperties': false,
      },
    },
  };
  List<Map<String, Object?>> history() => [
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': 'Montréal?'},
      ],
    },
    {
      'role': 'assistant',
      'content': '',
      'reasoning_content': 'check',
      'tool_calls': [
        {
          'type': 'function',
          'function': {
            'name': 'weather',
            'arguments': {
              'city': 'Montréal',
              'flags': [true, null, 3],
            },
          },
        },
      ],
    },
    {
      'role': 'tool',
      'content': [
        {
          'type': 'tool_response',
          'name': 'weather',
          'response': {'celsius': 17, 'empty': []},
        },
        {
          'type': 'tool_response',
          'name': 'weather',
          'response': '{"literal":true}',
        },
      ],
    },
  ];
  LiteRtLmV1ConversationSettings full() => LiteRtLmV1ConversationSettings(
    maxOutputTokens: 19,
    sampler: selected,
    systemMessage: '{"literal":"世界"}',
    messages: history(),
    tools: [tool()],
    extraContext: {
      'enable_thinking': false,
      'now': '2026-11-02',
      'nested': {'flag': true},
    },
    promptTemplate: '{{ messages }} {{ tools }}',
  );
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'litert_conversation_config_',
    );
    for (final entry in <String, List<String>>{
      'valid': [],
      'seed': ['-DOMIT_SAMPLER_SEED'],
      'template': ['-DOMIT_PROMPT_TEMPLATE'],
    }.entries) {
      final path =
          '${directory.path}/${entry.key}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        ...entry.value,
        'test/fixtures/litert_lm/c_api_v1_conversation.c',
        '-o',
        path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      if (entry.key == 'valid') {
        library = DynamicLibrary.open(path);
      } else {
        missing[entry.key] = DynamicLibrary.open(path);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() {
    expect(count('live'), 0);
    fail(0);
  });
  tearDown(() => expect(count('live'), 0));

  test(
    'configured sampler and preface preserve roles typed values and plain system text',
    () {
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(full());
      expect(count('output_tokens'), 19);
      expect(samplerInt(0), 7);
      expect(samplerInt(1), 19);
      expect(samplerFloat(0), closeTo(0.4, 1e-6));
      expect(samplerFloat(1), closeTo(0.3, 1e-6));
      expect(jsonDecode(preface(0)), '{"literal":"世界"}');
      expect(jsonDecode(preface(1)), history());
      expect(jsonDecode(preface(2)), [tool()]);
      expect(jsonDecode(preface(3)), {
        'enable_thinking': false,
        'now': '2026-11-02',
        'nested': {'flag': true},
      });
      expect(preface(4), '{{ messages }} {{ tools }}');
      expect(count('constrained'), 0);
      expect(count('live'), 2);
      conversation.close();
      runtime.dispose();
    },
  );
  test(
    'input mutation after construction cannot change native preface snapshot',
    () {
      final messages = history(), tools = [tool()];
      final extra = <String, Object?>{
        'nested': {'keep': true},
      };
      final expectedMessages = jsonDecode(jsonEncode(messages)),
          expectedTools = jsonDecode(jsonEncode(tools));
      final settings = LiteRtLmV1ConversationSettings(
        messages: messages,
        tools: tools,
        extraContext: extra,
      );
      (messages[1]['tool_calls'] as List).clear();
      messages.clear();
      tools.clear();
      (extra['nested'] as Map)['keep'] = false;
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(settings);
      expect(jsonDecode(preface(1)), expectedMessages);
      expect(jsonDecode(preface(2)), expectedTools);
      expect(jsonDecode(preface(3)), {
        'nested': {'keep': true},
      });
      conversation.close();
      runtime.dispose();
    },
  );
  for (final topK in [0, 1, 40]) {
    test(
      'zero temperature retains TOP_P fields but forces topK one from $topK',
      () {
        final runtime = loaded();
        final conversation = runtime.openConfiguredConversation(
          LiteRtLmV1ConversationSettings(
            sampler: LiteRtLmV1SamplerSettings(
              temperature: 0,
              topK: topK,
              topP: 0.4,
              seed: -2147483648,
            ),
          ),
        );
        expect(samplerInt(0), 1);
        expect(samplerInt(1), -2147483648);
        expect(samplerFloat(0), closeTo(0.4, 1e-6));
        expect(samplerFloat(1), 0);
        conversation.close();
        runtime.dispose();
      },
    );
  }
  test('convenience wrapper retains greedy preparation defaults', () {
    final runtime = loaded();
    final conversation = runtime.openConversation();
    expect(count('output_tokens'), 32);
    expect(samplerInt(0), 1);
    expect(samplerInt(1), 0);
    expect(samplerFloat(1), 0);
    expect(samplerFloat(0), closeTo(0.95, 1e-6));
    conversation.close();
    runtime.dispose();
  });
  test('NPU inherits when sampler absent and explicitly rejects overrides', () {
    final runtime = loaded(ComputeDevice.npu);
    final before = calls(6);
    expect(
      () => runtime.openConfiguredConversation(full()),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(calls(6), before);
    final conversation = runtime.openConfiguredConversation(
      LiteRtLmV1ConversationSettings(),
    );
    expect(calls(6), before);
    conversation.close();
    runtime.dispose();
  });
  test(
    'failed replacement retains selected backend until a successful load',
    () {
      final runtime = loaded();
      fail(3);
      expect(
        () => runtime.loadConfigured(
          '/new',
          const LiteRtLmV1EngineSettings(backend: ComputeDevice.npu),
        ),
        throwsA(isA<LlamaModelException>()),
      );
      fail(0);
      runtime.openConfiguredConversation(full()).close();
      runtime.loadConfigured(
        '/new',
        const LiteRtLmV1EngineSettings(backend: ComputeDevice.npu),
      );
      expect(
        () => runtime.openConfiguredConversation(full()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      runtime
          .openConfiguredConversation(LiteRtLmV1ConversationSettings())
          .close();
      runtime.dispose();
    },
  );
  for (final stage in [
    4,
    5,
    6,
    13,
    14,
    15,
    35,
    36,
    37,
    38,
    39,
    40,
    41,
    42,
    43,
    44,
    46,
  ]) {
    test(
      'configuration status failure $stage frees all temporaries and permits fresh child',
      () {
        final runtime = loaded();
        fail(stage);
        expect(
          () => runtime.openConfiguredConversation(full()),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.message,
              'original redacted native error',
              allOf(
                contains('stage$stage'),
                isNot(contains('cleanup overwrote')),
                isNot(contains('/secret')),
              ),
            ),
          ),
        );
        expect(count('live'), 1);
        fail(0);
        runtime.openConfiguredConversation(full()).close();
        expect(runtime.generateText('recovered'), 'recovered');
        runtime.dispose();
      },
    );
  }
  for (final stage in [60, 61, 62, 63]) {
    test(
      'null success $stage releases all partial configuration and retains engine',
      () {
        final runtime = loaded();
        fail(stage);
        expect(
          () => runtime.openConfiguredConversation(full()),
          throwsA(isA<LlamaStateException>()),
        );
        expect(count('live'), 1);
        fail(0);
        runtime.openConfiguredConversation(full()).close();
        runtime.dispose();
      },
    );
  }
  test('nonzero sampler preserves disabled topK and maximum int32 seed', () {
    final runtime = loaded();
    final conversation = runtime.openConfiguredConversation(
      LiteRtLmV1ConversationSettings(
        sampler: const LiteRtLmV1SamplerSettings(
          temperature: 1,
          topK: 0,
          topP: 1,
          seed: 0x7fffffff,
        ),
      ),
    );
    expect(samplerInt(0), 0);
    expect(samplerInt(1), 0x7fffffff);
    conversation.close();
    runtime.dispose();
  });
  test(
    'string arguments and single text content object retain exact JSON types',
    () {
      final messages = <Map<String, Object?>>[
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'type': 'function',
              'function': {'name': 'f', 'arguments': '{"x":1}'},
            },
          ],
        },
        {
          'role': 'user',
          'content': {'type': 'text', 'text': 'x'},
        },
      ];
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(
          systemMessage: '',
          messages: messages,
          tools: [],
          extraContext: {},
        ),
      );
      expect(jsonDecode(preface(0)), '');
      expect(jsonDecode(preface(1)), messages);
      expect(preface(2), '[]');
      expect(preface(3), '{}');
      conversation.close();
      runtime.dispose();
    },
  );
  test(
    'nested tool descriptor schema preserves arrays unions and explicit empty values',
    () {
      final tools = <Map<String, Object?>>[
        {
          'type': 'function',
          'function': {
            'name': 'f',
            'parameters': {
              'type': 'object',
              'properties': {
                'xs': {
                  'type': 'array',
                  'items': {
                    'anyOf': [
                      {'type': 'boolean'},
                      {'type': 'null'},
                    ],
                  },
                },
                'tag': {
                  'type': ['string', 'null'],
                  'enum': ['', null],
                },
              },
              'required': [],
              'additionalProperties': {'type': 'integer'},
            },
          },
        },
      ];
      final runtime = loaded();
      final conversation = runtime.openConfiguredConversation(
        LiteRtLmV1ConversationSettings(tools: tools),
      );
      expect(jsonDecode(preface(2)), tools);
      conversation.close();
      runtime.dispose();
    },
  );

  for (final name in ['seed', 'template']) {
    test('missing $name export refuses before conversation allocation', () {
      final runtime = LiteRtLmV1Runtime(missing[name]!);
      runtime.load('/model', cacheDir: '/cache');
      expect(
        () => runtime.openConfiguredConversation(full()),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(
        missing[name]!.lookupFunction<Int Function(), int Function()>(
          'fixture_created',
        )(),
        0,
      );
      runtime.dispose();
    });
  }
  final invalidMessages = <String, List<Map<String, Object?>>>{
    'missing role': [
      {'content': 'x'},
    ],
    'unknown role': [
      {'role': 'developer', 'content': 'x'},
    ],
    'missing content': [
      {'role': 'user'},
    ],
    'numeric text': [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 9},
        ],
      },
    ],
    'untyped part': [
      {
        'role': 'user',
        'content': [
          {'text': 'x'},
        ],
      },
    ],
    'video': [
      {
        'role': 'user',
        'content': [
          {'type': 'video', 'path': '/secret/video'},
        ],
      },
    ],
    'unknown field': [
      {'role': 'user', 'content': 'x', 'secret_extra': 'secret'},
    ],
    'tool missing response': [
      {
        'role': 'tool',
        'content': [
          {'type': 'tool_response', 'name': 'f'},
        ],
      },
    ],
    'tool wrong role': [
      {
        'role': 'user',
        'content': [
          {'type': 'tool_response', 'name': 'f', 'response': null},
        ],
      },
    ],
    'empty tool name': [
      {
        'role': 'tool',
        'content': [
          {'type': 'tool_response', 'name': '', 'response': null},
        ],
      },
    ],
    'string tool result': [
      {'role': 'tool', 'content': 'x'},
    ],
    'tool calls list content': [
      {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': ''},
        ],
        'tool_calls': [],
      },
    ],
    'call missing name': [
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'type': 'function',
            'function': {'arguments': {}},
          },
        ],
      },
    ],
    'call scalar arguments': [
      {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'type': 'function',
            'function': {'name': 'f', 'arguments': 2},
          },
        ],
      },
    ],
    'reasoning wrong role': [
      {'role': 'user', 'content': 'x', 'reasoning_content': 'x'},
    ],
  };
  for (final entry in invalidMessages.entries) {
    test(
      'invalid ${entry.key} history is rejected before native allocation',
      () {
        final before = calls(4);
        expect(
          () => LiteRtLmV1ConversationSettings(messages: entry.value),
          throwsA(isA<LlamaException>()),
        );
        expect(calls(4), before);
      },
    );
  }
  for (final entry in <String, Map<String, Object?>>{
    'missing type': {
      'function': {
        'name': 'f',
        'parameters': {'type': 'object'},
      },
    },
    'missing function': {'type': 'function'},
    'missing name': {
      'type': 'function',
      'function': {
        'parameters': {'type': 'object'},
      },
    },
    'scalar parameters': {
      'type': 'function',
      'function': {'name': 'f', 'parameters': 'bad'},
    },
    'bad properties': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {'type': 'object', 'properties': []},
      },
    },
    'bad property schema': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {
          'type': 'object',
          'properties': {'x': 2},
        },
      },
    },
    'bad nested type': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {
          'type': 'object',
          'properties': {
            'x': {'type': 2},
          },
        },
      },
    },
    'bad nested items': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {
          'type': 'object',
          'properties': {
            'x': {'type': 'array', 'items': 3},
          },
        },
      },
    },
    'bad required': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {
          'type': 'object',
          'required': [1],
        },
      },
    },
    'strict request': {
      'type': 'function',
      'function': {
        'name': 'f',
        'parameters': {'type': 'object'},
        'strict': true,
      },
    },
  }.entries) {
    test(
      'invalid ${entry.key} tools are rejected before native allocation',
      () {
        expect(
          () => LiteRtLmV1ConversationSettings(tools: [entry.value]),
          throwsA(isA<LlamaException>()),
        );
      },
    );
  }
  test(
    'cycles non-JSON objects invalid numbers and raw templates are typed refusals',
    () {
      final cycle = <String, Object?>{};
      cycle['self'] = cycle;
      for (final context in [
        cycle,
        {'bad': Object()},
        {'bad': double.nan},
        {
          'bad': {1: 'secret'},
        },
      ]) {
        expect(
          () => LiteRtLmV1ConversationSettings(extraContext: context),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      for (final template in ['', 'secret\u0000template']) {
        expect(
          () => LiteRtLmV1ConversationSettings(promptTemplate: template),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      for (final max in [0, -1, 0x80000000]) {
        expect(
          () => LiteRtLmV1ConversationSettings(maxOutputTokens: max),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      for (final sampler in [
        const LiteRtLmV1SamplerSettings(
          temperature: 1e-300,
          topK: 40,
          topP: 1,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: 1,
          topK: 40,
          topP: 1e-300,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: double.nan,
          topK: 1,
          topP: 1,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: 1e300,
          topK: 1,
          topP: 1,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: -1,
          topK: 1,
          topP: 1,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: 1,
          topK: -1,
          topP: 1,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: 1,
          topK: 1,
          topP: 2,
          seed: 0,
        ),
        const LiteRtLmV1SamplerSettings(
          temperature: 1,
          topK: 1,
          topP: 1,
          seed: 0x80000000,
        ),
      ]) {
        expect(
          () => LiteRtLmV1ConversationSettings(sampler: sampler),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
    },
  );
}
