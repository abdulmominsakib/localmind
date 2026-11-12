@Tags(['real-model', 'tool-model'])
@TestOn('vm')
library;

import 'dart:convert';

import 'package:llamadart/llamadart.dart' as llama;
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/constrained_tools.dart';
import 'package:genkit_llamadart/src/integration/genkit/converters/genkit_to_llama.dart';
import 'package:genkit/plugin.dart' as api;
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';
import '../test_support/tool_schema_grammar_validation.dart';

void main() {
  test(
    'native combined schema grammars enforce tool choice, output shape and local references',
    () async {
      final path = await resolveIntegrationToolModelPath();
      if (path == null) return;
      final tools = toLlamaTools([
        api.ToolDefinition(
          name: 'lookup',
          description: 'Lookup',
          inputSchema: {
            'type': 'object',
            'properties': {
              'value': {'type': 'null'},
            },
            'required': ['value'],
          },
        ),
      ]).tools;
      final engine = await llama.LlamaEngine.load(
        llama.LlamaModel(llama.ModelSource.path(path)),
        params: const llama.ModelParams(
          contextSize: 4096,
          device: llama.ComputeDevice.cpu,
        ),
      );
      addTearDown(engine.dispose);
      for (final choice in [llama.ToolChoice.auto, llama.ToolChoice.required]) {
        final schema = constrainedToolSchema(tools, choice, {
          'type': 'object',
          'properties': {
            'answer': {'type': 'string'},
          },
          'required': ['answer'],
          'additionalProperties': false,
        });
        final template = await engine.chatTemplate(
          [llama.LlamaChatMessage(role: 'user', content: 'Look up the value.')],
          tools: tools,
          toolChoice: choice,
          responseFormat: {
            'type': 'json_schema',
            'json_schema': {'schema': schema},
          },
          enableThinking: false,
          includeTokenCount: false,
        );
        expect(template.format, llama.ChatFormat.generic.index);
        expect(template.grammarLazy, isFalse);
        validateCompiledGrammar(path, template.grammar!, {
          '{"tool_call":{"name":"lookup","arguments":{"value":null}}}': true,
          '{"tool_call":{"name":"lookup","arguments":{"value":"null"}}}': false,
          '{"tool_call":{"name":"wrong","arguments":{"value":null}}}': false,
          '{"response":{"answer":"ok"}}': choice == llama.ToolChoice.auto,
          '{"response":{"answer":123}}': false,
          '{"response":{}}': false,
          '{"response":{"answer":"ok"},"extra":true}': false,
          '{"tool_call":{"name":"lookup","arguments":{"value":null}': false,
        });
      }
      const literal =
          '<tool_call>{"name":"lookup","arguments":{"value":null}}</tool_call>';
      final literalSchema = constrainedToolSchema(
        tools,
        llama.ToolChoice.auto,
        {'type': 'string', 'const': literal},
      );
      validateCompiledGrammar(
        path,
        JsonSchemaConverter.convert(literalSchema),
        {
          jsonEncode({'response': literal}): true,
          jsonEncode({'response': 'different text'}): false,
        },
      );
      final schema = constrainedToolSchema(tools, llama.ToolChoice.auto, {
        r'$ref': '#/properties/value',
        'properties': {
          'value': {r'$ref': r'#/$defs/value'},
        },
        r'$defs': {
          'value': {'type': 'integer', 'const': 7},
        },
      });
      validateCompiledGrammar(path, JsonSchemaConverter.convert(schema), {
        '{"response":7}': true,
        '{"response":"7"}': false,
        '{"response":8}': false,
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
