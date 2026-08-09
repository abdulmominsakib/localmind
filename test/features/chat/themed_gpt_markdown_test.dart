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
}
