import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/onboarding/screens/onboarding_server_type_screen.dart';
import 'package:localmind/features/servers/views/components/https_scheme_hint.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _wrapWithApp(Widget child) {
  return ProviderScope(
    child: ShadTheme(
      data: AppTheme.lightShadTheme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
}

void main() {
  testWidgets('shows OpenAI Compatible on the onboarding server picker', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapWithApp(const OnboardingServerTypeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('OpenAI Compatible'), findsWidgets);
    expect(find.text('Add more'), findsOneWidget);
    expect(find.text('on GitHub'), findsOneWidget);
  });

  testWidgets('shows the HTTPS hint only for https hosts', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrapWithApp(Material(child: HttpsSchemeHint(controller: controller))),
    );

    expect(find.text('HTTPS requires SSL'), findsNothing);
    expect(find.text('Most local setups use http://'), findsNothing);

    controller.text = 'https://localhost:1234';
    await tester.pump();

    expect(find.text('HTTPS requires SSL'), findsOneWidget);
    expect(find.text('Most local setups use http://'), findsOneWidget);

    controller.text = 'http://localhost:1234';
    await tester.pump();

    expect(find.text('HTTPS requires SSL'), findsNothing);
    expect(find.text('Most local setups use http://'), findsNothing);
  });
}
