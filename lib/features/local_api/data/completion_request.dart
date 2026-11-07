import 'dart:convert';

import '../../../core/inference/local_inference.dart';

class CompletionRequest {
  const CompletionRequest(this.inference, {required this.stream});
  final InferenceRequest inference;
  final bool stream;

  factory CompletionRequest.parse(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }
    final model = _string(json['model'], 'model');
    final stream = json['stream'] ?? false;
    if (stream is! bool) {
      throw const FormatException('stream must be a boolean.');
    }
    if ((json['n'] ?? 1) != 1) {
      throw const FormatException('Only one completion is supported.');
    }
    for (final field in [
      'audio',
      'modalities',
      'response_format',
      'stop',
      'logprobs',
      'logit_bias',
      'presence_penalty',
      'frequency_penalty',
      'seed',
    ]) {
      if (json[field] != null) {
        throw FormatException('$field is not supported.');
      }
    }

    final definitions = <InferenceTool>[];
    final names = <String>{};
    for (final definition in _list(json['tools'] ?? const [], 'tools')) {
      final function = _function(definition);
      final name = _string(function['name'], 'function name');
      if (!names.add(name)) throw const FormatException('Duplicate tool name.');
      final description = function['description'] ?? '';
      final parameters = function['parameters'] ?? <String, dynamic>{};
      if (description is! String || parameters is! Map<String, dynamic>) {
        throw const FormatException('Invalid function schema.');
      }
      if (function['strict'] == true) {
        throw const FormatException(
          'Strict function schemas are not supported.',
        );
      }
      definitions.add(InferenceTool(name, description, parameters));
    }

    final choice = json['tool_choice'] ?? 'auto';
    if (choice != 'auto' && choice != 'none') {
      throw const FormatException('tool_choice must be auto or none.');
    }

    final messages = <InferenceMessage>[];
    final pendingCalls = <String>{};
    final callIds = <String>{};
    for (final raw in _list(json['messages'], 'messages')) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Expected a message object.');
      }
      final role = InferenceRole.values
          .where((role) => role.name == raw['role'])
          .firstOrNull;
      if (role == null) {
        throw const FormatException('Unsupported message role.');
      }
      if (pendingCalls.isNotEmpty && role != InferenceRole.tool) {
        throw const FormatException(
          'Tool results must follow their assistant calls.',
        );
      }
      final calls = <InferenceToolCall>[];
      if (raw['tool_calls'] != null) {
        if (role != InferenceRole.assistant) {
          throw const FormatException(
            'Only assistant messages can contain tool calls.',
          );
        }
        for (final rawCall in _list(raw['tool_calls'], 'tool_calls')) {
          final function = _function(rawCall);
          final call = rawCall as Map<String, dynamic>;
          final id = _string(call['id'], 'tool call id');
          if (!callIds.add(id)) {
            throw const FormatException('Duplicate tool call ID.');
          }
          pendingCalls.add(id);
          final arguments = _string(
            function['arguments'],
            'function arguments',
          );
          if (jsonDecode(arguments) is! Map<String, dynamic>) {
            throw const FormatException(
              'Function arguments must encode a JSON object.',
            );
          }
          calls.add(
            InferenceToolCall(
              _string(function['name'], 'function name'),
              arguments,
              id: id,
            ),
          );
        }
      }
      final text = raw['content'] ?? (calls.isEmpty ? null : '');
      if (text is! String) {
        throw const FormatException('Only text message content is supported.');
      }
      String? toolCallId;
      if (role == InferenceRole.tool) {
        toolCallId = _string(raw['tool_call_id'], 'tool_call_id');
        if (!pendingCalls.remove(toolCallId)) {
          throw const FormatException(
            'Tool result has no matching assistant call.',
          );
        }
      }
      messages.add(
        InferenceMessage(role, text, calls: calls, toolCallId: toolCallId),
      );
    }
    if (messages.isEmpty ||
        pendingCalls.isNotEmpty ||
        ![
          InferenceRole.user,
          InferenceRole.tool,
        ].contains(messages.last.role)) {
      throw const FormatException(
        'Messages must end with a user message or complete tool results.',
      );
    }

    final tokens = json['max_completion_tokens'] ?? json['max_tokens'];
    if (tokens != null && (tokens is! int || tokens < 1)) {
      throw const FormatException('max_tokens must be a positive integer.');
    }
    return CompletionRequest(
      InferenceRequest(
        model: model,
        messages: List.unmodifiable(messages),
        tools: choice == 'none' ? const [] : List.unmodifiable(definitions),
        temperature: _number(json, 'temperature', 2),
        topP: _number(json, 'top_p', 1),
        maxTokens: tokens as int?,
      ),
      stream: stream,
    );
  }

  static List<dynamic> _list(Object? value, String name) {
    if (value is List<dynamic>) return value;
    throw FormatException('$name must be an array.');
  }

  static Map<String, dynamic> _function(Object? raw) {
    if (raw is Map<String, dynamic> &&
        raw['type'] == 'function' &&
        raw['function'] is Map<String, dynamic>) {
      return raw['function'] as Map<String, dynamic>;
    }
    throw const FormatException('Only function tools are supported.');
  }

  static String _string(Object? value, String name) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('$name must be a non-empty string.');
  }

  static double? _number(Map<String, dynamic> json, String key, int maximum) {
    final value = json[key];
    if (value == null) return null;
    if (value is num && value.isFinite && value >= 0 && value <= maximum) {
      return value.toDouble();
    }
    throw FormatException('$key must be between 0 and $maximum.');
  }
}
