import '../models/chat/chat_template_result.dart';

import 'tool_call_parsing_utils.dart';

/// Internal metadata key carrying tool choice for handler parity behavior.
///
/// This key is populated by [ChatTemplateEngine] and consumed by handlers that
/// need llama.cpp-compatible behavior dependent on `tool_choice`.
const String internalToolChoiceMetadataKey = 'llamadart.internal.tool_choice';

/// Internal metadata key carrying parallel tool-call preference.
///
/// Value is serialized as `'true'` or `'false'`.
const String internalParallelToolCallsMetadataKey =
    'llamadart.internal.parallel_tool_calls';

/// Internal metadata key carrying serialized chat_template_kwargs context.
///
/// Value is serialized as a JSON object string.
const String internalChatTemplateKwargsMetadataKey =
    'llamadart.internal.chat_template_kwargs';

/// Decodes the `chat_template_kwargs` stored under
/// [internalChatTemplateKwargsMetadataKey].
///
/// Returns an empty map when [metadata] carries none or an unreadable value.
Map<String, dynamic> chatTemplateKwargsFromMetadata(
  Map<String, String> metadata,
) {
  final rawKwargs = metadata[internalChatTemplateKwargsMetadataKey];
  if (rawKwargs == null || rawKwargs.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    final decoded = ToolCallParsingUtils.decodeJsonValue(rawKwargs);
    return ToolCallParsingUtils.coerceMap(decoded) ?? <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

/// Internal metadata key carrying caller-provided template `now` value.
///
/// Value is serialized as an ISO-8601 timestamp string in UTC.
const String internalTemplateNowMetadataKey = 'llamadart.internal.now';

/// Internal metadata key naming where the `templateSource` of
/// `ChatTemplateEngine.render` came from, such as `ModelParams.chatTemplate`.
///
/// A template that fails to render is named by it in the error.
const String internalTemplateSourceNameMetadataKey =
    'llamadart.internal.template_source_name';

final Expando<bool> _lfm2AutoGrammar = Expando<bool>(
  'llamadart.lfm2.autoGrammar',
);

/// Marks the newly constrained LFM2 Python-auto request, not force-JSON mode.
LlamaChatTemplateResult withLfm2AutoGrammar(
  LlamaChatTemplateResult result, {
  required bool enabled,
}) {
  if (enabled) _lfm2AutoGrammar[result] = true;
  return result;
}

/// Whether this result requires preservation of pre-grammar prompt penalties.
bool isLfm2AutoGrammar(LlamaChatTemplateResult result) =>
    _lfm2AutoGrammar[result] ?? false;

/// Copies the request policy only while the grammar itself is retained.
LlamaChatTemplateResult withLfm2AutoGrammarOf(
  LlamaChatTemplateResult copy,
  LlamaChatTemplateResult source,
) => withLfm2AutoGrammar(
  copy,
  enabled:
      isLfm2AutoGrammar(source) &&
      copy.grammar == source.grammar &&
      copy.grammarLazy == source.grammarLazy,
);

final Expando<bool> _singleToolCall = Expando<bool>('llamadart.singleToolCall');

/// Returns [result], marked when [single] as a render whose request allows at
/// most one tool call.
///
/// The Qwen3-Coder XML parse then takes only the first call, as llama.cpp's
/// parser does without parallel tool calls. Internal engine plumbing, not part
/// of the public API.
LlamaChatTemplateResult withSingleToolCall(
  LlamaChatTemplateResult result, {
  required bool single,
}) {
  if (single) _singleToolCall[result] = true;
  return result;
}

/// Whether [withSingleToolCall] marked [result].
bool singleToolCallOf(LlamaChatTemplateResult result) =>
    _singleToolCall[result] ?? false;

final Expando<bool> _bareFirstCall = Expando<bool>('llamadart.bareFirstCall');

/// Returns [result], marked when [bare] as a Qwen3-Coder render of a required
/// call whose first tool call may leave out `<tool_call>`, as llama.cpp allows
/// for a template without a thought.
///
/// The Qwen3-Coder XML parse then also ends the content at a declared tool's
/// `<function=…>` and takes the call that starts there. Internal engine
/// plumbing, not part of the public API.
LlamaChatTemplateResult withBareFirstCall(
  LlamaChatTemplateResult result, {
  required bool bare,
}) {
  if (bare) _bareFirstCall[result] = true;
  return result;
}

/// Whether [withBareFirstCall] marked [result].
bool bareFirstCallOf(LlamaChatTemplateResult result) =>
    _bareFirstCall[result] ?? false;
