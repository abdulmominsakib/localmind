import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/services/app_haptics.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/background_generation_notice.dart';
import 'package:localmind/features/chat/views/components/heartbeat_dot.dart';

import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class _FakeChatNotifier extends ChatNotifier {
  Conversation? loadedConversation;

  @override
  ChatState build() => const ChatState();

  @override
  Future<void> loadConversation(Conversation conversation) async {
    loadedConversation = conversation;
  }
}

Widget _buildTestApp({
  required Widget child,
  required List<Conversation> conversations,
  _FakeChatNotifier? chatNotifier,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: [
      appHapticsProvider.overrideWithValue(AppHaptics(() => false)),
      conv.conversationsProvider.overrideWith(
        () => _StaticConversationsNotifier(conversations),
      ),
      if (chatNotifier != null) chatProvider.overrideWith(() => chatNotifier),
    ],
    child: ShadTheme(
      data: AppTheme.lightShadTheme,
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

class _StaticConversationsNotifier extends conv.ConversationsNotifier {
  _StaticConversationsNotifier(this._conversations);
  final List<Conversation> _conversations;

  @override
  Future<List<Conversation>> build() async => _conversations;
}

void main() {
  final sampleConversation = Conversation(
    id: 'conv-123',
    title: 'Function Creation Guide',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets(
    'shows non-blocking info notice with title for a single remote generation',
    (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          conversations: [sampleConversation],
          child: BackgroundGenerationNotice(
            generations: const [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
            ],
            blocksSending: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify icon is present
      final iconFinder = find.byWidgetPredicate(
        (widget) =>
            widget is HugeIcon &&
            widget.icon == HugeIcons.strokeRoundedBackground,
      );
      expect(iconFinder, findsOneWidget);

      // Verify circular progress indicator is present
      final spinnerFinder = find.byType(CircularProgressIndicator);
      expect(spinnerFinder, findsOneWidget);

      // Non-blocking text should mention "in the background"
      expect(find.textContaining('background'), findsOneWidget);
      expect(find.textContaining('Function Creation Guide'), findsOneWidget);

      // Verify horizontal ordering: Icon (left) < Text (middle) < Spinner (right)
      final iconOffset = tester.getCenter(iconFinder);
      final textOffset = tester.getCenter(
        find.textContaining('Function Creation Guide'),
      );
      final spinnerOffset = tester.getCenter(spinnerFinder);

      expect(
        iconOffset.dx,
        lessThan(textOffset.dx),
        reason: 'Icon should be to the left of the text',
      );
      expect(
        textOffset.dx,
        lessThan(spinnerOffset.dx),
        reason:
            'Circular progress indicator should be to the right of the text',
      );
    },
  );

  testWidgets('shows blocking notice with title for on-device conflict', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        conversations: [sampleConversation],
        child: BackgroundGenerationNotice(
          generations: const [
            ActiveGeneration(conversationId: 'conv-123', isOnDevice: true),
          ],
          blocksSending: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Blocking text should mention "once it finishes"
    expect(find.textContaining('once it finishes'), findsOneWidget);
    expect(find.textContaining('Function Creation Guide'), findsOneWidget);
  });

  testWidgets('shows plural notice when multiple chats are generating', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        conversations: [sampleConversation],
        child: const BackgroundGenerationNotice(
          generations: [
            ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
            ActiveGeneration(conversationId: 'conv-456', isOnDevice: false),
          ],
          blocksSending: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Should show the plural form with count
    expect(find.textContaining('2'), findsOneWidget);
    expect(find.textContaining('background'), findsOneWidget);
  });

  testWidgets('triggers loadConversation on tap', (tester) async {
    final fakeChat = _FakeChatNotifier();

    await tester.pumpWidget(
      _buildTestApp(
        conversations: [sampleConversation],
        chatNotifier: fakeChat,
        child: BackgroundGenerationNotice(
          generations: const [
            ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
          ],
          blocksSending: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(fakeChat.loadedConversation?.id, equals('conv-123'));
    expect(
      fakeChat.loadedConversation?.title,
      equals('Function Creation Guide'),
    );
  });

  testWidgets('renders untitled fallback when conversation is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        conversations: [],
        child: const BackgroundGenerationNotice(
          generations: [
            ActiveGeneration(conversationId: 'non-existent', isOnDevice: false),
          ],
          blocksSending: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // The untitled non-blocking text
    expect(find.textContaining('background'), findsOneWidget);
  });

  testWidgets(
    'clicking notice with 2 chats expands to show the two listed chats and allows selecting one',
    (tester) async {
      final conv1 = sampleConversation;
      final conv2 = Conversation(
        id: 'conv-456',
        title: 'Second Background Task',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final fakeChat = _FakeChatNotifier();

      await tester.pumpWidget(
        _buildTestApp(
          conversations: [conv1, conv2],
          chatNotifier: fakeChat,
          child: const BackgroundGenerationNotice(
            generations: [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
              ActiveGeneration(conversationId: 'conv-456', isOnDevice: true),
            ],
            blocksSending: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initially collapsed: listed chat items are not visible
      expect(find.text('Second Background Task'), findsNothing);

      // Tap the header to expand
      await tester.tap(find.textContaining('2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now expanded: both chats are listed
      expect(find.text('Function Creation Guide'), findsOneWidget);
      expect(find.text('Second Background Task'), findsOneWidget);
      expect(find.text('On-Device'), findsOneWidget);

      // Only ONE CircularProgressIndicator exists (at the top header)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Each chat item uses a HeartbeatDot instead of a spinner
      expect(find.byType(HeartbeatDot), findsNWidgets(2));

      // Tapping the second chat loads it
      await tester.tap(find.text('Second Background Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeChat.loadedConversation?.id, equals('conv-456'));
      expect(
        fakeChat.loadedConversation?.title,
        equals('Second Background Task'),
      );
    },
  );

  testWidgets(
    'collapsing when one chat finishes animates without layout overflow',
    (tester) async {
      final conv1 = sampleConversation;
      final conv2 = Conversation(
        id: 'conv-456',
        title: 'Second Background Task',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        _buildTestApp(
          conversations: [conv1, conv2],
          child: const BackgroundGenerationNotice(
            generations: [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
              ActiveGeneration(conversationId: 'conv-456', isOnDevice: false),
            ],
            blocksSending: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expand
      await tester.tap(find.textContaining('2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(HeartbeatDot), findsNWidgets(2));

      // Simulate one chat completing (notice drops to 1 generation, triggers collapse)
      await tester.pumpWidget(
        _buildTestApp(
          conversations: [conv1, conv2],
          child: const BackgroundGenerationNotice(
            generations: [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
            ],
            blocksSending: false,
          ),
        ),
      );

      // Pump intermediate frames of collapse animation (where subpixel constraints happen)
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));

      // Fully collapsed to single notice
      expect(find.byType(HeartbeatDot), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping header again when expanded collapses the list of chats',
    (tester) async {
      final conv1 = sampleConversation;
      final conv2 = Conversation(
        id: 'conv-456',
        title: 'Second Background Task',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        _buildTestApp(
          conversations: [conv1, conv2],
          child: const BackgroundGenerationNotice(
            generations: [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
              ActiveGeneration(conversationId: 'conv-456', isOnDevice: false),
            ],
            blocksSending: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Expand
      await tester.tap(find.textContaining('2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Second Background Task'), findsOneWidget);

      // Tap header again to collapse. The spring needs longer than the
      // expand check to fall below the visibility threshold.
      await tester.tap(find.textContaining('2'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Second Background Task'), findsNothing);
    },
  );

  testWidgets(
    'blocked send with several chats opens the on-device chat on tap',
    (tester) async {
      final onDeviceConversation = Conversation(
        id: 'conv-456',
        title: 'Local Gemma Chat',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final fakeChat = _FakeChatNotifier();

      await tester.pumpWidget(
        _buildTestApp(
          conversations: [sampleConversation, onDeviceConversation],
          chatNotifier: fakeChat,
          child: const BackgroundGenerationNotice(
            generations: [
              ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
              ActiveGeneration(conversationId: 'conv-456', isOnDevice: true),
            ],
            blocksSending: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Local Gemma Chat'), findsOneWidget);
      expect(find.textContaining('once it finishes'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Opens the blocking chat instead of expanding a list.
      expect(fakeChat.loadedConversation?.id, equals('conv-456'));
      expect(find.byType(HeartbeatDot), findsNothing);
    },
  );

  testWidgets('listed chat without a title uses a short fallback name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        conversations: [sampleConversation],
        child: const BackgroundGenerationNotice(
          generations: [
            ActiveGeneration(conversationId: 'conv-123', isOnDevice: false),
            ActiveGeneration(conversationId: 'missing', isOnDevice: false),
          ],
          blocksSending: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.textContaining('2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Untitled chat'), findsOneWidget);
  });
}
