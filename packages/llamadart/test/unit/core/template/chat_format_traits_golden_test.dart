@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/chat_format_registry.dart';
import 'package:llamadart/src/core/template/handlers/apertus_handler.dart';
import 'package:llamadart/src/core/template/handlers/command_r7b_handler.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_r1_handler.dart';
import 'package:llamadart/src/core/template/handlers/deepseek_v3_handler.dart';
import 'package:llamadart/src/core/template/handlers/exaone_moe_handler.dart';
import 'package:llamadart/src/core/template/handlers/firefunction_v2_handler.dart';
import 'package:llamadart/src/core/template/handlers/function_gemma_handler.dart';
import 'package:llamadart/src/core/template/handlers/functionary_v31_llama31_handler.dart';
import 'package:llamadart/src/core/template/handlers/gemma_handler.dart';
import 'package:llamadart/src/core/template/handlers/granite_handler.dart';
import 'package:llamadart/src/core/template/handlers/gpt_oss_handler.dart';
import 'package:llamadart/src/core/template/handlers/hermes_handler.dart';
import 'package:llamadart/src/core/template/handlers/hunyuan_v3_handler.dart';
import 'package:llamadart/src/core/template/handlers/kimi_k2_handler.dart';
import 'package:llamadart/src/core/template/handlers/lfm2_handler.dart';
import 'package:llamadart/src/core/template/handlers/magistral_handler.dart';
import 'package:llamadart/src/core/template/handlers/mistral_handler.dart';
import 'package:llamadart/src/core/template/handlers/nemotron_v2_handler.dart';
import 'package:llamadart/src/core/template/xml_tool_call_format.dart';
import 'package:test/test.dart';

import '../../../support/chat_format_triggers.dart';
import '../../../support/raw_tool_schema_fixture.dart';

const String _goldenPath = 'test/fixtures/chat_format_traits.json';

void main() {
  final golden =
      jsonDecode(File(_goldenPath).readAsStringSync()) as Map<String, dynamic>;

  test('every format keeps its pinned traits', () {
    final pinned = golden['formats'] as Map<String, dynamic>;
    expect(pinned.keys, ChatFormat.values.map((format) => format.name));
    for (final format in ChatFormat.values) {
      expect(_traitsOf(format), pinned[format.name], reason: format.name);
    }
  });

  for (final (key, parseToolCalls) in const [
    ('incompleteToolCalls', true),
    ('incompleteToolCallsWithoutToolParsing', false),
  ]) {
    test('every format keeps its pinned $key', () {
      final pinned = golden[key] as Map<String, dynamic>;
      expect(pinned.keys, ChatFormat.values.map((format) => format.name));
      for (final format in ChatFormat.values) {
        expect(
          {
            for (final probe in _residualProbes)
              probe: _parseOutcome(format, probe, parseToolCalls),
          },
          pinned[format.name],
          reason: format.name,
        );
      }
    });
  }

  test('every trigger keeps its pinned routing', () {
    final pinned = golden['routing'] as Map<String, dynamic>;
    final sources = {
      'noTemplate': null,
      for (final MapEntry(:key, :value) in chatFormatTriggers.entries)
        key: value.source,
    };
    expect(pinned.keys, sources.keys);
    for (final MapEntry(key: name, value: source) in sources.entries) {
      expect(_routing(source), pinned[name], reason: name);
    }
  });
}

/// Scanner names, so the golden pins which scanner a format uses rather than
/// a function's identity.
final Map<String, Function> _openings = {
  'ApertusHandler': ApertusHandler.toolCallOpening,
  'CommandR7BHandler': CommandR7BHandler.toolCallOpening,
  'DeepseekR1Handler': DeepseekR1Handler.toolCallOpening,
  'DeepseekV3Handler': DeepseekV3Handler.toolCallOpening,
  'ExaoneMoeHandler': ExaoneMoeHandler.toolCallOpening,
  'FirefunctionV2Handler': FirefunctionV2Handler.toolCallOpening,
  'FunctionGemmaHandler': FunctionGemmaHandler.toolCallOpening,
  'FunctionaryV31Llama31Handler': FunctionaryV31Llama31Handler.toolCallOpening,
  'GemmaHandler': GemmaHandler.toolCallOpening,
  'GraniteHandler': GraniteHandler.toolCallOpening,
  'GptOssHandler': GptOssHandler.toolCallOpening,
  'HermesHandler': HermesHandler.toolCallOpening,
  'HunyuanV3Handler': HunyuanV3Handler.toolCallOpening,
  'KimiK2Handler': KimiK2Handler.toolCallOpening,
  'Lfm2Handler': Lfm2Handler.toolCallOpening,
  'MagistralHandler': MagistralHandler.toolCallOpening,
  'MistralHandler': MistralHandler.toolCallOpening,
  'NemotronV2Handler': NemotronV2Handler.toolCallOpening,
  'XmlToolCallFormat.apriel15': XmlToolCallFormat.apriel15.toolCallOpening,
  'XmlToolCallFormat.minicpm5': XmlToolCallFormat.minicpm5.toolCallOpening,
  'XmlToolCallFormat.minimaxM2': XmlToolCallFormat.minimaxM2.toolCallOpening,
  'XmlToolCallFormat.qwen3Coder': XmlToolCallFormat.qwen3Coder.toolCallOpening,
  'XmlToolCallFormat.seedOss': XmlToolCallFormat.seedOss.toolCallOpening,
  'XmlToolCallFormat.xiaomiMimo': XmlToolCallFormat.xiaomiMimo.toolCallOpening,
};

String? _openingName(Function? opening) {
  if (opening == null) return null;
  for (final MapEntry(:key, :value) in _openings.entries) {
    if (value == opening) return key;
  }
  return 'unknown';
}

Map<String, Object?> _traitsOf(ChatFormat format) {
  final traits = chatFormatRegistration(format).traits;
  return {
    'toolCallOpening': _openingName(traits.toolCallOpening),
    'keepsThoughtTagsAsContent': traits.keepsThoughtTagsAsContent,
    'parsesCallsInsideThoughts': traits.parsesCallsInsideThoughts,
    'mayEmbedToolEnvelopeAfterContent': traits.mayEmbedToolEnvelopeAfterContent,
    'retainsTextAroundToolCalls': traits.retainsTextAroundToolCalls,
    'endsThoughtAtToolCallOpening': traits.endsThoughtAtToolCallOpening,
    'hasRepeatedContentChannels': traits.hasRepeatedContentChannels,
    'disabledByResponseSchema': traits.disabledByResponseSchema,
    'requiredKeepsLazyGrammar': traits.requiredKeepsLazyGrammar,
    'routesThroughGeneric': traits.routesThroughGeneric,
    'toolChoiceNoneRendersContentOnly': traits.toolChoiceNoneRendersContentOnly,
    'qualifiesJsonSchemaTools': traits.qualifiesJsonSchemaTools,
    'hasIncompleteToolCallCheck': traits.leavesIncompleteToolCall != null,
  };
}

/// Final outputs that leave a tool-call opening unparsed in some format.
const List<String> _residualProbes = [
  'plain reply',
  '{"tool_call": {"name": "inspect"',
  '{"tool_calls": [',
  '<tool_call>{"name": "inspect"',
  '<tool_call>',
  '[TOOL_CALLS]',
  '[TOOL_CALLS]inspect[ARGS]{',
  '<tool_call:opensource>',
  '<tool_calls:opensource>',
  'text <tool_call>',
];

String _parseOutcome(ChatFormat format, String output, bool parseToolCalls) {
  try {
    final result = ChatTemplateEngine.parse(
      format.index,
      output,
      parseToolCalls: parseToolCalls,
      tools: [rawSchemaTool()],
    );
    return 'calls=${result.toolCalls.length}';
  } on LlamaException catch (error) {
    return '${error.runtimeType}: ${error.message}';
  } catch (error) {
    return error.runtimeType.toString();
  }
}

Map<String, String> _routing(String? template) {
  final legacy = ToolDefinition(
    name: 'inspect',
    description: 'Inspect',
    parameters: [ToolParam.string('code')],
  );
  const jsonObject = <String, dynamic>{'type': 'json_object'};
  String outcome({
    List<ToolDefinition>? tools,
    ToolChoice choice = ToolChoice.auto,
    Map<String, dynamic>? responseFormat,
  }) {
    try {
      final result = ChatTemplateEngine.render(
        templateSource: template,
        messages: [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
        ],
        metadata: const {},
        tools: tools,
        toolChoice: choice,
        responseFormat: responseFormat,
      );
      return '${ChatFormat.values[result.format].name}'
          ' lazy=${result.grammarLazy} grammar=${result.grammar != null}';
    } on LlamaException catch (error) {
      return '${error.runtimeType}: ${error.message}';
    } catch (error) {
      return error.runtimeType.toString();
    }
  }

  return {
    'noTools': outcome(),
    'noToolsNone': outcome(choice: ToolChoice.none),
    'auto': outcome(tools: [legacy]),
    'required': outcome(tools: [legacy], choice: ToolChoice.required),
    'none': outcome(tools: [legacy], choice: ToolChoice.none),
    'responseSchema': outcome(responseFormat: jsonObject),
    'toolsAndResponseSchema': outcome(
      tools: [legacy],
      responseFormat: jsonObject,
    ),
    'schemaTool': outcome(tools: [rawSchemaTool()]),
  };
}
