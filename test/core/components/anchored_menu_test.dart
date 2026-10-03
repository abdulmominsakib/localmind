import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/anchored_menu.dart';

void main() {
  const entries = [
    AnchoredMenuEntry(
      value: 'rename',
      icon: HugeIcons.strokeRoundedPencilEdit02,
      label: 'Rename',
    ),
    AnchoredMenuEntry.divider(),
    AnchoredMenuEntry(
      value: 'clear',
      icon: HugeIcons.strokeRoundedDelete01,
      label: 'Clear',
      isDestructive: true,
    ),
  ];

  Future<List<String?>> pumpMenuButton(WidgetTester tester) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Builder(
              builder: (context) => IconButton(
                key: const ValueKey('open'),
                icon: const SizedBox.shrink(),
                onPressed: () async =>
                    results.add(await showAnchoredMenu(context, entries)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('returns the tapped entry and closes', (tester) async {
    final results = await pumpMenuButton(tester);

    expect(find.byType(AnchoredMenu), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(results, ['clear']);
    expect(find.byType(AnchoredMenu), findsNothing);
  });

  testWidgets('back closes the menu without choosing', (tester) async {
    final results = await pumpMenuButton(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(results, [null]);
    expect(find.byType(AnchoredMenu), findsNothing);
  });
}
