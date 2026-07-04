import 'dart:async';
import 'dart:convert';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../servers/data/models/server.dart';
import 'chat_service.dart';
import 'models/chat_parameters.dart';
import 'models/message.dart';

class SmartReplyService {
  Future<List<String>> suggestRepliesWithLLM({
    required ChatService chatService,
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    String? personaSystemPrompt,
  }) async {
    if (messages.isEmpty) return [];

    final lastMessage = messages.last;

    // Construct the prompt message for generating suggestions
    final promptMessage = Message(
      id: 'smart-reply-prompt',
      conversationId: lastMessage.conversationId,
      role: MessageRole.user,
      content: 'Based on the conversation history above, suggest 3 short, natural, context-appropriate reply options that the user (human) might want to send next. '
          'Return them strictly as a JSON array of strings, for example: ["Reply 1", "Reply 2", "Reply 3"]. '
          'Each reply should be brief (under 8 words). Return ONLY the raw JSON array, with no markdown code block formatting (do not wrap in ```json), explanations, or extra text.',
      createdAt: DateTime.now(),
    );

    final apiMessages = [
      ...messages,
      promptMessage,
    ];

    const baseInstruction =
        'You are a smart reply assistant. Your job is to output exactly a JSON array containing 3 suggested short replies for the user. Do not output anything other than the JSON array.';

    // Use low temperature and small tokens for fast, cheap, and deterministic suggestions
    final suggestionParams = params.copyWith(
      temperature: 0.2,
      maxTokens: 128,
      systemPrompt: personaSystemPrompt != null && personaSystemPrompt.trim().isNotEmpty
          ? '$personaSystemPrompt\n\n$baseInstruction'
          : baseInstruction,
    );

    try {
      final completer = Completer<String>();
      String accumulatedContent = '';

      final stream = chatService.sendMessage(
        server: server,
        modelId: modelId,
        messages: apiMessages,
        params: suggestionParams,
      );

      StreamSubscription? subscription;
      subscription = stream.listen(
        (response) {
          if (response.type == ChatResponseType.message && response.content != null) {
            accumulatedContent += response.content!;
          } else if (response.type == ChatResponseType.done) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete(accumulatedContent);
            }
          } else if (response.type == ChatResponseType.error) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(response.content ?? 'Unknown streaming error');
            }
          }
        },
        onError: (err) {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
        },
        onDone: () {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete(accumulatedContent);
          }
        },
        cancelOnError: true,
      );

      final rawResponse = await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          subscription?.cancel();
          chatService.cancelStream();
          return accumulatedContent;
        },
      );

      return _parseSuggestions(rawResponse);
    } catch (e) {
      Log.warning('LLM SmartReply generation failed: $e');
      return [];
    }
  }

  Future<String?> generateUserMessage({
    required ChatService chatService,
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async {
    if (messages.isEmpty) return null;

    return _generateUserMessageViaChat(
      chatService: chatService,
      server: server,
      modelId: modelId,
      messages: messages,
      params: params,
    );
  }

  Future<String?> _generateUserMessageViaChat({
    required ChatService chatService,
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async {
    final promptMessage = Message(
      id: 'ai-user-response-prompt',
      conversationId: messages.last.conversationId,
      role: MessageRole.user,
      content:
          'Based on the conversation above, write the next user message that a human would naturally send. '
          'Return ONLY the raw message text with no quotes, labels, markdown, or explanation.',
      createdAt: DateTime.now(),
    );

    final suggestionParams = params.copyWith(
      temperature: 0.7,
      maxTokens: 256,
      systemPrompt:
          'You write realistic user messages for chat conversations. Output only the user message text.',
    );

    try {
      final completer = Completer<String>();
      var accumulatedContent = '';

      final stream = chatService.sendMessage(
        server: server,
        modelId: modelId,
        messages: [...messages, promptMessage],
        params: suggestionParams,
      );

      StreamSubscription? subscription;
      subscription = stream.listen(
        (response) {
          if (response.type == ChatResponseType.message &&
              response.content != null) {
            accumulatedContent += response.content!;
          } else if (response.type == ChatResponseType.done) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete(accumulatedContent);
            }
          } else if (response.type == ChatResponseType.error) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(response.content ?? 'Unknown error');
            }
          }
        },
        onError: (err) {
          subscription?.cancel();
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          subscription?.cancel();
          if (!completer.isCompleted) completer.complete(accumulatedContent);
        },
        cancelOnError: true,
      );

      final rawResponse = await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          subscription?.cancel();
          return accumulatedContent;
        },
      );

      return _cleanGeneratedUserMessage(rawResponse);
    } catch (e) {
      Log.warning('AI user message generation failed: $e');
      return null;
    }
  }

  String? _cleanGeneratedUserMessage(String? rawResponse) {
    if (rawResponse == null) return null;
    final cleaned = rawResponse.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      return cleaned.substring(1, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  List<String> _parseSuggestions(String text) {
    final cleaned = text.trim();

    // 1. Try parsing as JSON array
    try {
      final startIdx = cleaned.indexOf('[');
      final endIdx = cleaned.lastIndexOf(']');
      if (startIdx != -1 && endIdx != -1 && endIdx > startIdx) {
        final jsonStr = cleaned.substring(startIdx, endIdx + 1);
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {
      // Ignore JSON parsing failures and fall back to line-by-line parsing
    }

    // 2. Fallback: Line-based parsing (numbered list, bullet points, etc.)
    final suggestions = <String>[];
    final lines = cleaned.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Remove numbered list prefixes like "1. ", "2)", etc.
      // Also remove bullet points like "- ", "* "
      line = line.replaceFirst(RegExp(r'^(\d+\.\s*|\d+\)\s*|[-*+]\s*)'), '');
      line = line.trim();

      // Strip surrounding quotes if present
      if (line.startsWith('"') && line.endsWith('"')) {
        line = line.substring(1, line.length - 1).trim();
      } else if (line.startsWith("'") && line.endsWith("'")) {
        line = line.substring(1, line.length - 1).trim();
      }

      if (line.isNotEmpty && line.length < 100) {
        suggestions.add(line);
      }
    }
    return suggestions.take(3).toList();
  }

  List<String> getFallbackReplies(String content) {
    final cleanContent = content.trim();
    final lowerContent = cleanContent.toLowerCase();

    // 1. Greetings & Welcomes
    if (lowerContent.contains('hello') ||
        lowerContent.contains('hi') ||
        lowerContent.contains('hey') ||
        lowerContent.contains('greetings') ||
        lowerContent.contains('good morning') ||
        lowerContent.contains('good afternoon') ||
        lowerContent.contains('good evening') ||
        lowerContent.contains('welcome')) {
      return [
        'Hello! How are you?',
        'I have a question',
        'Let\'s get started!',
      ];
    }

    // 2. Gratitude & Farewells
    if (lowerContent.contains('thank you') ||
        lowerContent.contains('thanks') ||
        lowerContent.contains('great help') ||
        lowerContent.contains('solved') ||
        lowerContent.contains('goodbye') ||
        lowerContent.contains('bye') ||
        lowerContent.contains('see you')) {
      return [
        'You\'re welcome!',
        'Thanks for your help!',
        'Have a great day!',
      ];
    }

    // 3. Code & Programming
    if (lowerContent.contains('```') ||
        lowerContent.contains('function') ||
        lowerContent.contains('class ') ||
        lowerContent.contains('import ') ||
        lowerContent.contains('const ') ||
        lowerContent.contains('def ') ||
        lowerContent.contains('fn ') ||
        lowerContent.contains('public static') ||
        lowerContent.contains('std::') ||
        lowerContent.contains('package:')) {
      return [
        'Explain this code',
        'How can I improve this?',
        'Add error handling',
        'Write tests for this',
      ];
    }

    // 4. Debugging & Errors
    if (lowerContent.contains('error') ||
        lowerContent.contains('exception') ||
        lowerContent.contains('failed') ||
        lowerContent.contains('crash') ||
        lowerContent.contains('bug') ||
        lowerContent.contains('issue') ||
        lowerContent.contains('problem') ||
        lowerContent.contains('broken') ||
        lowerContent.contains('debug') ||
        lowerContent.contains('stacktrace')) {
      return [
        'How do I fix this error?',
        'What causes this issue?',
        'Show me a fix',
        'How to prevent this?',
      ];
    }

    // 5. Lists & Steps
    final hasNumberedList = RegExp(r'\b\d+\.\s').hasMatch(cleanContent);
    final hasBulletList = RegExp(r'^[\s]*[-*+]\s', multiLine: true).hasMatch(cleanContent);
    if (hasNumberedList ||
        hasBulletList ||
        lowerContent.contains('step 1') ||
        lowerContent.contains('firstly') ||
        lowerContent.contains('secondly') ||
        lowerContent.contains('finally') ||
        lowerContent.contains('steps:')) {
      return [
        'Can you elaborate on step 1?',
        'What is the next step?',
        'Give me a summary',
        'Can you simplify this?',
      ];
    }

    // 6. Questions asked by the assistant
    if (cleanContent.endsWith('?')) {
      final isYesNoQuestion = lowerContent.contains('do you') ||
          lowerContent.contains('can you') ||
          lowerContent.contains('is it') ||
          lowerContent.contains('are you') ||
          lowerContent.contains('would you') ||
          lowerContent.contains('should we');
      if (isYesNoQuestion) {
        return [
          'Yes, please.',
          'No, thank you.',
          'Can you explain more?',
        ];
      }
      return [
        'Sure, tell me more.',
        'I\'m not sure, what do you think?',
        'Can you give me an example?',
      ];
    }

    // 7. Writing & Content Creation
    if (lowerContent.contains('write') ||
        lowerContent.contains('essay') ||
        lowerContent.contains('poem') ||
        lowerContent.contains('story') ||
        lowerContent.contains('summarize') ||
        lowerContent.contains('draft') ||
        lowerContent.contains('paragraph') ||
        lowerContent.contains('grammar') ||
        lowerContent.contains('article') ||
        lowerContent.contains('translation') ||
        lowerContent.contains('translate')) {
      return [
        'Can you make it shorter?',
        'Make it more professional',
        'Can you change the tone?',
        'Check for grammatical errors',
      ];
    }

    // 8. Data & Tables
    if (lowerContent.contains('data') ||
        lowerContent.contains('json') ||
        lowerContent.contains('csv') ||
        lowerContent.contains('table') ||
        lowerContent.contains('chart') ||
        lowerContent.contains('database') ||
        lowerContent.contains('sql') ||
        lowerContent.contains('format') ||
        lowerContent.contains('query') ||
        lowerContent.contains('analytics')) {
      return [
        'Format this as a markdown table',
        'Convert this to JSON',
        'How do I query this?',
        'Summarize key insights',
      ];
    }

    // 9. Planning & Ideas
    if (lowerContent.contains('plan') ||
        lowerContent.contains('idea') ||
        lowerContent.contains('brainstorm') ||
        lowerContent.contains('suggest') ||
        lowerContent.contains('recommend') ||
        lowerContent.contains('options') ||
        lowerContent.contains('alternatives') ||
        lowerContent.contains('strategies') ||
        lowerContent.contains('tips')) {
      return [
        'Give me more options',
        'Which one do you recommend?',
        'What are the pros and cons?',
        'Help me choose between them',
      ];
    }

    // 10. Default General suggestions
    return [
      'Tell me more',
      'Give me an example',
      'Can you explain this simpler?',
      'What are the alternatives?',
    ];
  }

  void reset() {}

  void dispose() {}
}
