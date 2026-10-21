import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/bootstrap/bootstrap_screen.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/bootstrap/bootstrap_state.dart';
import 'package:localmind/features/chat/views/components/message_list/ascii_logo_view.dart';

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

  testWidgets('plays the ASCII logo with the wordmark', (tester) async {
    await tester.pumpWidget(
      const BootstrapScreen(state: BootstrapState(), showStatus: false),
    );
    await tester.pump(BootstrapScreen.wordmarkDelay * 2);

    expect(find.byType(AsciiLogoView), findsOneWidget);
    expect(find.text('LocalMind'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the error and retry when startup failed', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      BootstrapScreen(
        state: const BootstrapState(
          stage: BootstrapStage.error,
          error: 'disk full',
        ),
        onRetry: () => retried = true,
      ),
    );
    await tester.pump(BootstrapScreen.wordmarkDelay * 2);

    expect(find.text('disk full'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('draws the logo in light ink on a dark system theme', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const BootstrapScreen(state: BootstrapState()));

    final logoText = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(AsciiLogoView),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(logoText.style?.color, AppColors.darkPrimaryText);
  });
}
