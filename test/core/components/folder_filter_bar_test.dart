import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/components/folder_filter_bar.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  testWidgets('user folder chip triggers onFolderAction on long-press', (
    tester,
  ) async {
    FolderFilterItem? captured;
    Offset? capturedPos;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: FolderFilterBar(
            folders: const [
              FolderFilterItem(id: 'research', name: 'Research'),
            ],
            selectedFolderId: null,
            onFilterChanged: (_) {},
            onCreateFolder: () {},
            onFolderAction: (folder, pos) {
              captured = folder;
              capturedPos = pos;
            },
          ),
        ),
      ),
    );

    // Long-press is hard to simulate reliably in a widget test (the
    // recognizer waits for a kLongPressTimeout), so we instead tap the
    // chip to verify the primary tap path still works through the gesture
    // wrapper, then verify the wrapper respects the no-callback case.
    await tester.tap(find.text('Research'));
    expect(captured, isNull, reason: 'tap should not trigger action');

    // Pump long-press just to confirm the wrapper renders without errors.
    await tester.longPress(find.text('Research'));
    await tester.pump();
    // The wrapper delivers globalPosition; we just confirm the callback fired
    // for the right folder (callbacks receive the folder id, not the name).
    expect(captured?.id, 'research');
    expect(capturedPos, isNotNull);
  });

  testWidgets('FolderFilterBar does not throw when onFolderAction is null',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: FolderFilterBar(
            folders: const [
              FolderFilterItem(id: 'a', name: 'A'),
            ],
            selectedFolderId: null,
            onFilterChanged: (_) {},
            onCreateFolder: () {},
            // onFolderAction deliberately omitted.
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('A'));
    expect(tester.takeException(), isNull);
  });
}