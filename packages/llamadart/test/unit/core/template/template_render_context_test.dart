import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/src/core/models/chat/chat_message.dart';
import 'package:llamadart/src/core/models/chat/chat_role.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/template/template_render_context.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateRenderContext', () {
    for (final payload in <Object?>[
      {
        'city': 'Montréal 👋',
        'quote': '"line\\next\n',
        'nested': [17, true, null],
      },
      [
        1,
        {'value': '한글'},
      ],
      17,
      1.5,
      false,
      null,
      'unchanged "text" 👋',
    ]) {
      for (final typedContentOnly in [false, true]) {
        test('serializes typed tool result ${payload.runtimeType}, '
            'typedContentOnly=$typedContentOnly', () {
          final part = LlamaToolResultContent(
            id: 'call_0',
            name: 'get_weather',
            result: payload,
          );
          final message = LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [part],
          );
          final before = message.toJson();
          final rendered = TemplateRenderContext.messagesForTemplate([
            message,
          ], typedContentOnly: typedContentOnly).single;
          final expected = payload is String ? payload : jsonEncode(payload);
          expect(
            rendered['content'],
            typedContentOnly
                ? [
                    {'type': 'text', 'text': expected},
                  ]
                : expected,
          );
          expect(rendered['tool_call_id'], 'call_0');
          expect(rendered['name'], 'get_weather');
          expect(message.toJson(), before);
          expect(identical(part.result, payload), true);
        });
      }
    }
    for (final typedContentOnly in [false, true]) {
      test('renders one tool message per tool result, '
          'typedContentOnly=$typedContentOnly', () {
        const message = LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(
              id: 'call_0',
              name: 'get_weather',
              result: 'RESULT_ONE',
            ),
            LlamaToolResultContent(
              id: 'call_1',
              name: 'get_time',
              result: {'value': 'RESULT_TWO'},
            ),
          ],
        );
        Object content(String text) => typedContentOnly
            ? [
                {'type': 'text', 'text': text},
              ]
            : text;

        expect(
          TemplateRenderContext.messagesForTemplate([
            message,
          ], typedContentOnly: typedContentOnly),
          [
            {
              'role': 'tool',
              'tool_call_id': 'call_0',
              'name': 'get_weather',
              'content': content('RESULT_ONE'),
            },
            {
              'role': 'tool',
              'tool_call_id': 'call_1',
              'name': 'get_time',
              'content': content('{"value":"RESULT_TWO"}'),
            },
          ],
        );
      });
    }

    for (final typedContentOnly in [false, true]) {
      test('gives tool-call-only and reasoning-only assistant turns empty '
          'content, typedContentOnly=$typedContentOnly', () {
        const messages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                name: 'weather',
                arguments: {'city': 'Seoul'},
                rawJson: '{"city":"Seoul"}',
              ),
            ],
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [LlamaThinkingContent('Let me think.')],
          ),
        ];

        final rendered = TemplateRenderContext.messagesForTemplate(
          messages,
          typedContentOnly: typedContentOnly,
        );

        final empty = typedContentOnly
            ? [
                {'type': 'text', 'text': ''},
              ]
            : '';
        expect(rendered.map((message) => message['content']), [empty, empty]);
        expect(messages.first.toJson()['content'], isNull);
      });
    }

    test('passes JSON-object arguments as objects with objectArguments', () {
      const messages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              name: 'search',
              arguments: {'query': 'cafes'},
              rawJson: '{"query":"cafes","filters":{"limit":3}}',
            ),
            LlamaToolCallContent(
              name: 'truncated',
              arguments: {},
              rawJson: '{"query": "caf',
            ),
            LlamaToolCallContent(name: 'list', arguments: {}, rawJson: '[1,2]'),
          ],
        ),
      ];

      List<Object?> arguments({required bool objectArguments}) => [
        for (final call
            in TemplateRenderContext.messagesForTemplate(
                  messages,
                  objectArguments: objectArguments,
                ).single['tool_calls']
                as List)
          call['function']['arguments'],
      ];

      expect(arguments(objectArguments: true), [
        {
          'query': 'cafes',
          'filters': {'limit': 3},
        },
        '{"query": "caf',
        '[1,2]',
      ]);
      expect(arguments(objectArguments: false), [
        '{"query":"cafes","filters":{"limit":3}}',
        '{"query": "caf',
        '[1,2]',
      ]);
    });

    group('splitToolResults', () {
      test('returns messages with at most one result unchanged', () {
        const messages = [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hi'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [LlamaToolResultContent(name: 'a', result: 'A')],
          ),
        ];

        expect(
          TemplateRenderContext.splitToolResults(messages),
          same(messages),
        );
      });

      test('keeps other parts, role and turn marker with the first result', () {
        const thinking = LlamaThinkingContent('why');
        const first = LlamaToolResultContent(name: 'a', result: 'A');
        const second = LlamaToolResultContent(name: 'b', result: 'B');
        const text = LlamaTextContent('note');
        const user = LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text: 'hi',
        );

        final split = TemplateRenderContext.splitToolResults(const [
          user,
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [thinking, first, second, text],
            continuesPreviousTurn: true,
          ),
        ]);

        expect(split, hasLength(3));
        expect(split[0], same(user));
        expect(split[1].parts, [thinking, first, text]);
        expect(split[2].parts, [second]);
        for (final message in split.skip(1)) {
          expect(message.role, LlamaChatRole.user);
          expect(message.continuesPreviousTurn, isTrue);
        }
      });

      test('splits repeated identical results', () {
        const result = LlamaToolResultContent(name: 'a', result: 'A');

        final split = TemplateRenderContext.splitToolResults(const [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.tool,
            content: [result, result],
          ),
        ]);

        expect(split.map((message) => message.parts), [
          [result],
          [result],
        ]);
      });
    });

    test(
      'tool-result normalization does not stringify ordinary media parts',
      () {
        final message = LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('look 👋'),
            LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
          ],
        );
        expect(
          TemplateRenderContext.messagesForTemplate([message]).single,
          message.toJson(),
        );
      },
    );

    group('multimodal', () {
      final image = LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3]));
      const audio = LlamaAudioContent(path: '/tmp/clip.wav');
      final video = LlamaVideoContent(path: '/tmp/clip.mp4');

      Object? content(List<LlamaContentPart> parts) =>
          TemplateRenderContext.messagesForTemplate([
            LlamaChatMessage.withContent(
              role: LlamaChatRole.user,
              content: parts,
            ),
          ], multimodal: true).single['content'];

      test('puts the media marker in the text where each image, audio and '
          'video part was', () {
        expect(
          content([
            const LlamaTextContent('a'),
            image,
            const LlamaTextContent('b'),
            audio,
            video,
            const LlamaTextContent('c'),
          ]),
          'a<__media__>b<__media__><__media__>c',
        );
        expect(content([image, image]), '<__media__><__media__>');
      });

      test('serializes a message without media as it does otherwise', () {
        const messages = [
          LlamaChatMessage.fromText(role: LlamaChatRole.system, text: 'sys'),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [LlamaThinkingContent('why'), LlamaTextContent('answer')],
          ),
        ];

        expect(
          TemplateRenderContext.messagesForTemplate(messages, multimodal: true),
          TemplateRenderContext.messagesForTemplate(messages),
        );
      });

      test('leaves the media parts in the typed message', () {
        final message = LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [const LlamaTextContent('look'), image],
        );

        TemplateRenderContext.messagesForTemplate([message], multimodal: true);

        expect(message.parts, [const LlamaTextContent('look'), image]);
      });
    });

    test('serializes tool-call policy without mutating typed messages', () {
      final imageBytes = Uint8List.fromList([1, 2, 3, 4]);
      final messages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            LlamaImageContent(bytes: imageBytes, width: 1, height: 1),
            const LlamaTextContent('Extract text.'),
          ],
        ),
        const LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              id: 'call_1',
              name: 'lookup',
              arguments: {'query': 'ocr'},
              rawJson: '{"query":"ocr"}',
            ),
          ],
        ),
      ];

      final renderedMessages = TemplateRenderContext.messagesForTemplate(
        messages,
        toolCallSerialization: const TemplateToolCallSerialization(
          normalizeArguments: true,
          useGenericSchema: true,
          moveToolCallsToContent: true,
        ),
      );

      final sourceImage = messages.first.parts
          .whereType<LlamaImageContent>()
          .single;
      expect(identical(sourceImage.bytes, imageBytes), isTrue);
      expect(messages.last.parts, contains(isA<LlamaToolCallContent>()));

      final userContent = renderedMessages.first['content'] as List;
      expect(
        userContent.first['image_url']['url'],
        startsWith('data:image/jpeg;base64,'),
      );
      expect(
        userContent.last,
        equals({'type': 'text', 'text': 'Extract text.'}),
      );

      final assistantMessage = renderedMessages.last;
      expect(assistantMessage.containsKey('tool_calls'), isFalse);
      final content = assistantMessage['content'] as String;
      expect(content, contains('"tool_calls"'));
      expect(content, contains('"lookup"'));
      expect(content, contains('"query"'));
    });

    test('normalizes function arguments only in the render-context maps', () {
      const messages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaToolCallContent(
              name: 'weather',
              arguments: {'city': 'Seoul'},
              rawJson: '{"city":"Seoul"}',
            ),
          ],
        ),
      ];

      final renderedMessages = TemplateRenderContext.messagesForTemplate(
        messages,
        toolCallSerialization: const TemplateToolCallSerialization(
          normalizeArguments: true,
        ),
      );

      final call = (renderedMessages.single['tool_calls'] as List).single;
      expect(call['function']['arguments'], equals({'city': 'Seoul'}));
      final originalCall = messages.single.parts
          .whereType<LlamaToolCallContent>()
          .single;
      expect(originalCall.rawJson, equals('{"city":"Seoul"}'));
    });

    test('normalizes map tool-call arguments with non-string keys', () {
      final messages = [
        <String, dynamic>{
          'role': 'assistant',
          'tool_calls': [
            {
              'type': 'function',
              'function': {
                'name': 'lookup',
                'arguments': <Object?, Object?>{1: 'one', 'city': 'Seoul'},
              },
            },
          ],
        },
      ];

      TemplateRenderContext.normalizeToolCallArgs(messages);

      final call = (messages.single['tool_calls'] as List).single;
      expect(
        call['function']['arguments'],
        equals({'1': 'one', 'city': 'Seoul'}),
      );
    });

    test('rejects non-object JSON tool-call arguments', () {
      final messages = [
        <String, dynamic>{
          'role': 'assistant',
          'tool_calls': [
            {
              'type': 'function',
              'function': {'name': 'weather', 'arguments': '[1,2,3]'},
            },
          ],
        },
      ];

      expect(
        () => TemplateRenderContext.normalizeToolCallArgs(messages),
        throwsFormatException,
      );
    });

    test(
      'merges leading system message without losing following typed parts',
      () {
        const messages = [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.system,
            text: 'You are concise.',
          ),
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [
              LlamaImageContent(path: '/tmp/page.png'),
              LlamaTextContent('Extract text.'),
            ],
          ),
        ];

        final merged = TemplateRenderContext.mergeLeadingSystemMessage(
          messages,
          supportsSystemRole: false,
        );

        expect(merged, hasLength(1));
        expect(merged.single.role, equals(LlamaChatRole.user));
        expect(
          merged.single.parts.whereType<LlamaImageContent>(),
          hasLength(1),
        );
        expect(
          merged.single.parts.map((part) => part.runtimeType),
          equals([LlamaTextContent, LlamaImageContent, LlamaTextContent]),
        );
        expect(
          merged.single.parts.whereType<LlamaTextContent>().map(
            (part) => part.text,
          ),
          equals(['You are concise.', 'Extract text.']),
        );
      },
    );

    test(
      'can encode moved tool calls compactly for template compatibility',
      () {
        final messages = [
          <String, dynamic>{
            'role': 'assistant',
            'content': 'prefix:',
            'tool_calls': [
              {
                'name': 'weather',
                'arguments': {'city': 'Seoul'},
              },
            ],
          },
        ];

        TemplateRenderContext.moveToolCallsToContent(messages, indentSpaces: 0);

        expect(messages.single.containsKey('tool_calls'), isFalse);
        expect(
          messages.single['content'],
          equals(
            'prefix:${jsonEncode({
              'tool_calls': [
                {
                  'name': 'weather',
                  'arguments': {'city': 'Seoul'},
                },
              ],
            })}',
          ),
        );
      },
    );

    test(
      'keeps only text from list content in text-oriented tool-call moves',
      () {
        final messages = [
          <String, dynamic>{
            'role': 'assistant',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,abc'},
              },
              {
                'type': 'image_url',
                'image_url': {'url': 'file:///tmp/page.png'},
              },
              {'type': 'text', 'text': 'prefix:'},
            ],
            'tool_calls': [
              {
                'name': 'weather',
                'arguments': {'city': 'Seoul'},
              },
            ],
          },
        ];

        TemplateRenderContext.moveToolCallsToContent(messages, indentSpaces: 0);

        expect(messages.single.containsKey('tool_calls'), isFalse);
        final content = messages.single['content'];
        expect(content, isA<String>());
        expect(content, contains('prefix:'));
        expect(content, contains('"tool_calls"'));
        expect(content, contains('weather'));
        expect(content, isNot(contains('image_url')));
        expect(content, isNot(contains('data:image')));
        expect(content, isNot(contains('file:///tmp/page.png')));
      },
    );

    test(
      'keeps list content structured when explicitly preserving content parts',
      () {
        final messages = [
          <String, dynamic>{
            'role': 'assistant',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/jpeg;base64,abc'},
              },
              {'type': 'text', 'text': 'prefix:'},
            ],
            'tool_calls': [
              {
                'name': 'weather',
                'arguments': {'city': 'Seoul'},
              },
            ],
          },
        ];

        TemplateRenderContext.moveToolCallsToContent(
          messages,
          indentSpaces: 0,
          preserveContentList: true,
        );

        expect(messages.single.containsKey('tool_calls'), isFalse);
        final content = messages.single['content'];
        expect(content, isA<List>());
        expect(content, hasLength(3));
        expect(content.first['type'], equals('image_url'));
        expect(content[1], equals({'type': 'text', 'text': 'prefix:'}));
        expect(content.last['type'], equals('text'));
        expect(content.last['text'], contains('"tool_calls"'));
      },
    );

    test('keeps moved tool calls as text parts for multimodal contexts', () {
      const messages = [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.assistant,
          content: [
            LlamaTextContent('prefix:'),
            LlamaToolCallContent(
              name: 'weather',
              arguments: {'city': 'Seoul'},
              rawJson: '{"city":"Seoul"}',
            ),
          ],
        ),
      ];

      final renderedMessages = TemplateRenderContext.messagesForTemplate(
        messages,
        toolCallSerialization:
            TemplateToolCallSerialization.genericSchemaInContent,
        multimodal: true,
      );

      expect(renderedMessages.single.containsKey('tool_calls'), isFalse);
      final content = renderedMessages.single['content'];
      expect(content, isA<List>());
      expect(content, hasLength(2));
      expect(content.first, equals({'type': 'text', 'text': 'prefix:'}));
      expect(content.last['type'], equals('text'));
      expect(content.last['text'], contains('"tool_calls"'));
      expect(content.last['text'], contains('"weather"'));
    });

    test(
      'keeps the audio marker when moving tool calls for multimodal contexts',
      () {
        const messages = [
          LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaAudioContent(path: '/tmp/prompt.wav'),
              LlamaTextContent('prefix:'),
              LlamaToolCallContent(
                name: 'transcribe_hint',
                arguments: {'language': 'ko'},
                rawJson: '{"language":"ko"}',
              ),
            ],
          ),
        ];

        final renderedMessages = TemplateRenderContext.messagesForTemplate(
          messages,
          toolCallSerialization:
              TemplateToolCallSerialization.genericSchemaInContent,
          multimodal: true,
        );

        expect(renderedMessages.single.containsKey('tool_calls'), isFalse);
        final content = renderedMessages.single['content'];
        expect(content, isA<List>());
        expect(content, hasLength(2));
        expect(
          content.first,
          equals({'type': 'text', 'text': '<__media__>prefix:'}),
        );
        expect(content.last['type'], equals('text'));
        expect(content.last['text'], contains('"tool_calls"'));
        expect(content.last['text'], contains('transcribe_hint'));
      },
    );
  });

  group('TemplateRenderContext tool results as user turns', () {
    const user = LlamaChatMessage.fromText(
      role: LlamaChatRole.user,
      text: 'Weather?',
    );
    const call = LlamaChatMessage.withContent(
      role: LlamaChatRole.assistant,
      content: [
        LlamaToolCallContent(
          id: 'call00001',
          name: 'get_weather',
          arguments: {'city': 'Paris'},
          rawJson: '{"city":"Paris"}',
        ),
      ],
    );
    LlamaChatMessage result(String id, Object? value) =>
        LlamaChatMessage.withContent(
          role: LlamaChatRole.tool,
          content: [
            LlamaToolResultContent(id: id, name: 'get_weather', result: value),
          ],
        );

    test('writes each result as llama.cpp minja did', () {
      final turns = TemplateRenderContext.toolResultsAsUserTurns([
        {'role': 'user', 'content': 'Weather?'},
        {
          'role': 'tool',
          'tool_call_id': 'call00001',
          'name': 'get_weather',
          'content': 'sunny',
        },
      ]);

      expect(turns, [
        {'role': 'user', 'content': 'Weather?'},
        {
          'role': 'user',
          'content':
              '{\n'
              '  "tool_response": {\n'
              '    "tool": "get_weather",\n'
              '    "content": "sunny",\n'
              '    "tool_call_id": "call00001"\n'
              '  }\n'
              '}',
        },
      ]);
    });

    test('leaves out an absent name or id', () {
      final turns = TemplateRenderContext.toolResultsAsUserTurns([
        {'role': 'tool', 'tool_call_id': null, 'content': 'sunny'},
      ]);

      expect(
        turns.single['content'],
        '{\n  "tool_response": {\n'
        '    "content": "sunny"\n  }\n}',
      );
    });

    test('joins only consecutive results', () {
      Map<String, dynamic> tool(String content) => {
        'role': 'tool',
        'content': content,
      };
      final assistant = {'role': 'assistant', 'content': 'Next.'};
      final turns = TemplateRenderContext.toolResultsAsUserTurns([
        tool('one'),
        tool('two'),
        assistant,
        tool('three'),
      ]);

      expect(turns.map((turn) => turn['role']), ['user', 'assistant', 'user']);
      expect(turns[0]['content'], allOf(contains('one'), contains('two')));
      expect(turns[0]['content'], contains('}\n{'));
      expect(turns[1], same(assistant));
      expect(
        turns[2]['content'],
        allOf(contains('three'), isNot(contains('two'))),
      );
    });

    test('joins only the user immediately after a run of results', () {
      final before = {'role': 'user', 'content': 'Before'};
      final following = {'role': 'user', 'content': 'Next', 'name': 'reader'};
      final after = {'role': 'user', 'content': 'Separate'};
      final assistant = {'role': 'assistant', 'content': 'Answer'};
      final messages = [
        before,
        {'role': 'tool', 'content': 'one'},
        {'role': 'tool', 'content': 'two'},
        following,
        after,
        assistant,
        {'role': 'tool', 'content': 'three'},
        assistant,
      ];
      final snapshot = jsonEncode(messages);
      final turns = TemplateRenderContext.toolResultsAsUserTurns(messages);
      expect(turns.map((turn) => turn['role']), [
        'user',
        'user',
        'user',
        'assistant',
        'user',
        'assistant',
      ]);
      expect(turns[0], same(before));
      expect(turns[1], {
        ...following,
        'content':
            '{\n  "tool_response": {\n    "content": "one"\n  }\n}'
            '\n{\n  "tool_response": {\n    "content": "two"\n  }\n}\nNext',
      });
      expect(turns[2], same(after));
      expect(turns[3], same(assistant));
      expect(turns[4]['content'], isNot(contains('Next')));
      expect(jsonEncode(messages), snapshot);
    });

    for (final typedContent in [false, true]) {
      test('keeps result JSON and following user media in order '
          '(typedContent=$typedContent)', () {
        final following = LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Inspect 👋 '),
            LlamaImageContent(bytes: Uint8List.fromList([1, 2, 3])),
            const LlamaTextContent(' after results.'),
          ],
        );
        final messages = [
          user,
          call,
          result('call00001', {
            'value': [false, null],
          }),
          following,
        ];
        final snapshot = jsonEncode(messages.map((m) => m.toJson()).toList());
        final turns = TemplateRenderContext.messagesForTemplate(
          messages,
          toolResultsAsUser: true,
          toolCallsAsContent: true,
          multimodal: true,
          mediaMarker: '<media>',
          typedContentOnly: typedContent,
        );
        const expected =
            '{\n  "tool_response": {\n'
            '    "tool": "get_weather",\n'
            r'    "content": "{\"value\":[false,null]}",'
            '\n    "tool_call_id": "call00001"\n  }\n}'
            '\nInspect 👋 <media> after results.';
        expect(turns, hasLength(3));
        expect(turns.last['role'], 'user');
        expect(
          turns.last['content'],
          typedContent
              ? [
                  {'type': 'text', 'text': expected},
                ]
              : expected,
        );
        expect(jsonEncode(messages.map((m) => m.toJson()).toList()), snapshot);
      });
    }

    test('keeps tool messages without toolResultsAsUser', () {
      final rendered = TemplateRenderContext.messagesForTemplate([
        user,
        call,
        result('call00001', 'sunny'),
      ], toolCallsAsContent: true);

      expect(rendered.map((message) => message['role']), [
        'user',
        'assistant',
        'tool',
      ]);
      expect(rendered[1]['tool_calls'], isA<List>());
    });

    test('changes nothing without a tool message', () {
      final plain = TemplateRenderContext.messagesForTemplate([user, call]);
      final flagged = TemplateRenderContext.messagesForTemplate(
        [user, call],
        toolResultsAsUser: true,
        toolCallsAsContent: true,
      );

      expect(flagged, plain);
      expect(flagged[1]['tool_calls'], isA<List>());
    });

    test('moves tool calls into content only with toolCallsAsContent', () {
      final messages = [user, call, result('call00001', 'sunny')];
      final kept = TemplateRenderContext.messagesForTemplate(
        messages,
        toolResultsAsUser: true,
      );
      final moved = TemplateRenderContext.messagesForTemplate(
        messages,
        toolResultsAsUser: true,
        toolCallsAsContent: true,
      );

      expect(kept.map((message) => message['role']), [
        'user',
        'assistant',
        'user',
      ]);
      expect(kept[1]['tool_calls'], isA<List>());
      expect(moved[1].containsKey('tool_calls'), isFalse);
      expect(
        moved[1]['content'],
        '{\n'
        '  "tool_calls": [\n'
        '    {\n'
        '      "name": "get_weather",\n'
        '      "arguments": {\n'
        '        "city": "Paris"\n'
        '      },\n'
        '      "id": "call00001"\n'
        '    }\n'
        '  ]\n'
        '}',
      );
      expect(moved[2], kept[2]);
    });

    test('keeps arguments that are not a JSON object as a string', () {
      final rendered = TemplateRenderContext.messagesForTemplate(
        [
          user,
          const LlamaChatMessage.withContent(
            role: LlamaChatRole.assistant,
            content: [
              LlamaToolCallContent(
                id: 'call00001',
                name: 'get_weather',
                arguments: {},
                rawJson: '{"ci',
              ),
            ],
          ),
          result('call00001', 'sunny'),
        ],
        toolResultsAsUser: true,
        toolCallsAsContent: true,
      );

      final content = rendered[1]['content'] as String;
      final calls = (jsonDecode(content) as Map)['tool_calls'] as List;
      expect(calls.single['arguments'], '{"ci');
      expect(rendered[2]['role'], 'user');
    });

    test('gives a typed-content template the user turn as a text part', () {
      final rendered = TemplateRenderContext.messagesForTemplate(
        [user, call, result('call00001', 'sunny')],
        toolResultsAsUser: true,
        typedContentOnly: true,
      );

      final content = rendered.last['content'] as List;
      expect(rendered.last['role'], 'user');
      expect(content.single['type'], 'text');
      expect(content.single['text'], contains('"tool_response"'));
    });
  });
}
