@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('old or unvalidated Web bridge remains unsupported', () async {
    final engine = await _loadedEngine(promptSpeechToTextSupported: false);
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    final capabilities = await recognizer.capabilities;

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('v0.1.30'));
    await engine.dispose();
  });

  test('validated Web bridge advertises WAV, MP3 and FLAC bytes', () async {
    final engine = await _loadedEngine(promptSpeechToTextSupported: true);
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    final capabilities = await recognizer.capabilities;

    expect(capabilities.isSupported, isTrue);
    expect(
      capabilities.implementation,
      SpeechToTextImplementation.multimodalPromptAdapter,
    );
    expect(
      capabilities.inputKinds,
      equals(<SpeechAudioInputKind>{SpeechAudioInputKind.encodedBytes}),
    );
    expect(
      capabilities.encodedAudioFormats,
      equals(<String>{'wav', 'mp3', 'flac'}),
    );
    await engine.dispose();
  });

  for (final (encoding, magic) in <(String, List<int>)>[
    ('wav', <int>[0x52, 0x49, 0x46, 0x46]),
    ('MP3', <int>[0x49, 0x44, 0x33, 0x04]),
    ('mp3', <int>[0xff, 0xf3, 0x88, 0xc4]),
    ('flac', <int>[0x66, 0x4c, 0x61, 0x43]),
  ]) {
    test('validated Web bridge transcribes encoded $encoding bytes', () async {
      final backend = _WebSpeechBackend(promptSpeechToTextSupported: true);
      final engine = LlamaEngine(backend);
      await engine.loadModel('https://example.com/qwen3-asr.gguf');
      await engine.loadMultimodalProjector(
        'https://example.com/qwen3-asr-mmproj.gguf',
      );
      final recognizer = SpeechToTextEngine.attach(
        engine,
        adapter: const Qwen3AsrAdapter(),
      );

      final task = await recognizer.transcribe(
        SpeechToTextRequest(
          audio: SpeechAudioBytesInput(
            Uint8List.fromList(magic),
            format: SpeechAudioFormat(encoding: encoding),
          ),
        ),
      );
      final events = await task.events.toList();
      final completion = await task.done;

      expect(events, hasLength(1));
      expect((events.single as SpeechToTextFinalEvent).result.text, 'Hello.');
      expect(completion.state, SpeechToTextCompletionState.completed);
      expect((backend.lastParts!.single as LlamaAudioContent).bytes, magic);
      await engine.dispose();
    });
  }

  test('validated Web bridge keeps the raw bytes-only prompt path', () async {
    final backend = _WebSpeechBackend(promptSpeechToTextSupported: true);
    final engine = LlamaEngine(backend);
    await engine.loadModel('https://example.com/qwen3-asr.gguf');
    await engine.loadMultimodalProjector(
      'https://example.com/qwen3-asr-mmproj.gguf',
    );
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    final task = await recognizer.transcribe(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
        maxOutputTokens: 37,
      ),
    );
    await task.done;

    expect(backend.lastPrompt, 'Transcribe this audio accurately.');
    expect(backend.lastParts, hasLength(1));
    expect(backend.lastParts!.single, isA<LlamaAudioContent>());
    expect((backend.lastParts!.single as LlamaAudioContent).bytes, <int>[
      0x52,
      0x49,
      0x46,
      0x46,
    ]);
    expect(backend.lastGenerationParams?.maxTokens, 37);
    expect(backend.lastGenerationParams?.temp, 0);
    expect(backend.lastGenerationParams?.topK, 1);
    expect(backend.lastGenerationParams?.topP, 1);
    expect(backend.lastGenerationParams?.penalty, 1);
    expect(backend.lastGenerationParams?.seed, 1);
    expect(backend.lastGenerationParams?.streamBatchTokenThreshold, 1);
    await engine.dispose();
  });

  test('validated Web bridge reports an empty transcript as failure', () async {
    final backend = _WebSpeechBackend(
      promptSpeechToTextSupported: true,
      generationText: ' <asr_text> ',
    );
    final engine = LlamaEngine(backend);
    await engine.loadModel('https://example.com/qwen3-asr.gguf');
    await engine.loadMultimodalProjector(
      'https://example.com/qwen3-asr-mmproj.gguf',
    );
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    final task = await recognizer.transcribe(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
      ),
    );
    expect(await task.events.toList(), isEmpty);
    final completion = await task.done;

    expect(completion.state, SpeechToTextCompletionState.failed);
    expect(completion.result, isNull);
    expect(
      completion.error,
      isA<LlamaSpeechException>()
          .having(
            (error) => error.message,
            'message',
            contains('empty transcript'),
          )
          .having(
            (error) => error.details,
            'details',
            'The audio may be silent, or the loaded model may not be a '
                'Qwen3-ASR model: its projector type could not be checked.',
          ),
    );
    await expectLater(task.result, throwsA(same(completion.error)));

    backend.generationText = 'Recovered transcript.';
    final retry = await recognizer.transcribe(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
      ),
    );
    expect((await retry.done).result?.text, 'Recovered transcript.');
    await engine.dispose();
  });

  test('validated Web bridge cancels an active transcription', () async {
    final generationGate = Completer<void>();
    final backend = _WebSpeechBackend(
      promptSpeechToTextSupported: true,
      generationGate: generationGate,
    );
    final engine = LlamaEngine(backend);
    await engine.loadModel('https://example.com/qwen3-asr.gguf');
    await engine.loadMultimodalProjector(
      'https://example.com/qwen3-asr-mmproj.gguf',
    );
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    final task = await recognizer.transcribe(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
      ),
    );
    task.cancel();
    final completion = await task.done;

    expect(backend.cancelCalled, isFalse);
    expect(completion.state, SpeechToTextCompletionState.cancelled);
    expect(await task.events.toList(), isEmpty);
    await expectLater(task.result, throwsA(isA<LlamaStateException>()));
    await engine.dispose();
  });

  for (final call in <String>['unloadModel', 'dispose']) {
    test('validated Web bridge cancels a transcription on $call', () async {
      final generationGate = Completer<void>();
      final backend = _WebSpeechBackend(
        promptSpeechToTextSupported: true,
        generationGate: generationGate,
        partialText: 'And so, my fellow',
      );
      final engine = LlamaEngine(backend);
      await engine.loadModel('https://example.com/qwen3-asr.gguf');
      await engine.loadMultimodalProjector(
        'https://example.com/qwen3-asr-mmproj.gguf',
      );
      final recognizer = SpeechToTextEngine.attach(
        engine,
        adapter: const Qwen3AsrAdapter(),
      );

      final task = await recognizer.transcribe(
        SpeechToTextRequest(
          audio: SpeechAudioBytesInput(
            Uint8List.fromList(<int>[0x52, 0x49, 0x46, 0x46]),
            format: const SpeechAudioFormat(encoding: 'wav'),
          ),
        ),
      );
      final events = task.events.toList();
      await backend.partialSent.future;
      await (call == 'unloadModel' ? engine.unloadModel() : engine.dispose());

      final completion = await task.done;
      expect(completion.state, SpeechToTextCompletionState.cancelled);
      expect(completion.result, isNull);
      expect(await events, isEmpty);
      await engine.dispose();
    });
  }

  test('Web rejects local paths and unvalidated encoded formats', () async {
    final engine = await _loadedEngine(promptSpeechToTextSupported: true);
    final recognizer = SpeechToTextEngine.attach(
      engine,
      adapter: const Qwen3AsrAdapter(),
    );

    await expectLater(
      recognizer.transcribe(
        SpeechToTextRequest(
          audio: SpeechAudioBytesInput(Uint8List.fromList(<int>[1])),
        ),
      ),
      throwsA(
        isA<LlamaAudioFormatException>().having(
          (error) => error.toString(),
          'message',
          contains('SpeechAudioFormat.encoding: WAV, MP3, or FLAC'),
        ),
      ),
    );
    await expectLater(
      recognizer.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/fixture.wav'),
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.toString(),
          'message',
          contains('encoded audio bytes only'),
        ),
      ),
    );
    await expectLater(
      recognizer.transcribe(
        SpeechToTextRequest(
          audio: SpeechAudioBytesInput(
            Uint8List.fromList(<int>[0x4f, 0x67, 0x67, 0x53]),
            format: const SpeechAudioFormat(encoding: 'ogg'),
          ),
        ),
      ),
      throwsA(
        isA<LlamaAudioFormatException>().having(
          (error) => error.toString(),
          'message',
          contains('WAV, MP3, or FLAC'),
        ),
      ),
    );
    await engine.dispose();
  });

  test('load fetches the model and projector by URL on Web', () async {
    final backend = _WebSpeechBackend(promptSpeechToTextSupported: true);
    final progress = <ModelDownloadProgress>[];
    final recognizer = await SpeechToTextEngine.load(
      SpeechToTextModel(
        ModelSource.parse('https://example.com/qwen3-asr.gguf'),
        projector: ModelSource.parse(
          'https://example.com/qwen3-asr-mmproj.gguf',
        ),
        adapter: const Qwen3AsrAdapter(),
      ),
      onProgress: progress.add,
      backend: backend,
    );

    expect(backend.modelUrl, 'https://example.com/qwen3-asr.gguf');
    expect(backend.projectorUrl, 'https://example.com/qwen3-asr-mmproj.gguf');
    expect([for (final p in progress) p.fraction], [0.25, 0.5, 1.0]);

    final result = await recognizer.transcribeOnce(
      SpeechToTextRequest(
        audio: SpeechAudioBytesInput(
          Uint8List.fromList(<int>[1, 2, 3]),
          format: const SpeechAudioFormat(encoding: 'wav'),
        ),
      ),
    );

    expect(result.text, 'Hello.');
    await recognizer.dispose();
    expect(backend.disposeCalls, 1);
  });

  test('load disposes an engine that cannot recognize speech', () async {
    final backend = _WebSpeechBackend(promptSpeechToTextSupported: false);

    await expectLater(
      SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.parse('https://example.com/qwen3-asr.gguf'),
          projector: ModelSource.parse(
            'https://example.com/qwen3-asr-mmproj.gguf',
          ),
          adapter: const Qwen3AsrAdapter(),
        ),
        backend: backend,
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('v0.1.30'),
        ),
      ),
    );
    expect(backend.disposeCalls, 1);
  });

  test('dedicated LiteRT-LM speech remains unsupported on Web', () async {
    await expectLater(
      SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.path('/models/moonshine.tflite'),
          tokenizer: ModelSource.path('/models/tokenizer.json'),
          adapter: const LiteRtLmAsrAdapter(
            LiteRtLmAsrModelPreset.moonshineTiny,
          ),
        ),
      ),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('native runtime'),
        ),
      ),
    );

    // ignore: deprecated_member_use_from_same_package
    final engine = SpeechToTextEngine.liteRtLm(
      const LiteRtLmAsrRuntimeConfig(
        modelPath: '/models/moonshine.tflite',
        tokenizerPath: '/models/tokenizer.json',
        modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
      ),
    );

    final capabilities = await engine.capabilities;

    expect(capabilities.isSupported, isFalse);
    expect(capabilities.unsupportedReason, contains('native runtime'));
    await expectLater(
      engine.startStream(),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}

Future<LlamaEngine> _loadedEngine({
  required bool promptSpeechToTextSupported,
}) async {
  final engine = LlamaEngine(
    _WebSpeechBackend(promptSpeechToTextSupported: promptSpeechToTextSupported),
  );
  await engine.loadModel('https://example.com/qwen3-asr.gguf');
  await engine.loadMultimodalProjector(
    'https://example.com/qwen3-asr-mmproj.gguf',
  );
  return engine;
}

class _WebSpeechBackend
    implements
        LlamaBackend,
        BackendMultimodalSupport,
        BackendPromptSpeechToTextSupport {
  @override
  final bool supportsPromptSpeechToText;
  final Completer<void>? generationGate;
  final String? partialText;
  final Completer<void> partialSent = Completer<void>();
  String generationText;
  bool cancelCalled = false;
  int disposeCalls = 0;
  String? modelUrl;
  String? projectorUrl;
  String? lastPrompt;
  List<LlamaContentPart>? lastParts;
  GenerationParams? lastGenerationParams;

  _WebSpeechBackend({
    required bool promptSpeechToTextSupported,
    this.generationGate,
    this.partialText,
    this.generationText = 'Hello.',
  }) : supportsPromptSpeechToText = promptSpeechToTextSupported;

  @override
  String? get promptSpeechToTextUnsupportedReason => supportsPromptSpeechToText
      ? null
      : 'Web typed speech-to-text requires bridge v0.1.30 or newer.';

  @override
  bool get isReady => true;

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
  Future<bool> supportsAudio(int mmContextHandle) async => true;

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;

  @override
  Future<String> getBackendName() async => 'WebGPU test';

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 4096;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async => const {
    'llm.context_length': '4096',
  };

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async => 'prompt';

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    lastPrompt = prompt;
    lastParts = parts;
    lastGenerationParams = params;
    final partial = partialText;
    if (partial != null) {
      yield utf8.encode(partial);
      partialSent.complete();
    }
    final gate = generationGate;
    if (gate != null) {
      await gate.future;
    }
    if (!cancelCalled) {
      yield utf8.encode(generationText);
    }
  }

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  void cancelGeneration() {
    cancelCalled = true;
    final gate = generationGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
