import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/stt/utils/stt_error_messages.dart';
import 'package:localmind/l10n/app_localizations.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('maps error_client to a recognizer hint instead of "client" (#100)', () {
    final message = sttErrorMessage(l10n, 'error_client');
    expect(message, l10n.stt_error_client);
    expect(message, isNot(contains('error: client')));
  });

  test('maps a missing recognizer to the install hint', () {
    expect(
      sttErrorMessage(l10n, sttUnavailableCode),
      l10n.stt_error_unavailable,
    );
  });

  test('falls back to a readable name for unknown codes', () {
    expect(
      sttErrorMessage(l10n, 'error_something_new'),
      l10n.stt_error_generic('something new'),
    );
  });

  test('passes through non-code messages', () {
    expect(sttErrorMessage(l10n, 'No server connected'), 'No server connected');
  });

  test('only no-match and timeout count as "no speech"', () {
    expect(isNoSpeechSttError('error_no_match'), isTrue);
    expect(isNoSpeechSttError('error_speech_timeout'), isTrue);
    expect(isNoSpeechSttError('error_client'), isFalse);
  });
}
