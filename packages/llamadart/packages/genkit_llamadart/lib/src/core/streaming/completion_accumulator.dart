import 'dart:collection';

import 'package:llamadart/llamadart.dart' as llama;

final class CompletionResult {
  const CompletionResult({
    required this.text,
    required this.reasoning,
    required this.toolCalls,
    this.usage,
    this.finishReason,
  });

  final String text;
  final String reasoning;
  final List<llama.LlamaCompletionChunkToolCall> toolCalls;
  final llama.LlamaGenerationUsage? usage;
  final String? finishReason;
}

class CompletionAccumulator {
  final StringBuffer _text = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  final SplayTreeMap<int, _AccumulatedToolCall> _toolCallsByIndex =
      SplayTreeMap<int, _AccumulatedToolCall>();

  llama.LlamaGenerationUsage? usage;
  String? finishReason;

  void addChunk(llama.LlamaCompletionChunk chunk) {
    usage = chunk.usage ?? usage;
    if (chunk.choices.isEmpty) {
      return;
    }

    final choice = chunk.choices.first;
    final delta = choice.delta;

    if (delta.content != null) {
      _text.write(delta.content);
    }
    if (delta.thinking != null) {
      _reasoning.write(delta.thinking);
    }
    if (delta.toolCalls != null && delta.toolCalls!.isNotEmpty) {
      for (final toolCall in delta.toolCalls!) {
        _toolCallsByIndex
            .putIfAbsent(
              toolCall.index,
              () => _AccumulatedToolCall(toolCall.index),
            )
            .merge(toolCall);
      }
    }
    if (choice.finishReason != null) {
      finishReason = choice.finishReason;
    }
  }

  CompletionResult toResult() {
    return CompletionResult(
      usage: usage,
      text: _text.toString(),
      reasoning: _reasoning.toString(),
      toolCalls: _toolCallsByIndex.values
          .map((toolCall) => toolCall.toToolCall())
          .toList(growable: false),
      finishReason: finishReason,
    );
  }
}

class _AccumulatedToolCall {
  _AccumulatedToolCall(this.index);

  final int index;
  String? _id;
  String? _type;
  String? _name;
  final StringBuffer _arguments = StringBuffer();

  void merge(llama.LlamaCompletionChunkToolCall delta) {
    _id ??= delta.id;
    _type ??= delta.type;

    final function = delta.function;
    if (function == null) {
      return;
    }

    _name ??= function.name;
    if (function.arguments != null && function.arguments!.isNotEmpty) {
      _arguments.write(function.arguments);
    }
  }

  llama.LlamaCompletionChunkToolCall toToolCall() {
    final arguments = _arguments.isEmpty ? null : _arguments.toString();
    return llama.LlamaCompletionChunkToolCall(
      index: index,
      id: _id,
      type: _type,
      function: _name == null && arguments == null
          ? null
          : llama.LlamaCompletionChunkFunction(
              name: _name,
              arguments: arguments,
            ),
    );
  }
}
