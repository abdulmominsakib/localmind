import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_api_error.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/tools/tool_definition.dart';
import 'package:localmind/features/chat/data/tools/adapters/ollama_tool_adapter.dart';
import 'package:localmind/features/chat/data/tools/adapters/openai_tool_adapter.dart';
import 'package:localmind/features/chat/data/tools/adapters/openrouter_tool_adapter.dart';
import 'package:localmind/features/servers/data/models/server.dart';

class StreamInterceptor extends Interceptor {
  final List<String> lines;
  final int statusCode;
  StreamInterceptor(this.lines, {this.statusCode = 200});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final controller = StreamController<Uint8List>();
    handler.resolve(Response(
      requestOptions: options,
      data: ResponseBody(
        controller.stream,
        statusCode,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
      statusCode: statusCode,
    ));

    // Emit lines asynchronously
    Future.microtask(() async {
      for (final line in lines) {
        controller.add(Uint8List.fromList(utf8.encode('$line\n')));
        await Future.delayed(const Duration(milliseconds: 1));
      }
      await controller.close();
    });
  }
}

class CapturingStreamInterceptor extends StreamInterceptor {
  RequestOptions? capturedRequest;

  CapturingStreamInterceptor(super.lines);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequest = options;
    super.onRequest(options, handler);
  }
}

void main() {
  group('createAdapterForServerType', () {
    test('uses OpenAI adapter for OpenAI-compatible servers', () {
      final adapter = createAdapterForServerType(ServerType.openAICompatible);
      expect(adapter, isA<OpenAiToolAdapter>());
    });

    test('uses OpenRouter adapter for OpenRouter servers', () {
      final adapter = createAdapterForServerType(ServerType.openRouter);
      expect(adapter, isA<OpenRouterToolAdapter>());
    });

    test('uses Ollama adapter for Ollama servers', () {
      final adapter = createAdapterForServerType(ServerType.ollama);
      expect(adapter, isA<OllamaToolAdapter>());
    });

    test('uses Ollama adapter for Ollama Cloud servers', () {
      final adapter = createAdapterForServerType(ServerType.ollamaCloud);
      expect(adapter, isA<OllamaToolAdapter>());
    });
  });

  group('ChatService implementation tool call adapter integration', () {
    test('OpenAICompatibleChatService uses OpenAiToolAdapter and parses OpenAI stream tool calls', () async {
      final lines = [
        'data: {"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "call_openai_1", "type": "function", "function": {"name": "calc.add", "arguments": ""}}]}}]}',
        'data: {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": "{\\"a\\":1,\\"b\\":2}"}}]}}]}',
        'data: [DONE]'
      ];

      final dio = Dio()..interceptors.add(StreamInterceptor(lines));
      final service = OpenAICompatibleChatService(dio);

      final server = Server(
        id: 'test-openai',
        name: 'Test OpenAI',
        type: ServerType.openAICompatible,
        host: 'localhost',
        port: 8080,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );

      final responseStream = service.sendMessage(
        server: server,
        modelId: 'test-model',
        messages: [
          Message(
            id: 'msg_1',
            conversationId: 'conv_1',
            role: MessageRole.user,
            content: 'hello',
            createdAt: DateTime.now(),
          )
        ],
        params: ChatParameters.defaults(),
        tools: [
          const ToolDefinition(
            name: 'calc.add',
            description: 'Add two numbers',
            inputSchema: {'type': 'object'},
            providerType: ToolProviderType.builtIn,
          )
        ],
      );

      final responses = await responseStream.toList();
      final toolCalls = responses
          .where((r) => r.type == ChatResponseType.toolCall)
          .map((r) => r.toolCall)
          .toList();

      expect(toolCalls, isNotEmpty);
      expect(toolCalls.first!.tool, 'calc.add');
      expect(toolCalls.first!.arguments['a'], 1);
      expect(toolCalls.first!.arguments['b'], 2);
    });

    test('OllamaChatService uses OllamaToolAdapter and parses Ollama stream tool calls', () async {
      final lines = [
        '{"message": {"tool_calls": [{"id": "call_ollama_1", "function": {"name": "calc.multiply", "arguments": "{\\"a\\":5,\\"b\\":6}"}}]}}',
        '{"done": true}'
      ];

      final dio = Dio()..interceptors.add(StreamInterceptor(lines));
      final service = OllamaChatService(dio);

      final server = Server(
        id: 'test-ollama',
        name: 'Test Ollama',
        type: ServerType.ollama,
        host: 'localhost',
        port: 11434,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );

      final responseStream = service.sendMessage(
        server: server,
        modelId: 'test-model',
        messages: [
          Message(
            id: 'msg_2',
            conversationId: 'conv_2',
            role: MessageRole.user,
            content: 'hello',
            createdAt: DateTime.now(),
          )
        ],
        params: ChatParameters.defaults(),
        tools: [
          const ToolDefinition(
            name: 'calc.multiply',
            description: 'Multiply two numbers',
            inputSchema: {'type': 'object'},
            providerType: ToolProviderType.builtIn,
          )
        ],
      );

      final responses = await responseStream.toList();
      final toolCalls = responses
          .where((r) => r.type == ChatResponseType.toolCall)
          .map((r) => r.toolCall)
          .toList();

      expect(toolCalls, isNotEmpty);
      expect(toolCalls.first!.tool, 'calc.multiply');
      expect(toolCalls.first!.arguments['a'], 5);
      expect(toolCalls.first!.arguments['b'], 6);
    });
  });

  group('Ollama vision message formatting', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'localmind_ollama_vision_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('sends multiple images as ordered raw base64 values', () async {
      final firstBytes = [1, 2, 3];
      final secondBytes = [4, 5, 6];
      final firstImage = await File(
        '${tempDirectory.path}/first.png',
      ).writeAsBytes(firstBytes);
      final secondImage = await File(
        '${tempDirectory.path}/second.jpg',
      ).writeAsBytes(secondBytes);
      final interceptor = CapturingStreamInterceptor(['{"done":true}']);
      final service = OllamaChatService(
        Dio()..interceptors.add(interceptor),
        imageCompressionEnabled: false,
      );

      final responses = await service
          .sendMessage(
            server: _ollamaTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'vision-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'What is shown?',
                attachmentPaths: [firstImage.path, secondImage.path],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['content'], 'What is shown?');
      expect(message['images'], [
        base64Encode(firstBytes),
        base64Encode(secondBytes),
      ]);
      expect(responses.last.type, ChatResponseType.done);
    });

    test(
      'keeps text-only messages unchanged and appends text attachments',
      () async {
        final textFile = await File(
          '${tempDirectory.path}/notes.txt',
        ).writeAsString('attachment text');
        final interceptor = CapturingStreamInterceptor(['{"done":true}']);
        final service = OllamaChatService(Dio()..interceptors.add(interceptor));

        await service
            .sendMessage(
              server: _ollamaTestServer(),
              modelId: 'text-model',
              messages: [
                Message(
                  id: 'text-message',
                  conversationId: 'conversation',
                  role: MessageRole.user,
                  content: 'Summarize this',
                  attachmentPaths: [textFile.path],
                  createdAt: DateTime.now(),
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .toList();

        final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
        final message =
            (body['messages'] as List).single as Map<String, dynamic>;
        expect(
          message['content'],
          'Summarize this\n\n--- notes.txt ---\nattachment text',
        );
        expect(message.containsKey('images'), isFalse);
      },
    );

    test('skips missing images without aborting the request', () async {
      final interceptor = CapturingStreamInterceptor(['{"done":true}']);
      final service = OllamaChatService(Dio()..interceptors.add(interceptor));

      final responses = await service
          .sendMessage(
            server: _ollamaTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'missing-image-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'Continue without the missing image',
                attachmentPaths: ['${tempDirectory.path}/missing.png'],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['content'], 'Continue without the missing image');
      expect(message.containsKey('images'), isFalse);
      expect(responses.last.type, ChatResponseType.done);
    });

    test('surfaces Ollama native stream errors', () async {
      final interceptor = CapturingStreamInterceptor([
        '{"error":"this model does not support images"}',
      ]);
      final service = OllamaChatService(Dio()..interceptors.add(interceptor));

      final responses = await service
          .sendMessage(
            server: _ollamaTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'failed-vision-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'What is shown?',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      expect(responses, hasLength(1));
      expect(responses.single.type, ChatResponseType.error);
      final parsed = ChatApiError.tryParse(responses.single.content);
      expect(parsed, isNotNull);
      expect(
        parsed!.message,
        'The selected model does not support images. Choose a vision '
            'model such as llava, qwen2.5vl, gemma3, or llama3.2-vision.',
      );
    });

    test('decodes Ollama HTTP 400 error bodies', () async {
      final interceptor = StreamInterceptor(
        ['{"error":"unable to decode image"}'],
        statusCode: 400,
      );
      final service = OllamaChatService(Dio()..interceptors.add(interceptor));

      final responses = await service
          .sendMessage(
            server: _ollamaTestServer(),
            modelId: 'qwen3-vl:2b',
            messages: [
              Message(
                id: 'http-error-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'Describe the image',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      expect(responses, hasLength(1));
      expect(responses.single.type, ChatResponseType.error);
      final parsed = ChatApiError.tryParse(responses.single.content);
      expect(parsed, isNotNull);
      expect(
        parsed!.message,
        'The server could not decode the attached image. Try a smaller '
            'or different-format image, or enable image compression in Settings.',
      );
    });

    test(
      'decodes structured Ollama HTTP 400 error envelope with type tag',
      () async {
        final interceptor = StreamInterceptor(
          [
            '{"error":{"code":400,"message":"request (4286 tokens) exceeds the available context size (4096 tokens), try increasing it","type":"exceed_context_size_error","n_prompt_tokens":4286,"n_ctx":4096}}',
          ],
          statusCode: 400,
        );
        final service = OllamaChatService(Dio()..interceptors.add(interceptor));

        final responses = await service
            .sendMessage(
              server: _ollamaTestServer(),
              modelId: 'qwen3-vl:2b',
              messages: [
                Message(
                  id: 'context-error-message',
                  conversationId: 'conversation',
                  role: MessageRole.user,
                  content: 'Tell me a story',
                  createdAt: DateTime.now(),
                ),
              ],
              params: ChatParameters.defaults(),
            )
            .toList();

        expect(responses, hasLength(1));
        expect(responses.single.type, ChatResponseType.error);
        final parsed = ChatApiError.tryParse(responses.single.content);
        expect(parsed, isNotNull);
        expect(
          parsed!.message,
          'The conversation is longer than the model\'s context window. '
              'Increase `num_ctx` for the model or start a new chat.',
        );
        expect(parsed.type, 'exceed_context_size_error');
        expect(parsed.code, '400');
      },
    );
  });

  group('OpenAI-compatible attachment formatting', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'localmind_openai_attachment_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('sends image attachments as base64 data-URL content parts', () async {
      // Minimal PNG and JPEG headers so mime-type detection is exercised.
      final pngBytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02];
      final jpegBytes = [0xff, 0xd8, 0xff, 0xe0, 0x03, 0x04, 0x05];
      final png = await File('${tempDirectory.path}/photo.png')
          .writeAsBytes(pngBytes);
      final jpeg = await File('${tempDirectory.path}/photo.jpg')
          .writeAsBytes(jpegBytes);
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenAICompatibleChatService(
        Dio()..interceptors.add(interceptor),
        imageCompressionEnabled: false,
      );

      final responses = await service
          .sendMessage(
            server: _openAiTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'vision-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'What is shown?',
                attachmentPaths: [png.path, jpeg.path],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final content = (body['messages'] as List).single['content'] as List;
      expect(content, hasLength(3));
      expect(content[0], {'type': 'text', 'text': 'What is shown?'});
      expect(
        content[1],
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/png;base64,${base64Encode(pngBytes)}',
          },
        },
      );
      expect(
        content[2],
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/jpeg;base64,${base64Encode(jpegBytes)}',
          },
        },
      );
      expect(responses.last.type, ChatResponseType.done);
    });

    test('keeps messages without attachments as plain string content', () async {
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenAICompatibleChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openAiTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'text-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'hello',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['content'], 'hello');
    });

    test('inlines text attachment contents into the user message', () async {
      final textFile = await File(
        '${tempDirectory.path}/notes.md',
      ).writeAsString('Attachment text');
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenAICompatibleChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openAiTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'text-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'Summarize this',
                attachmentPaths: [textFile.path],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(
        message['content'],
        'Summarize this\n\n--- notes.md ---\nAttachment text',
      );
    });

    test('skips missing image attachments without aborting the request', () async {
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenAICompatibleChatService(
        Dio()..interceptors.add(interceptor),
      );

      final responses = await service
          .sendMessage(
            server: _openAiTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'missing-image-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'Continue without the missing image',
                attachmentPaths: ['${tempDirectory.path}/missing.png'],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(message['content'], 'Continue without the missing image');
      expect(responses.last.type, ChatResponseType.done);
    });
  });

  group('OpenRouter attachment formatting', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'localmind_openrouter_attachment_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('sends image attachments as base64 data-URL content parts', () async {
      final pngBytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02];
      final png = await File('${tempDirectory.path}/photo.png')
          .writeAsBytes(pngBytes);
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenRouterChatService(
        Dio()..interceptors.add(interceptor),
        imageCompressionEnabled: false,
      );

      final responses = await service
          .sendMessage(
            server: _openRouterTestServer(),
            modelId: 'vision-model',
            messages: [
              Message(
                id: 'vision-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'What is shown?',
                attachmentPaths: [png.path],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final content = (body['messages'] as List).single['content'] as List;
      expect(content, hasLength(2));
      expect(content[0], {'type': 'text', 'text': 'What is shown?'});
      expect(
        content[1],
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:image/png;base64,${base64Encode(pngBytes)}',
          },
        },
      );
      expect(responses.last.type, ChatResponseType.done);
    });

    test('inlines text attachment contents into the user message', () async {
      final textFile = await File(
        '${tempDirectory.path}/notes.txt',
      ).writeAsString('attachment text');
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenRouterChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openRouterTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'text-message',
                conversationId: 'conversation',
                role: MessageRole.user,
                content: 'Summarize this',
                attachmentPaths: [textFile.path],
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final message = (body['messages'] as List).single as Map<String, dynamic>;
      expect(
        message['content'],
        'Summarize this\n\n--- notes.txt ---\nattachment text',
      );
    });
  });

  group('OpenAI-compatible & OpenRouter assistant prefill handling', () {
    test('strips trailing empty assistant when not continuing generation', () async {
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenAICompatibleChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openAiTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'u1',
                conversationId: 'c',
                role: MessageRole.user,
                content: 'hi',
                createdAt: DateTime.now(),
              ),
              Message(
                id: 'a1',
                conversationId: 'c',
                role: MessageRole.assistant,
                content: '',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final msgs = (body['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs, hasLength(1));
      expect(msgs.last['role'], 'user');
    });

    test('keeps trailing assistant prefill when continuing generation (OpenRouter)', () async {
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenRouterChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openRouterTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'u1',
                conversationId: 'c',
                role: MessageRole.user,
                content: 'hi',
                createdAt: DateTime.now(),
              ),
              Message(
                id: 'a1',
                conversationId: 'c',
                role: MessageRole.assistant,
                content: 'Sure, ',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
            continueGeneration: true,
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final msgs = (body['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs, hasLength(2));
      expect(msgs.last['role'], 'assistant');
      expect(msgs.last['content'], 'Sure, ');
    });

    test('strips trailing empty assistant on OpenRouter too', () async {
      final interceptor = CapturingStreamInterceptor(['data: [DONE]']);
      final service = OpenRouterChatService(
        Dio()..interceptors.add(interceptor),
      );

      await service
          .sendMessage(
            server: _openRouterTestServer(),
            modelId: 'text-model',
            messages: [
              Message(
                id: 'u1',
                conversationId: 'c',
                role: MessageRole.user,
                content: 'hi',
                createdAt: DateTime.now(),
              ),
              Message(
                id: 'a1',
                conversationId: 'c',
                role: MessageRole.assistant,
                content: '',
                createdAt: DateTime.now(),
              ),
            ],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      final msgs = (body['messages'] as List).cast<Map<String, dynamic>>();
      expect(msgs, hasLength(1));
      expect(msgs.last['role'], 'user');
    });
  });
}

Server _openAiTestServer() {
  return Server(
    id: 'test-openai',
    name: 'Test OpenAI',
    type: ServerType.openAICompatible,
    host: 'localhost',
    port: 8080,
    createdAt: DateTime.now(),
    lastConnectedAt: DateTime.now(),
  );
}

Server _openRouterTestServer() {
  return Server(
    id: 'test-openrouter',
    name: 'Test OpenRouter',
    type: ServerType.openRouter,
    host: 'localhost',
    port: 8080,
    createdAt: DateTime.now(),
    lastConnectedAt: DateTime.now(),
  );
}

Server _ollamaTestServer() {
  return Server(
    id: 'test-ollama',
    name: 'Test Ollama',
    type: ServerType.ollama,
    host: 'localhost',
    port: 11434,
    createdAt: DateTime.now(),
    lastConnectedAt: DateTime.now(),
  );
}
