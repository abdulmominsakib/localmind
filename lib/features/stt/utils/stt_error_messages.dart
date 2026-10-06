import '../../../l10n/app_localizations.dart';

/// Reported when the device has no speech recognition service at all.
const sttUnavailableCode = 'stt_unavailable';

/// Reported when the microphone permission was requested and refused.
const micPermissionDeniedCode = 'mic_permission_denied';

/// Reported when the microphone permission was refused permanently and only
/// the OS settings page can restore it.
const micPermissionPermanentlyDeniedCode = 'mic_permission_permanently_denied';

/// Speech recognizer error codes that the plugin reports for permission
/// problems. Shared here because the notifier re-checks the real grant state
/// before trusting them (Samsung recognizers fire them when granted).
bool isPermissionSttErrorCode(String code) =>
    code == 'error_permission' || code == 'error_insufficient_permissions';

/// Whether [error] means the recognizer ran but heard nothing usable.
bool isNoSpeechSttError(String? error) =>
    error == 'error_no_match' || error == 'error_speech_timeout';

/// Maps a speech_to_text error code to a user-facing message. Anything that
/// isn't a known code (e.g. an already-readable message) is returned as is.
String sttErrorMessage(AppLocalizations? l10n, String error) {
  if (l10n == null) return error;
  switch (error) {
    case sttUnavailableCode:
      return l10n.stt_error_unavailable;
    case micPermissionDeniedCode:
    case micPermissionPermanentlyDeniedCode:
      return l10n.stt_error_permission;
    case 'error_no_match':
      return l10n.stt_error_no_match;
    case 'error_speech_timeout':
      return l10n.stt_error_speech_timeout;
    case 'error_permission':
    case 'error_insufficient_permissions':
      return l10n.stt_error_permission;
    case 'error_busy':
    case 'error_recognizer_busy':
    case 'error_too_many_requests':
      return l10n.stt_error_busy;
    case 'error_network':
    case 'error_network_timeout':
    case 'error_server':
    case 'error_server_disconnected':
      return l10n.stt_error_network;
    case 'error_audio':
    case 'error_audio_error':
      return l10n.stt_error_audio;
    case 'error_client':
      return l10n.stt_error_client;
    case 'error_language_not_supported':
    case 'error_language_unavailable':
      return l10n.stt_error_language;
    default:
      if (error.startsWith('error_')) {
        final cleanName = error.replaceFirst('error_', '').replaceAll('_', ' ');
        return l10n.stt_error_generic(cleanName);
      }
      return error;
  }
}
