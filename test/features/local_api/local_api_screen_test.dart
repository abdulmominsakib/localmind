import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/inference/local_inference.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/local_api/views/local_api_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts off and requires a loaded model before serving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalApiScreen(),
        ),
      ),
    );
    expect(find.text('Server stopped'), findsOneWidget);
    expect(find.text('8000'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start server'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('API key'), findsNothing);
  });

  testWidgets('shows eligible model and its tool support', (tester) async {
    SharedPreferences.setMockInitialValues({
      'localApiPort': 8088,
      'localApiLan': true,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          localInferenceModelProvider.overrideWithValue(
            const LocalInferenceModel(
              'gemma4-e2b-instruct',
              supportsTools: true,
              supportsSampling: false,
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LocalApiScreen(),
        ),
      ),
    );
    expect(find.text('Server stopped'), findsOneWidget);
    expect(find.text('gemma4-e2b-instruct'), findsOneWidget);
    expect(find.text('Text and tool calls'), findsOneWidget);
    expect(find.text('8088'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start server'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
