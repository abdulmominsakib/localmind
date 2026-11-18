String? backupImportString(Object? value) => value is String ? value : null;

int backupImportPromptsProcessed(Object? value) {
  if (value == null) return 0;
  if (value is! int || value < 0) {
    throw const FormatException('Invalid promptsProcessed counter');
  }
  return value;
}

DateTime? backupImportDateTime(Object? value) {
  final raw = backupImportString(value);
  if (raw == null) return null;
  try {
    return DateTime.parse(raw);
  } catch (_) {
    return null;
  }
}
