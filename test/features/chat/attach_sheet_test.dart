import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/chat/views/components/attach_sheet.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/l10n/app_localizations.dart';

ModelInfo _model({
  bool reasoning = true,
  List<String>? efforts = const ['low', 'medium', 'high'],
  bool mandatory = false,
}) => ModelInfo(
  id: 'm',
  name: 'M',
  serverType: ServerType.openRouter,
  serverId: 's',
  supportsReasoning: reasoning,
  supportedReasoningEfforts: efforts,
  reasoningMandatory: mandatory,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ModelInfo? model,
  bool? sendAsAssistant,
  ValueChanged<bool>? onSendAsAssistantChanged,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AttachSheet(
              model: model,
              sendAsAssistant: sendAsAssistant,
              onSendAsAssistantChanged: onSendAsAssistantChanged,
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('shows only sources when there are no options', (tester) async {
    await _pump(tester, model: _model(reasoning: false));
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Thinking mode'), findsNothing);
    expect(find.text('Send as assistant'), findsNothing);
  });

  testWidgets('thinking pills set the effort or turn it off', (tester) async {
    final container = await _pump(tester, model: _model());
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.text('High'));
    await tester.pump();
    var config = container.read(chatReasoningConfigProvider);
    expect(config.enabled, isTrue);
    expect(config.effort, ReasoningEffort.high);

    await tester.tap(find.text('Off'));
    await tester.pump();
    config = container.read(chatReasoningConfigProvider);
    expect(config.enabled, isFalse);
  });

  testWidgets('a model that always reasons offers no Off', (tester) async {
    await _pump(tester, model: _model(mandatory: true));
    expect(find.text('Off'), findsNothing);
    expect(find.text('Low'), findsOneWidget);
  });

  testWidgets('send as assistant reports its toggle', (tester) async {
    bool? reported;
    await _pump(
      tester,
      sendAsAssistant: false,
      onSendAsAssistantChanged: (v) => reported = v,
    );
    await tester.tap(find.byKey(const ValueKey('attach_send_as_assistant')));
    await tester.pump();
    expect(reported, isTrue);
  });
}
