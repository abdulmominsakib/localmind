import 'package:flutter_riverpod/flutter_riverpod.dart';

final messageSelectionModeProvider =
    NotifierProvider<MessageSelectionModeNotifier, bool>(
      MessageSelectionModeNotifier.new,
    );

class MessageSelectionModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;

  void disable() {
    state = false;
    ref.read(selectedMessageIdsProvider.notifier).clear();
  }
}

final selectedMessageIdsProvider =
    NotifierProvider<SelectedMessageIdsNotifier, Set<String>>(
      SelectedMessageIdsNotifier.new,
    );

class SelectedMessageIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final updated = {...state};
    if (!updated.remove(id)) updated.add(id);
    state = updated;
  }

  void clear() => state = const {};
}
