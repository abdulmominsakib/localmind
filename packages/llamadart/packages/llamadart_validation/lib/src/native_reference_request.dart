import 'dart:convert';

import 'package:llamadart/llamadart.dart';

/// Text-only request for the pinned C API, independent of the public adapter.
/// The system setter accepts JSON content, not a role/content message object.
Map<String, dynamic> nativeReferenceRequest(
  String prompt, {
  List<LlamaChatMessage>? history,
}) {
  final messages =
      history ??
      [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)];
  if (messages.isEmpty ||
      messages.last.role != LlamaChatRole.user ||
      messages.last.content != prompt) {
    throw ArgumentError('Native control requires the final user prompt');
  }
  if (messages.any(
    (message) =>
        message.parts.any((part) => part is! LlamaTextContent) ||
        ![
          LlamaChatRole.system,
          LlamaChatRole.user,
          LlamaChatRole.assistant,
        ].contains(message.role),
  )) {
    throw UnsupportedError('Native control accepts text chat messages only');
  }
  Map<String, dynamic> encode(LlamaChatMessage message) => {
    'role': message.role.name,
    'content': [
      {'type': 'text', 'text': message.content},
    ],
  };
  final seed = messages.take(messages.length - 1);
  final system = seed
      .where((message) => message.role == LlamaChatRole.system)
      .map((message) => message.content.trim())
      .where((text) => text.isNotEmpty)
      .join('\n');
  final past = seed
      .where((message) => message.role != LlamaChatRole.system)
      .map(encode)
      .toList();
  return {
    'system_message_json': system.isEmpty ? null : jsonEncode(system),
    'messages_json': past.isEmpty ? null : jsonEncode(past),
    'message_json': jsonEncode(encode(messages.last)),
    'extra_context_json': jsonEncode({'enable_thinking': true}),
    'enable_constrained_decoding': false,
  };
}
