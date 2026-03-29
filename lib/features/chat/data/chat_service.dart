import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/core/models/enums.dart';

abstract class ChatService {
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  });

  void cancelStream();

  static ChatService forServer(ServerType type, Dio dio) {
    switch (type) {
      case ServerType.lmStudio:
        return LMStudioChatService(dio);
      case ServerType.ollama:
        return OllamaChatService(dio);
      case ServerType.openRouter:
        return OpenRouterChatService(dio);
    }
  }
}

class LMStudioChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;

  LMStudioChatService(this._dio);

  @override
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          if (server.apiKey != null) 'Authorization': 'Bearer ${server.apiKey}',
        },
      ),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') {
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final content = json['choices']?[0]?['delta']?['content'];
            if (content != null && content is String) {
              yield content;
            }
          } catch (e) {
            // Skip malformed JSON
          }
        }
      }
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
}

class OllamaChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;

  OllamaChatService(this._dio);

  @override
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'stream': true,
      'options': {
        'temperature': params.temperature,
        'top_p': params.topP,
        'num_predict': params.maxTokens,
      },
    };

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(responseType: ResponseType.stream),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.isNotEmpty) {
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            final content = json['message']?['content'];
            if (content != null && content is String) {
              yield content;
            }
            if (json['done'] == true) {
              return;
            }
          } catch (e) {
            // Skip malformed JSON
          }
        }
      }
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
}

class OpenRouterChatService implements ChatService {
  final Dio _dio;
  CancelToken? _cancelToken;

  OpenRouterChatService(this._dio);

  @override
  Stream<String> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    _cancelToken = CancelToken();

    final body = {
      'model': modelId,
      'messages': messages
          .map((m) => {'role': _roleToString(m.role), 'content': m.content})
          .toList(),
      'temperature': params.temperature,
      'top_p': params.topP,
      'max_tokens': params.maxTokens,
      'stream': true,
    };

    final response = await _dio.post<ResponseBody>(
      server.chatEndpoint,
      data: body,
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${server.apiKey}',
          'HTTP-Referer': 'https://localmind.app',
          'X-Title': 'LocalMind',
        },
      ),
      cancelToken: _cancelToken,
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += String.fromCharCodes(chunk);
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') {
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final content = json['choices']?[0]?['delta']?['content'];
            if (content != null && content is String) {
              yield content;
            }
          } catch (e) {
            // Skip malformed JSON
          }
        }
      }
    }
  }

  @override
  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
  }
}

String _roleToString(MessageRole role) {
  switch (role) {
    case MessageRole.user:
      return 'user';
    case MessageRole.assistant:
      return 'assistant';
    case MessageRole.system:
      return 'system';
  }
}
