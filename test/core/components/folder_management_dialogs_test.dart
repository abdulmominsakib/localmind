import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/components/folder_management_dialogs.dart';
import 'package:localmind/l10n/app_localizations.dart';

Future<void> _pumpHarness(
  WidgetTester tester,
  Future<void> Function(BuildContext) body,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            // Trigger the dialog from a real user interaction instead of a
            // post-frame callback: pushing a route mid-frame marks focus
            // scopes dirty outside their build scope, which newer Flutter
            // versions reject with a "dirty widget in the wrong build scope"
            // assertion.
            onPressed: () => body(ctx),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  // Allow async dialog futures to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('showRenameFolderDialog returns trimmed name on save', (
    tester,
  ) async {
    String? result;
    await _pumpHarness(tester, (ctx) async {
      result = await showRenameFolderDialog(ctx, currentName: 'Old');
    });
    // The dialog should be visible.
    expect(find.text('Rename folder'), findsOneWidget);
    // Replace the existing name.
    await tester.enterText(find.byType(TextField), '  New Name  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, 'New Name');
  });

  testWidgets('showRenameFolderDialog rejects empty name', (tester) async {
    String? result;
    await _pumpHarness(tester, (ctx) async {
      result = await showRenameFolderDialog(ctx, currentName: 'Old');
    });
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pump();
    // Dialog still visible because validation failed.
    expect(find.text('Please enter a folder name'), findsOneWidget);
    expect(result, isNull);
    // Cancel closes the dialog.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('showDeleteFolderConfirmation returns true on confirm', (
    tester,
  ) async {
    bool result = false;
    await _pumpHarness(tester, (ctx) async {
      result = await showDeleteFolderConfirmation(ctx, folderName: 'Notes');
    });
    expect(find.text('Delete folder?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('showDeleteFolderConfirmation returns false on cancel', (
    tester,
  ) async {
    bool result = true;
    await _pumpHarness(tester, (ctx) async {
      result = await showDeleteFolderConfirmation(ctx, folderName: 'Notes');
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
