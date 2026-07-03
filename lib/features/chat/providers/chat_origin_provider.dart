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

/// Folder to auto-assign to the next conversation created by sendMessage,
/// set by the history screen's "new chat in this folder" FAB and consumed
/// once when that conversation is actually created.
final pendingNewChatFolderIdProvider =
    NotifierProvider<PendingNewChatFolderIdNotifier, String?>(
      PendingNewChatFolderIdNotifier.new,
    );

class PendingNewChatFolderIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? folderId) => state = folderId;

  String? consume() {
    final value = state;
    state = null;
    return value;
  }
}
