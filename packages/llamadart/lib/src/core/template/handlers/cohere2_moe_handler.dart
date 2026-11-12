import '../chat_format.dart';
import 'command_r7b_handler.dart';

/// Handler for Cohere2 MoE / North Code templates.
///
/// This format is similar to Command-R action blocks, but content responses are
/// wrapped in `<|START_TEXT|>...<|END_TEXT|>` instead of
/// `<|START_RESPONSE|>...<|END_RESPONSE|>`.
class Cohere2MoeHandler extends CommandR7BHandler {
  /// The markers that, as in llama.cpp (`620d2225`), end a forced-open thought
  /// that skips `<|END_THINKING|>` and start the content.
  static const List<String> forcedThoughtContentOpenings = [
    '<|START_TEXT|>',
    '<|START_ACTION|>',
  ];

  @override
  ChatFormat get format => ChatFormat.cohere2Moe;

  @override
  List<String> get additionalStops => ['<|END_TEXT|>'];

  @override
  List<String>? get verbatimForcedThoughtOpenings =>
      forcedThoughtContentOpenings;

  @override
  bool get opensThoughtUnlessReasoningOff => true;

  // Matches what llama.cpp 620d2225 common/parsers/cohere2moe.cpp preserves.
  @override
  List<String> get preservedTokens => const [
    '<|START_OF_TURN_TOKEN|>',
    '<|END_OF_TURN_TOKEN|>',
    '<|CHATBOT_TOKEN|>',
    '<|USER_TOKEN|>',
    '<|SYSTEM_TOKEN|>',
    '<|START_THINKING|>',
    '<|END_THINKING|>',
    '<|START_TEXT|>',
    '<|END_TEXT|>',
    '<|START_ACTION|>',
    '<|END_ACTION|>',
    '<|START_TOOL_RESULT|>',
    '<|END_TOOL_RESULT|>',
  ];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<|END_ACTION|>'];
  }
}
