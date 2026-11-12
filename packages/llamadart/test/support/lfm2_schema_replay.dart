import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

/// Replays captured raw bytes through the production public parser.
///
/// Run the same helper in an unchanged baseline checkout to isolate parser
/// differences from generation. Input contains actual emissions, never a wire
/// reconstructed from an already parsed argument value.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run test/support/lfm2_schema_replay.dart <captures.json> <results.json>',
    );
    exitCode = 64;
    return;
  }
  final captures = (jsonDecode(File(arguments[0]).readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final rows = <Map<String, dynamic>>[];
  for (final capture in captures) {
    final row = <String, dynamic>{
      'id': capture['id'],
      'model': capture['model'],
      'raw_sha256': sha256
          .convert(utf8.encode(capture['raw'] as String))
          .toString(),
    };
    try {
      row['result'] = replayLfm2Capture(capture);
    } catch (error) {
      row['error'] = {
        'type': error.runtimeType.toString(),
        'message': error.toString(),
      };
    }
    rows.add(row);
  }
  File(
    arguments[1],
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
}

/// Reconstructs the tool declaration, preserving its original declaration API.
ToolDefinition lfm2CaptureTool(Map<String, dynamic> capture) {
  final data = capture['tool'] as Map<String, dynamic>;
  final schema = data['schema'] as Map<String, dynamic>;
  if (data['origin'] == 'canonical_schema') {
    return ToolDefinition.fromJsonSchema(
      name: data['name'] as String,
      description: data['description'] as String? ?? 'Captured tool',
      schema: schema,
    );
  }
  final properties = schema['properties'] as Map<String, dynamic>;
  final required =
      (schema['required'] as List?)?.cast<String>().toSet() ?? <String>{};
  return ToolDefinition(
    name: data['name'] as String,
    description: data['description'] as String? ?? 'Captured tool',
    parameters: [
      for (final entry in properties.entries)
        _parameter(
          entry.key,
          entry.value as Map<String, dynamic>,
          required.contains(entry.key),
        ),
    ],
  );
}

ToolParam _parameter(String name, Map<String, dynamic> schema, bool required) {
  final description = schema['description'] as String?;
  return switch (schema['type']) {
    'string' when schema['enum'] is List => ToolParam.enumType(
      name,
      values: (schema['enum'] as List).cast<String>(),
      description: description,
      required: required,
    ),
    'string' => ToolParam.string(
      name,
      description: description,
      required: required,
    ),
    'integer' => ToolParam.integer(
      name,
      description: description,
      required: required,
    ),
    'number' => ToolParam.number(
      name,
      description: description,
      required: required,
    ),
    'boolean' => ToolParam.boolean(
      name,
      description: description,
      required: required,
    ),
    'null' => ToolParam.nullType(
      name,
      description: description,
      required: required,
    ),
    'array' => ToolParam.array(
      name,
      itemType: _parameter(
        'item',
        schema['items'] as Map<String, dynamic>,
        false,
      ),
      description: description,
      required: required,
    ),
    'object' => ToolParam.object(
      name,
      properties: [
        for (final entry
            in (schema['properties'] as Map<String, dynamic>).entries)
          _parameter(
            entry.key,
            entry.value as Map<String, dynamic>,
            (schema['required'] as List? ?? const []).contains(entry.key),
          ),
      ],
      description: description,
      required: required,
    ),
    _ => throw FormatException(
      'Unsupported captured legacy parameter type ${schema['type']}',
    ),
  };
}

/// Parsed content, reasoning and decoded call arguments for exact comparison.
Map<String, dynamic> replayLfm2Capture(Map<String, dynamic> capture) {
  final declarations = capture['tools'];
  final tools = declarations is List
      ? [
          for (final encoded in declarations)
            lfm2CaptureTool({
              'tool': {
                'name': (encoded as Map)['function']['name'],
                'description': encoded['function']['description'],
                'schema': encoded['function']['parameters'],
                'origin': 'legacy_parameters',
              },
            }),
        ]
      : [lfm2CaptureTool(capture)];
  final parsed = ChatTemplateEngine.parse(
    capture['format'] as int? ?? ChatFormat.lfm2.index,
    capture['raw'] as String,
    thinkingForcedOpen: capture['thinking_forced_open'] as bool? ?? false,
    tools: tools,
  );
  return {
    'content': parsed.content,
    'reasoning': parsed.reasoningContent,
    'calls': [
      for (final call in parsed.toolCalls)
        {
          'name': call.function?.name,
          'arguments': jsonDecode(call.function!.arguments!),
        },
    ],
  };
}
