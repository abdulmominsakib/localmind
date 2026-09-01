import '../../../../l10n/app_localizations.dart';

/// Formats raw on-device engine, download, or initialization errors into
/// clean, user-friendly, and localized error messages.
String formatOnDeviceError(
  Object error, {
  bool isBuiltIn = false,
  AppLocalizations? l10n,
}) {
  final raw = error.toString();

  // 1. Built-in AI / System AI availability errors
  if (isBuiltIn ||
      raw.contains('BuiltInAiUnavailableException') ||
      raw.contains('unavailableDeviceUnsupported') ||
      raw.contains('unavailableOther') ||
      raw.contains('BuiltInAiAvailability')) {
    return l10n?.builtin_ai_not_supported ??
        'Built-in AI is not supported on this device.';
  }

  // 2. Missing or invalid Hugging Face token
  if (raw.contains('missing_huggingface_token') ||
      raw.contains('GatedRepo') ||
      raw.contains('401') ||
      raw.contains('403')) {
    return l10n?.model_missing_huggingface_token ??
        'Hugging Face token required to download this model.';
  }

  // 3. Disk space errors
  if (raw.contains('ENOSPC') ||
      raw.contains('No space left') ||
      raw.contains('not enough storage')) {
    return 'Not enough storage space to download this model.';
  }

  // 4. Network / Connection errors
  if (raw.contains('SocketException') ||
      raw.contains('Connection closed') ||
      raw.contains('Failed host lookup') ||
      raw.contains('TimeoutException')) {
    return 'Network connection failed. Please check your internet connection.';
  }

  // 5. Clean up standard Exception/StateError prefixes
  var clean = raw;
  if (clean.startsWith('Exception: ')) {
    clean = clean.substring('Exception: '.length);
  } else if (clean.startsWith('StateError: ')) {
    clean = clean.substring('StateError: '.length);
  } else if (clean.startsWith('StateError (')) {
    clean = clean.replaceAll(RegExp(r'^StateError \((.*)\)$'), r'$1');
  }

  return clean;
}
