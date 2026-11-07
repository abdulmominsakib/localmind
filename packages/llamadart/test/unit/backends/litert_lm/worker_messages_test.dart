@TestOn('vm')
library;

import 'dart:isolate';

import 'package:llamadart/src/backends/litert_lm/worker_messages.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  final rp = ReceivePort();
  final sp = rp.sendPort;

  group('LiteRT-LM worker messages', () {
    test('requests keep request fields', () {
      final modelLoad = LiteRtLmModelLoadRequest(
        'model.litertlm',
        const ModelParams(),
        sp,
      );
      expect(modelLoad.modelPath, 'model.litertlm');
      expect(modelLoad.sendPort, sp);

      expect(LiteRtLmModelFreeRequest(1, sp).modelHandle, 1);
      expect(
        LiteRtLmContextCreateRequest(1, const ModelParams(), sp).modelHandle,
        1,
      );
      expect(LiteRtLmContextFreeRequest(1, sp).contextHandle, 1);

      final generate = LiteRtLmGenerateRequest(
        1,
        'prompt',
        const GenerationParams(),
        sp,
        parts: const [],
      );
      expect(generate.contextHandle, 1);
      expect(generate.prompt, 'prompt');
      expect(generate.parts, isEmpty);

      final generateChat = LiteRtLmGenerateChatRequest(
        1,
        const [
          LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'hello'),
        ],
        const GenerationParams(),
        sp,
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'description': 'Get weather',
              'parameters': {'type': 'object'},
            },
          },
        ],
        toolChoice: ToolChoice.none,
        chatTemplateKwargs: const {'locale': 'en_CA'},
      );
      expect(generateChat.contextHandle, 1);
      expect(generateChat.messages.single.content, 'hello');
      expect(generateChat.tools?.single['function']['name'], 'get_weather');
      expect(generateChat.toolChoice, ToolChoice.none);
      expect(generateChat.chatTemplateKwargs, {'locale': 'en_CA'});

      expect(LiteRtLmCancelGenerationRequest(sp).sendPort, sp);
      expect(LiteRtLmTokenizeRequest(1, 'text', true, sp).text, 'text');
      expect(
        LiteRtLmDetokenizeRequest(1, const <int>[1, 2], false, sp).tokens,
        const <int>[1, 2],
      );
      expect(LiteRtLmMetadataRequest(1, sp).modelHandle, 1);
      expect(
        LiteRtLmLoraRequest(1, 'set', path: 'adapter', sendPort: sp).path,
        'adapter',
      );
      expect(LiteRtLmBackendInfoRequest(sp).sendPort, sp);
      expect(LiteRtLmAvailableBackendsRequest(sp).sendPort, sp);
      expect(LiteRtLmResolvedGpuLayersRequest(sp).sendPort, sp);
      expect(LiteRtLmPerformanceContextRequest(1, sp).contextHandle, 1);
      expect(LiteRtLmGpuSupportRequest(sp).sendPort, sp);
      expect(LiteRtLmDisposeRequest(sp).sendPort, sp);
      expect(
        LiteRtLmLogLevelRequest(LlamaLogLevel.info, sp).logLevel,
        LlamaLogLevel.info,
      );
      expect(LiteRtLmGetContextSizeRequest(1, sp).contextHandle, 1);
      expect(
        LiteRtLmMultimodalContextCreateRequest(1, 'proj', sp).mmProjPath,
        'proj',
      );
      expect(LiteRtLmMultimodalContextFreeRequest(1, sp).mmContextHandle, 1);
      expect(LiteRtLmSupportsVisionRequest(1, sp).mmContextHandle, 1);
      expect(LiteRtLmSupportsAudioRequest(1, sp).mmContextHandle, 1);
      expect(LiteRtLmSystemInfoRequest(sp).sendPort, sp);
      expect(
        LiteRtLmChatTemplateRequest(
          1,
          const <Map<String, dynamic>>[],
          null,
          true,
          sp,
        ).addAssistant,
        isTrue,
      );
    });

    test('maps Dart errors into worker error responses', () {
      expect(
        LiteRtLmErrorResponse.from(UnsupportedError('nope')).kind,
        'unsupported',
      );
      expect(LiteRtLmErrorResponse.from(ArgumentError('bad')).kind, 'argument');
      expect(LiteRtLmErrorResponse.from(StateError('wrong')).kind, 'state');

      final generic = LiteRtLmErrorResponse.from(Exception('native failed'));
      expect(generic.kind, 'exception');
      expect(generic.message, contains('native failed'));
    });

    test('responses keep response fields', () {
      expect(LiteRtLmHandleResponse(1).handle, 1);
      expect(LiteRtLmTokenResponse(const <int>[1]).bytes, const <int>[1]);
      expect(LiteRtLmTokenizeResponse(const <int>[2]).tokens, const <int>[2]);
      expect(LiteRtLmDetokenizeResponse('text').text, 'text');
      expect(
        LiteRtLmMetadataResponse(const <String, String>{'a': 'b'}).metadata,
        const <String, String>{'a': 'b'},
      );
      expect(LiteRtLmGetContextSizeResponse(4096).size, 4096);
      expect(LiteRtLmErrorResponse('bad', kind: 'state').kind, 'state');
      expect(
        LiteRtLmBackendInfoResponse('LiteRT-LM gpu').name,
        'LiteRT-LM gpu',
      );
      expect(LiteRtLmGpuSupportResponse(true).support, isTrue);
      expect(LiteRtLmResolvedGpuLayersResponse(999).layers, 999);
      final perf = LiteRtLmPerformanceContextResponse(
        loadMs: 1,
        promptEvalMs: 2,
        evalMs: 3,
        sampleMs: 4,
        promptEvalTokens: 5,
        evalTokens: 6,
        sampleCount: 7,
        reusedGraphs: 8,
      );
      expect(perf.evalTokens, 6);
      expect(LiteRtLmSystemInfoResponse(10, 4).freeVram, 4);
      expect(LiteRtLmChatTemplateResponse('prompt').result, 'prompt');
      expect(LiteRtLmDoneResponse(), isNotNull);
      expect(
        LiteRtLmWorkerHandshake(LlamaLogLevel.debug).initialLogLevel,
        LlamaLogLevel.debug,
      );
    });
  });

  rp.close();
}
