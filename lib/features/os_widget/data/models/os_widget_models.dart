enum OsWidgetAction { chat, newChat, voice, unknown }

class OsWidgetInvocation {
  final OsWidgetAction action;
  final String? prompt;
  final Uri? uri;

  const OsWidgetInvocation({required this.action, this.prompt, this.uri});

  factory OsWidgetInvocation.fromUri(Uri uri) {
    final actionParam =
        uri.queryParameters['action'] ??
        (uri.host.isNotEmpty && uri.host != 'widget' ? uri.host : null);
    final prompt = uri.queryParameters['prompt'] ?? uri.queryParameters['text'];

    final action = switch (actionParam) {
      'new_chat' || 'newChat' => OsWidgetAction.newChat,
      'voice' => OsWidgetAction.voice,
      'chat' => OsWidgetAction.chat,
      _ => OsWidgetAction.chat,
    };

    return OsWidgetInvocation(
      action: action,
      prompt: prompt != null && prompt.trim().isNotEmpty ? prompt.trim() : null,
      uri: uri,
    );
  }
}
