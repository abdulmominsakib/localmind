import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/chat_service.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/data/models/mcp_integration.dart';
import 'package:localmind/features/servers/data/models/server.dart';

class CapturingStreamInterceptor extends Interceptor {
  RequestOptions? capturedRequest;
  final List<String> lines;

  CapturingStreamInterceptor(this.lines);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequest = options;
    final controller = StreamController<Uint8List>();
    handler.resolve(Response(
      requestOptions: options,
      data: ResponseBody(
        controller.stream,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
      statusCode: 200,
    ));

    Future.microtask(() async {
      for (final line in lines) {
        controller.add(Uint8List.fromList(utf8.encode('$line\n')));
        await Future.delayed(const Duration(milliseconds: 1));
      }
      await controller.close();
    });
  }
}

void main() {
  group('LM Studio MCP Integration Tests', () {
    final server = Server(
      id: 'lmstudio-server',
      name: 'LM Studio',
      type: ServerType.lmStudio,
      host: 'localhost',
      port: 1234,
      createdAt: DateTime.now(),
      lastConnectedAt: DateTime.now(),
    );

    final userMessage = Message(
      id: 'msg_1',
      conversationId: 'conv_1',
      role: MessageRole.user,
      content: 'Search Hugging Face models',
      createdAt: DateTime.now(),
    );

    test('LMStudioChatService includes integrations array in body payload', () async {
      final interceptor = CapturingStreamInterceptor([
        'data: {"choices":[{"delta":{"content":"Hello"}}]}',
        'data: [DONE]',
      ]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = LMStudioChatService(dio);

      final integrations = [
        const McpIntegration(
          type: McpIntegrationType.ephemeralMcp,
          serverLabel: 'huggingface',
          serverUrl: 'https://huggingface.co/mcp',
          allowedTools: ['model_search'],
          headers: {'Authorization': 'Bearer test-token'},
        ),
        const McpIntegration(
          type: McpIntegrationType.plugin,
          pluginId: 'mcp/playwright',
        ),
      ];

      final responses = await service.sendMessage(
        server: server,
        modelId: 'test-model',
        messages: [userMessage],
        params: ChatParameters.defaults(),
        integrations: integrations,
      ).toList();

      expect(responses.any((r) => r.type == ChatResponseType.message), isTrue);
      expect(interceptor.capturedRequest, isNotNull);

      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      expect(body['integrations'], isNotNull);
      final bodyIntegrations = body['integrations'] as List;
      expect(bodyIntegrations.length, equals(2));

      expect(bodyIntegrations[0], equals({
        'type': 'ephemeral_mcp',
        'server_label': 'huggingface',
        'server_url': 'https://huggingface.co/mcp',
        'allowed_tools': ['model_search'],
        'headers': {'Authorization': 'Bearer test-token'},
      }));

      expect(bodyIntegrations[1], equals({
        'type': 'plugin',
        'id': 'mcp/playwright',
      }));
    });

    test('LMStudioChatService emits toolCall response on tool_call.success event', () async {
      final interceptor = CapturingStreamInterceptor([
        'data: {"type": "tool_call.start", "tool": "model_search"}',
        'data: {"type": "tool_call.success", "tool": "model_search", "arguments": {"sort": "trendingScore"}, "output": "Model A, Model B"}',
        'data: [DONE]',
      ]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = LMStudioChatService(dio);

      final responses = await service.sendMessage(
        server: server,
        modelId: 'test-model',
        messages: [userMessage],
        params: ChatParameters.defaults(),
        integrations: [
          const McpIntegration(
            type: McpIntegrationType.ephemeralMcp,
            serverLabel: 'huggingface',
            serverUrl: 'https://huggingface.co/mcp',
          ),
        ],
      ).toList();

      final toolCalls = responses.where((r) => r.type == ChatResponseType.toolCall).toList();
      expect(toolCalls.length, equals(1));
      expect(toolCalls.first.toolCall?.tool, equals('model_search'));
      expect(toolCalls.first.toolCall?.arguments, equals({'sort': 'trendingScore'}));
    });

    test('OpenAICompatibleChatService includes integrations array in payload', () async {
      final interceptor = CapturingStreamInterceptor([
        'data: {"choices":[{"delta":{"content":"Hi"}}]}',
        'data: [DONE]',
      ]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = OpenAICompatibleChatService(dio);

      final integrations = [
        const McpIntegration(
          type: McpIntegrationType.plugin,
          pluginId: 'mcp/filesystem',
        ),
      ];

      await service.sendMessage(
        server: server,
        modelId: 'test-model',
        messages: [userMessage],
        params: ChatParameters.defaults(),
        integrations: integrations,
      ).toList();

      expect(interceptor.capturedRequest, isNotNull);
      final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
      expect(body['integrations'], isNotNull);
      expect(body['integrations'], equals([
        {'type': 'plugin', 'id': 'mcp/filesystem'},
      ]));
    });
  });
}
