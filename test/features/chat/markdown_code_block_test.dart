import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/highlighter_provider.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/markdown/markdown_code_block.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/markdown/themed_gpt_markdown.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HighlighterThemes themes;

  // Load assets outside any widget test's fake-async zone: rootBundle caches
  // the load, and one started inside a widget test never completes for the
  // tests after it.
  setUpAll(() async {
    await Highlighter.initialize(['dart']);
    themes = await HighlighterThemes.load();
  });

  Future<void> pumpMarkdown(WidgetTester tester, String content) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MarkdownBodyContent(content: content, isDark: false),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('highlighterLanguageFor', () {
    test('maps common fence labels to grammars', () {
      expect(highlighterLanguageFor('dart'), 'dart');
      expect(highlighterLanguageFor('Python title=main.py'), 'python');
      expect(highlighterLanguageFor('ts'), 'typescript');
      expect(highlighterLanguageFor('yml'), 'yaml');
    });

    test('returns null when no grammar exists', () {
      expect(highlighterLanguageFor('bash'), isNull);
      expect(highlighterLanguageFor(''), isNull);
    });
  });

  testWidgets('fenced code renders in a code block with its label', (
    tester,
  ) async {
    await pumpMarkdown(tester, 'Run:\n\n```bash\necho \$HOME\n```\n');

    expect(find.byType(MarkdownCodeBlock), findsOneWidget);
    expect(find.text('bash'), findsOneWidget);
    // The `$` → LaTeX pass must not touch code.
    expect(find.textContaining(r'echo $HOME'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy button copies the code and confirms', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpMarkdown(tester, '```dart\nvoid main() {}\n```');
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copied, 'void main() {}');
    expect(find.text('Copied!'), findsOneWidget);

    // The confirmation resets, and leaving early must not throw.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('inline code renders as monospace chip', (tester) async {
    await pumpMarkdown(tester, 'Call `runApp()` first.');

    expect(find.byType(MarkdownInlineCode), findsOneWidget);
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(MarkdownInlineCode),
        matching: find.byType(Text),
      ),
    );
    expect(text.data, 'runApp()');
    expect(text.style?.fontFamily, 'monospace');
  });

  testWidgets('known languages are syntax highlighted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HighlightedCode(
          code: 'final greeting = "hi";',
          language: 'dart',
          theme: themes.light,
          color: Colors.black,
        ),
      ),
    );

    final rich = tester.widget<RichText>(find.byType(RichText));
    final colors = <Color?>{};
    rich.text.visitChildren((span) {
      colors.add(span.style?.color);
      return true;
    });
    expect(colors.whereType<Color>().length, greaterThan(2));
  });
}
