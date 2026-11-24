import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/providers/turn_instruction_provider.dart';
import 'package:localmind/features/chat/views/components/turn_instruction_chip.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  group('withTurnInstruction', () {
    test('appends the note after the system prompt', () {
      expect(
        withTurnInstruction('Be kind.', 'Use bullets'),
        'Be kind.\n\nFor this reply only: Use bullets',
      );
    });

    test('stands alone when there is no system prompt', () {
      expect(
        withTurnInstruction(null, 'Use bullets'),
        'For this reply only: Use bullets',
      );
    });

    test('leaves the prompt alone without a note', () {
      expect(withTurnInstruction('Be kind.', null), 'Be kind.');
      expect(withTurnInstruction('Be kind.', '   '), 'Be kind.');
    });
  });

  group('turnInstructionProvider', () {
    test('take returns the note once', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(turnInstructionProvider.notifier);

      notifier.set('  Answer in French ');
      expect(container.read(turnInstructionProvider), 'Answer in French');
      expect(notifier.take(), 'Answer in French');
      expect(notifier.take(), isNull);
    });

    test('blank input clears it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(turnInstructionProvider.notifier);
      notifier.set('x');
      notifier.set('   ');
      expect(container.read(turnInstructionProvider), isNull);
    });

    test('switching chats discards it', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(turnInstructionProvider.notifier).set('Short answer');
      container
          .read(activeConversationIdProvider.notifier)
          .setActiveConversationId('other');
      expect(container.read(turnInstructionProvider), isNull);
    });
  });

  testWidgets('composer chip shows the note and clears it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TurnInstructionChip()),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('turn_instruction_chip')), findsNothing);

    container.read(turnInstructionProvider.notifier).set('Use a table');
    await tester.pump();
    expect(find.textContaining('Use a table'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('turn_instruction_clear')));
    await tester.pump();
    expect(container.read(turnInstructionProvider), isNull);
  });

  testWidgets('dialog saves the typed note', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: TurnInstructionDialog()),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('turn_instruction_input')),
      'Keep it under 50 words',
    );
    await tester.tap(find.byKey(const ValueKey('turn_instruction_save')));
    await tester.pump();
    expect(container.read(turnInstructionProvider), 'Keep it under 50 words');
  });
}
