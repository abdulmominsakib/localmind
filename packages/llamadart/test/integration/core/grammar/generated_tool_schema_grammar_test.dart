@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/lazy_grammar_triggers.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:llamadart/src/core/engine/chat_completion_request_planner.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:llamadart/src/core/grammar/tool_grammar_generator.dart'
    as grammar;
import 'package:llamadart/src/core/template/handlers/mistral_handler.dart';
import 'package:test/test.dart';

import '../../../support/llama_cpp_grammar_load.dart';
import '../../../test_helper.dart';

void main() {
  late File modelFile;
  late LlamaEngine engine;
  Pointer<llama_model>? nativeModel;

  final tool = ToolDefinition(
    name: 'ping',
    description: 'Return a deterministic ping tool call.',
    parameters: const [],
    handler: (_) async => null,
  );
  final generatedGrammar = grammar.ToolGrammarGenerator.generate([
    tool,
  ], toolChoice: grammar.ToolChoice.required)!.grammar;

  setUpAll(() async {
    modelFile = await TestHelper.getTestModel();
    engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      modelFile.path,
      modelParams: const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 256,
        gpuLayers: 0,
      ),
    );
    final path = modelFile.path.toNativeUtf8();
    try {
      nativeModel = llama_model_load_from_file(
        path.cast<Char>(),
        llama_model_default_params(),
      );
    } finally {
      malloc.free(path);
    }
    expect(nativeModel, isNot(nullptr));
  });

  tearDownAll(() async {
    final loadedNativeModel = nativeModel;
    if (loadedNativeModel != null && loadedNativeModel != nullptr) {
      llama_model_free(loadedNativeModel);
    }
    await engine.dispose();
  });

  test('LFM2 native lazy grammar waits through visible content and reasoning', () {
    final tools = [
      ToolDefinition(name: 'clock', description: '', parameters: []),
    ];
    for (final forcedOpen in [false, true]) {
      final rendered = Lfm2Handler().render(
        templateSource: forcedOpen ? '<think>' : 'assistant',
        messages: const [],
        metadata: {internalToolChoiceMetadataKey: 'auto'},
        tools: tools,
      );
      final triggers = [
        for (final trigger in rendered.grammarTriggers)
          GenerationGrammarTrigger.typed(
            type: GrammarTriggerType.fromWireValue(trigger.type),
            value: trigger.value,
            token: trigger.token,
          ),
      ];
      const hiddenCall = '<|tool_call_start|>[not_declared()]<|tool_call_end|>';
      final prefix = forcedOpen
          ? 'Reasoning $hiddenCall remains hidden.</think> Visible prefix. '
          : 'Visible prefix. <think>Reasoning $hiddenCall stays hidden.</think> More content. ';
      const call = '<|tool_call_start|>[clock()]<|tool_call_end|>';
      expect(rendered.grammarLazy, isTrue);
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          rendered.grammar!,
          '$prefix$call',
          triggers: triggers,
        ),
        isTrue,
      );
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          rendered.grammar!,
          '$prefix${call.replaceFirst('clock', 'unknown')}',
          triggers: triggers,
        ),
        isFalse,
      );
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          rendered.grammar!,
          '$prefix$call Visible suffix.',
          triggers: triggers,
        ),
        isFalse,
        reason:
            'As in pinned upstream, activation constrains the call through its closing marker and end.',
      );
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          rendered.grammar!,
          prefix,
          triggers: triggers,
        ),
        isTrue,
        reason:
            'Auto may end without calling; a reasoning marker must not activate the grammar.',
      );
    }
  }, tags: ['local-only']);

  test('native compiler accepts generated tool schema grammar', () async {
    final output = await _generateThroughProductionTools(
      engine,
      tool,
      'Call the ping tool now.',
    );

    expect(
      output,
      equals({
        'name': 'ping',
        'arguments': <String, dynamic>{},
        'content': '',
        'finishReason': 'tool_calls',
      }),
    );
  });

  test(
    'compiled grammar rejects a schema-invalid requested tool call',
    () async {
      const invalidRequestedOutput =
          '{"tool_call":{"name":"not_ping","arguments":{"extra":true}}}';
      final output = await _generateThroughProductionTools(
        engine,
        tool,
        'Output exactly $invalidRequestedOutput',
      );

      expect(
        output,
        equals({
          'name': 'ping',
          'arguments': <String, dynamic>{},
          'content': '',
          'finishReason': 'tool_calls',
        }),
      );
    },
  );

  test('compiled grammar deterministically filters invalid candidates', () {
    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        generatedGrammar,
        '{"tool_call":{"name":"ping","arguments":{}}}',
      ),
      isTrue,
    );
    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        generatedGrammar,
        '{"tool_call":{"name":"not_ping","arguments":{"extra":true}}}',
      ),
      isFalse,
    );
  });

  test('compiled Mistral grammar enforces the tool-call id pattern', () {
    final mistralGrammar = MistralHandler().buildGrammar([tool])!;

    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        mistralGrammar,
        '[TOOL_CALLS][{"name":"ping","arguments":{},"id":"abc123XYZ"}]',
      ),
      isTrue,
    );
    for (final invalidId in ['abc', 'abc123XYZ0', 'abc12_XYZ']) {
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          mistralGrammar,
          '[TOOL_CALLS][{"name":"ping","arguments":{},"id":"$invalidId"}]',
        ),
        isFalse,
        reason: 'id "$invalidId" must not satisfy the generated grammar.',
      );
    }
  });

  test('compiled pattern grammar never admits a JSON-invalid string', () {
    final spanningRange = JsonSchemaConverter.convert({
      'type': 'string',
      'pattern': r'^[ -~]+$',
    });

    expect(
      _compiledGrammarAccepts(nativeModel!, spanningRange, '"abc"'),
      isTrue,
    );
    for (final invalid in [r'"ab"cd"', r'"ab\cd"', r'"ab\"']) {
      expect(
        _compiledGrammarAccepts(nativeModel!, spanningRange, invalid),
        isFalse,
        reason: '$invalid is not valid JSON and must not satisfy the grammar.',
      );
    }
  });

  test('compiled LFM2 required grammar keeps raw inner quotes in strings', () {
    final lfm2Grammar = Lfm2Handler()
        .render(
          templateSource: 'assistant',
          messages: const [],
          metadata: {internalToolChoiceMetadataKey: 'required'},
          tools: [
            ToolDefinition(
              name: 'run',
              description: '',
              parameters: [ToolParam.string('code', required: true)],
            ),
          ],
        )
        .grammar!;
    String call(String code) =>
        '<|tool_call_start|>[{"name": "run", "arguments": '
        '{"code": "$code"}}]<|tool_call_end|>';

    for (final code in [
      'print(f"hi {name}")',
      '{"a": 1, "b": "two"}',
      r'say \"hi\"',
    ]) {
      expect(
        _compiledGrammarAccepts(nativeModel!, lfm2Grammar, call(code)),
        isTrue,
        reason: code,
      );
    }
    for (final code in ['a", "b', 'a"}]] b']) {
      expect(
        _compiledGrammarAccepts(nativeModel!, lfm2Grammar, call(code)),
        isFalse,
        reason: code,
      );
    }
  });

  test(
    'backends without lazy grammar get a compiled required grammar only',
    () {
      String? plannedGrammar(ToolChoice toolChoice) {
        const messages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'Call the ping tool now.',
          ),
        ];
        final templateResult = ChatTemplateEngine.render(
          templateSource: _hermesTemplate,
          messages: messages,
          metadata: const {},
          tools: [tool],
          toolChoice: toolChoice,
        );
        return ChatCompletionRequestPlanner.build(
          backend: _EagerGrammarBackend(),
          templateResult: templateResult,
          messages: messages,
          tools: [tool],
          toolChoice: toolChoice,
          parallelToolCalls: false,
        ).generationParams.grammar;
      }

      expect(plannedGrammar(ToolChoice.auto), isNull);
      final required = plannedGrammar(ToolChoice.required);
      expect(required, isNotNull);
      expect(
        _compiledGrammarAccepts(
          nativeModel!,
          required!,
          '<tool_call>{"name": "ping", "arguments": {}}</tool_call>',
        ),
        isTrue,
      );
      for (final invalid in [
        'Hello!',
        '<tool_call>{"name": "not_ping", "arguments": {}}</tool_call>',
        '<tool_call>{{"name": "ping", "arguments": {}}}</tool_call>',
      ]) {
        expect(
          _compiledGrammarAccepts(nativeModel!, required, invalid),
          isFalse,
          reason: '$invalid must not satisfy the required grammar.',
        );
      }
    },
  );

  test('native sampler loads PodSpec-sized open schema grammars', () async {
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        for (final name in largeKeySets['Kubernetes PodSpec']!)
          name: {'type': 'string'},
      },
      'additionalProperties': true,
    };
    final podTool = ToolDefinition.fromJsonSchema(
      name: 'apply_pod',
      description: 'Apply a pod spec.',
      schema: schema,
    );
    const messages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Apply it.'),
    ];
    const params = GenerationParams(maxTokens: 8, temp: 0);
    for (final toolChoice in [ToolChoice.required, ToolChoice.auto]) {
      await engine
          .create(
            messages,
            tools: [podTool],
            toolChoice: toolChoice,
            params: params,
          )
          .drain<void>();
    }
    await engine
        .create(
          messages,
          params: params,
          responseFormat: {
            'type': 'json_schema',
            'json_schema': {'schema': schema},
          },
        )
        .drain<void>();

    final required = grammar.ToolGrammarGenerator.generate([
      podTool,
    ], toolChoice: grammar.ToolChoice.required)!.grammar;
    String call(String arguments) =>
        '{"tool_call":{"name":"apply_pod","arguments":$arguments}}';
    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        required,
        call('{"hostname":"a","extra":"b"}'),
      ),
      isTrue,
    );
    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        required,
        call('{"hostname":"a","hostname":"b"}'),
      ),
      isFalse,
    );
  });

  test('compiled grammar rejects an incomplete valid prefix at EOG', () {
    expect(
      _compiledGrammarAccepts(
        nativeModel!,
        generatedGrammar,
        '{"tool_call":{"name":"ping","arguments":{}}',
      ),
      isFalse,
    );
  });

  test(
    'native compiler rejects a broken generated grammar dependency',
    () async {
      final invalidGrammar = generatedGrammar.replaceFirst(
        'root ::= ',
        'root ::= undefined-generated-rule ',
      );

      expect(
        invalidGrammar,
        isNot(equals(generatedGrammar)),
        reason: 'The adversarial mutation must modify the generated root rule.',
      );
      await expectLater(
        engine.create(
          const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: 'Call the ping tool now.',
            ),
          ],
          params: GenerationParams(
            grammar: invalidGrammar,
            maxTokens: 16,
            temp: 0,
          ),
        ).drain<void>(),
        throwsA(isA<LlamaInferenceException>()),
      );
    },
  );
}

bool _compiledGrammarAccepts(
  Pointer<llama_model> model,
  String generatedGrammar,
  String candidate, {
  List<GenerationGrammarTrigger> triggers = const [],
}) {
  final barrier = NativeBarrierApi.tryResolve(isWindows: Platform.isWindows);
  expect(
    barrier,
    isNotNull,
    reason:
        'The pinned native runtime must export its grammar exception barrier.',
  );
  final nativeBarrier = barrier!;
  final vocab = llama_model_get_vocab(model);
  final grammarPointer = generatedGrammar.toNativeUtf8();
  final rootPointer = 'root'.toNativeUtf8();
  late final Pointer<llama_sampler> sampler;
  if (triggers.isEmpty) {
    sampler = llama_sampler_init_grammar(
      vocab,
      grammarPointer.cast<Char>(),
      rootPointer.cast<Char>(),
    );
  } else {
    final inputs = lazyGrammarTriggerInputs(triggers);
    final patterns = [
      for (final pattern in inputs.patterns) pattern.toNativeUtf8(),
    ];
    final pointers = calloc<Pointer<Char>>(patterns.length);
    try {
      for (var i = 0; i < patterns.length; i++) {
        pointers[i] = patterns[i].cast<Char>();
      }
      expect(inputs.tokens, isEmpty);
      sampler = nativeBarrier.samplerInitGrammarLazyPatterns(
        vocab,
        grammarPointer.cast<Char>(),
        rootPointer.cast<Char>(),
        pointers,
        patterns.length,
        nullptr,
        0,
      );
    } finally {
      for (final pattern in patterns) {
        malloc.free(pattern);
      }
      calloc.free(pointers);
    }
  }
  malloc
    ..free(grammarPointer)
    ..free(rootPointer);
  expect(sampler, isNot(nullptr));

  try {
    final prefixedTokens = _tokenize(vocab, '\n$candidate');
    final prefixTokens = _tokenize(vocab, '\n');
    expect(
      prefixedTokens.take(prefixTokens.length),
      orderedEquals(prefixTokens),
    );
    final candidateTokens = prefixedTokens.sublist(prefixTokens.length);
    final data = calloc<llama_token_data>(1);
    final array = calloc<llama_token_data_array>();
    try {
      array.ref
        ..data = data
        ..size = 1
        ..selected = -1
        ..sorted = false;
      for (final token in candidateTokens) {
        data.ref
          ..id = token
          ..logit = 0
          ..p = 0;
        llama_sampler_apply(sampler, array);
        if (data.ref.logit == double.negativeInfinity) return false;
        if (!nativeBarrier.samplerAccept(sampler, token)) return false;
      }
      final eog = llama_vocab_eos(vocab);
      expect(
        llama_vocab_is_eog(vocab, eog),
        isTrue,
        reason:
            'The test model EOS token must be a valid end-of-generation token.',
      );
      data.ref
        ..id = eog
        ..logit = 0
        ..p = 0;
      llama_sampler_apply(sampler, array);
      return data.ref.logit.isFinite;
    } finally {
      calloc
        ..free(data)
        ..free(array);
    }
  } finally {
    llama_sampler_free(sampler);
  }
}

List<int> _tokenize(Pointer<llama_vocab> vocab, String value) {
  final text = value.toNativeUtf8();
  try {
    final required = -llama_tokenize(
      vocab,
      text.cast<Char>(),
      text.length,
      nullptr,
      0,
      false,
      true,
    );
    expect(
      required,
      greaterThan(0),
      reason: 'llama_tokenize must report a positive token buffer size.',
    );
    final tokens = calloc<llama_token>(required);
    try {
      expect(
        llama_tokenize(
          vocab,
          text.cast<Char>(),
          text.length,
          tokens,
          required,
          false,
          true,
        ),
        required,
      );
      return [for (var index = 0; index < required; index++) tokens[index]];
    } finally {
      calloc.free(tokens);
    }
  } finally {
    malloc.free(text);
  }
}

Future<Map<String, dynamic>> _generateThroughProductionTools(
  LlamaEngine engine,
  ToolDefinition tool,
  String prompt,
) async {
  final chunks = await engine
      .create(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
        tools: [tool],
        toolChoice: ToolChoice.required,
        params: const GenerationParams(maxTokens: 96, temp: 0),
      )
      .toList();
  final calls = chunks
      .expand((chunk) => chunk.choices.first.delta.toolCalls ?? const [])
      .toList();
  expect(calls, hasLength(1));
  final call = calls.single;

  return {
    'name': call.function?.name,
    'arguments': jsonDecode(call.function?.arguments ?? 'null'),
    'content': chunks
        .map((chunk) => chunk.choices.first.delta.content ?? '')
        .join(),
    'finishReason': chunks.last.choices.first.finishReason,
  };
}

const _hermesTemplate =
    '{%- if tools %}<tools>{{ tools[0] | tojson }}</tools>'
    '<tool_call>{"name": <function-name>, "arguments": <args-json-object>}</tool_call>{% endif %}'
    '{% for message in messages %}<|im_start|>{{ message["role"] }}\n{{ message["content"] }}<|im_end|>\n{% endfor %}'
    '{% if add_generation_prompt %}<|im_start|>assistant\n{% endif %}';

class _EagerGrammarBackend implements LlamaBackend, BackendLazyGrammarSupport {
  @override
  bool get supportsLazyGrammar => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
