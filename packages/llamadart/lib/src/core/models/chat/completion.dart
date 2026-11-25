import 'dart:convert';

import '../inference/generation_usage.dart';
import 'chat_message.dart';
import 'chat_role.dart';
import 'completion_chunk.dart';
import 'content_part.dart';

/// A chat completion collected from a stream of [LlamaCompletionChunk]s.
///
/// Get one with `collect()` on a completion stream, `LlamaEngine.complete`
/// or `ChatSession.send`.
class LlamaCompletion {
  /// The concatenated content deltas.
  final String text;

  /// The concatenated reasoning deltas, or an empty string.
  final String thinking;

  /// The tool calls assembled from their streamed fragments, ordered by
  /// index.
  ///
  /// [LlamaToolCallContent.arguments] is empty when the streamed arguments
  /// are not a JSON object; [LlamaToolCallContent.rawJson] keeps them as
  /// generated.
  final List<LlamaToolCallContent> toolCalls;

  /// Raw named calls from an unfinished LFM envelope at a reported length limit.
  ///
  /// These diagnostics preserve generated argument text, including incomplete
  /// containers and escapes. They are never decoded, executable or included in
  /// [message]. Natural EOF and cancellation do not populate this field.
  final List<LlamaCompletionChunkToolCall> partialToolCalls;

  /// Why generation stopped, from the stream's final chunk.
  ///
  /// It does not report a cancel. On native llama.cpp and LiteRT-LM, a
  /// generation stopped by `LlamaEngine.cancelGeneration`, before or during
  /// generation, usually still ends with [LlamaFinishReason.stop] and the
  /// text generated so far. On WebGPU, `cancelGeneration` can instead fail
  /// the stream with a generation error. The code that cancels knows it did;
  /// on native llama.cpp and LiteRT-LM a `LlamaEngineObserver` also sees the
  /// cancel as `LlamaOperationResult.cancelled`.
  ///
  /// Null when the stream ended without a final chunk, or when its
  /// `finish_reason` is not a [LlamaFinishReason].
  final LlamaFinishReason? finishReason;

  /// Token counts and timings, when the backend reports them.
  final LlamaGenerationUsage? usage;

  /// Creates a collected completion.
  const LlamaCompletion({
    required this.text,
    this.thinking = '',
    this.toolCalls = const [],
    this.partialToolCalls = const [],
    this.finishReason,
    this.usage,
  });

  /// The completion as an assistant message, ready to append to the history
  /// passed to `LlamaEngine.create`.
  ///
  /// Its parts are the [thinking], the [text] and then the [toolCalls],
  /// leaving out an empty [thinking] or [text]. `ChatSession` records its
  /// replies the same way, without the whitespace that ends [text].
  LlamaChatMessage get message => LlamaChatMessage.withContent(
    role: LlamaChatRole.assistant,
    content: [
      if (thinking.isNotEmpty) LlamaThinkingContent(thinking),
      if (text.isNotEmpty) LlamaTextContent(text),
      ...toolCalls,
    ],
  );

  @override
  String toString() =>
      'LlamaCompletion(text: $text, thinking: $thinking, '
      'toolCalls: ${toolCalls.length}, partialToolCalls: ${partialToolCalls.length}, '
      'finishReason: $finishReason, '
      'usage: $usage)';
}

/// Collects completion chunks into a [LlamaCompletion].
///
/// Reads the first choice of each chunk, like [LlamaCompletionChunkExtension].
class LlamaCompletionAccumulator {
  final StringBuffer _text = StringBuffer();
  final StringBuffer _thinking = StringBuffer();
  final Map<int, _ToolCallBuilder> _toolCalls = {};
  final List<LlamaCompletionChunkToolCall> _partialToolCalls = [];
  String? _finishReason;
  LlamaGenerationUsage? _usage;

  /// Adds the deltas of [chunk].
  void add(LlamaCompletionChunk chunk) {
    _usage = chunk.usage ?? _usage;
    final choice = chunk.choices.firstOrNull;
    if (choice == null) return;
    final delta = choice.delta;
    if (delta.content != null) _text.write(delta.content);
    if (delta.thinking != null) _thinking.write(delta.thinking);
    for (final fragment in delta.toolCalls ?? const []) {
      final builder = _toolCalls.putIfAbsent(
        fragment.index,
        _ToolCallBuilder.new,
      );
      if (fragment.id != null) builder.id = fragment.id;
      final function = fragment.function;
      if (function?.name != null) builder.name = function!.name;
      if (function?.arguments != null) {
        builder.arguments.write(function!.arguments);
      }
    }
    _partialToolCalls.addAll(delta.partialToolCalls ?? const []);
    _finishReason = choice.finishReason ?? _finishReason;
  }

  /// The completion collected so far.
  LlamaCompletion build() {
    final indices = _toolCalls.keys.toList()..sort();
    return LlamaCompletion(
      text: _text.toString(),
      thinking: _thinking.toString(),
      toolCalls: [for (final index in indices) _toolCalls[index]!.build()],
      partialToolCalls: List.unmodifiable(_partialToolCalls),
      finishReason: LlamaFinishReason.fromWireValue(_finishReason),
      usage: _usage,
    );
  }
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  LlamaToolCallContent build() {
    final rawJson = arguments.toString();
    var decoded = <String, dynamic>{};
    if (rawJson.isNotEmpty) {
      try {
        final value = jsonDecode(rawJson);
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        // Partial or invalid JSON keeps empty arguments; rawJson holds it.
      }
    }
    return LlamaToolCallContent(
      id: id,
      name: name ?? '',
      arguments: decoded,
      rawJson: rawJson,
    );
  }
}

/// Text and collection helpers for a chat-completion stream, such as the
/// one `LlamaEngine.create` or `ChatSession.create` returns.
///
/// Each helper listens to the stream once, and reads the first choice of
/// each chunk.
///
/// ```dart
/// final reply = await engine.create(messages).text();
///
/// await engine.create(messages).textDeltas().forEach(stdout.write);
///
/// final completion = await engine.create(messages, tools: tools).collect();
/// if (completion.finishReason == LlamaFinishReason.toolCalls) {
///   for (final call in completion.toolCalls) {
///     print('${call.name}(${call.arguments})');
///   }
/// }
/// ```
extension LlamaCompletionStreamExtension on Stream<LlamaCompletionChunk> {
  /// The non-empty content deltas, in order.
  Stream<String> textDeltas() =>
      map((chunk) => chunk.text).where((text) => text.isNotEmpty);

  /// The concatenated content deltas, once the stream is done.
  Future<String> text() => textDeltas().join();

  /// The text, reasoning, tool calls, finish reason and usage of the whole
  /// stream, once it is done.
  Future<LlamaCompletion> collect() async {
    final accumulator = LlamaCompletionAccumulator();
    await for (final chunk in this) {
      accumulator.add(chunk);
    }
    return accumulator.build();
  }
}
