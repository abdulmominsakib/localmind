import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/views/components/reasoning_widget.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';

Widget _buildTestWidget({
  required String reasoningContent,
  bool isStreaming = false,
  bool hasMainContent = true,
  AppSettings? settings,
}) {
  final appSettings = settings ?? AppSettings();
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => _MockSettingsNotifier(appSettings)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReasoningWidget(
            reasoningContent: reasoningContent,
            isStreaming: isStreaming,
            hasMainContent: hasMainContent,
          ),
        ),
      ),
    ),
  );
}

class _MockSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  _MockSettingsNotifier(this._initial);

  @override
  AppSettings build() => _initial;
}

void main() {
  group('ReasoningWidget Tests', () {
    testWidgets(
      'remains expanded when hasMainContent is false (no main response)',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Thinking about the problem...',
            isStreaming: false,
            hasMainContent: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(GptMarkdown), findsOneWidget);
        expect(find.text('Thinking about the problem...'), findsOneWidget);

        final sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 1.0);
      },
    );

    testWidgets(
      'remains expanded after streaming if autoCollapseThinking is false',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Step-by-step reasoning',
            isStreaming: false,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: false),
          ),
        );
        await tester.pumpAndSettle();

        final sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 1.0);
        expect(find.text('Step-by-step reasoning'), findsOneWidget);
      },
    );

    testWidgets(
      'default settings keep the bubble expanded after generation (issue #28)',
      (tester) async {
        // No settings override: relies on the default value of autoCollapseThinking.
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'The answer lived inside the thinking block',
            isStreaming: false,
            hasMainContent: true,
          ),
        );
        await tester.pumpAndSettle();

        final sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 1.0);
        expect(
          find.text('The answer lived inside the thinking block'),
          findsOneWidget,
        );
      },
    );

    testWidgets('is expanded while isStreaming is true', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          reasoningContent: 'Currently thinking live...',
          isStreaming: true,
          hasMainContent: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final sizeTransition = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      expect(sizeTransition.sizeFactor.value, 1.0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'collapses when streaming ends if hasMainContent is true and autoCollapseThinking is true',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Finished thinking',
            isStreaming: false,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pumpAndSettle();

        final sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 0.0);
      },
    );

    testWidgets('toggles expanded state on tap', (tester) async {
      await tester.pumpWidget(
        _buildTestWidget(
          reasoningContent: 'Click to see details',
          isStreaming: false,
          hasMainContent: true,
          settings: AppSettings(autoCollapseThinking: true),
        ),
      );
      await tester.pumpAndSettle();

      // Initially collapsed
      var sizeTransition = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      expect(sizeTransition.sizeFactor.value, 0.0);

      // Tap header to expand
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      sizeTransition = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      expect(sizeTransition.sizeFactor.value, 1.0);

      // Tap header to collapse again
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      sizeTransition = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      expect(sizeTransition.sizeFactor.value, 0.0);
    });

    testWidgets(
      'transitions from streaming to non-streaming: remains expanded if hasMainContent is false',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Full answer in reasoning block',
            isStreaming: true,
            hasMainContent: false,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Stream ends, rebuild with isStreaming: false
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Full answer in reasoning block',
            isStreaming: false,
            hasMainContent: false,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pumpAndSettle();

        final sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 1.0);
      },
    );

    testWidgets(
      'transitions from streaming to non-streaming: collapses if hasMainContent is true and autoCollapseThinking is true',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Intermediary reasoning',
            isStreaming: true,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        var sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 1.0);

        // Stream ends, rebuild with isStreaming: false and hasMainContent: true
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Intermediary reasoning',
            isStreaming: false,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pumpAndSettle();

        sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 0.0);
      },
    );

    testWidgets(
      'transitions from streaming to non-streaming: respects manual expand/collapse toggle',
      (tester) async {
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Streaming reasoning...',
            isStreaming: true,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // User manually collapses while streaming
        await tester.tap(find.byType(InkWell));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        var sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 0.0);

        // Stream finishes: since user manually collapsed, it stays collapsed
        await tester.pumpWidget(
          _buildTestWidget(
            reasoningContent: 'Streaming reasoning...',
            isStreaming: false,
            hasMainContent: true,
            settings: AppSettings(autoCollapseThinking: true),
          ),
        );
        await tester.pumpAndSettle();

        sizeTransition = tester.widget<SizeTransition>(
          find.byType(SizeTransition),
        );
        expect(sizeTransition.sizeFactor.value, 0.0);
      },
    );
  });
}
