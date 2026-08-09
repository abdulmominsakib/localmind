import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/bootstrap/bootstrap_screen.dart';
import 'package:localmind/bootstrap/bootstrap_state.dart';

void main() {
  testWidgets('falls back to English for an unsupported device locale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BootstrapScreen(
        state: BootstrapState(),
        locale: Locale('de', 'DE'),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Initializing...'), findsOneWidget);
  });
}
