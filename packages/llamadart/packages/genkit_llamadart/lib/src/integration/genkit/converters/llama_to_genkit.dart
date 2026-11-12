import 'dart:convert';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../../core/streaming/completion_accumulator.dart';

final RegExp _inlineToolCallPattern = RegExp(
  r'<tool_call>\s*(\{.*?\})\s*</tool_call>',
  dotAll: true,
);

genkit.ModelResponseChunk? toGenkitChunk(llama.LlamaCompletionChunk chunk) {
  if (chunk.choices.isEmpty) {
    return null;
  }

  final choice = chunk.choices.first;
  final parts = <genkit.Part>[];
  final delta = choice.delta;

  if (delta.thinking != null && delta.thinking!.isNotEmpty) {
    parts.add(genkit.ReasoningPart(reasoning: delta.thinking!));
  }
  if (delta.content != null && delta.content!.isNotEmpty) {
    parts.add(genkit.TextPart(text: delta.content!));
  }
  if (delta.toolCalls != null) {
    parts.addAll(delta.toolCalls!.map(toGenkitToolRequestPart));
  }

  if (parts.isEmpty) {
    return null;
  }

  return genkit.ModelResponseChunk(
    role: genkit.Role.model,
    index: choice.index,
    content: parts,
    aggregated: false,
  );
}

genkit.ToolRequestPart toGenkitToolRequestPart(
  llama.LlamaCompletionChunkToolCall toolCall,
) {
  final function = toolCall.function;
  final rawArguments = function?.arguments;

  return genkit.ToolRequestPart(
    toolRequest: genkit.ToolRequest(
      ref: toolCall.id ?? 'call_${toolCall.index}',
      name: function?.name ?? 'unknown',
      input: _decodeToolArguments(rawArguments),
    ),
    metadata: rawArguments == null
        ? null
        : <String, dynamic>{'rawArguments': rawArguments},
  );
}

genkit.FinishReason mapFinishReason(String? finishReason) {
  return switch (finishReason) {
    'length' => genkit.FinishReason.length,
    'content_filter' => genkit.FinishReason.blocked,
    'tool_calls' => genkit.FinishReason.stop,
    'stop' => genkit.FinishReason.stop,
    null => genkit.FinishReason.stop,
    _ => genkit.FinishReason.unknown,
  };
}

genkit.ModelResponse toGenkitModelResponse(
  CompletionResult result, {
  required double latencyMs,
  required Map<String, dynamic> raw,
  bool allowToolCalls = true,
}) {
  if (result.toolCalls.isNotEmpty &&
      (!allowToolCalls || result.finishReason == 'length')) {
    throw _invalidToolCall();
  }
  for (final call in result.toolCalls) {
    if (call.function?.name == null || call.function!.name!.isEmpty) {
      throw _invalidToolCall();
    }
    _decodeFinalToolArguments(call.function?.arguments);
  }
  final fallback = allowToolCalls && result.toolCalls.isEmpty
      ? _extractInlineToolCalls(result.text)
      : null;
  if (fallback != null && result.finishReason == 'length') {
    throw _invalidToolCall();
  }
  final fallbackToolRequests =
      fallback?.toolRequests ?? const <genkit.ToolRequestPart>[];
  final visibleText = fallback?.remainingText ?? result.text;

  final parts = <genkit.Part>[];
  if (result.reasoning.isNotEmpty) {
    parts.add(genkit.ReasoningPart(reasoning: result.reasoning));
  }
  if (visibleText.isNotEmpty ||
      (result.toolCalls.isEmpty &&
          fallbackToolRequests.isEmpty &&
          parts.isEmpty)) {
    parts.add(genkit.TextPart(text: visibleText));
  }
  parts.addAll(result.toolCalls.map(toGenkitToolRequestPart));
  parts.addAll(fallbackToolRequests);

  return genkit.ModelResponse(
    message: genkit.Message(role: genkit.Role.model, content: parts),
    finishReason: mapFinishReason(result.finishReason),
    usage: toGenkitUsage(result.usage),
    latencyMs: latencyMs,
    raw: {...raw, if (result.usage != null) 'usage': result.usage!.toJson()},
  );
}

_InlineToolExtractionResult? _extractInlineToolCalls(String text) {
  final matches = _inlineToolCallPattern
      .allMatches(text)
      .toList(growable: false);
  final remainingText = text.replaceAll(_inlineToolCallPattern, '').trim();
  if (remainingText.contains('<tool_call>') ||
      remainingText.contains('</tool_call>')) {
    throw _invalidToolCall();
  }
  if (matches.isEmpty) {
    return null;
  }

  final toolRequests = <genkit.ToolRequestPart>[];
  for (var i = 0; i < matches.length; i++) {
    final payload = matches[i].group(1);
    if (payload == null) {
      return null;
    }

    final decoded = _tryDecodeMap(payload);
    if (decoded == null) {
      throw _invalidToolCall();
    }

    final name = decoded['name'];
    if (name is! String || name.isEmpty) {
      throw _invalidToolCall();
    }

    final id = decoded['id'];
    toolRequests.add(
      genkit.ToolRequestPart(
        toolRequest: genkit.ToolRequest(
          ref: id is String && id.isNotEmpty ? id : 'call_$i',
          name: name,
          input: _decodeFinalToolInput(decoded['arguments']),
        ),
        metadata: <String, dynamic>{'rawToolCall': payload},
      ),
    );
  }

  return _InlineToolExtractionResult(
    toolRequests: toolRequests,
    remainingText: remainingText,
  );
}

Map<String, dynamic> _decodeFinalToolInput(Object? value) {
  if (value == null) {
    return const <String, dynamic>{};
  }
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  if (value is String) {
    return _decodeFinalToolArguments(value);
  }
  throw _invalidToolCall();
}

Map<String, dynamic> _decodeFinalToolArguments(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final decoded = _tryDecodeMap(raw);
  if (decoded == null) throw _invalidToolCall();
  return decoded;
}

genkit.GenkitException _invalidToolCall() => genkit.GenkitException(
  'The model returned an invalid, truncated or disallowed tool call. '
  'No tool was executed; check the model template, tool choice and token limit.',
  status: genkit.StatusCode.dataLoss,
);

Map<String, dynamic>? _tryDecodeMap(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } catch (_) {
    return null;
  }
  return null;
}

class _InlineToolExtractionResult {
  const _InlineToolExtractionResult({
    required this.toolRequests,
    required this.remainingText,
  });

  final List<genkit.ToolRequestPart> toolRequests;
  final String remainingText;
}

Map<String, dynamic> _decodeToolArguments(String? rawArguments) {
  if (rawArguments == null || rawArguments.isEmpty) {
    return const <String, dynamic>{};
  }

  try {
    final decoded = jsonDecode(rawArguments);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{'value': decoded};
  } catch (_) {
    return <String, dynamic>{'_raw': rawArguments};
  }
}

genkit.GenerationUsage? toGenkitUsage(llama.LlamaGenerationUsage? usage) =>
    usage == null
    ? null
    : genkit.GenerationUsage(
        inputTokens: usage.promptTokens,
        outputTokens: usage.completionTokens,
        totalTokens: usage.totalTokens,
        cachedContentTokens: usage.cachedPromptTokens,
      );
