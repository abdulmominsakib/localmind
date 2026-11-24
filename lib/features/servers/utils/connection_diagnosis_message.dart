import '../../../l10n/app_localizations.dart';
import '../data/models/connection_diagnosis.dart';

/// User-facing text for a connection test result. Never includes the URL
/// or credentials, so it is safe to show in screenshots and support threads.
String connectionDiagnosisMessage(
  AppLocalizations? l10n,
  ConnectionDiagnosis diagnosis,
) {
  if (diagnosis.ok) {
    final success = l10n?.connection_successful ?? 'Connection successful';
    if (!diagnosis.nativeApiUnavailable) return success;
    return l10n?.connection_warning_lmstudio_native ??
        'Connected, but only through the OpenAI-compatible /v1 routes.';
  }
  final status = diagnosis.statusCode ?? 0;
  return switch (diagnosis.failure) {
    ConnectionFailureKind.unreachable =>
      l10n?.connection_failed_unreachable ?? "Couldn't reach the server.",
    ConnectionFailureKind.timeout =>
      l10n?.connection_failed_timeout ?? "The server didn't respond in time.",
    ConnectionFailureKind.tls =>
      l10n?.connection_failed_tls ?? 'Secure connection failed.',
    ConnectionFailureKind.unauthorized =>
      l10n?.connection_failed_unauthorized(status) ??
          'The server rejected the request (HTTP $status).',
    ConnectionFailureKind.notFound =>
      l10n?.connection_failed_not_found ??
          'The server answered, but not on the expected API routes.',
    ConnectionFailureKind.unexpectedStatus =>
      l10n?.connection_failed_status(status) ??
          'The server answered with HTTP $status.',
    ConnectionFailureKind.missingApiKey =>
      l10n?.connection_failed_missing_key ?? 'This provider needs an API key.',
    null => l10n?.connection_failed ?? 'Connection failed',
  };
}
