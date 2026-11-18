import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/core/storage/objectbox_store.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/objectbox.g.dart';

void main() {
  test(
    'increments the latest row and preserves synced chat metadata',
    () async {
      final updatedAt = DateTime.utc(2026, 11, 18);
      final row = ConversationEntity(
        id: 'chat',
        title: 'Synced chat',
        createdAt: updatedAt,
        updatedAt: updatedAt,
        mcpEnabled: false,
        systemPrompt: 'Synced instructions',
        promptsProcessed: 7,
      );
      final db = _Database(row);
      final cached = row.toDomain().copyWith(
        mcpEnabled: true,
        systemPrompt: 'Old instructions',
        promptsProcessed: 2,
      );
      final container = ProviderContainer.test(
        overrides: [
          databaseProvider.overrideWithValue(db),
          conversationsProvider.overrideWith(() => _Notifier(cached)),
        ],
      );
      await container.read(conversationsProvider.future);
      final notifier = container.read(conversationsProvider.notifier);

      await Future.wait([
        notifier.incrementPromptsProcessed(row.id),
        notifier.incrementPromptsProcessed(row.id),
      ]);

      expect(row.promptsProcessed, 9);
      expect(row.updatedAt, updatedAt);
      final saved = container.read(conversationsProvider).requireValue.single;
      expect(saved.promptsProcessed, 9);
      expect(saved.mcpEnabled, isFalse);
      expect(saved.systemPrompt, 'Synced instructions');

      row.promptsProcessed = 0x7fffffffffffffff;
      await notifier.incrementPromptsProcessed(row.id);
      expect(row.promptsProcessed, 0x7fffffffffffffff);
      expect(db.box.writes, 2);
    },
  );
}

class _Notifier extends ConversationsNotifier {
  _Notifier(this.cached);

  final Conversation cached;

  @override
  Future<List<Conversation>> build() async => [cached];
}

class _Database extends Fake implements ObjectBoxStore {
  _Database(ConversationEntity row) {
    box = _ConversationBox(store, row);
  }

  @override
  final _Store store = _Store();

  late final _ConversationBox box;

  @override
  Box<ConversationEntity> get conversationBox => box;
}

class _Store extends Fake implements Store {
  bool writing = false;

  @override
  R runInTransaction<R>(TxMode mode, R Function() fn) {
    expect(mode, TxMode.write);
    writing = true;
    try {
      return fn();
    } finally {
      writing = false;
    }
  }
}

class _ConversationBox extends Fake implements Box<ConversationEntity> {
  _ConversationBox(this.store, this.row);

  final _Store store;
  ConversationEntity row;
  int writes = 0;

  @override
  QueryBuilder<ConversationEntity> query([Condition<ConversationEntity>? qc]) {
    expect(store.writing, isTrue);
    return _Builder(row);
  }

  @override
  int put(ConversationEntity object, {PutMode mode = PutMode.put}) {
    expect(store.writing, isTrue);
    row = object;
    writes++;
    return object.internalId;
  }
}

class _Builder extends Fake implements QueryBuilder<ConversationEntity> {
  _Builder(this.row);

  final ConversationEntity row;

  @override
  Query<ConversationEntity> build() => _Query(row);
}

class _Query extends Fake implements Query<ConversationEntity> {
  _Query(this.row);

  final ConversationEntity row;

  @override
  ConversationEntity findFirst() => row;

  @override
  void close() {}
}
