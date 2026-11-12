import 'dart:convert';

import '../exceptions.dart';
import '../grammar/llguidance_schema_contract.dart';
import '../models/chat/chat_message.dart';
import '../models/chat/chat_role.dart';
import '../models/chat/content_part.dart';
import '../models/inference/generation_params.dart';

/// Validates the schema-chat SPI contract and snapshots its JSON payload.
String jsonSchemaChatPayload(Map<String, dynamic> schema) {
  validateLlguidanceResponseSchema(schema);
  return jsonEncode(schema);
}

/// Rejects request modes outside the schema-chat SPI before native admission.
void validateJsonSchemaChatRequest(
  List<LlamaChatMessage> messages,
  GenerationParams params, {
  bool hasTools = false,
  bool requiredTools = false,
  bool parallelToolCalls = false,
  bool enableThinking = false,
}) {
  String? reason;
  if (hasTools || requiredTools || parallelToolCalls) {
    reason = 'tools and parallel tool calls';
  } else if (enableThinking) {
    reason =
        'thinking with the loaded model; only model families qualified to '
        'reason before a constrained reply (Gemma 4 on LiteRT-LM) accept it. '
        'Pass enableThinking: false and set no enable_thinking or thinking '
        'chat template kwarg to true';
  } else if (params.thinkingBudget != null) {
    reason = 'thinking budgets';
  } else if (params.isSpeculativeDecodingEnabled) {
    reason = 'speculative decoding';
  } else if (params.stopSequences.isNotEmpty) {
    reason = 'caller stop sequences';
  } else if (params.grammar != null ||
      params.grammarLazy ||
      params.grammarTriggers.isNotEmpty ||
      params.preservedTokens.isNotEmpty ||
      params.grammarRoot != 'root') {
    reason = 'GBNF grammar parameters';
  } else if (messages.isEmpty ||
      messages.last.role != LlamaChatRole.user ||
      messages.any(
        (message) =>
            message.role == LlamaChatRole.tool ||
            message.continuesPreviousTurn ||
            message.parts.any((part) => part is! LlamaTextContent),
      )) {
    reason =
        'media, reasoning, tool messages, or assistant continuation; '
        'use system/user/assistant text ending in a user message';
  }
  if (reason != null) {
    throw LlamaUnsupportedException(
      'Native JSON Schema chat does not support $reason.',
    );
  }
}
