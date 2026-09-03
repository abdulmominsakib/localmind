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
import 'package:localmind/features/chat/providers/chat_reasoning_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';

class CapturingStreamInterceptor extends Interceptor {
  RequestOptions? capturedRequest;
  final List<String> lines;

  CapturingStreamInterceptor(this.lines);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    capturedRequest = options;
    final controller = StreamController<Uint8List>();
    handler.resolve(
      Response(
        requestOptions: options,
        data: ResponseBody(
          controller.stream,
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        ),
        statusCode: 200,
      ),
    );

    Future.microtask(() async {
      for (final line in lines) {
        controller.add(Uint8List.fromList(utf8.encode('$line\n')));
        await Future.delayed(const Duration(milliseconds: 1));
      }
      await controller.close();
    });
  }
}

/// Asserts that [body] uses the native /api/v1/chat reasoning shape:
/// `reasoning` is a string equal to [expected], and the OpenAI-compat
/// keys the shared [_applyReasoningControl] would otherwise write are
/// absent. Used by the reasoning-control tests.
void expectNativeReasoningShape(Map<String, dynamic> body, Object expected) {
  expect(
    body['reasoning'],
    isA<String>(),
    reason: 'native endpoint expects reasoning as a string',
  );
  expect(body['reasoning'], equals(expected));
  expect(body.containsKey('reasoning_effort'), isFalse);
  expect(body.containsKey('think'), isFalse);
  expect(body.containsKey('enable_thinking'), isFalse);
}

/// Builds the minimal successful SSE stub for a single model turn —
/// chat.start + chat.end — keyed by [modelId].
List<String> _lmStudioMinimalStub(String modelId) => [
  'event: chat.start',
  'data: {"type":"chat.start","model_instance_id":"$modelId"}',
  '',
  'event: chat.end',
  'data: {"type":"chat.end","result":{"model_instance_id":"$modelId","output":[],"stats":{"input_tokens":1,"total_output_tokens":1}}}',
  '',
];

/// Sets up an LM Studio chat harness with a captured request and the
/// minimal SSE stub for [modelId]. The returned [CapturingStreamInterceptor]
/// has [RequestOptions.data] populated after [service] processes the
/// request.
({CapturingStreamInterceptor interceptor, Dio dio, LMStudioChatService service})
buildLmStudioHarness({String modelId = 'test-model'}) {
  final interceptor = CapturingStreamInterceptor(_lmStudioMinimalStub(modelId));
  final dio = Dio()..interceptors.add(interceptor);
  return (
    interceptor: interceptor,
    dio: dio,
    service: LMStudioChatService(dio),
  );
}

void main() {
  group('LM Studio MCP Integration Tests (native /api/v1/chat)', () {
    final server = Server(
      id: 'lmstudio-server',
      name: 'LM Studio',
      type: ServerType.lmStudio,
      host: 'localhost',
      port: 1234,
      apiKey: 'test-token',
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

    test(
      'endpoint is /api/v1/chat and body uses input/system_prompt/max_output_tokens',
      () async {
        final interceptor = CapturingStreamInterceptor([
          'event: chat.start',
          'data: {"type":"chat.start","model_instance_id":"test-model"}',
          '',
          'event: message.delta',
          'data: {"type":"message.delta","content":"Hello"}',
          '',
          'event: chat.end',
          'data: {"type":"chat.end","result":{"model_instance_id":"test-model","output":[],"stats":{"input_tokens":5,"total_output_tokens":1}}}',
          '',
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

        final responses = await service
            .sendMessage(
              server: server,
              modelId: 'test-model',
              messages: [userMessage],
              params: ChatParameters.defaults(),
              integrations: integrations,
            )
            .toList();

        expect(
          responses.any((r) => r.type == ChatResponseType.message),
          isTrue,
        );
        expect(interceptor.capturedRequest, isNotNull);

        // Endpoint must be the native one.
        expect(
          interceptor.capturedRequest!.path,
          equals('http://localhost:1234/api/v1/chat'),
        );

        // Auth header must be propagated when the server has an apiKey.
        expect(
          interceptor.capturedRequest!.headers['Authorization'],
          equals('Bearer test-token'),
        );

        final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
        expect(body['model'], equals('test-model'));
        expect(body['stream'], isTrue);

        // Wire format expectations (per LM Studio's /api/v1/chat spec).
        expect(body['input'], isA<String>());
        expect(body['input'], contains('Search Hugging Face models'));
        expect(
          body.containsKey('messages'),
          isFalse,
          reason: 'messages is OpenAI-style; the native endpoint uses input',
        );
        expect(
          body.containsKey('max_tokens'),
          isFalse,
          reason: 'native endpoint uses max_output_tokens',
        );
        expect(body['max_output_tokens'], isA<int>());

        // Integrations payload shape matches the spec.
        expect(body['integrations'], isNotNull);
        final bodyIntegrations = body['integrations'] as List;
        expect(bodyIntegrations.length, equals(2));

        expect(
          bodyIntegrations[0],
          equals({
            'type': 'ephemeral_mcp',
            'server_label': 'huggingface',
            'server_url': 'https://huggingface.co/mcp',
            'allowed_tools': ['model_search'],
            'headers': {'Authorization': 'Bearer test-token'},
          }),
        );

        expect(
          bodyIntegrations[1],
          equals({'type': 'plugin', 'id': 'mcp/playwright'}),
        );
      },
    );

    test(
      'reasoning control uses native string shape, not OpenAI-compat object',
      () async {
        // Regression: the shared _applyReasoningControl writes `reasoning` as
        // an object and extra OpenAI-compat keys (reasoning_effort/think/
        // enable_thinking). LM Studio's native /api/v1/chat rejects all of
        // those with HTTP 400, so LMStudioChatService must emit the native
        // string form ('off'|'low'|'medium'|'high'|'xhigh') only.
        final harness = buildLmStudioHarness();

        await harness.service
            .sendMessage(
              server: server,
              modelId: 'test-model',
              messages: [userMessage],
              params: ChatParameters.defaults().copyWith(
                reasoningEnabled: true,
                reasoningEffort: ReasoningEffort.medium,
              ),
            )
            .toList();

        final body =
            harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
        // Must send the actual effort enum value ('medium'), not the
        // generic 'on' which newer models like meta/muse-glimmer reject.
        expectNativeReasoningShape(body, 'medium');
      },
    );

    test('reasoning enabled sends the requested enum value, not "on" '
        '(muse-glimmer regression)', () async {
      // Regression for https://github.com/abdulmominsakib/localmind/issues/75
      // meta/muse-glimmer accepts only 'low'|'medium'|'high'|'xhigh' and
      // rejects 'on' with HTTP 400. The native LM Studio chat service
      // must forward the user's selected effort instead of the
      // hard-coded 'on'. We bracket the enum with the lightest and
      // heaviest advertised efforts — `effort.apiValue` is a constant
      // per enum value, so additional iterations would only test the
      // same mapping again.
      const glimmerAllowed = ['low', 'medium', 'high', 'xhigh'];
      const bracketingEfforts = [ReasoningEffort.low, ReasoningEffort.xhigh];

      for (final effort in bracketingEfforts) {
        final harness = buildLmStudioHarness(modelId: 'meta/muse-glimmer');

        await harness.service
            .sendMessage(
              server: server,
              modelId: 'meta/muse-glimmer',
              messages: [userMessage],
              params: ChatParameters.defaults().copyWith(
                reasoningEnabled: true,
                reasoningEffort: effort,
                reasoningAllowedOptions: glimmerAllowed,
                reasoningDefaultOption: 'medium',
              ),
            )
            .toList();

        final body =
            harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
        expectNativeReasoningShape(body, effort.apiValue);
      }
    });

    test('reasoning disabled omits key when off is not advertised '
        '(muse-glimmer follow-up)', () async {
      // Follow-up on #75: muse-glimmer also rejects 'off' with HTTP 400
      // (supported: low|medium|high|xhigh). Disabling thinking must omit
      // the key so the server falls back to its default instead of 400.
      final harness = buildLmStudioHarness(modelId: 'meta/muse-glimmer');

      await harness.service
          .sendMessage(
            server: server,
            modelId: 'meta/muse-glimmer',
            messages: [userMessage],
            params: ChatParameters.defaults().copyWith(
              reasoningEnabled: false,
              reasoningEffort: ReasoningEffort.low,
              reasoningAllowedOptions: const ['low', 'medium', 'high', 'xhigh'],
              reasoningDefaultOption: 'medium',
            ),
          )
          .toList();

      final body =
          harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
      expect(body.containsKey('reasoning'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('think'), isFalse);
      expect(body.containsKey('enable_thinking'), isFalse);
    });

    test('binary on/off model sends literal "on" when enabled', () async {
      final harness = buildLmStudioHarness();

      await harness.service
          .sendMessage(
            server: server,
            modelId: 'test-model',
            messages: [userMessage],
            params: ChatParameters.defaults().copyWith(
              reasoningEnabled: true,
              reasoningEffort: ReasoningEffort.low,
              reasoningAllowedOptions: const ['off', 'on'],
              reasoningDefaultOption: 'on',
            ),
          )
          .toList();

      final body =
          harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
      expectNativeReasoningShape(body, 'on');
    });

    test('minimal/max efforts snap to LM Studio range', () async {
      for (final (effort, expected) in [
        (ReasoningEffort.minimal, 'low'),
        (ReasoningEffort.max, 'xhigh'),
      ]) {
        final harness = buildLmStudioHarness();

        await harness.service
            .sendMessage(
              server: server,
              modelId: 'test-model',
              messages: [userMessage],
              params: ChatParameters.defaults().copyWith(
                reasoningEnabled: true,
                reasoningEffort: effort,
              ),
            )
            .toList();

        final body =
            harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
        expectNativeReasoningShape(body, expected);
      }
    });

    test('unsupported model omits reasoning key entirely', () async {
      final harness = buildLmStudioHarness();

      await harness.service
          .sendMessage(
            server: server,
            modelId: 'test-model',
            messages: [userMessage],
            params: ChatParameters.defaults(),
          )
          .toList();

      final body =
          harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
      expect(body.containsKey('reasoning'), isFalse);
    });

    test('reasoning disabled sends native "off" string', () async {
      final harness = buildLmStudioHarness();

      await harness.service
          .sendMessage(
            server: server,
            modelId: 'test-model',
            messages: [userMessage],
            params: ChatParameters.defaults().copyWith(reasoningEnabled: false),
          )
          .toList();

      final body =
          harness.interceptor.capturedRequest!.data as Map<String, dynamic>;
      expectNativeReasoningShape(body, 'off');
    });

    test(
      'tool_call.success event surfaces as a completed tool call with output',
      () async {
        final interceptor = CapturingStreamInterceptor([
          'event: chat.start',
          'data: {"type":"chat.start","model_instance_id":"test-model"}',
          '',
          'event: tool_call.start',
          'data: {"type":"tool_call.start","tool":"model_search","provider_info":{"type":"ephemeral_mcp","server_label":"huggingface"}}',
          '',
          'event: tool_call.arguments',
          'data: {"type":"tool_call.arguments","tool":"model_search","arguments":{"sort":"trendingScore"}}',
          '',
          'event: tool_call.success',
          'data: {"type":"tool_call.success","tool":"model_search","arguments":{"sort":"trendingScore"},"output":"Model A, Model B","provider_info":{"type":"ephemeral_mcp","server_label":"huggingface"}}',
          '',
          'event: chat.end',
          'data: {"type":"chat.end","result":{"model_instance_id":"test-model","output":[],"stats":{"input_tokens":10,"total_output_tokens":2}}}',
          '',
        ]);
        final dio = Dio()..interceptors.add(interceptor);
        final service = LMStudioChatService(dio);

        final responses = await service
            .sendMessage(
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
            )
            .toList();

        final toolCalls = responses
            .where((r) => r.type == ChatResponseType.toolCall)
            .toList();
        expect(toolCalls.length, equals(1));
        expect(toolCalls.first.toolCall?.tool, equals('model_search'));
        expect(
          toolCalls.first.toolCall?.arguments,
          equals({'sort': 'trendingScore'}),
        );
        // The native endpoint executes the tool server-side; the output
        // must be propagated so the client doesn't re-execute it.
        expect(toolCalls.first.toolCall?.output, equals('Model A, Model B'));
        expect(
          toolCalls.first.toolCall?.providerInfo?.serverLabel,
          equals('huggingface'),
        );

        // The aggregated stats arrive on the chat.end event.
        final done = responses
            .where((r) => r.type == ChatResponseType.done)
            .firstOrNull;
        expect(done?.stats?.inputTokens, equals(10));
        expect(done?.stats?.totalOutputTokens, equals(2));
      },
    );

    test('mcp_connection_error surfaces as ChatResponseType.error', () async {
      final interceptor = CapturingStreamInterceptor([
        'event: error',
        'data: {"type":"error","error":{"type":"mcp_connection_error","message":"Could not reach https://huggingface.co/mcp"}}',
        '',
      ]);
      final dio = Dio()..interceptors.add(interceptor);
      final service = LMStudioChatService(dio);

      final responses = await service
          .sendMessage(
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
          )
          .toList();

      final errors = responses
          .where((r) => r.type == ChatResponseType.error)
          .toList();
      expect(errors, hasLength(1));
      expect(
        errors.first.content,
        contains('Could not reach https://huggingface.co/mcp'),
      );
    });

    test(
      'OpenAICompatibleChatService still sends integrations on /v1/chat/completions',
      () async {
        // Sanity check that the OpenAI-compatible path was not regressed.
        final openAiServer = Server(
          id: 'openai-server',
          name: 'OAI Compat',
          type: ServerType.openAICompatible,
          host: 'localhost',
          port: 1234,
          createdAt: DateTime.now(),
          lastConnectedAt: DateTime.now(),
        );
        final interceptor = CapturingStreamInterceptor([
          'data: {"choices":[{"delta":{"content":"Hi"}}]}',
          'data: [DONE]',
        ]);
        final dio = Dio()..interceptors.add(interceptor);
        final service = OpenAICompatibleChatService(dio);

        await service
            .sendMessage(
              server: openAiServer,
              modelId: 'test-model',
              messages: [userMessage],
              params: ChatParameters.defaults(),
              integrations: [
                const McpIntegration(
                  type: McpIntegrationType.plugin,
                  pluginId: 'mcp/filesystem',
                ),
              ],
            )
            .toList();

        expect(interceptor.capturedRequest, isNotNull);
        final body = interceptor.capturedRequest!.data as Map<String, dynamic>;
        expect(body['integrations'], isNotNull);
        expect(
          body['integrations'],
          equals([
            {'type': 'plugin', 'id': 'mcp/filesystem'},
          ]),
        );
      },
    );
  });
}
