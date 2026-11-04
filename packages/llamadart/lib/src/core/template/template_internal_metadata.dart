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

/// Internal metadata key carrying caller-provided template `now` value.
///
/// Value is serialized as an ISO-8601 timestamp string in UTC.
const String internalTemplateNowMetadataKey = 'llamadart.internal.now';
