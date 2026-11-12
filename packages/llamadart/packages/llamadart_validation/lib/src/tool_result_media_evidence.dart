import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

import 'case_catalog.dart';
import 'manifest.dart';

/// Image fixture [color] as `{png_base64, sha256}`; the bytes are rechecked
/// against their locked hash.
Map<String, dynamic> toolResultMediaImage(String color) {
  final image = ((toolResultMediaFixture['images'] as Map)[color] as Map)
      .cast<String, dynamic>();
  if ('${sha256.convert(base64Decode(image['png_base64'] as String))}' !=
      image['sha256']) {
    throw StateError(
      'Tool-result media fixture $color does not match its hash',
    );
  }
  return image;
}

/// Colors in fixture order; each answer must name its own color and not the
/// other, so a constant guess cannot pass both.
List<String> get toolResultMediaColors =>
    ((toolResultMediaFixture['images'] as Map).keys).cast<String>().toList();

/// Rechecks the recorded requests and answers instead of trusting `passed`
/// flags: the model called the tool itself, the whole request is exactly the
/// fixture conversation with the photo as the tool result's only image, and
/// each answer names its photo's color only.
bool validToolResultMediaCaseEvidence(
  String id,
  Map<String, dynamic> record,
  ValidationProfile profile,
) {
  if (id != 'M01.tool_result_image' || profile.toolResultProjector == null) {
    return false;
  }
  const fixture = toolResultMediaFixture;
  final media = record['tool_result_media'];
  if (media is! List || !media.contains('image')) return false;
  final call = record['call'];
  if (call is! Map ||
      call['tool_choice'] != 'required' ||
      call['stream_completed'] != true ||
      call['completion_order_valid'] != true ||
      call['max_tokens'] != fixture['call_max_tokens'] ||
      canonicalJson(call['tools']) != canonicalJson([_tool().toJson()]) ||
      canonicalJson(call['finish_reasons']) != canonicalJson(['tool_calls']) ||
      _calledTool(call['tool_call_deltas']) != fixture['tool']) {
    return false;
  }
  final colors = toolResultMediaColors;
  final trials = record['trials'];
  if (trials is! List || trials.length != colors.length) return false;
  for (var index = 0; index < colors.length; index++) {
    final color = colors[index];
    final trial = trials[index];
    if (trial is! Map ||
        trial['color'] != color ||
        trial['stream_completed'] != true ||
        trial['completion_order_valid'] != true ||
        trial['tool_choice'] != null ||
        trial['max_tokens'] != fixture['max_tokens'] ||
        trial['image_sha256'] != toolResultMediaImage(color)['sha256'] ||
        trial['tool_call_deltas'] is! List ||
        (trial['tool_call_deltas'] as List).isNotEmpty ||
        !_textFinish(trial['finish_reasons'])) {
      return false;
    }
    final answer = '${trial['content']}'.toLowerCase();
    bool names(String name) => RegExp('\\b$name\\b').hasMatch(answer);
    if (!names(color) ||
        colors.any((other) => other != color && names(other))) {
      return false;
    }
    if (!_requestIsFixture(trial['messages'], color)) return false;
  }
  return true;
}

ToolDefinition _tool() => ToolDefinition(
  name: toolResultMediaFixture['tool'] as String,
  description: toolResultMediaFixture['tool_description'] as String,
  parameters: const [],
);

String _calledTool(Object? deltas) {
  if (deltas is! List || deltas.isEmpty) return '';
  final name = StringBuffer();
  for (final delta in deltas) {
    final function = delta is Map ? delta['function'] : null;
    name.write(function is Map ? function['name'] ?? '' : '');
  }
  return name.toString();
}

bool _textFinish(Object? reasons) =>
    canonicalJson(reasons) == canonicalJson(['stop']) ||
    canonicalJson(reasons) == canonicalJson(['length']);

bool _requestIsFixture(Object? messages, String color) {
  const fixture = toolResultMediaFixture;
  if (messages is! List || messages.length != 3) return false;
  final tool = messages[2];
  if (canonicalJson(messages[0]) !=
          canonicalJson({'role': 'user', 'content': fixture['question']}) ||
      canonicalJson(messages[1]) !=
          canonicalJson({
            'role': 'assistant',
            'tool_calls': [
              {
                'type': 'function',
                'function': {'name': fixture['tool'], 'arguments': '{}'},
                'id': fixture['call_id'],
              },
            ],
            'content': null,
          }) ||
      tool is! Map ||
      tool['role'] != 'tool' ||
      tool['tool_call_id'] != fixture['call_id'] ||
      tool['name'] != fixture['tool'] ||
      tool['content'] is! List) {
    return false;
  }
  final parts = tool['content'] as List;
  if (parts.length != 2 ||
      canonicalJson(parts[0]) !=
          canonicalJson({'type': 'text', 'text': '{"ok":true}'})) {
    return false;
  }
  final image = parts[1];
  final Object? url = image is Map && image['type'] == 'image_url'
      ? (image['image_url'] is Map ? (image['image_url'] as Map)['url'] : null)
      : null;
  return url is String &&
      RegExp(
        '^data:image/[a-z]+;base64,'
        '${RegExp.escape(toolResultMediaImage(color)['png_base64'] as String)}\$',
      ).hasMatch(url);
}
