import 'dart:convert';

/// Structured API error details from LM Studio, OpenAI-compatible, etc.
class ChatApiError {
  const ChatApiError({
    required this.message,
    this.type,
    this.code,
    this.param,
  });

  final String message;
  final String? type;
  final String? code;
  final String? param;

  bool get hasMetadata =>
      (type?.isNotEmpty ?? false) ||
      (code?.isNotEmpty ?? false) ||
      (param?.isNotEmpty ?? false);

  String encode() => jsonEncode({
        'message': message,
        if (type != null && type!.isNotEmpty) 'type': type,
        if (code != null && code!.isNotEmpty) 'code': code,
        if (param != null && param!.isNotEmpty) 'param': param,
      });

  static ChatApiError? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final map = jsonDecode(trimmed) as Map<String, dynamic>;
      final message = map['message']?.toString();
      if (message == null || message.isEmpty) return null;
      return ChatApiError(
        message: message,
        type: map['type']?.toString(),
        code: map['code']?.toString(),
        param: map['param']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static ChatApiError? fromErrorMap(Map<String, dynamic>? error) {
    if (error == null) return null;
    final message = error['message']?.toString();
    if (message == null || message.isEmpty) return null;
    return ChatApiError(
      message: message,
      type: error['type']?.toString(),
      code: error['code']?.toString(),
      param: error['param']?.toString(),
    );
  }

  static ChatApiError? fromResponseBody(dynamic data) {
    if (data == null) return null;
    Map<String, dynamic>? map;
    if (data is Map<String, dynamic>) {
      map = data;
    } else if (data is String && data.trim().isNotEmpty) {
      try {
        map = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;

    final nested = map['error'];
    if (nested is Map<String, dynamic>) {
      return fromErrorMap(nested);
    }
    return fromErrorMap(map);
  }
}

String? encodeChatErrorMessage(ChatApiError? error) {
  if (error == null) return null;
  return error.encode();
}
