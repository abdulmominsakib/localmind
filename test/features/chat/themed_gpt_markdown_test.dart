import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/markdown/themed_gpt_markdown.dart';

void main() {
  testWidgets('renders Markdown image URLs with NetworkImage', (tester) async {
    const url = 'https://example.com/picture.png';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ThemedGptMarkdown(
            content: '![Example picture]($url)',
            isDark: false,
            style: TextStyle(),
          ),
        ),
      ),
    );

    final networkImages = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>();
    expect(networkImages.map((image) => image.url), contains(url));
  });

  testWidgets(
    'MarkdownBodyContent wraps with SelectionArea when selectable is true',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownBodyContent(
              content: 'Hello world',
              isDark: false,
              selectable: true,
            ),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
    },
  );

  testWidgets(
    'MarkdownBodyContent does not wrap with SelectionArea when selectable is false',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownBodyContent(
              content: 'Streaming content',
              isDark: false,
              selectable: false,
            ),
          ),
        ),
      );

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text('Streaming content'), findsOneWidget);
    },
  );
}
