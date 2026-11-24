import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;

/// An extra instruction for the next reply only, set from the composer.
///
/// It is added to the system prompt of the next request and then cleared, so
/// it never changes the chat's saved prompt. Switching to another chat
/// discards it.
final turnInstructionProvider =
    NotifierProvider<TurnInstructionNotifier, String?>(
      TurnInstructionNotifier.new,
    );

class TurnInstructionNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.watch(conv.activeConversationIdProvider);
    return null;
  }

  void set(String? instruction) {
    final trimmed = instruction?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  void clear() => state = null;

  /// Returns the instruction and clears it, for the send that uses it.
  String? take() {
    final value = state;
    state = null;
    return value;
  }
}

/// Appends [instruction] to [systemContent] as a one-reply note.
String? withTurnInstruction(String? systemContent, String? instruction) {
  final note = instruction?.trim();
  if (note == null || note.isEmpty) return systemContent;
  final line = 'For this reply only: $note';
  if (systemContent == null || systemContent.trim().isEmpty) return line;
  return '$systemContent\n\n$line';
}
