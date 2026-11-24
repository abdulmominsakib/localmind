import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/features/conversations/views/components/conversation_tile.dart';
import 'package:localmind/l10n/app_localizations.dart';

Conversation _conv(String id, {List<String> tags = const []}) => Conversation(
  id: id,
  title: 'Chat $id',
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
  tags: tags,
);

class _FakeConversations extends ConversationsNotifier {
  _FakeConversations(this._items);
  final List<Conversation> _items;

  @override
  Future<List<Conversation>> build() async => _items;
}

void main() {
  group('normalizeConversationTags', () {
    test('trims, drops blanks and # and dedupes case-insensitively', () {
      expect(
        normalizeConversationTags([' Work ', '', '#ideas', 'work', 'a   b']),
        ['Work', 'ideas', 'a b'],
      );
    });

    test('caps tag length', () {
      final tag = normalizeConversationTags(['x' * 80]).single;
      expect(tag.length, maxConversationTagLength);
    });
  });

  test('tags survive the ObjectBox entity round trip', () {
    final entity = ConversationEntity.fromDomain(
      _conv('1', tags: ['work', 'Rust']),
    );
    expect(entity.toDomain().tags, ['work', 'Rust']);

    final untagged = ConversationEntity.fromDomain(_conv('2'));
    expect(untagged.tagsJson, isNull);
    expect(untagged.toDomain().tags, isEmpty);
  });

  test('a corrupt tag column reads as no tags', () {
    final entity = ConversationEntity.fromDomain(_conv('1'))
      ..tagsJson = '{not json';
    expect(entity.toDomain().tags, isEmpty);
  });

  test('tag filter narrows history and the tag list is deduped', () async {
    final container = ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith(
          () => _FakeConversations([
            _conv('a', tags: ['Work']),
            _conv('b', tags: ['work', 'home']),
            _conv('c'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(conversationsProvider.future);

    expect(container.read(conversationTagsProvider), ['home', 'Work']);

    container.read(historyTagFilterProvider.notifier).setFilter('WORK');
    final ids = container
        .read(filteredConversationsProvider)
        .value!
        .map((c) => c.id)
        .toSet();
    expect(ids, {'a', 'b'});
  });

  test('search matches tags', () async {
    final container = ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith(
          () => _FakeConversations([
            _conv('a', tags: ['travel']),
            _conv('b'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(conversationsProvider.future);

    container.read(conversationSearchProvider.notifier).setSearchQuery('trav');
    final ids = container
        .read(filteredConversationsProvider)
        .value!
        .map((c) => c.id);
    expect(ids, ['a']);
  });

  testWidgets('actions sheet offers tags only when wired', (tester) async {
    Future<void> pump({
      VoidCallback? onEditTags,
      List<String> tags = const [],
    }) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationActionsSheet(
              conversation: _conv('1', tags: tags),
              onTogglePin: () {},
              onRename: () {},
              onDuplicate: () {},
              onMoveToFolder: () {},
              onEditTags: onEditTags,
              onExport: () {},
              onArchive: () {},
              onDelete: () {},
            ),
          ),
        ),
      );
    }

    await pump();
    expect(
      find.byKey(const ValueKey('conversation_action_tags')),
      findsNothing,
    );

    await pump(onEditTags: () {});
    expect(find.text('Add tags'), findsOneWidget);

    await pump(onEditTags: () {}, tags: ['work']);
    expect(find.text('Edit tags'), findsOneWidget);
  });
}
