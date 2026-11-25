import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/data/models/live_generation.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_notifier.dart';
import 'package:localmind/features/chat/views/components/prompt_processing_indicator.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';

class _FixedChatNotifier extends ChatNotifier {
  _FixedChatNotifier(this._fixedState);
  final ChatState _fixedState;

  @override
  ChatState build() => _fixedState;
}

class _MockSettingsNotifier extends SettingsNotifier {
  _MockSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  AppSettings build() => _settings;
}

class _NoActiveConversation extends conv.ActiveConversationNotifier {
  @override
  Conversation? build() => null;
}

Widget _host({required ChatState chatState, AppSettings? settings}) {
  return ProviderScope(
    overrides: [
      chatProvider.overrideWith(() => _FixedChatNotifier(chatState)),
      settingsProvider.overrideWith(
        () => _MockSettingsNotifier(
          settings ?? AppSettings(showPromptProcessingIndicator: true),
        ),
      ),
      conv.activeConversationProvider.overrideWith(_NoActiveConversation.new),
      conv.activeConversationIdProvider.overrideWith(
        () => _NoActiveConversationId(),
      ),
      conv.conversationsProvider.overrideWith(_EmptyConversations.new),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 320,
            height: 48,
            child: const PromptProcessingStatusBar(),
          ),
        ),
      ),
    ),
  );
}

class _NoActiveConversationId extends conv.ActiveConversationIdNotifier {
  @override
  String? build() => null;
}

class _EmptyConversations extends conv.ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async => [];
}

void main() {
  group('PromptProcessingStatusBar processing', () {
    testWidgets('shows percentage on first build without 400 ms delay', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now(),
              estimatedPrefillMs: 3000,
            ),
          ),
        ),
      );

      expect(find.textContaining('Processing prompt'), findsOneWidget);
      expect(find.textContaining('%'), findsOneWidget);
    });

    testWidgets('percentage advances while prefill is still running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now().subtract(
                const Duration(milliseconds: 300),
              ),
              estimatedPrefillMs: 4000,
            ),
          ),
        ),
      );

      final before = tester.widget<Text>(find.textContaining('%')).data;
      // The indicator derives its value from wall clock time, which fake async
      // pumping does not advance, so let real time pass and then fire the
      // periodic repaint ticker.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 900)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final after = tester.widget<Text>(find.textContaining('%')).data;

      expect(before, isNot(after));
      int pct(String? label) =>
          int.parse(RegExp(r'(\d+)%').firstMatch(label!)!.group(1)!);
      expect(pct(after), greaterThan(pct(before)));

      // The bar is first built while idle, so the repaint ticker must be
      // started from build() rather than initState alone.
      expect(find.text('Processing prompt'), findsOneWidget);
    });

    testWidgets('never reports 100% while prefill is still running', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now().subtract(const Duration(seconds: 30)),
              estimatedPrefillMs: 1000,
            ),
          ),
        ),
      );

      expect(find.textContaining('Processing prompt'), findsOneWidget);
      expect(find.textContaining('100%'), findsNothing);
      expect(find.textContaining('99%'), findsOneWidget);

      final arc = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(arc.value, lessThanOrEqualTo(0.99));
    });

    testWidgets('caps the arc when the backend reports full progress', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now().subtract(const Duration(seconds: 2)),
              estimatedPrefillMs: 1000,
              realPrefillProgress: 1.0,
            ),
          ),
        ),
      );

      expect(find.textContaining('99%'), findsOneWidget);
      final arc = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(arc.value, 0.99);
    });
  });

  group('PromptProcessingStatusBar disabled', () {
    testWidgets('renders nothing when the indicator setting is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.processingPrompt,
              startedAt: DateTime.now().subtract(const Duration(seconds: 2)),
              estimatedPrefillMs: 4000,
            ),
          ),
          settings: AppSettings(showPromptProcessingIndicator: false),
        ),
      );

      expect(find.byType(PromptProcessingStatusBar), findsOneWidget);
      expect(find.textContaining('Processing prompt'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('PromptProcessingStatusBar generating', () {
    testWidgets(
      'shows thinking state with elapsed time when reasoning arrived but no content',
      (tester) async {
        await tester.pumpWidget(
          _host(
            chatState: ChatState(
              liveGeneration: LiveGeneration(
                phase: LiveGenerationPhase.generating,
                startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
                estimatedPrefillMs: 1000,
                firstTokenAt: DateTime.now().subtract(
                  const Duration(seconds: 4),
                ),
              ),
              streamingMessage: Message(
                id: 'm1',
                conversationId: 'c1',
                role: MessageRole.assistant,
                content: '',
                reasoningContent: 'some thinking',
                createdAt: DateTime.now(),
                status: MessageStatus.streaming,
              ),
            ),
          ),
        );

        expect(find.textContaining('Thinking'), findsOneWidget);
        expect(find.textContaining('s'), findsOneWidget);
        expect(find.textContaining('tok/s'), findsNothing);
        expect(find.textContaining('0 tok'), findsNothing);
      },
    );

    testWidgets('switches to generating stats once content arrives', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.generating,
              startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
              estimatedPrefillMs: 1000,
              firstTokenAt: DateTime.now().subtract(const Duration(seconds: 4)),
            ),
            streamingMessage: Message(
              id: 'm1',
              conversationId: 'c1',
              role: MessageRole.assistant,
              content: 'Hello world from the model',
              reasoningContent: 'some thinking',
              createdAt: DateTime.now(),
              status: MessageStatus.streaming,
            ),
          ),
        ),
      );

      expect(find.textContaining('Generating'), findsOneWidget);
      expect(find.textContaining('tok/s'), findsOneWidget);
    });
  });

  group('composer status line', () {
    testWidgets('generating shows a dot, a plain label and steady stats', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.generating,
              startedAt: DateTime.now().subtract(const Duration(seconds: 3)),
              estimatedPrefillMs: 500,
              firstTokenAt: DateTime.now().subtract(const Duration(seconds: 2)),
            ),
            streamingMessage: Message(
              id: 'm1',
              conversationId: 'c1',
              role: MessageRole.assistant,
              content: 'x' * 400,
              createdAt: DateTime.now(),
              status: MessageStatus.streaming,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('live_status_generating')),
        findsOneWidget,
      );
      expect(find.text('Generating'), findsOneWidget);
      expect(find.textContaining('…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 100 tokens over ~2 s: a whole number, no decimal jitter.
      expect(
        find.textContaining(RegExp(r'^\d+ tok/s · \d+\.\ds$')),
        findsOneWidget,
      );

      // Centred in the composer, small and quiet.
      final line = tester.getCenter(
        find.byKey(const ValueKey('live_status_generating')),
      );
      final box = tester.getCenter(find.byType(PromptProcessingStatusBar));
      expect((line.dx - box.dx).abs(), lessThan(2));
      expect(
        tester.widget<Text>(find.text('Generating')).style?.fontSize,
        lessThanOrEqualTo(12),
      );
    });

    testWidgets('finished reply says Done, then goes away', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        _host(
          chatState: ChatState(
            liveGeneration: LiveGeneration(
              phase: LiveGenerationPhase.completed,
              startedAt: now.subtract(const Duration(seconds: 7)),
              estimatedPrefillMs: 500,
              completedAt: now,
              outputTokens: 223,
              tokensPerSecond: 60.04,
              generationTimeMs: 6300,
            ),
          ),
        ),
      );

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('223 tok · 60 tok/s · 6.3s'), findsOneWidget);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2700)),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Done'), findsNothing);
    });

    test('formats speed and duration', () {
      expect(formatTokensPerSecond(68.44), '68');
      expect(formatTokensPerSecond(7.25), '7.3');
      expect(formatLiveDuration(1900), '1.9s');
      expect(formatLiveDuration(65000), '1m 05s');
    });
  });
}
