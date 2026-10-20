import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/views/components/conversation_tile.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  testWidgets('actions sheet clears the Android navigation bar', (
    tester,
  ) async {
    const navBarHeight = 48.0;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: navBarHeight),
          ),
          child: Scaffold(
            body: ConversationActionsSheet(
              conversation: Conversation(
                id: 'conv-1',
                title: 'New Chat',
                createdAt: DateTime.utc(2026, 10, 20),
                updatedAt: DateTime.utc(2026, 10, 20),
              ),
              onTogglePin: () {},
              onRename: () {},
              onDuplicate: () {},
              onMoveToFolder: () {},
              onExport: () {},
              onArchive: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(
      (scroll.padding! as EdgeInsets).bottom,
      greaterThanOrEqualTo(navBarHeight),
    );
  });
}
