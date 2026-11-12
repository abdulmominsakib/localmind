import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  final audio = genkit.MediaPart(
    media: genkit.Media(
      url: 'data:audio/wav;base64,AQID',
      contentType: 'audio/wav',
    ),
  );
  genkit.ModelRequest request(
    List<genkit.Part> parts, {
    Map<String, dynamic>? config,
  }) => genkit.ModelRequest(
    messages: [genkit.Message(role: genkit.Role.user, content: parts)],
    config: config,
  );
  Future<api.Model<Map<String, dynamic>>> action(
    LlamaDartMediaPlugin plugin,
  ) async => (await plugin.init()).single as api.Model<Map<String, dynamic>>;

  test(
    'media model registration rejects empty names and nonpositive limits',
    () {
      final engine = _Recognizer();
      final valid = LlamaDartSpeechToTextModel(name: 'asr', engine: engine);
      expect(valid.engine, same(engine));
      expect(valid.ownsEngine, isFalse);
      for (final name in ['', '   ']) {
        expect(
          () => LlamaDartSpeechToTextModel(name: name, engine: engine),
          throwsArgumentError,
        );
      }
      for (final limit in [0, -1]) {
        expect(
          () => LlamaDartSpeechToTextModel(
            name: 'asr',
            engine: engine,
            maxInputBytes: limit,
          ),
          throwsArgumentError,
        );
        expect(
          () => LlamaDartSpeechToTextModel(
            name: 'asr',
            engine: engine,
            maxOutputBytes: limit,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'Genkit batch recognition passes encoded bytes and adapter options',
    () async {
      final engine = _Recognizer();
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartSpeechToTextModel(name: 'asr', engine: engine)],
      );
      final ai = genkit.Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final response = await ai.generate(
        model: LlamaDartMediaPlugin.modelRef('asr'),
        messages: request([audio]).messages,
        config: {'contextPrompt': 'Genkit', 'maxOutputTokens': 64},
      );
      expect(response.text, 'Hello from Genkit.');
      expect(response.usage!.inputCharacters, 0);
      expect(response.usage!.inputAudioFiles, 1);
      expect(response.usage!.outputCharacters, 'Hello from Genkit.'.length);
      expect(response.usage!.outputAudioFiles, 0);
      expect(response.usage!.inputTokens, isNull);
      expect(response.usage!.thoughtsTokens, isNull);
      expect((engine.request!.audio as llama.SpeechAudioBytesInput).bytes, [
        1,
        2,
        3,
      ]);
      expect(engine.request!.contextPrompt, 'Genkit');
      expect(engine.request!.maxOutputTokens, 64);
      expect(engine.calls, 1);
    },
  );

  test(
    'complete WAV and synthesis progress are emitted through Genkit',
    () async {
      final engine = _Synthesizer();
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartTextToSpeechModel(name: 'tts', engine: engine)],
      );
      addTearDown(plugin.dispose);
      final chunks = <genkit.ModelResponseChunk>[];
      final response = await (await action(plugin))(
        request(
          [genkit.TextPart(text: 'Hello'), audio],
          config: {'language': 'en', 'seed': 7},
        ),
        onChunk: chunks.add,
      );
      expect(engine.request!.text, 'Hello');
      expect(engine.request!.language, 'en');
      expect(engine.request!.seed, 7);
      expect(
        (engine.request!.speakerReference as llama.SpeechAudioBytesInput).bytes,
        [1, 2, 3],
      );
      final part = response.message!.content.single.mediaPart!;
      expect(part.media.contentType, 'audio/wav');
      final bytes = UriData.parse(part.media.url).contentAsBytes();
      expect(ascii.decode(bytes.take(4).toList()), 'RIFF');
      expect(bytes.length, 48);
      expect(chunks.first.custom!['llamadartProgress']['phase'], 'generating');
      expect(chunks.last.content.single.mediaPart!.media.url, part.media.url);
      expect(response.usage!.inputCharacters, engine.request!.text.length);
      expect(response.usage!.inputAudioFiles, 1);
      expect(response.usage!.outputAudioFiles, 1);
      expect(response.usage!.outputCharacters, 0);
      expect(response.usage!.outputTokens, isNull);
    },
  );

  test(
    'image options reach the engine and complete PNG returns to Genkit',
    () async {
      final engine = _ImageEngine();
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartImageModel(name: 'image', engine: engine)],
      );
      addTearDown(plugin.dispose);
      final response = await (await action(plugin))(
        request(
          [genkit.TextPart(text: 'A red dot')],
          config: {
            'width': 64,
            'height': 64,
            'steps': 1,
            'guidanceScale': 1,
            'seed': 3,
            'negativePrompt': 'blur',
            'sampler': 'euler',
            'scheduler': 'karras',
          },
        ),
      );
      expect(engine.request!.prompt, 'A red dot');
      expect(engine.request!.width, 64);
      expect(engine.request!.steps, 1);
      expect(engine.request!.seed, 3);
      expect(engine.request!.negativePrompt, 'blur');
      expect(engine.request!.sampler, llama.ImageGenerationSampler.euler);
      expect(engine.request!.scheduler, llama.ImageGenerationScheduler.karras);
      final part = response.message!.content.single.mediaPart!;
      expect(part.media.contentType, 'image/png');
      expect(response.usage!.inputCharacters, 'A red dot'.length);
      expect(response.usage!.inputImages, 0);
      expect(response.usage!.outputImages, 1);
      expect(response.usage!.outputCharacters, 0);
      expect(response.usage!.outputTokens, isNull);
      expect(UriData.parse(part.media.url).contentAsBytes().take(8), [
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
      ]);
    },
  );

  test('unknown sampler and scheduler fail before image inference', () async {
    final engine = _ImageEngine();
    final plugin = LlamaDartMediaPlugin(
      models: [LlamaDartImageModel(name: 'image', engine: engine)],
    );
    addTearDown(plugin.dispose);
    final model = await action(plugin);
    for (final config in [
      {'sampler': 'unknown'},
      {'scheduler': 'unknown'},
    ]) {
      await expectLater(
        model(request([genkit.TextPart(text: 'Hi')], config: config)),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.invalidArgument,
          ),
        ),
      );
    }
    expect(engine.request, isNull);
  });

  test('shape and config errors prevent every runtime task', () async {
    final engine = _Recognizer();
    final plugin = LlamaDartMediaPlugin(
      models: [LlamaDartSpeechToTextModel(name: 'asr', engine: engine)],
    );
    addTearDown(plugin.dispose);
    final model = await action(plugin);
    for (final req in [
      request([audio], config: {'maxOutputTokens': 0}),
      request([audio], config: {'unknown': 'SECRET'}),
      request([audio], config: {'languageHint': 'en'}),
      request([genkit.TextPart(text: 'not audio')]),
      request([audio, audio]),
      genkit.ModelRequest(
        messages: [
          genkit.Message(role: genkit.Role.system, content: [audio]),
        ],
      ),
      genkit.ModelRequest(
        messages: request([audio]).messages,
        output: genkit.OutputConfig(format: 'json'),
      ),
    ]) {
      await expectLater(model(req), throwsA(isA<genkit.GenkitException>()));
    }
    expect(engine.calls, 0);
  });

  test(
    'malformed audio fails with sanitized INVALID_ARGUMENT and no content',
    () async {
      final engine = _Recognizer()
        ..error = llama.LlamaAudioFormatException(
          'SECRET signed URL and source path',
        );
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartSpeechToTextModel(name: 'asr', engine: engine)],
      );
      addTearDown(plugin.dispose);
      final chunks = <genkit.ModelResponseChunk>[];
      await expectLater(
        (await action(plugin))(request([audio]), onChunk: chunks.add),
        throwsA(
          isA<genkit.GenkitException>()
              .having(
                (e) => e.status,
                'status',
                genkit.StatusCode.invalidArgument,
              )
              .having((e) => e.message.contains('SECRET'), 'sanitized', false),
        ),
      );
      expect(chunks.expand((chunk) => chunk.content), isEmpty);
    },
  );
  test(
    'unsupported capabilities reject before resolving or starting tasks',
    () async {
      final engine = _Recognizer()..supported = false;
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartSpeechToTextModel(name: 'asr', engine: engine)],
      );
      addTearDown(plugin.dispose);
      expect(await plugin.list(), hasLength(1));
      expect(engine.probes, 0);
      await expectLater(
        (await action(plugin))(request([audio])),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.unimplemented,
          ),
        ),
      );
      expect(engine.calls, 0);
      expect(engine.probes, 1);
    },
  );

  test('invalid synthesis config fails before a runtime task', () async {
    final engine = _Synthesizer();
    final plugin = LlamaDartMediaPlugin(
      models: [LlamaDartTextToSpeechModel(name: 'tts', engine: engine)],
    );
    addTearDown(plugin.dispose);
    final model = await action(plugin);
    for (final config in [
      {'topP': 0},
      {'maxFrames': 512.0},
      {'temperature': double.nan},
      {'seed': -1},
    ]) {
      await expectLater(
        model(request([genkit.TextPart(text: 'Hi')], config: config)),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.invalidArgument,
          ),
        ),
      );
    }
    expect(engine.request, isNull);
  });
  test(
    'byte limits reject input and generated WAV or PNG without content chunks',
    () async {
      final definitions = <LlamaDartMediaModel>[
        LlamaDartSpeechToTextModel(
          name: 'asr',
          engine: _Recognizer(),
          maxInputBytes: 2,
        ),
        LlamaDartTextToSpeechModel(
          name: 'tts',
          engine: _Synthesizer(),
          maxOutputBytes: 45,
        ),
        LlamaDartImageModel(
          name: 'image',
          engine: _ImageEngine(),
          maxOutputBytes: 1,
        ),
      ];
      for (final definition in definitions) {
        final plugin = LlamaDartMediaPlugin(models: [definition]);
        final chunks = <genkit.ModelResponseChunk>[];
        await expectLater(
          (await action(plugin))(
            request(
              definition is LlamaDartSpeechToTextModel
                  ? [audio]
                  : [genkit.TextPart(text: 'Hi')],
            ),
            onChunk: chunks.add,
          ),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(chunks.expand((chunk) => chunk.content), isEmpty);
        await plugin.dispose();
      }
    },
  );

  test('invalid PCM and truncated synthesis never publish audio', () async {
    for (final result in [
      llama.TextToSpeechResult(
        samples: Float32List.fromList([double.nan]),
        sampleRateHz: 24000,
        channelCount: 1,
        framesGenerated: 1,
        truncated: false,
      ),
      llama.TextToSpeechResult(
        samples: Float32List.fromList([0]),
        sampleRateHz: 24000,
        channelCount: 1,
        framesGenerated: 1,
        truncated: true,
      ),
      llama.TextToSpeechResult(
        samples: Float32List.fromList([0]),
        sampleRateHz: 0,
        channelCount: 1,
        framesGenerated: 1,
        truncated: false,
      ),
    ]) {
      final engine = _Synthesizer()..result = result;
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartTextToSpeechModel(name: 'tts', engine: engine)],
      );
      final chunks = <genkit.ModelResponseChunk>[];
      await expectLater(
        (await action(plugin))(
          request([genkit.TextPart(text: 'Hi')]),
          onChunk: chunks.add,
        ),
        throwsA(isA<genkit.GenkitException>()),
      );
      expect(chunks.expand((chunk) => chunk.content), isEmpty);
      await plugin.dispose();
    }
  });

  test(
    'cancellation settles one task and next queued request recovers',
    () async {
      final engine = _Recognizer()
        ..pending = Completer<llama.SpeechToTextResult>();
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartSpeechToTextModel(name: 'asr', engine: engine)],
      );
      final model = await action(plugin);
      final cancellation = genkit.CancellationController();
      final first = model(request([audio]), cancel: cancellation.token);
      final failure = expectLater(
        first,
        throwsA(isA<genkit.CancelledException>()),
      );
      await engine.started.future;
      cancellation.cancel();
      await failure;
      expect(engine.cancellations, 1);
      engine.pending = null;
      expect((await model(request([audio]))).text, 'Hello from Genkit.');
      await plugin.dispose();
    },
  );

  test(
    'disposal drains accepted work, disposes owned engines once and preserves borrowed engines',
    () async {
      final owned = _Recognizer()
        ..pending = Completer<llama.SpeechToTextResult>();
      final borrowed = _Synthesizer();
      final plugin = LlamaDartMediaPlugin(
        models: [
          LlamaDartSpeechToTextModel(
            name: 'asr',
            engine: owned,
            ownsEngine: true,
          ),
          LlamaDartTextToSpeechModel(name: 'tts', engine: borrowed),
        ],
      );
      final actions = await plugin.init();
      final model = actions.first as api.Model<Map<String, dynamic>>;
      final first = model(request([audio]));
      final second = model(request([audio]));
      await owned.started.future;
      final disposing = plugin.dispose();
      await expectLater(model(request([audio])), throwsStateError);
      expect(owned.disposals, 0);
      owned.pending!.complete(const llama.SpeechToTextResult(text: 'done'));
      await Future.wait([first, second]);
      await disposing;
      await plugin.dispose();
      expect(owned.calls, 2);
      expect(owned.disposals, 1);
      expect(borrowed.disposals, 0);
    },
  );

  test('registration rejects duplicate engine ownership across names', () {
    final engine = _Recognizer();
    expect(
      () => LlamaDartMediaPlugin(
        models: [
          LlamaDartSpeechToTextModel(name: 'a', engine: engine),
          LlamaDartSpeechToTextModel(name: 'b', engine: engine),
        ],
      ),
      throwsArgumentError,
    );
  });
}

class _Recognizer implements llama.SpeechToTextEngine {
  bool supported = true;
  Object? error;
  int calls = 0;
  int probes = 0;
  int disposals = 0;
  int cancellations = 0;
  llama.SpeechToTextRequest? request;
  Completer<llama.SpeechToTextResult>? pending;
  final started = Completer<void>();
  @override
  Future<llama.SpeechToTextCapabilities> get capabilities async {
    probes++;
    return llama.SpeechToTextCapabilities(
      isSupported: supported,
      inputKinds: {llama.SpeechAudioInputKind.encodedBytes},
      supportsCancellation: true,
    );
  }

  @override
  Future<llama.SpeechToTextTask> transcribe(
    llama.SpeechToTextRequest value,
  ) async {
    calls++;
    if (error != null) {
      throw error!;
    }
    request = value;
    if (!started.isCompleted) started.complete();
    return _AsrTask(
      pending?.future ??
          Future.value(
            const llama.SpeechToTextResult(text: 'Hello from Genkit.'),
          ),
      () {
        cancellations++;
        if (pending != null && !pending!.isCompleted) {
          pending!.completeError(llama.LlamaStateException('cancelled'));
        }
      },
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AsrTask implements llama.SpeechToTextTask {
  _AsrTask(this.result, this.onCancel);
  @override
  final Future<llama.SpeechToTextResult> result;
  final void Function() onCancel;
  @override
  void cancel() => onCancel();
  @override
  Stream<llama.SpeechToTextEvent> get events => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Synthesizer implements llama.TextToSpeechEngine {
  int disposals = 0;
  llama.TextToSpeechRequest? request;
  llama.TextToSpeechResult result = llama.TextToSpeechResult(
    samples: Float32List.fromList([0.25, -0.25]),
    sampleRateHz: 24000,
    channelCount: 1,
    framesGenerated: 2,
    truncated: false,
  );
  @override
  Future<llama.TextToSpeechCapabilities> get capabilities async =>
      const llama.TextToSpeechCapabilities(
        isSupported: true,
        supportsLanguage: true,
        supportsSpeakerReference: true,
        speakerReferenceInputKinds: {llama.SpeechAudioInputKind.encodedBytes},
        supportsCancellation: true,
      );
  @override
  Future<llama.TextToSpeechTask> synthesize(
    llama.TextToSpeechRequest value,
  ) async {
    request = value;
    return _TtsTask(result);
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TtsTask implements llama.TextToSpeechTask {
  _TtsTask(this.value);
  final llama.TextToSpeechResult value;
  @override
  Future<llama.TextToSpeechResult> get result async => value;
  @override
  Stream<llama.TextToSpeechEvent> get events => Stream.fromIterable([
    const llama.TextToSpeechProgressEvent(
      phase: llama.TextToSpeechProgressPhase.generating,
      promptTokensRemaining: 0,
      framesGenerated: 1,
      truncated: false,
    ),
  ]);
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageEngine implements llama.ImageGenerationEngine {
  llama.ImageGenerationRequest? request;
  @override
  Future<llama.ImageGenerationCapabilities> get capabilities async =>
      const llama.ImageGenerationCapabilities(
        isSupported: true,
        supportsCancellation: true,
      );
  @override
  Future<llama.ImageGenerationTask> generate(
    llama.ImageGenerationRequest value,
  ) async {
    request = value;
    return _ImageTask();
  }

  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageTask implements llama.ImageGenerationTask {
  @override
  Future<llama.ImageGenerationResult> get result async =>
      llama.ImageGenerationResult(
        images: [
          llama.GeneratedImage(
            width: 1,
            height: 1,
            channels: 3,
            pixels: Uint8List.fromList([255, 0, 0]),
          ),
        ],
        seed: 3,
        elapsed: Duration.zero,
      );
  @override
  Stream<llama.ImageGenerationEvent> get events => const Stream.empty();
  @override
  void cancel() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
