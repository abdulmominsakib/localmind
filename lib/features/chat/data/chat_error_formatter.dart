import 'dart:convert';

import 'chat_api_error.dart';

/// Best-effort mapping for the most common chat API failure modes into the
/// `ChatApiError` JSON shape rendered by `ChatErrorDisplay`.
///
/// The same shape works whether the upstream is Ollama, LM Studio,
/// OpenAI-compatible, OpenRouter, or a remote service. Anything that can't be
/// confidently identified falls back to a plain `message` so the bubble still
/// shows something useful instead of raw JSON.
class ChatErrorFormatter {
  const ChatErrorFormatter._();

  /// Convenience wrapper used by stream handlers that already have a body.
  static String formatBody(String rawBody, {int? statusCode}) {
    final decoded = _tryDecodeObject(rawBody);
    if (decoded == null) {
      final trimmed = rawBody.trim();
      if (trimmed.isEmpty) return _genericFromStatus(statusCode).encode();
      return ChatApiError(message: trimmed).encode();
    }
    return _fromKnownShape(decoded, statusCode).encode();
  }

  /// Map a `DioException` into the same shape, decoding the response body
  /// when it's a stream (which is the case for streaming chat requests).
  static Future<String> formatDioException(
    dynamic error, {
    Future<String> Function(dynamic)? readBody,
  }) async {
    int? statusCode;
    String? rawBody;
    final errorType = _readErrorType(error);

    if (errorType != null) {
      statusCode = errorType.statusCode;
      final data = errorType.response?.data;
      if (data != null) {
        if (readBody != null) {
          try {
            rawBody = await readBody(data);
          } catch (_) {
            rawBody = null;
          }
        } else if (data is String) {
          rawBody = data;
        }
      }
    }

    if (rawBody != null && rawBody.isNotEmpty) {
      final body = formatBody(rawBody, statusCode: statusCode);
      // If the body produced a generic-shaped message, layer in the status
      // code so the bubble shows it.
      if (statusCode != null && statusCode >= 400) {
        final decoded = _tryDecodeObject(body);
        if (decoded != null) {
          final merged = ChatApiError.fromErrorMap(decoded);
          if (merged != null) {
            return merged.copyWithCodeIfMissing(statusCode.toString()).encode();
          }
        }
      }
      return body;
    }

    if (errorType != null) {
      final fromStatus = _genericFromStatus(statusCode);
      return fromStatus.copyWithTypeIfMissing(_dioTypeLabel(errorType)).encode();
    }

    return ChatApiError(message: error.toString()).encode();
  }

  // ---------------------------------------------------------------------------
  // Shape detection
  // ---------------------------------------------------------------------------

  static ChatApiError _fromKnownShape(
    Map<String, dynamic> decoded,
    int? statusCode,
  ) {
    // Ollama / llama.cpp structured error: {"error": {...}}.
    final errorField = decoded['error'];
    if (errorField is Map) {
      final nested = errorField;
      final message = nested['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return ChatApiError(
          message: _humanize(message),
          type: nested['type']?.toString(),
          code: nested['code']?.toString() ?? statusCode?.toString(),
        );
      }
    }
    if (errorField is String && errorField.isNotEmpty) {
      return ChatApiError(
        message: _humanize(errorField),
        code: statusCode?.toString(),
      );
    }

    // OpenAI / OpenRouter / LM Studio: {"error": {"message": ..., "type": ...,
    // "code": ..., "param": ...}} or top-level {"message": ...}.
    final topMessage = decoded['message'];
    if (topMessage is String && topMessage.isNotEmpty) {
      return ChatApiError(
        message: _humanize(topMessage),
        type: decoded['type']?.toString(),
        code: decoded['code']?.toString() ?? statusCode?.toString(),
        param: decoded['param']?.toString(),
      );
    }

    // Anthropic-style: {"type": "error", "error": {"type": ..., "message": ...}}
    final anthropicType = decoded['type'];
    if (anthropicType == 'error' && errorField is Map) {
      final nested = errorField;
      final message = nested['message']?.toString();
      if (message != null && message.isNotEmpty) {
        return ChatApiError(
          message: _humanize(message),
          type: nested['type']?.toString(),
          code: statusCode?.toString(),
        );
      }
    }

    return _genericFromStatus(statusCode);
  }

  static ChatApiError _genericFromStatus(int? statusCode) {
    switch (statusCode) {
      case 400:
        return const ChatApiError(
          message:
              'The server rejected the request. Check the model name, message format, and any attached files.',
        );
      case 401:
        return const ChatApiError(
          message: 'Invalid API key or unauthorized.',
          type: 'authentication',
        );
      case 402:
        return const ChatApiError(
          message: 'Monthly credit limit reached or insufficient balance.',
          type: 'billing',
        );
      case 403:
        return const ChatApiError(
          message:
              'Access forbidden. Your API key might not have permission for this model.',
          type: 'authorization',
        );
      case 404:
        return const ChatApiError(
          message:
              'Model not found. Pull or load the model in Ollama, then try again.',
          type: 'model_not_found',
        );
      case 408:
      case 504:
        return const ChatApiError(
          message: 'The model took too long to respond.',
          type: 'timeout',
        );
      case 413:
        return const ChatApiError(
          message:
              'Image too large for the server to accept. Try enabling image compression in Settings.',
          type: 'payload_too_large',
        );
      case 429:
        return const ChatApiError(
          message: 'Rate limit exceeded. Please wait before trying again.',
          type: 'rate_limited',
        );
      case 500:
        return const ChatApiError(
          message: 'Internal server error from the AI provider.',
          type: 'server_error',
        );
      case 502:
        return const ChatApiError(
          message: 'Bad gateway. The provider is having issues.',
          type: 'bad_gateway',
        );
      case 503:
        return const ChatApiError(
          message: 'Service unavailable. The provider might be overloaded.',
          type: 'service_unavailable',
        );
    }
    return const ChatApiError(message: 'Chat request failed.');
  }

  // ---------------------------------------------------------------------------
  // Message-level pattern detection
  // ---------------------------------------------------------------------------

  static String _humanize(String message) {
    final lower = message.toLowerCase();

    if (lower.contains('exceed') &&
        (lower.contains('context') || lower.contains('n_ctx'))) {
      return 'The conversation is longer than the model\'s context window. '
          'Increase `num_ctx` for the model or start a new chat.';
    }
    if (lower.contains('model') && lower.contains('not found')) {
      return 'The selected model is not loaded on the server. Pull or load it '
          'in Ollama, then try again.';
    }
    if (lower.contains('unable to load model')) {
      return 'Ollama could not load the model. It may need to be re-pulled '
          '(e.g. `ollama pull qwen3-vl:2b`).';
    }
    if (lower.contains('unable to decode image')) {
      return 'The server could not decode the attached image. Try a smaller '
          'or different-format image, or enable image compression in Settings.';
    }
    if (lower.contains('does not support images')) {
      return 'The selected model does not support images. Choose a vision '
          'model such as llava, qwen2.5vl, gemma3, or llama3.2-vision.';
    }
    if (lower.contains('econnrefused') ||
        lower.contains('connection refused') ||
        lower.contains('failed to connect')) {
      return 'Could not reach the local AI server. Confirm Ollama is running '
          '(`ollama serve`) and the address/port in Settings is correct.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'The model took too long to respond. Try again or increase the '
          'server timeout in Settings.';
    }
    if (lower.contains('rate limit')) {
      return 'Rate limit reached. Wait a moment before retrying.';
    }
    return message;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Map<String, dynamic>? _tryDecodeObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Not JSON — leave it for the caller to treat as a plain message.
    }
    return null;
  }

  /// Returns the underlying Dio exception type when available, otherwise
  /// null. Defined as a free-standing function instead of importing dio here
  /// so the formatter stays free of HTTP-coupling.
  static dynamic _readErrorType(dynamic error) {
    // Heuristic: anything with a `response` getter and `type` getter is
    // likely a DioException. We avoid a hard dependency so callers can pass
    // their own typed exception.
    try {
      final dyn = error as dynamic;
      final response = dyn.response;
      final type = dyn.type;
      if (response != null || type != null) return error;
    } catch (_) {
      // Not a Dio-shaped object.
    }
    return null;
  }

  static String? _dioTypeLabel(dynamic error) {
    try {
      final dyn = error as dynamic;
      final type = dyn.type?.toString();
      return type == null || type.isEmpty ? null : type;
    } catch (_) {
      return null;
    }
  }
}