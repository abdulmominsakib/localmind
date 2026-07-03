import 'package:dio/dio.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import 'models/message.dart';

/// Builds a raw completion prompt for LM Studio `/api/v0/completions`.
///
/// LM Studio applies model-specific chat templates internally when possible.
/// We first try server-side template endpoints, then fall back to common
/// architecture templates using model metadata from `/api/v0/models/{model}`.
class LmStudioPromptFormatter {
  LmStudioPromptFormatter(this._dio);

  final Dio _dio;
  static final _imEnd = String.fromCharCodes([
    0x3C, 0x7C, 0x69, 0x6D, 0x5F, 0x65, 0x6E, 0x64, 0x7C, 0x3E,
  ]);

  /// Turn-boundary control tokens across every template family this
  /// formatter knows about. Since the model's actual architecture may be
  /// unknown when a server-side template was used, or misdetected, this
  /// union is passed as `stop` sequences for raw-completion requests
  /// (continue / generate-user-turn) so a model that leaks its own
  /// control tokens into the visible text gets truncated there instead
  /// of showing them (e.g. `end_of_turn`) to the user.
  static const List<String> turnBoundaryStopSequences = [
    '<end_of_turn>',
    '<start_of_turn>',
    '<|eot_id|>',
    '<|start_header_id|>',
    '<|end_header_id|>',
    '<|begin_of_text|>',
    '[INST]',
    '[/INST]',
    '[SYSTEM_PROMPT]',
    '[/SYSTEM_PROMPT]',
    '</s>',
    '<|im_start|>',
    '<|im_end|>',
  ];

  Future<String> formatForCompletion({
    required String baseUrl,
    required Map<String, String> authHeaders,
    required String modelId,
    required List<Message> messages,
    required LmStudioPromptMode mode,
    String? systemPrompt,
  }) async {
    final apiMessages = _toApiMessages(messages, systemPrompt: systemPrompt);

    final fromServer = await _tryServerTemplate(
      baseUrl: baseUrl,
      authHeaders: authHeaders,
      modelId: modelId,
      messages: apiMessages,
      mode: mode,
    );
    if (fromServer != null && fromServer.isNotEmpty) {
      return fromServer;
    }

    final arch = await _fetchModelArch(
      baseUrl: baseUrl,
      authHeaders: authHeaders,
      modelId: modelId,
    );
    return _formatLocally(
      apiMessages,
      arch: arch,
      mode: mode,
    );
  }

  Future<String?> _tryServerTemplate({
    required String baseUrl,
    required Map<String, String> authHeaders,
    required String modelId,
    required List<Map<String, String>> messages,
    required LmStudioPromptMode mode,
  }) async {
    final endpoints = [
      '$baseUrl/api/v1/models/apply-prompt-template',
      '$baseUrl/api/v0/apply-prompt-template',
      '$baseUrl/v1/apply-template',
      '$baseUrl/apply-template',
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await _dio.post<dynamic>(
          endpoint,
          data: {
            'model': modelId,
            'messages': messages,
            if (mode == LmStudioPromptMode.continueAssistant)
              'continue_assistant': true,
            if (mode == LmStudioPromptMode.generateUserTurn)
              'add_generation_prompt': true,
          },
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              ...authHeaders,
            },
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        if (response.statusCode != 200 || response.data == null) continue;

        final data = response.data;
        if (data is String && data.trim().isNotEmpty) return data;
        if (data is Map) {
          for (final key in ['prompt', 'text', 'formatted', 'content']) {
            final value = data[key];
            if (value is String && value.trim().isNotEmpty) return value;
          }
        }
      } catch (e) {
        Log.debug('LM Studio template endpoint failed ($endpoint): $e');
      }
    }
    return null;
  }

  Future<String?> _fetchModelArch({
    required String baseUrl,
    required Map<String, String> authHeaders,
    required String modelId,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        '$baseUrl/api/v0/models/${Uri.encodeComponent(modelId)}',
        options: Options(headers: authHeaders),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data['arch']?.toString();
      }
    } catch (_) {}
    return null;
  }

  List<Map<String, String>> _toApiMessages(
    List<Message> messages, {
    String? systemPrompt,
  }) {
    final result = <Map<String, String>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      result.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    for (final message in messages) {
      if (message.role == MessageRole.system) {
        result.add({'role': 'system', 'content': message.content});
        continue;
      }
      if (message.role == MessageRole.user) {
        result.add({'role': 'user', 'content': message.content});
        continue;
      }
      if (message.role == MessageRole.assistant) {
        result.add({'role': 'assistant', 'content': message.content});
      }
    }
    return result;
  }

  String _formatLocally(
    List<Map<String, String>> messages, {
    required String? arch,
    required LmStudioPromptMode mode,
  }) {
    final normalizedArch = (arch ?? '').toLowerCase();
    if (normalizedArch.contains('gemma')) {
      return _formatGemma(messages, mode: mode);
    }
    if (normalizedArch.contains('llama') ||
        normalizedArch.contains('gpt-oss') ||
        normalizedArch.contains('granite')) {
      return _formatLlama3(messages, mode: mode);
    }
    if (normalizedArch.contains('mistral') || normalizedArch.contains('devstral')) {
      return _formatMistral(messages, mode: mode);
    }
    if (normalizedArch.contains('qwen')) {
      return _formatQwen(messages, mode: mode);
    }
    return _formatChatMl(messages, mode: mode);
  }

  String _formatGemma(
    List<Map<String, String>> messages, {
    required LmStudioPromptMode mode,
  }) {
    final buffer = StringBuffer();
    String? pendingSystem;

    for (final message in messages) {
      final role = message['role'] ?? 'user';
      final content = message['content'] ?? '';
      if (role == 'system') {
        pendingSystem = content;
        continue;
      }
      if (role == 'user') {
        if (pendingSystem != null) {
          buffer.write('<start_of_turn>user\n');
          buffer.write('$pendingSystem\n\n$content<end_of_turn>\n');
          pendingSystem = null;
        } else {
          buffer.write('<start_of_turn>user\n$content<end_of_turn>\n');
        }
        continue;
      }
      if (role == 'assistant') {
        pendingSystem = null;
        buffer.write('<start_of_turn>model\n$content');
        if (mode != LmStudioPromptMode.continueAssistant ||
            message != messages.last) {
          buffer.write('<end_of_turn>\n');
        }
      }
    }

    if (pendingSystem != null) {
      buffer.write('<start_of_turn>user\n$pendingSystem<end_of_turn>\n');
    }

    if (mode == LmStudioPromptMode.generateUserTurn) {
      buffer.write('<start_of_turn>user\n');
    } else if (mode == LmStudioPromptMode.continueAssistant &&
        messages.isNotEmpty &&
        messages.last['role'] == 'assistant') {
      // Already opened model turn without closing token.
    } else if (mode == LmStudioPromptMode.completeAssistant) {
      buffer.write('<start_of_turn>model\n');
    }

    return buffer.toString();
  }

  String _formatLlama3(
    List<Map<String, String>> messages, {
    required LmStudioPromptMode mode,
  }) {
    const bos = '<|begin_of_text|>';
    const startHeader = '<|start_header_id|>';
    const endHeader = '<|end_header_id|>';
    const eot = '<|eot_id|>';

    final buffer = StringBuffer(bos);
    for (final message in messages) {
      final role = message['role'] ?? 'user';
      final content = message['content'] ?? '';
      switch (role) {
        case 'system':
          buffer.write('$startHeader$role$endHeader\n\n');
          buffer.write('$content$eot');
        case 'user':
          buffer.write('$startHeader$role$endHeader\n\n');
          buffer.write('$content$eot');
        case 'assistant':
          buffer.write('$startHeader$role$endHeader\n\n');
          buffer.write(content);
          if (mode != LmStudioPromptMode.continueAssistant ||
              message != messages.last) {
            buffer.write(eot);
          }
      }
    }

    if (mode == LmStudioPromptMode.generateUserTurn) {
      buffer.write('${startHeader}user$endHeader\n\n');
    } else if (mode == LmStudioPromptMode.completeAssistant) {
      buffer.write('${startHeader}assistant$endHeader\n\n');
    }

    return buffer.toString();
  }

  String _formatMistral(
    List<Map<String, String>> messages, {
    required LmStudioPromptMode mode,
  }) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final role = message['role'] ?? 'user';
      final content = message['content'] ?? '';
      switch (role) {
        case 'system':
          buffer.write('[SYSTEM_PROMPT]$content[/SYSTEM_PROMPT]');
        case 'user':
          buffer.write('[INST]$content[/INST]');
        case 'assistant':
          buffer.write(content);
          if (mode != LmStudioPromptMode.continueAssistant ||
              message != messages.last) {
            buffer.write('</s>');
          }
      }
    }

    if (mode == LmStudioPromptMode.generateUserTurn) {
      buffer.write('[INST]');
    } else if (mode == LmStudioPromptMode.completeAssistant) {
      // Mistral assistant continuation typically follows [/INST].
    }

    return buffer.toString();
  }

  String _formatQwen(
    List<Map<String, String>> messages, {
    required LmStudioPromptMode mode,
  }) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final role = message['role'] ?? 'user';
      final content = message['content'] ?? '';
      switch (role) {
        case 'system':
          buffer.write('<|im_start|>system\n$content$_imEnd\n');
        case 'user':
          buffer.write('<|im_start|>user\n$content$_imEnd\n');
        case 'assistant':
          buffer.write('<|im_start|>assistant\n$content');
          if (mode != LmStudioPromptMode.continueAssistant ||
              message != messages.last) {
            buffer.write('$_imEnd\n');
          }
      }
    }

    if (mode == LmStudioPromptMode.generateUserTurn) {
      buffer.write('<|im_start|>user\n');
    } else if (mode == LmStudioPromptMode.completeAssistant) {
      buffer.write('<|im_start|>assistant\n');
    }

    return buffer.toString();
  }

  String _formatChatMl(
    List<Map<String, String>> messages, {
    required LmStudioPromptMode mode,
  }) {
    return _formatQwen(messages, mode: mode);
  }
}

enum LmStudioPromptMode {
  /// Standard assistant reply generation.
  completeAssistant,

  /// Continue an partially generated assistant message (no new user turn).
  continueAssistant,

  /// Open a new user turn and generate the user's message content.
  generateUserTurn,
}
