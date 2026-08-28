import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/sidebar/components/github_repo_card.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: GitHubRepoCard())),
    );
  }

  testWidgets('GitHubRepoCard renders title and star prompt', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('Open Source'), findsOneWidget);
    expect(find.text('Star on GitHub'), findsOneWidget);
  });

  testWidgets(
    'GitHubRepoCard does not throw an unhandled exception when tapped',
    (tester) async {
      // In the test environment there is no native URL launcher. The try/catch
      // in _launchUrl must swallow any failure so the app does not crash.
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(GitHubRepoCard));
      await tester.pumpAndSettle();

      // The core regression: no unhandled exception must reach the framework.
      expect(tester.takeException(), isNull);
    },
  );
}
