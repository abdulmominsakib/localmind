import '../inference/generation_usage.dart';

/// A tool call in a completion chunk, shaped like OpenAI's streaming
/// `ToolCall`.
///
/// `LlamaEngine.create` does not stream calls as fragments. It emits each
/// call once, complete, in the final chunk, whose `finishReason` is
/// `tool_calls`. When the backend reports that the reply ended at the token
/// limit, every call is withheld, including complete ones, and the reply
/// finishes with `length`.
/// The same raw record type backs `partialToolCalls`, where entries can be
/// unfinished diagnostics and must never be executed.
class LlamaCompletionChunkToolCall {
  /// The position of this call among the calls of the completion.
  final int index;

  /// The call ID. `LlamaEngine.create` fills `call_<index>` when the model
  /// output has none for executable calls; diagnostics keep any generated ID.
  final String? id;

  /// The type of the tool call. Usually "function".
  final String? type;

  /// The function name and its arguments text.
  final LlamaCompletionChunkFunction? function;

  /// Creates a new [LlamaCompletionChunkToolCall].
  LlamaCompletionChunkToolCall({
    required this.index,
    this.id,
    this.type,
    this.function,
  });

  /// Creates a [LlamaCompletionChunkToolCall] from a JSON map.
  factory LlamaCompletionChunkToolCall.fromJson(Map<String, dynamic> json) {
    return LlamaCompletionChunkToolCall(
      index: json['index'] as int,
      id: json['id'] as String?,
      type: json['type'] as String?,
      function: json['function'] != null
          ? LlamaCompletionChunkFunction.fromJson(
              json['function'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// Converts this object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (function != null) 'function': function!.toJson(),
    };
  }

  @override
  String toString() =>
      'LlamaCompletionChunkToolCall(index: $index, id: $id, type: $type, function: $function)';
}

/// Represents a function call within a tool call.
class LlamaCompletionChunkFunction {
  /// The name of the function.
  final String? name;

  /// The function arguments as text. From `LlamaEngine.create` this is the
  /// complete arguments as a string, not a streaming fragment: usually a JSON
  /// object, but it can be empty or not an object. In `partialToolCalls`, this
  /// is raw diagnostic text and may be unfinished Python or JSON syntax.
  final String? arguments;

  /// Creates a new [LlamaCompletionChunkFunction].
  LlamaCompletionChunkFunction({this.name, this.arguments});

  /// Creates a [LlamaCompletionChunkFunction] from a JSON map.
  factory LlamaCompletionChunkFunction.fromJson(Map<String, dynamic> json) {
    return LlamaCompletionChunkFunction(
      name: json['name'] as String?,
      arguments: json['arguments'] as String?,
    );
  }

  /// Converts this object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      if (name != null) 'name': name,
      if (arguments != null) 'arguments': arguments,
    };
  }

  @override
  String toString() =>
      'LlamaCompletionChunkFunction(name: $name, arguments: $arguments)';
}

/// Represents a streaming chunk of a chat completion.
/// Aligns with OpenAI's `ChatCompletionChunk`.
class LlamaCompletionChunk {
  /// A unique identifier for the completion.
  final String id;

  /// The object type, which is always "chat.completion.chunk".
  final String object;

  /// The Unix timestamp (in seconds) of when the completion was created.
  final int created;

  /// The name of the model used for completion.
  ///
  /// `LlamaEngine` reports the last path segment of the source the model was
  /// loaded from, such as `qwen.gguf`: the file name of a local path, or the
  /// last segment of a URL path without its query or fragment. For a
  /// downloaded `ModelSource`, that is its `fileName`. A local file name is
  /// reported as written, `%` included; a URL segment is percent-decoded. It
  /// is `llama_model` when that segment is empty or contains one of
  /// `/ \ ? # @ ; & =` as written or percent-escaped, when a URL segment
  /// does not percent-decode to UTF-8, and for `data:` and `blob:` URLs.
  ///
  /// The value leaves out directories, hosts, queries and fragments, but not
  /// the segment itself: a URL whose last segment is a token reports that
  /// token.
  final String model;

  /// A list of completion choices.
  final List<LlamaCompletionChunkChoice> choices;

  /// Token counts and timings of the request, set only on the final chunk
  /// and only when the backend reports them.
  final LlamaGenerationUsage? usage;

  /// Creates a new [LlamaCompletionChunk].
  LlamaCompletionChunk({
    required this.id,
    required this.object,
    required this.created,
    required this.model,
    required this.choices,
    this.usage,
  });

  /// Creates a [LlamaCompletionChunk] from a JSON map.
  factory LlamaCompletionChunk.fromJson(Map<String, dynamic> json) {
    return LlamaCompletionChunk(
      id: json['id'] as String,
      object: json['object'] as String,
      created: json['created'] as int,
      model: json['model'] as String,
      choices: (json['choices'] as List<dynamic>)
          .map(
            (e) =>
                LlamaCompletionChunkChoice.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      usage: json['usage'] == null
          ? null
          : LlamaGenerationUsage.fromJson(
              json['usage'] as Map<String, dynamic>,
            ),
    );
  }

  /// Converts this object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'object': object,
      'created': created,
      'model': model,
      'choices': choices.map((e) => e.toJson()).toList(),
      if (usage != null) 'usage': usage!.toJson(),
    };
  }

  @override
  String toString() =>
      'LlamaCompletionChunk(id: $id, object: $object, created: $created, model: $model, choices: $choices'
      '${usage == null ? '' : ', usage: $usage'})';
}

/// Represents a choice in a completion chunk.
class LlamaCompletionChunkChoice {
  /// The index of the choice in the list of choices.
  final int index;

  /// A chat completion delta generated by streamed model responses.
  final LlamaCompletionChunkDelta delta;

  /// The reason the model stopped generating tokens.
  final String? finishReason;

  /// Creates a new [LlamaCompletionChunkChoice].
  LlamaCompletionChunkChoice({
    required this.index,
    required this.delta,
    this.finishReason,
  });

  /// Creates a [LlamaCompletionChunkChoice] from a JSON map.
  factory LlamaCompletionChunkChoice.fromJson(Map<String, dynamic> json) {
    return LlamaCompletionChunkChoice(
      index: json['index'] as int,
      delta: LlamaCompletionChunkDelta.fromJson(
        json['delta'] as Map<String, dynamic>,
      ),
      finishReason: json['finish_reason'] as String?,
    );
  }

  /// Converts this object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'delta': delta.toJson(),
      if (finishReason != null) 'finish_reason': finishReason,
    };
  }

  @override
  String toString() =>
      'LlamaCompletionChunkChoice(index: $index, delta: $delta, finishReason: $finishReason)';
}

/// Represents a delta in a completion choice.
class LlamaCompletionChunkDelta {
  /// The contents of the chunk message.
  final String? content;

  /// The tool calls information.
  final List<LlamaCompletionChunkToolCall>? toolCalls;

  /// Raw calls from an unfinished LFM tool envelope at a reported length limit.
  ///
  /// Terminal diagnostics only: arguments preserve generated text and may not
  /// be JSON. Never execute these records or add them to message history.
  /// Natural EOF and cancellation do not populate this field or imply a limit.
  final List<LlamaCompletionChunkToolCall>? partialToolCalls;

  /// The thinking content (LlamaDart extension).
  final String? thinking;

  /// The role of the author of this message.
  final String? role;

  /// Creates a new [LlamaCompletionChunkDelta].
  LlamaCompletionChunkDelta({
    this.content,
    this.toolCalls,
    this.partialToolCalls,
    this.thinking,
    this.role,
  });

  /// Creates a [LlamaCompletionChunkDelta] from a JSON map.
  factory LlamaCompletionChunkDelta.fromJson(Map<String, dynamic> json) {
    return LlamaCompletionChunkDelta(
      content: json['content'] as String?,
      toolCalls: (json['tool_calls'] as List<dynamic>?)
          ?.map(
            (e) => LlamaCompletionChunkToolCall.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      partialToolCalls: (json['partial_tool_calls'] as List<dynamic>?)
          ?.map(
            (e) => LlamaCompletionChunkToolCall.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      thinking: json['thinking'] as String?,
      role: json['role'] as String?,
    );
  }

  /// Converts this object to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      if (content != null) 'content': content,
      if (toolCalls != null)
        'tool_calls': toolCalls!.map((e) => e.toJson()).toList(),
      if (partialToolCalls != null)
        'partial_tool_calls': partialToolCalls!.map((e) => e.toJson()).toList(),
      if (thinking != null) 'thinking': thinking,
      if (role != null) 'role': role,
    };
  }

  @override
  String toString() =>
      'LlamaCompletionChunkDelta(content: $content, toolCalls: $toolCalls, partialToolCallCount: ${partialToolCalls?.length ?? 0}, thinking: $thinking, role: $role)';
}

/// Why a completion stopped, typed from the `finish_reason` wire value of a
/// [LlamaCompletionChunkChoice].
enum LlamaFinishReason {
  /// The model ended its output or hit a stop sequence. Wire value `stop`.
  stop('stop'),

  /// Generation stopped at `GenerationParams.maxTokens` or a full context
  /// before the model ended its output. Wire value `length`.
  length('length'),

  /// The final chunk carries tool calls. Wire value `tool_calls`.
  toolCalls('tool_calls');

  const LlamaFinishReason(this.wireValue);

  /// The `finish_reason` string this value is reported as.
  final String wireValue;

  /// Returns the value whose [wireValue] is [value].
  ///
  /// Returns null for null and for a value this enum does not know, such as
  /// one read by [LlamaCompletionChunk.fromJson]; the raw string stays on
  /// [LlamaCompletionChunkChoice.finishReason].
  static LlamaFinishReason? fromWireValue(String? value) {
    for (final reason in values) {
      if (reason.wireValue == value) return reason;
    }
    return null;
  }
}

/// Shortcuts for the first choice of a [LlamaCompletionChunk].
///
/// `LlamaEngine` and `ChatSession` stream one choice per chunk, so these
/// replace `chunk.choices.first.delta` lookups:
///
/// ```dart
/// await for (final chunk in engine.create(messages)) {
///   stdout.write(chunk.text);
/// }
/// ```
extension LlamaCompletionChunkExtension on LlamaCompletionChunk {
  /// The content delta of the first choice, or an empty string when the
  /// chunk has no choice or no content.
  String get text => choices.firstOrNull?.delta.content ?? '';

  /// The reasoning delta of the first choice, or an empty string when the
  /// chunk has no choice or no reasoning.
  String get thinking => choices.firstOrNull?.delta.thinking ?? '';

  /// The tool-call deltas of the first choice, or an empty list.
  ///
  /// Each entry is a fragment to accumulate by
  /// [LlamaCompletionChunkToolCall.index]; collect the stream with
  /// `collect()` to get complete tool calls.
  List<LlamaCompletionChunkToolCall> get toolCalls =>
      choices.firstOrNull?.delta.toolCalls ?? const [];

  /// Non-executable terminal diagnostics of the first choice, or an empty list.
  List<LlamaCompletionChunkToolCall> get partialToolCalls =>
      choices.firstOrNull?.delta.partialToolCalls ?? const [];

  /// The typed finish reason of the first choice.
  ///
  /// Null on every chunk but the final one, and for a `finish_reason` that
  /// [LlamaFinishReason] does not know.
  LlamaFinishReason? get finishReason =>
      LlamaFinishReason.fromWireValue(choices.firstOrNull?.finishReason);
}
