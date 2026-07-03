import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the currently active chat was opened from, so the root back
/// handler can return there instead of always starting a new chat.
enum ChatOrigin { none, history, savedMessages }

final chatOriginProvider =
    NotifierProvider<ChatOriginNotifier, ChatOrigin>(ChatOriginNotifier.new);

class ChatOriginNotifier extends Notifier<ChatOrigin> {
  @override
  ChatOrigin build() => ChatOrigin.none;

  void set(ChatOrigin origin) => state = origin;

  void clear() => state = ChatOrigin.none;
}
