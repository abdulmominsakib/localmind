import '../data/models/message.dart';

class MessageVariants {
  static String groupId(Message message) =>
      message.variantGroupId?.isNotEmpty == true
      ? message.variantGroupId!
      : message.id;

  static List<Message> resolveActiveTimeline(List<Message> allMessages) {
    if (allMessages.isEmpty) return [];

    final normalized = allMessages.map(_normalizeLegacy).toList();
    final withParents = _ensureParentLinks(normalized);

    final childrenOf = <String, List<Message>>{};
    final roots = <Message>[];
    for (final message in withParents) {
      final parentId = message.parentMessageId;
      if (parentId == null || parentId.isEmpty) {
        roots.add(message);
      } else {
        childrenOf.putIfAbsent(parentId, () => []).add(message);
      }
    }

    if (roots.isEmpty) {
      return _legacyFlatResolve(normalized);
    }

    roots.sort((a, b) {
      final order = a.threadOrder.compareTo(b.threadOrder);
      if (order != 0) return order;
      return a.createdAt.compareTo(b.createdAt);
    });

    final timeline = <Message>[];
    var current = _pickActiveSibling(roots);
    while (true) {
      timeline.add(current);
      final children = childrenOf[current.id];
      if (children == null || children.isEmpty) break;
      current = _pickActiveSibling(children);
    }
    return timeline;
  }

  static List<Message> _legacyFlatResolve(List<Message> normalized) {
    final byGroup = <String, List<Message>>{};
    for (final message in normalized) {
      byGroup.putIfAbsent(groupId(message), () => []).add(message);
    }

    final active = <Message>[];
    for (final group in byGroup.values) {
      group.sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
      final selected = group.firstWhere(
        (m) => m.isActiveVariant,
        orElse: () => group.last,
      );
      active.add(selected);
    }

    active.sort((a, b) {
      final orderCompare = a.threadOrder.compareTo(b.threadOrder);
      if (orderCompare != 0) return orderCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
    return active;
  }

  static List<Message> _ensureParentLinks(List<Message> messages) {
    if (messages.any((m) => m.parentMessageId?.isNotEmpty == true)) {
      return messages;
    }

    final byThreadOrder = <int, List<Message>>{};
    for (final message in messages) {
      byThreadOrder.putIfAbsent(message.threadOrder, () => []).add(message);
    }
    final orders = byThreadOrder.keys.toList()..sort();

    String? previousActiveId;
    final updated = <Message>[];
    for (final order in orders) {
      final group = byThreadOrder[order]!;
      for (final message in group) {
        updated.add(message.copyWith(parentMessageId: previousActiveId));
      }
      final active = group.firstWhere(
        (m) => m.isActiveVariant,
        orElse: () => group.last,
      );
      previousActiveId = active.id;
    }
    return updated;
  }

  static Message _pickActiveSibling(List<Message> siblings) {
    final byGroup = <String, List<Message>>{};
    for (final message in siblings) {
      byGroup.putIfAbsent(groupId(message), () => []).add(message);
    }

    if (byGroup.length == 1) {
      final group = byGroup.values.first;
      group.sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
      return group.firstWhere(
        (m) => m.isActiveVariant,
        orElse: () => group.last,
      );
    }

    siblings.sort((a, b) {
      final order = a.threadOrder.compareTo(b.threadOrder);
      if (order != 0) return order;
      return a.createdAt.compareTo(b.createdAt);
    });
    return siblings.firstWhere(
      (m) => m.isActiveVariant,
      orElse: () => siblings.first,
    );
  }

  static List<Message> variantsForMessage(
    List<Message> allMessages,
    Message message,
  ) {
    final gid = groupId(message);
    return allMessages.where((m) => groupId(m) == gid).toList()
      ..sort((a, b) => a.variantIndex.compareTo(b.variantIndex));
  }

  static int activeVariantIndex(List<Message> variants) {
    final index = variants.indexWhere((m) => m.isActiveVariant);
    return index >= 0 ? index : variants.length - 1;
  }

  static Message _normalizeLegacy(Message message) {
    if (message.variantGroupId?.isNotEmpty == true) return message;
    return message.copyWith(
      variantGroupId: message.id,
      variantIndex: 0,
      isActiveVariant: true,
    );
  }

  static int nextThreadOrder(List<Message> activeTimeline) {
    if (activeTimeline.isEmpty) return 0;
    return activeTimeline
            .map((m) => m.threadOrder)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }
}
