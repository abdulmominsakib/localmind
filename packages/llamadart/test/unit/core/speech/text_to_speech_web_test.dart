@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('typed text-to-speech exposes byte-only Web capabilities', () async {
    final backend = _WebBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModelFromUrl('https://example.com/qwen3-tts.gguf');
    await engine.loadMultimodalProjector(
      'https://example.com/qwen3-tts-mmproj.gguf',
    );
    final speechEngine = TextToSpeechEngine.attach(
      engine,
      adapter: const Qwen3TtsAdapter(),
    );

    final capabilities = await speechEngine.capabilities;
    final task = await speechEngine.synthesize(
      TextToSpeechRequest(
        text: 'Hello from Web.',
        speakerReference: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[82, 73, 70, 70]),
        ),
      ),
    );
    final completion = await task.done;

    expect(capabilities.isSupported, isTrue);
    expect(
      capabilities.implementation,
      TextToSpeechImplementation.webAudioGeneration,
    );
    expect(capabilities.speakerReferenceInputKinds, {
      SpeechAudioInputKind.encodedBytes,
    });
    expect(
      () => capabilities.speakerReferenceInputKinds.clear(),
      throwsUnsupportedError,
    );
    expect(completion.state, TextToSpeechCompletionState.completed);
    expect(completion.result?.samples, <double>[0.25, -0.25]);
    expect(backend.lastRequest?.speakerAudioBytes, isNotEmpty);
  });

  test('typed text-to-speech reports a Web synthesis failure through done '
      'and result, not events', () async {
    final backend = _WebBackend()..synthesisError = StateError('bridge failed');
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModelFromUrl('https://example.com/qwen3-tts.gguf');
    await engine.loadMultimodalProjector(
      'https://example.com/qwen3-tts-mmproj.gguf',
    );
    final speechEngine = TextToSpeechEngine.attach(
      engine,
      adapter: const Qwen3TtsAdapter(),
    );

    final task = await speechEngine.synthesize(
      const TextToSpeechRequest(text: 'Fail on Web.'),
    );

    expect(await task.events.toList(), isEmpty);
    final completion = await task.done;
    expect(completion.state, TextToSpeechCompletionState.failed);
    expect(completion.error, isA<LlamaTextToSpeechException>());
    await expectLater(task.result, throwsA(same(completion.error)));

    backend.synthesisError = null;
    final retry = await speechEngine.synthesize(
      const TextToSpeechRequest(text: 'Retry on Web.'),
    );
    expect((await retry.done).state, TextToSpeechCompletionState.completed);
  });

  test('load reports Web progress from 0 to 1, ending once the projector '
      'loads', () async {
    final backend = _WebBackend();
    final progress = <ModelDownloadProgress>[];
    final synthesizer = await TextToSpeechEngine.load(
      TextToSpeechModel(
        ModelSource.parse('https://example.com/qwen3-tts.gguf'),
        projector: ModelSource.parse(
          'https://example.com/qwen3-tts-mmproj.gguf',
        ),
        adapter: const Qwen3TtsAdapter(),
      ),
      onProgress: progress.add,
      backend: backend,
    );
    addTearDown(synthesizer.dispose);

    expect(backend.modelUrl, 'https://example.com/qwen3-tts.gguf');
    expect(backend.projectorUrl, 'https://example.com/qwen3-tts-mmproj.gguf');
    expect([for (final p in progress) p.fraction], [0.25, 0.5, 1.0]);
  });

  test('typed text-to-speech rejects browser-local speaker paths', () async {
    final speechEngine = TextToSpeechEngine.attach(
      LlamaEngine(_WebBackend()),
      adapter: const Qwen3TtsAdapter(),
    );

    await expectLater(
      speechEngine.synthesize(
        const TextToSpeechRequest(
          text: 'Hello.',
          speakerReference: SpeechAudioFileInput('/tmp/speaker.wav'),
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('encoded bytes'),
        ),
      ),
    );
  });
}

class _WebBackend
    implements LlamaBackend, BackendMultimodalSupport, BackendTextToSpeech {
  bool _ready = false;
  BackendTextToSpeechRequest? lastRequest;
  Object? synthesisError;
  String? modelUrl;
  String? projectorUrl;

  @override
  bool get isReady => _ready;

  @override
  bool get supportsUrlLoading => true;

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    modelUrl = url;
    onProgress?.call(0.5);
    onProgress?.call(1);
    _ready = true;
    return 1;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async {
    projectorUrl = mmProjPath;
    return 3;
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<String> getBackendName() async => 'WebGPU';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async => const BackendTextToSpeechCapabilities(
    isSupported: true,
    model: BackendTextToSpeechModel.qwen3Tts,
    sampleRateHz: 24000,
    channelCount: 1,
    supportsLanguage: true,
    supportsSpeakerReference: true,
    supportsCancellation: true,
  );

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    lastRequest = request;
    final error = synthesisError;
    if (error != null) throw error;
    return BackendTextToSpeechResult(
      samples: Float32List.fromList(<double>[0.25, -0.25]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: 1,
      truncated: false,
    );
  }

  @override
  void cancelTextToSpeech() {}

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
