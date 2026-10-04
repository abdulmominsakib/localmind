import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/utils/ascii_logo.dart';

/// Where a new chat's messages will go, which decides what the new-chat
/// screen promises about privacy.
enum NewChatReach {
  /// No server is set up yet.
  none,

  /// Runs on this phone; nothing is sent anywhere.
  onDevice,

  /// The user's own LM Studio or Ollama server.
  selfHosted,

  /// An OpenAI-compatible URL — it may be self-hosted or a hosted API, so
  /// the screen makes no privacy claim either way.
  endpoint,

  /// A hosted service such as OpenRouter, Requesty or Ollama Cloud.
  cloud,
}

/// What the status pill on the new-chat screen reports.
enum NewChatReadiness {
  ready,

  /// Connected, but no model is chosen yet.
  noModel,

  /// The server can't be reached.
  disconnected,
}

class NewChatPresence {
  const NewChatPresence({
    required this.reach,
    required this.logo,
    this.serverType,
  });

  /// [serverType] is the active server's type, or null when there is none.
  factory NewChatPresence.forServerType(ServerType? serverType) {
    final (reach, logo) = switch (serverType) {
      null => (NewChatReach.none, AsciiLogo.localMind),
      ServerType.onDevice => (NewChatReach.onDevice, AsciiLogo.localMind),
      ServerType.lmStudio => (NewChatReach.selfHosted, AsciiLogo.lmStudio),
      ServerType.ollama => (NewChatReach.selfHosted, AsciiLogo.ollama),
      ServerType.openAICompatible => (NewChatReach.endpoint, AsciiLogo.server),
      ServerType.ollamaCloud => (NewChatReach.cloud, AsciiLogo.ollama),
      ServerType.openRouter => (NewChatReach.cloud, AsciiLogo.openRouter),
      ServerType.requesty => (NewChatReach.cloud, AsciiLogo.requesty),
    };
    return NewChatPresence(reach: reach, logo: logo, serverType: serverType);
  }

  final NewChatReach reach;
  final AsciiLogo logo;
  final ServerType? serverType;
}
