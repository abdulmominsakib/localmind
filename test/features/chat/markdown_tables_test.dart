import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/markdown/markdown_table.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/markdown/themed_gpt_markdown.dart';
import 'package:localmind/features/chat/utils/markdown_tables.dart';

void main() {
  group('normalizeMarkdownTables', () {
    test('adds outer pipes to tables written without them', () {
      const input = 'Name | Age\n--- | ---:\nAda | 36\n\nAfter.';
      expect(
        normalizeMarkdownTables(input),
        '| Name | Age |\n| --- | ---: |\n| Ada | 36 |\n\nAfter.',
      );
    });

    test('keeps empty cells so columns stay aligned', () {
      const input = '| a | b | c |\n|---|---|---|\n| 1 || 3 |';
      expect(
        normalizeMarkdownTables(input),
        '| a | b | c |\n|---|---|---|\n| 1 | | 3 |',
      );
    });

    test('keeps escaped pipes inside their cell', () {
      const input = '| Op | Meaning |\n|---|---|\n| a \\| b | or |';
      expect(
        normalizeMarkdownTables(input),
        '| Op | Meaning |\n|---|---|\n| a $escapedTablePipe b | or |',
      );
    });

    test('leaves non-table pipes and code alone', () {
      const prose = 'Use a | b to pipe.\nNot a table.';
      expect(normalizeMarkdownTables(prose), prose);

      const code = '```\na | b\n--- | ---\n```';
      expect(normalizeMarkdownTables(code), code);
    });
  });

  Future<void> pumpMarkdown(WidgetTester tester, String content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownBodyContent(content: content, isDark: false),
        ),
      ),
    );
    await tester.pump();
  }

  String cellText(WidgetTester tester, int index) {
    final cell = tester
        .widgetList<MarkdownTableCell>(find.byType(MarkdownTableCell))
        .elementAt(index);
    return cell.text.trim();
  }

  testWidgets('renders a table written without outer pipes', (tester) async {
    await pumpMarkdown(tester, 'Name | Role\n--- | ---\nAda | Engineer');

    expect(find.byType(MarkdownTable), findsOneWidget);
    expect(find.byType(MarkdownTableCell), findsNWidgets(4));
    expect(cellText(tester, 2), 'Ada');
    expect(cellText(tester, 3), 'Engineer');
  });

  testWidgets('empty cells keep the columns aligned', (tester) async {
    await pumpMarkdown(tester, '| a | b | c |\n|---|---|---|\n| 1 || 3 |');

    expect(find.byType(MarkdownTableCell), findsNWidgets(6));
    expect(cellText(tester, 3), '1');
    expect(cellText(tester, 4), '');
    expect(cellText(tester, 5), '3');
  });

  testWidgets('bracketed numbers stay text instead of citation chips', (
    tester,
  ) async {
    await pumpMarkdown(tester, 'Read arr[0] then step [2].');

    expect(find.textContaining('[0]', findRichText: true), findsWidgets);
    expect(find.textContaining('[2]', findRichText: true), findsWidgets);
  });

  testWidgets('long cells wrap at the column cap without overflowing', (
    tester,
  ) async {
    final long = List.filled(40, 'word').join(' ');
    await pumpMarkdown(
      tester,
      '| Key | Notes | `code` |\n|---|---|---|\n| a | $long | `x \\| y` |',
    );

    expect(tester.takeException(), isNull);
    final notes = tester.getSize(find.byType(MarkdownTableCell).at(4));
    expect(notes.width, lessThanOrEqualTo(280));
    expect(notes.height, greaterThan(60));
    // The escaped pipe stays inside its cell and renders as `|`.
    expect(find.byType(MarkdownTableCell), findsNWidgets(6));
    expect(find.text('x | y'), findsOneWidget);
  });
}
