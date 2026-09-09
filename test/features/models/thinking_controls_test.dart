import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/models/components/inline_thinking_selector.dart';
import 'package:localmind/features/models/components/thinking_mode_chip.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

Widget _app(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

ModelInfo _model({
  required List<String> supportedEfforts,
  bool mandatory = false,
}) {
  return ModelInfo(
    id: 'thinking-model',
    name: 'Thinking model',
    serverType: ServerType.ollama,
    serverId: 'ollama',
    supportsReasoning: true,
    supportedReasoningEfforts: supportedEfforts,
    reasoningMandatory: mandatory,
  );
}

void main() {
  testWidgets('binary model selector labels its boolean state On', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const InlineThinkingSelector(
          isDark: false,
          isSelected: true,
          supportedEfforts: ['off', 'on'],
        ),
      ),
    );

    expect(find.text('Thinking mode'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Medium'), findsNothing);
  });

  testWidgets('mandatory binary selector exposes only On', (tester) async {
    await tester.pumpWidget(
      _app(
        const InlineThinkingSelector(
          isDark: false,
          isSelected: true,
          supportedEfforts: ['on'],
          reasoningMandatory: true,
        ),
      ),
    );

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
    expect(find.text('Medium'), findsNothing);
  });

  testWidgets('compact binary chip displays On and toggles to Off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        ThinkingModeChip(
          model: _model(supportedEfforts: const ['off', 'on']),
          isDark: false,
        ),
      ),
    );

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Medium'), findsNothing);

    await tester.tap(find.text('On'));
    await tester.pump();

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('On'), findsNothing);
  });

  testWidgets('mandatory compact binary chip stays On', (tester) async {
    await tester.pumpWidget(
      _app(
        ThinkingModeChip(
          model: _model(supportedEfforts: const ['on'], mandatory: true),
          isDark: false,
        ),
      ),
    );

    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
    expect(find.text('Medium'), findsNothing);
  });

  test('mandatory model normalization can represent an On-only capability', () {
    expect(hasGranularReasoningChoice(const ['on']), isFalse);
    expect(
      resolveOllamaThinkValue(
        enabled: false,
        effort: ReasoningEffort.medium,
        allowedOptions: const ['on'],
      ),
      isNull,
    );
    expect(
      resolveOllamaThinkValue(
        enabled: true,
        effort: ReasoningEffort.medium,
        allowedOptions: const ['on'],
      ),
      isTrue,
    );
  });
}
