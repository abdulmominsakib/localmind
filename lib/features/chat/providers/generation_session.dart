import 'dart:async';

import 'package:localmind/features/servers/data/models/server.dart';

import '../data/chat_service.dart';
import '../data/models/message.dart' show Message;

/// Snapshot of a reply that is generating, exposed to the UI. Only the
/// conversation and whether it occupies the (single) on-device engine matter
/// to views.
class ActiveGeneration {
  const ActiveGeneration({
    required this.conversationId,
    required this.isOnDevice,
  });

  final String conversationId;
  final bool isOnDevice;
}

/// Everything that belongs to one in-flight reply. Remote replies (LM Studio,
/// Ollama, OpenRouter, ...) can run one session per conversation at the same
/// time; on-device replies share a single engine, so at most one on-device
/// session exists at a time.
class GenerationSession {
  GenerationSession({
    required this.conversationId,
    required this.server,
    required this.chatService,
    required this.persisted,
  });

  static const _checkpointChunkThreshold = 20;
  static const _checkpointTimeThreshold = Duration(seconds: 2);

  final String conversationId;
  final Server server;

  /// Service that owns this stream. Cancelling must target it, never a
  /// service shared with another reply.
  final ChatService chatService;

  /// False for temporary chats, whose messages are never written to disk.
  final bool persisted;

  bool get isOnDevice => server.isOnDevice;

  StreamSubscription<ChatResponse>? subscription;
  Timer? uiUpdateTimer;

  /// Most recent snapshot of the streaming assistant message. A chat that is
  /// reopened while this reply still runs reattaches to it.
  Message? latestMessage;

  /// Set once the reply is cancelled or replaced; late events are ignored.
  bool cancelled = false;

  int chunkCount = 0;
  DateTime? lastCheckpointTime;
  int lastSavedContentLength = 0;
  int lastSavedReasoningLength = 0;

  ChatStats? stats;
  DateTime? startTime;
  DateTime? firstTokenTime;

  void resetStreamMetrics() {
    stats = null;
    startTime = DateTime.now();
    firstTokenTime = null;
  }

  void noteFirstToken() {
    firstTokenTime ??= DateTime.now();
  }

  bool shouldCheckpointSave(Message message) {
    final now = DateTime.now();
    final contentLength = message.content.length;
    final reasoningLength = message.reasoningContent?.length ?? 0;

    final hasNewContent =
        contentLength > lastSavedContentLength ||
        reasoningLength > lastSavedReasoningLength;
    if (!hasNewContent) return false;

    final meetsChunkThreshold = chunkCount >= _checkpointChunkThreshold;
    final meetsTimeThreshold =
        lastCheckpointTime != null &&
        now.difference(lastCheckpointTime!) >= _checkpointTimeThreshold;

    return meetsChunkThreshold || meetsTimeThreshold;
  }

  void resetCheckpointMetrics() {
    chunkCount = 0;
    lastCheckpointTime = DateTime.now();
  }

  void updateSavedMetrics(Message message) {
    lastSavedContentLength = message.content.length;
    lastSavedReasoningLength = message.reasoningContent?.length ?? 0;
  }

  void cancelUiTimer() {
    uiUpdateTimer?.cancel();
    uiUpdateTimer = null;
  }

  /// Stops delivering events for this reply and cancels the UI timer and the
  /// stream subscription. Does not cancel the underlying request.
  Future<void> detach() async {
    cancelled = true;
    cancelUiTimer();
    final sub = subscription;
    subscription = null;
    if (sub != null) {
      await sub.cancel();
    }
  }
}
