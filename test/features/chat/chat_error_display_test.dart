import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/data/chat_api_error.dart';
import 'package:localmind/features/chat/views/components/chat_bubble/chat_error_display.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  testWidgets('localizes the on-device vision capability error', (
    tester,
  ) async {
    final encoded = const ChatApiError(
      message: 'Fallback vision error',
      code: ChatApiError.onDeviceVisionNotSupportedCode,
    ).encode();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ChatErrorDisplay(errorMessage: encoded)),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'The active model does not support image attachments. '
        'Please attach a vision projector (mmproj) or select a vision-supported model.',
      ),
      findsOneWidget,
    );
    expect(find.text('Fallback vision error'), findsNothing);
  });
}
