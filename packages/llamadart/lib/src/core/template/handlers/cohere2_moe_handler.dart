import '../chat_format.dart';
import 'command_r7b_handler.dart';

/// Handler for Cohere2 MoE / North Code templates.
///
/// This format is similar to Command-R action blocks, but content responses are
/// wrapped in `<|START_TEXT|>...<|END_TEXT|>` instead of
/// `<|START_RESPONSE|>...<|END_RESPONSE|>`.
class Cohere2MoeHandler extends CommandR7BHandler {
  @override
  ChatFormat get format => ChatFormat.cohere2Moe;

  @override
  List<String> get additionalStops => ['<|END_TEXT|>'];

  @override
  List<String> getStops({bool hasTools = false, bool enableThinking = true}) {
    return [...additionalStops, if (hasTools) '<|END_ACTION|>'];
  }
}
