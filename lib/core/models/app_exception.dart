class AppException implements Exception {
  final AppErrorType type;
  final String message;
  final String? detail;
  final dynamic originalError;

  const AppException({
    required this.type,
    required this.message,
    this.detail,
    this.originalError,
  });

  @override
  String toString() => detail != null ? '$message: $detail' : message;
}

enum AppErrorType {
  connectionTimeout(
    'Connection timed out. Check your network and server address.',
  ),
  connectionRefused('Could not connect to server. Is it running?'),
  authFailed('Authentication failed. Check your API key.'),
  serverError('Server returned an error. Check server logs.'),
  networkError('Network error. Check your internet connection.'),
  parseError('Failed to parse server response.'),
  modelNotFound('Model not found on server.'),
  contextLengthExceeded(
    'Context length exceeded. Try shortening your messages.',
  ),
  rateLimited('Rate limited. Please wait before sending more messages.'),
  storageError('Storage error. Your data may not be saved.'),
  unknown('An unexpected error occurred.');

  const AppErrorType(this.userMessage);
  final String userMessage;

  static AppErrorType fromStatusCode(int statusCode) {
    if (statusCode == 401 || statusCode == 403) return AppErrorType.authFailed;
    if (statusCode == 404) return AppErrorType.modelNotFound;
    if (statusCode == 429) return AppErrorType.rateLimited;
    if (statusCode >= 500) return AppErrorType.serverError;
    return AppErrorType.unknown;
  }

  static AppErrorType fromException(dynamic error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('connection refused') ||
        msg.contains('connection failed')) {
      return AppErrorType.connectionRefused;
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return AppErrorType.connectionTimeout;
    }
    if (msg.contains('unauthorized') ||
        msg.contains('forbidden') ||
        msg.contains('401')) {
      return AppErrorType.authFailed;
    }
    if (msg.contains('429') || msg.contains('rate limit')) {
      return AppErrorType.rateLimited;
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return AppErrorType.networkError;
    }
    if (msg.contains('formatexception') || msg.contains('parse')) {
      return AppErrorType.parseError;
    }
    return AppErrorType.unknown;
  }
}
