import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/inference/local_inference.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/data/on_device_gemma_service.dart';
import 'package:localmind/features/on_device/providers/external_inference_provider.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';

void main() {
  test(
    'Gemma tool follow-up uses a new session and only client-supplied history',
    () async {
      final runtime = _Runtime();
      final container = ProviderContainer(
        overrides: [
          onDeviceEngineProvider.overrideWith(_LoadedEngine.new),
          onDeviceGemmaServiceProvider.overrideWithValue(runtime),
        ],
      );
      addTearDown(container.dispose);
      final inference = container.read(externalInferenceProvider);
      expect(inference.model?.supportsTools, isTrue);

      final first = await inference
          .generate(
            const InferenceRequest(
              model: _model,
              messages: [
                InferenceMessage(InferenceRole.user, 'Look up the budget.'),
              ],
              tools: [
                InferenceTool('budget', 'Get the budget', {'type': 'object'}),
              ],
            ),
            InferenceCancellation(),
          )
          .toList();
      expect(first.single, isA<InferenceCall>());
      expect((first.single as InferenceCall).call.name, 'budget');

      final followUp = await inference
          .generate(
            const InferenceRequest(
              model: _model,
              messages: [
                InferenceMessage(
                  InferenceRole.system,
                  'Answer from the tool result.',
                ),
                InferenceMessage(InferenceRole.user, 'What is the budget?'),
                InferenceMessage(
                  InferenceRole.assistant,
                  '',
                  calls: [InferenceToolCall('budget', '{}', id: 'call_1')],
                ),
                InferenceMessage(
                  InferenceRole.tool,
                  '42',
                  toolCallId: 'call_1',
                ),
              ],
              tools: [],
            ),
            InferenceCancellation(),
          )
          .toList();
      expect((followUp.single as InferenceText).text, 'The budget is 42.');
      expect(runtime.sessions, hasLength(2));
      expect(runtime.sessions.every((session) => session.closed), isTrue);
      expect(runtime.sessions.last.prompt, contains('"tool_call_id":"call_1"'));
      expect(runtime.sessions.last.prompt, contains('42'));
      expect(
        runtime.sessions.last.prompt,
        isNot(contains('Look up the budget.')),
      );
    },
  );
}

const _model = 'gemma4-e2b-instruct';

class _LoadedEngine extends OnDeviceEngineNotifier {
  @override
  OnDeviceEngineState build() => const OnDeviceEngineState(
    status: OnDeviceEngineStatus.loaded,
    loadedModelId: _model,
    loadedRuntime: OnDeviceModelRuntime.gemma,
  );
}

class _Runtime extends OnDeviceGemmaService {
  final sessions = <_Session>[];

  @override
  bool get isLoaded => true;

  @override
  String? get currentModelId => _model;

  @override
  Future<OnDeviceInferenceSession> createChat({
    String? systemInstruction,
    List<gemma.Tool> tools = const [],
    bool? supportImage,
  }) async {
    expect(supportImage, isFalse);
    if (sessions.isEmpty) {
      expect(tools.single.name, 'budget');
      expect(tools.single.parameters, {'type': 'object'});
    } else {
      expect(tools, isEmpty);
      expect(systemInstruction, 'Answer from the tool result.');
    }
    final session = _Session(
      tools.isEmpty
          ? const gemma.TextResponse('The budget is 42.')
          : const gemma.FunctionCallResponse(name: 'budget', args: {}),
    );
    sessions.add(session);
    return session;
  }
}

class _Session implements OnDeviceInferenceSession {
  _Session(this.response);
  final gemma.ModelResponse response;
  String? prompt;
  bool closed = false;

  @override
  Future<void> addQueryChunk(gemma.Message message) async =>
      prompt = message.text;

  @override
  Stream<gemma.ModelResponse> generateChatResponseAsync() =>
      Stream.value(response);

  @override
  Future<void> stopGeneration() async {}

  @override
  Future<void> close() async => closed = true;
}
