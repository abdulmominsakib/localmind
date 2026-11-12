part of 'runner.dart';

/// Structured-output boundary of a [ValidationEngine], separate so that other
/// adapters need not implement it.
abstract interface class StructuredValidationEngine {
  /// The loaded engine's reported grammar and structured-output capabilities.
  Future<LlamaEngineCapabilities> structuredCapabilities();

  /// Streams one chat request without thinking. [responseFormat], [grammar]
  /// and the lazy-grammar options reach the public API unchanged. When
  /// [parseWith] is set, the stream is finalized with `parseStructuredJson`
  /// and the result or its typed error is recorded. A request rejected before
  /// streaming records its typed error instead of throwing.
  Future<Map<String, dynamic>> generateStructured(
    String prompt,
    ValidationProfile profile, {
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
    LlamaStructuredOutput<Object?>? parseWith,
    String? grammar,
    bool grammarLazy = false,
    List<GenerationGrammarTrigger> grammarTriggers = const [],
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  });

  /// Runs `LlamaEngine.createStructuredJson` without thinking and records the
  /// decoded value or its typed error.
  Future<Map<String, dynamic>> createStructuredJson(
    String prompt,
    ValidationProfile profile,
    LlamaStructuredOutput<Object?> output, {
    required int maxTokens,
  });
}

Map<String, dynamic> _typedError(Object error) => {
  'error_type': error.runtimeType.toString(),
  'message': redactDiagnostic(
    error is LlamaException ? error.message : '$error',
  ),
  if (error is LlamaException && error.details != null)
    'details': redactDiagnostic('${error.details}'),
};

mixin _PublicStructuredValidation implements StructuredValidationEngine {
  LlamaEngine get _engine;

  @override
  Future<LlamaEngineCapabilities> structuredCapabilities() =>
      _engine.capabilities;

  @override
  Future<Map<String, dynamic>> createStructuredJson(
    String prompt,
    ValidationProfile profile,
    LlamaStructuredOutput<Object?> output, {
    required int maxTokens,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final value = await _engine.createStructuredJson(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
        output: output,
        params: profile.generationParams.copyWith(maxTokens: maxTokens),
        enableThinking: false,
      );
      return {'value': value, 'wall_ms': watch.elapsedMicroseconds / 1000};
    } on LlamaException catch (error) {
      return {'error': _typedError(error)};
    }
  }

  @override
  Future<Map<String, dynamic>> generateStructured(
    String prompt,
    ValidationProfile profile, {
    required int maxTokens,
    Map<String, dynamic>? responseFormat,
    LlamaStructuredOutput<Object?>? parseWith,
    String? grammar,
    bool grammarLazy = false,
    List<GenerationGrammarTrigger> grammarTriggers = const [],
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
  }) async {
    final deltas = <String>[];
    final toolDeltas = <Map<String, dynamic>>[];
    final finish = <String>[];
    var chunks = 0;
    var bytes = 0;
    var ordered = true;
    var completed = false;
    final evidence = <String, dynamic>{
      'prompt': prompt,
      'max_tokens': maxTokens,
      'response_format': responseFormat,
      'parse_schema': parseWith == null
          ? null
          : parseWith.schema ?? parseWith.responseFormat,
      'grammar': grammar,
      'grammar_lazy': grammarLazy,
      'grammar_triggers': [
        for (final trigger in grammarTriggers)
          {'type': trigger.triggerType.name, 'value': trigger.value},
      ],
      'tools': tools?.map((tool) => tool.toJson()).toList(),
      'tool_choice': toolChoice?.name,
      'enable_thinking': false,
    };
    final watch = Stopwatch()..start();
    final Stream<LlamaCompletionChunk> stream;
    try {
      stream = _engine.create(
        [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
        params: profile.generationParams.copyWith(
          maxTokens: maxTokens,
          grammar: grammar,
          grammarLazy: grammarLazy,
          grammarTriggers: grammarTriggers,
        ),
        enableThinking: false,
        tools: tools,
        toolChoice: toolChoice,
        responseFormat: responseFormat,
      );
    } on LlamaException catch (error) {
      return {...evidence, 'error': _typedError(error), 'chunks': 0};
    }
    final observed = stream.map((chunk) {
      chunks++;
      for (final choice in chunk.choices) {
        if (choice.index != 0 || finish.isNotEmpty) ordered = false;
        for (final tool
            in choice.delta.toolCalls ?? <LlamaCompletionChunkToolCall>[]) {
          toolDeltas.add(tool.toJson());
        }
        final content = choice.delta.content ?? '';
        if (content.isNotEmpty) {
          bytes += utf8.encode(content).length;
          if (bytes > 65536) {
            _engine.cancelGeneration();
            throw StateError('Output exceeded the 64 KiB core limit');
          }
          deltas.add(content);
        }
        if (choice.finishReason != null) finish.add(choice.finishReason!);
      }
      return chunk;
    });
    final outcome = <String, dynamic>{};
    try {
      if (parseWith == null) {
        await observed.drain<void>();
      } else {
        try {
          outcome['parsed'] = await observed.parseStructuredJson(parseWith);
        } on LlamaInferenceException catch (error) {
          if (finish.isEmpty) rethrow;
          outcome['parse_error'] = _typedError(error);
        }
      }
      completed = true;
    } on LlamaException catch (error) {
      outcome['error'] = _typedError(error);
    }
    watch.stop();
    return {
      ...evidence,
      ...outcome,
      'content': deltas.join(),
      'content_deltas': deltas,
      'chunks': chunks,
      'finish_reasons': finish,
      'tool_call_deltas': toolDeltas,
      'stream_completed': completed,
      'completion_order_valid': ordered && finish.length == 1,
      'wall_ms': watch.elapsedMicroseconds / 1000,
    };
  }
}

extension on ValidationRunner {
  StructuredValidationEngine? get _structuredEngine =>
      engine is StructuredValidationEngine
      ? engine as StructuredValidationEngine
      : null;

  String get _structuredRuntime => profile.runtime == 'litert'
      ? 'litert'
      : engine.isWeb
      ? 'web'
      : 'native';

  int get _structuredMaxTokens => structuredOutputFixture['max_tokens'] as int;

  Future<Map<String, dynamic>> _structuredCase(String id) async {
    final structured = _structuredEngine;
    if (structured == null || profile.nativeReference) {
      return {
        'status': 'NOT_RUN',
        'reason': 'Requires the public structured-output API adapter',
      };
    }
    _operationPhase = 'structured.capabilities';
    final capabilities = await _checked(structured.structuredCapabilities);
    final reported = {
      'grammar': capabilities.supportsGrammar,
      'lazy_grammar': capabilities.supportsLazyGrammar,
      'structured_output': capabilities.supportsStructuredOutput,
    };
    if (id == 'S01.capabilities') {
      final diagnostics = await _checked(engine.diagnostics);
      final evidence = {
        'expected_runtime': _structuredRuntime,
        'expected': expectedStructuredCapabilities(
          _structuredRuntime,
          profile: profile,
          environment: _structuredEnvironment,
          diagnostics: diagnostics,
          preparation: _structuredPreparation,
        ),
        if (_structuredRuntime == 'litert')
          'native_schema_admitted': capabilities.supportsStructuredOutput,
        if (_structuredRuntime == 'litert') 'diagnostics': diagnostics,
        'reported': reported,
      };
      if ((evidence['expected'] as Map)['structured_output'] == null) {
        return {
          ...evidence,
          'status': 'NOT_RUN',
          'reason':
              'Native JSON Schema capability expectation lacks verified host/model/runtime provenance',
        };
      }
      return {
        ...evidence,
        'status':
            validStructuredCaseEvidence(
              id,
              evidence,
              runtime: _structuredRuntime,
              profile: profile,
              environment: _structuredEnvironment,
              diagnostics: diagnostics,
              preparation: _structuredPreparation,
            )
            ? 'PASS'
            : 'FAIL',
      };
    }
    final required = switch (id) {
      'S04.grammar' => 'grammar',
      'S05.grammar.lazy' => 'lazy_grammar',
      'S08.tools.schema' => 'grammar',
      _ => 'structured_output',
    };
    if (reported[required] != true) {
      return {
        'reported': reported,
        'status': 'NOT_RUN',
        'reason':
            'The loaded runtime reports no $required support; the pack '
            'qualifies only constrained decoding',
      };
    }
    Future<Map<String, dynamic>> generate(
      String phase,
      String prompt, {
      Map<String, dynamic>? responseFormat,
      LlamaStructuredOutput<Object?>? parseWith,
      String? grammar,
      bool grammarLazy = false,
      List<GenerationGrammarTrigger> grammarTriggers = const [],
      List<ToolDefinition>? tools,
      ToolChoice? toolChoice,
    }) {
      _operationPhase = 'structured.$phase';
      return _checked(
        () => structured.generateStructured(
          prompt,
          profile,
          maxTokens: _structuredMaxTokens,
          responseFormat: responseFormat,
          parseWith: parseWith,
          grammar: grammar,
          grammarLazy: grammarLazy,
          grammarTriggers: grammarTriggers,
          tools: tools,
          toolChoice: toolChoice,
        ),
      );
    }

    Map<String, dynamic> verdict(Map<String, dynamic> evidence) {
      final control = evidence['control'];
      if (control is Map && structuredControlConforms(id, evidence)) {
        return {
          ...evidence,
          'status': 'NOT_RUN',
          'reason':
              'The unconstrained control already satisfied the case, so the '
              'fixture cannot show that the constraint was applied',
        };
      }
      return {
        ...evidence,
        'status':
            validStructuredCaseEvidence(
              id,
              evidence,
              runtime: _structuredRuntime,
            )
            ? 'PASS'
            : 'FAIL',
      };
    }

    final schemaFixture = structuredFixture('json_schema');
    final schemaOutput = LlamaStructuredOutput<Object?>.jsonSchema(
      schema: Map<String, dynamic>.from(schemaFixture['schema'] as Map),
      decoder: (value) => value,
    );
    switch (id) {
      case 'S02.json_object':
        final prompt = structuredFixture('json_object')['prompt'] as String;
        final output = LlamaStructuredOutput<Object?>.jsonObject(
          decoder: (value) => value,
        );
        final control = await generate('control', prompt);
        _partialCaseEvidence = {'control': control};
        return verdict({
          'control': control,
          'constrained': await generate(
            'json_object',
            prompt,
            responseFormat: output.responseFormat,
            parseWith: output,
          ),
        });
      case 'S03.json_schema':
        final prompt = schemaFixture['prompt'] as String;
        final control = await generate('control', prompt);
        _partialCaseEvidence = {'control': control};
        final constrained = await generate(
          'json_schema',
          prompt,
          responseFormat: schemaOutput.responseFormat,
          parseWith: schemaOutput,
        );
        _partialCaseEvidence = {'control': control, 'constrained': constrained};
        _operationPhase = 'structured.create_structured_json';
        return verdict({
          'control': control,
          'constrained': constrained,
          'helper': await _checked(
            () => structured.createStructuredJson(
              prompt,
              profile,
              schemaOutput,
              maxTokens: _structuredMaxTokens,
            ),
          ),
        });
      case 'S04.grammar':
        final fixture = structuredFixture('grammar');
        final prompt = fixture['prompt'] as String;
        final control = await generate('control', prompt);
        _partialCaseEvidence = {'control': control};
        return verdict({
          'control': control,
          'constrained': await generate(
            'grammar',
            prompt,
            grammar: fixture['grammar'] as String,
          ),
        });
      case 'S05.grammar.lazy':
        final fixture = structuredFixture('lazy_grammar');
        final prompt = fixture['prompt'] as String;
        final control = await generate('control', prompt);
        _partialCaseEvidence = {'control': control};
        return verdict({
          'control': control,
          'constrained': await generate(
            'lazy_grammar',
            prompt,
            grammar: fixture['grammar'] as String,
            grammarLazy: true,
            grammarTriggers: [
              GenerationGrammarTrigger.typed(
                type: GrammarTriggerType.word,
                value: fixture['trigger'] as String,
              ),
            ],
          ),
        });
      case 'S06.reject':
        return _structuredRejections(generate);
      case 'S07.stream':
        final output = await generate(
          'stream',
          schemaFixture['prompt'] as String,
          responseFormat: schemaOutput.responseFormat,
          parseWith: schemaOutput,
        );
        final content = output['content'] as String;
        final rejections = <Map<String, dynamic>>[];
        for (final length in structuredPartialLengths(
          (output['content_deltas'] as List).cast<String>(),
        )) {
          try {
            schemaOutput.parse(content.substring(0, length));
            rejections.add({'length': length, 'accepted': true});
          } on LlamaException catch (error) {
            rejections.add({'length': length, ..._typedError(error)});
          }
        }
        return verdict({'output': output, 'partial_rejections': rejections});
      case 'S08.tools.schema':
        final fixture = structuredFixture('tools');
        final tool = ToolDefinition.fromJsonSchema(
          name: fixture['name'] as String,
          description: fixture['description'] as String,
          schema: Map<String, dynamic>.from(fixture['schema'] as Map),
        );
        final output = await generate(
          'tools',
          fixture['prompt'] as String,
          tools: [tool],
          toolChoice: ToolChoice.required,
        );
        final call = structuredToolCall(output['tool_call_deltas']);
        return verdict({
          'output': output,
          'reconstructed_name': call?.name,
          'reconstructed_arguments': call?.arguments,
        });
      default:
        throw StateError('No implementation for catalog case $id');
    }
  }

  Future<Map<String, dynamic>> _structuredRejections(
    Future<Map<String, dynamic>> Function(
      String phase,
      String prompt, {
      Map<String, dynamic>? responseFormat,
      LlamaStructuredOutput<Object?>? parseWith,
    })
    generate,
  ) async {
    final fixture = structuredFixture('reject');
    final objectOutput = LlamaStructuredOutput<Object?>.jsonObject(
      decoder: (value) => value,
    );
    final malformed = await generate(
      'reject.malformed',
      fixture['malformed_prompt'] as String,
      parseWith: objectOutput,
    );
    _partialCaseEvidence = {'malformed': malformed};
    final generatedFormat = LlamaStructuredOutput<Object?>.jsonSchema(
      schema: Map<String, dynamic>.from(fixture['generated_schema'] as Map),
      decoder: (value) => value,
    );
    final parsedFormat = LlamaStructuredOutput<Object?>.jsonSchema(
      schema: Map<String, dynamic>.from(fixture['parsed_schema'] as Map),
      decoder: (value) => value,
    );
    final mismatch = await generate(
      'reject.mismatch',
      fixture['mismatch_prompt'] as String,
      responseFormat: generatedFormat.responseFormat,
      parseWith: parsedFormat,
    );
    Map<String, dynamic> unsupportedSchema;
    try {
      LlamaStructuredOutput<Object?>.jsonSchema(
        schema: Map<String, dynamic>.from(fixture['unsupported_schema'] as Map),
        decoder: (value) => value,
      );
      unsupportedSchema = {'accepted': true};
    } on LlamaException catch (error) {
      unsupportedSchema = _typedError(error);
    }
    final unsupportedFormat = await generate(
      'reject.response_format',
      fixture['malformed_prompt'] as String,
      responseFormat: Map<String, dynamic>.from(
        fixture['unsupported_response_format'] as Map,
      ),
    );
    final recovery = await generate(
      'reject.recovery',
      profile.fixtureText('hello', 'prompt'),
    );
    final evidence = <String, dynamic>{
      'malformed': malformed,
      'mismatch': mismatch,
      'unsupported_schema': unsupportedSchema,
      'unsupported_response_format': {
        ...?unsupportedFormat['error'] as Map<String, dynamic>?,
        'chunks': unsupportedFormat['chunks'],
        'content': unsupportedFormat['content'],
      },
      'recovery': recovery,
    };
    if (!identical(
      decodeJsonOr(malformed['content'] as String, _malformedProbe),
      _malformedProbe,
    )) {
      return {
        ...evidence,
        'status': 'NOT_RUN',
        'reason':
            'The unconstrained malformed-output request produced valid JSON, '
            'so it cannot exercise the malformed-output rejection',
      };
    }
    return {
      ...evidence,
      'status':
          validStructuredCaseEvidence(
            'S06.reject',
            evidence,
            runtime: _structuredRuntime,
          )
          ? 'PASS'
          : 'FAIL',
    };
  }
}

const _malformedProbe = Object();
