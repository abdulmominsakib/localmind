@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_parse_result.dart';
import 'package:llamadart/src/core/template/chat_template_engine.dart';
import 'package:llamadart/src/core/template/template_caps.dart';
import 'package:llamadart/src/core/template/thinking_utils.dart';
import 'package:test/test.dart';

/// Diagnostic test that exercises every fixture template through the full
/// render + parse pipeline to identify exactly which models break.
void main() {
  final fixturesDir = Directory('test/fixtures/templates');
  final templateFiles = fixturesDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final simpleMessages = [
    LlamaChatMessage(role: 'user', content: 'Hello, how are you?'),
  ];

  final systemMessages = [
    LlamaChatMessage(role: 'system', content: 'You are a helpful assistant.'),
    LlamaChatMessage(role: 'user', content: 'Hello, how are you?'),
  ];

  final multiTurnMessages = [
    LlamaChatMessage(role: 'system', content: 'You are a helpful assistant.'),
    LlamaChatMessage(role: 'user', content: 'What is 2+2?'),
    LlamaChatMessage(role: 'assistant', content: '4'),
    LlamaChatMessage(role: 'user', content: 'And 3+3?'),
  ];

  final metadata = <String, String>{
    'tokenizer.ggml.bos_token': '<s>',
    'tokenizer.ggml.eos_token': '</s>',
  };

  group('Format Detection', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('detects format for $name', () {
        final source = file.readAsStringSync();
        final format = detectChatFormat(source);
        expect(format, isNotNull);
      });
    }
  });

  group('Render Pipeline - Simple Messages', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('renders $name with simple messages', () {
        final source = file.readAsStringSync();
        final result = ChatTemplateEngine.render(
          templateSource: source,
          messages: simpleMessages,
          metadata: metadata,
        );
        expect(result.prompt, isNotEmpty);
      });
    }
  });

  group('Render Pipeline - System + User Messages', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('renders $name with system messages', () {
        final source = file.readAsStringSync();
        final result = ChatTemplateEngine.render(
          templateSource: source,
          messages: systemMessages,
          metadata: metadata,
        );
        // Verify the system message content appears somewhere
        expect(result.prompt, contains('helpful assistant'));
      });
    }
  });

  group('Render Pipeline - Multi-Turn', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('renders $name with multi-turn messages', () {
        final source = file.readAsStringSync();
        final result = ChatTemplateEngine.render(
          templateSource: source,
          messages: multiTurnMessages,
          metadata: metadata,
        );
        expect(result.prompt, isNotEmpty);
        // Verify both user messages appear
        expect(result.prompt, contains('2+2'));
        expect(result.prompt, contains('3+3'));
      });
    }
  });

  group('Render Pipeline - enableThinking=false', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('renders $name with enableThinking=false', () {
        final source = file.readAsStringSync();
        final result = ChatTemplateEngine.render(
          templateSource: source,
          messages: simpleMessages,
          metadata: metadata,
          enableThinking: false,
        );
        expect(result.prompt, isNotEmpty);
      });
    }
  });

  group('Parse Pipeline - Content Output', () {
    for (final file in templateFiles) {
      final name = file.path.split('/').last.replaceAll('.jinja', '');
      test('parses simple content for $name', () {
        final source = file.readAsStringSync();
        final format = detectChatFormat(source);
        final result = ChatTemplateEngine.parse(
          format.index,
          'I am fine, thank you!',
        );
        expect(result.content, contains('fine'));
      });
    }
  });

  group('Parse Pipeline - Thinking Output', () {
    final thinkingCases = {
      'Qwen3-4B': '<think>\nLet me reason...\n</think>\n\nThe answer is 42.',
      'DeepSeek-R1-Distill-Llama-8B':
          '<think>\nLet me reason...\n</think>\n\nThe answer is 42.',
      'Ministral-3-3B-Reasoning':
          '[THINK]Let me reason...[/THINK]The answer is 42.',
    };

    for (final entry in thinkingCases.entries) {
      test('parses thinking for ${entry.key}', () {
        // Find the matching fixture
        final file = templateFiles.firstWhere(
          (f) => f.path.contains(entry.key),
          orElse: () => throw StateError('No fixture for ${entry.key}'),
        );
        final source = file.readAsStringSync();
        final format = detectChatFormat(source);
        final result = ChatTemplateEngine.parse(format.index, entry.value);
        expect(result.content, contains('42'));
        expect(result.reasoningContent, contains('reason'));
      });
    }
  });

  group('Regression Tests', () {
    test('Llama 3 parses name+parameters tool call object', () {
      const output =
          '{"type": "function", "name": "get_current_time", "parameters": {}}';
      final result = ChatTemplateEngine.parse(ChatFormat.llama3.index, output);
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.function?.name, equals('get_current_time'));
    });

    test('DeepSeek-R1-Distill-Qwen caps (TypedContent False Positive)', () {
      final file = templateFiles.firstWhere(
        (f) => f.path.contains('DeepSeek-R1-Distill-Qwen-1_5B'),
      );
      final source = file.readAsStringSync();
      final caps = TemplateCaps.detect(source);
      // BUG: Was previously true because it matched tool['type']
      expect(
        caps.supportsTypedContent,
        isFalse,
        reason: 'DeepSeek R1 template uses string concatenation, not blocks',
      );
    });

    test('Robust Thinking forced-open detection', () {
      expect(isThinkingForcedOpen('<think>'), isTrue);
      expect(isThinkingForcedOpen('<think>\n'), isTrue);
      expect(isThinkingForcedOpen('  <think>  '), isTrue);
      expect(isThinkingForcedOpen('<think> '), isTrue);
      expect(isThinkingForcedOpen('<think>\r\n'), isTrue);
      expect(isThinkingForcedOpen('Not thinking'), isFalse);

      // Custom tags
      expect(isThinkingForcedOpen('[THINK]\n', startTag: '[THINK]'), isTrue);
      expect(
        isThinkingForcedOpen(
          '<|START_THINKING|>\n',
          startTag: '<|START_THINKING|>',
        ),
        isTrue,
      );

      // Escaped newlines (common in JSON/Templates)
      expect(isThinkingForcedOpen('<think>\\n'), isTrue);
      expect(isThinkingForcedOpen('<think>\\r\\n'), isTrue);
      expect(isThinkingForcedOpen('<think> \\n '), isTrue);
    });

    test('Reasoning content unescaping', () {
      final input = '<think>Line1\\nLine2\\r\\nLine3</think> Content';
      final result = extractThinking(input);
      expect(result.reasoning, equals('Line1\nLine2\r\nLine3'));
      expect(result.content, equals('Content'));

      final input2 = 'Start\\nMiddle</think> End';
      final result2 = extractThinking(input2, thinkingForcedOpen: true);
      // Wait, startIdx is -1. thinkingForcedOpen=true.
      // But endIdx matches "Start\\nMiddle".
      // We stripping text before end tag.
      expect(result2.reasoning, equals('Start\nMiddle'));
      expect(result2.content, equals('End'));
    });

    test('Pre-opened thinking extraction (Streaming)', () {
      // 1. ThinkingUtils logic
      final ext = extractThinking(
        'Still reasoning...',
        thinkingForcedOpen: true,
      );
      expect(ext.reasoning, equals('Still reasoning...'));
      expect(ext.content, isEmpty);

      final ext2 = extractThinking(
        'Still reasoning...</think> Final answer',
        thinkingForcedOpen: true,
      );
      expect(ext2.reasoning, equals('Still reasoning...'));
      expect(ext2.content, equals('Final answer'));

      // 2. DeepSeek Handler propagation
      final result = ChatTemplateEngine.parse(
        ChatFormat.deepseekR1.index,
        'Deep thoughts...',
        isPartial: true,
        thinkingForcedOpen: true,
      );
      expect(result.reasoningContent, equals('Deep thoughts...'));
      expect(result.content, isEmpty);
    });

    test('LlamaChatMessage Reasoning separation', () {
      final message = LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          const LlamaThinkingContent('The thoughts'),
          const LlamaTextContent('The answer'),
        ],
      );

      // content getter should skip thinking
      expect(message.content, equals('The answer'));
      // reasoning getter should find it
      expect(message.reasoning, equals('The thoughts'));
      // toJson should keep them separate
      final json = message.toJson();
      expect(json['reasoning_content'], equals('The thoughts'));
      expect(json['content'], equals('The answer'));
    });

    test('ChatParseResult.toAssistantMessage helper', () {
      const result = ChatParseResult(
        content: 'Final answer',
        reasoningContent: 'Thoughts...',
      );
      final message = result.toAssistantMessage();

      expect(message.role, equals(LlamaChatRole.assistant));
      expect(message.content, equals('Final answer'));
      expect(message.reasoning, equals('Thoughts...'));
      expect(message.parts.length, equals(2));
      expect(message.parts[0], isA<LlamaThinkingContent>());
      expect(message.parts[1], isA<LlamaTextContent>());
    });

    test('TranslateGemma fixture injects default language codes', () {
      final file = templateFiles.firstWhere(
        (f) => f.path.contains('TranslateGemma-2B-it'),
      );
      final source = file.readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        metadata: metadata,
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.translateGemma.index));
      expect(
        result.prompt,
        contains('[source_lang_code]en-GB[/source_lang_code]'),
      );
      expect(
        result.prompt,
        contains('[target_lang_code]en-GB[/target_lang_code]'),
      );
      expect(result.prompt, contains('hello'));
    });

    test('TranslateGemma fixture respects metadata language overrides', () {
      final file = templateFiles.firstWhere(
        (f) => f.path.contains('TranslateGemma-2B-it'),
      );
      final source = file.readAsStringSync();

      final result = ChatTemplateEngine.render(
        templateSource: source,
        messages: const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: '안녕하세요'),
        ],
        metadata: {
          ...metadata,
          'source_lang_code': 'ko-KR',
          'target_lang_code': 'en-US',
        },
        addAssistant: false,
      );

      expect(result.format, equals(ChatFormat.translateGemma.index));
      expect(
        result.prompt,
        contains('[source_lang_code]ko-KR[/source_lang_code]'),
      );
      expect(
        result.prompt,
        contains('[target_lang_code]en-US[/target_lang_code]'),
      );
      expect(result.prompt, contains('안녕하세요'));
    });
  });
}
