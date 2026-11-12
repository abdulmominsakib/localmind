import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/src/native_reference_request.dart';
import 'package:test/test.dart';

void main() {
  const prompt = 'What is the secret code? Reply with only the code.';
  const messages = [
    LlamaChatMessage.fromText(
      role: LlamaChatRole.system,
      text: 'Remember the secret code exactly.',
    ),
    LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'The secret code is cedar17.',
    ),
    LlamaChatMessage.fromText(
      role: LlamaChatRole.assistant,
      text: 'I will remember the code.',
    ),
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
  ];
  test('C API receives system content and seeds only prior turns', () {
    final wire = nativeReferenceRequest(prompt, history: messages);
    // This is the pinned upstream C API's parse-and-wrap contract.
    final preface = [
      {
        'role': 'system',
        'content': jsonDecode(wire['system_message_json'] as String),
      },
      ...jsonDecode(wire['messages_json'] as String) as List,
    ];
    expect(preface.first, {
      'role': 'system',
      'content': 'Remember the secret code exactly.',
    });
    expect(preface.skip(1), [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'The secret code is cedar17.'},
        ],
      },
      {
        'role': 'assistant',
        'content': [
          {'type': 'text', 'text': 'I will remember the code.'},
        ],
      },
    ]);
    expect(jsonDecode(wire['message_json'] as String), {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': prompt},
      ],
    });
    expect(wire['enable_constrained_decoding'], false);
    expect(jsonDecode(wire['extra_context_json'] as String), {
      'enable_thinking': true,
    });
  });
  test('literal system control reproduces the public double-encoded bytes', () {
    final systemObject = {
      'role': 'system',
      'content': [
        {'type': 'text', 'text': messages.first.content},
      ],
    };
    final wire = nativeReferenceRequest(
      prompt,
      history: [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.system,
          text: jsonEncode(systemObject),
        ),
        ...messages.skip(1),
      ],
    );
    expect(wire['system_message_json'], jsonEncode(jsonEncode(systemObject)));
    expect(
      wire['messages_json'],
      nativeReferenceRequest(prompt, history: messages)['messages_json'],
    );
  });
  test('history-free prompt does not create a preface', () {
    final wire = nativeReferenceRequest('héllo 👋');
    expect(wire['system_message_json'], isNull);
    expect(wire['messages_json'], isNull);
    expect(
      jsonDecode(wire['message_json'] as String)['content'][0]['text'],
      'héllo 👋',
    );
  });
  test(
    'mismatched final prompt and empty history fail before native calls',
    () {
      expect(
        () => nativeReferenceRequest('different', history: messages),
        throwsArgumentError,
      );
      expect(
        () => nativeReferenceRequest(prompt, history: []),
        throwsArgumentError,
      );
      expect(
        () => nativeReferenceRequest(
          'I will remember the code.',
          history: messages.take(3).toList(),
        ),
        throwsArgumentError,
      );
    },
  );
}
