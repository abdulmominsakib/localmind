import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;

/// "Search the web" for the next message only, set from the composer.
///
/// The app runs the search itself and adds the results to the prompt, so it
/// also works with models that can't call tools. Cleared by the send that
/// uses it and when switching chats.
final webSearchNextProvider = NotifierProvider<WebSearchNextNotifier, bool>(
  WebSearchNextNotifier.new,
);

class WebSearchNextNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(conv.activeConversationIdProvider);
    return false;
  }

  void set(bool value) => state = value;

  bool take() {
    final value = state;
    state = false;
    return value;
  }
}
