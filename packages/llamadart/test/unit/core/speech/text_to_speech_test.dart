@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('TextToSpeechEngine', () {
    late _TextToSpeechBackend backend;
    late LlamaEngine llamaEngine;
    late TextToSpeechEngine speechEngine;

    setUp(() {
      backend = _TextToSpeechBackend();
      llamaEngine = LlamaEngine(backend);
      speechEngine = TextToSpeechEngine.attach(
        llamaEngine,
        adapter: const Qwen3TtsAdapter(),
      );
    });

    tearDown(() => llamaEngine.dispose());

    test('reports an unloaded engine as unsupported', () async {
      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('Load a model'));
    });

    test('reports exact native Qwen3-TTS capabilities', () async {
      await _loadTextToSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.backendName, 'Metal');
      expect(
        capabilities.implementation,
        TextToSpeechImplementation.nativeAudioGeneration,
      );
      expect(capabilities.sampleRateHz, 24000);
      expect(capabilities.channelCount, 1);
      expect(capabilities.supportsLanguage, isTrue);
      expect(
        capabilities.supportedLanguages,
        containsAll(<String>[
          'en',
          'zh',
          'ja',
          'ko',
          'de',
          'fr',
          'ru',
          'pt',
          'es',
          'it',
        ]),
      );
      expect(capabilities.supportsSpeakerReference, isTrue);
      expect(capabilities.speakerReferenceInputKinds, {
        SpeechAudioInputKind.file,
        SpeechAudioInputKind.encodedBytes,
      });
      expect(
        () => capabilities.speakerReferenceInputKinds.clear(),
        throwsUnsupportedError,
      );
      expect(capabilities.supportsIncrementalAudio, isFalse);
      expect(capabilities.supportsCancellation, isTrue);
      expect(capabilities.supportsOutputBackpressure, isFalse);
      expect(capabilities.maxConcurrentTasks, 1);
    });

    test('emits progress then final PCM and encodes a valid WAV', () async {
      await _loadTextToSpeechModel(llamaEngine);
      final speakerBytes = Uint8List.fromList(<int>[82, 73, 70, 70]);

      final task = await speechEngine.synthesize(
        TextToSpeechRequest(
          text: 'Hello from llamadart.',
          language: 'English',
          speakerReference: SpeechAudioBytesInput(speakerBytes),
          maxFrames: 64,
          seed: 7,
        ),
      );
      final events = await task.events.toList();
      final completion = await task.done;

      expect(events, hasLength(3));
      expect(events[0], isA<TextToSpeechProgressEvent>());
      expect(events[1], isA<TextToSpeechProgressEvent>());
      final finalEvent = events[2] as TextToSpeechFinalEvent;
      expect(completion.state, TextToSpeechCompletionState.completed);
      expect(completion.result, same(finalEvent.result));
      expect(await task.result, same(finalEvent.result));
      expect(finalEvent.result.sampleRateHz, 24000);
      expect(finalEvent.result.channelCount, 1);
      expect(finalEvent.result.samples, <double>[-1, -0.5, 0, 0.5, 1]);
      expect(finalEvent.result.duration.inMicroseconds, 208);
      expect(backend.lastRequest?.text, 'Hello from llamadart.');
      expect(backend.lastRequest?.language, 'en');
      expect(backend.lastRequest?.speakerAudioBytes, speakerBytes);
      expect(backend.lastRequest?.maxFrames, 64);
      expect(backend.lastRequest?.seed, 7);
      expect(backend.lastSynthesisContextHandle, 2);
      expect(backend.lastSynthesisMmContextHandle, 3);
      expect(backend.lastCapabilitiesContextHandle, 2);
      expect(backend.lastCapabilitiesMmContextHandle, 3);

      final wav = finalEvent.result.toWavBytes();
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 24000);
      expect(ByteData.sublistView(wav).getUint16(22, Endian.little), 1);
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 10);
      expect(ByteData.sublistView(wav).getInt16(44, Endian.little), -32768);
      expect(ByteData.sublistView(wav).getInt16(52, Endian.little), 32767);
    });

    test('accepts a speaker reference file', () async {
      await _loadTextToSpeechModel(llamaEngine);

      final task = await speechEngine.synthesize(
        const TextToSpeechRequest(
          text: 'Clone this voice.',
          speakerReference: SpeechAudioFileInput('/tmp/speaker.wav'),
        ),
      );
      await task.done;

      expect(backend.lastRequest?.speakerAudioPath, '/tmp/speaker.wav');
      expect(backend.lastRequest?.speakerAudioBytes, isNull);
    });

    test('reserves the engine before asynchronous preflight', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockCapabilities = true;

      final first = speechEngine.synthesize(
        const TextToSpeechRequest(text: 'First.'),
      );
      await backend.capabilityProbeStarted.future;

      await expectLater(
        speechEngine.synthesize(const TextToSpeechRequest(text: 'Second.')),
        throwsA(isA<LlamaStateException>()),
      );
      backend.releaseCapabilities();
      await (await first).done;
    });

    test('shares the lease across separate TTS wrappers', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockSynthesis = true;
      final other = TextToSpeechEngine.attach(
        llamaEngine,
        adapter: const Qwen3TtsAdapter(),
      );

      final first = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'First.'),
      );
      await backend.synthesisStarted.future;
      await expectLater(
        other.synthesize(const TextToSpeechRequest(text: 'Second.')),
        throwsA(isA<LlamaStateException>()),
      );
      backend.releaseSynthesis();
      await first.done;
    });

    test('shares the engine lease with typed speech recognition', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockSynthesis = true;
      final recognizer = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );

      final synthesis = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'First.'),
      );
      await backend.synthesisStarted.future;
      await expectLater(
        recognizer.transcribe(
          SpeechToTextRequest(
            audio: SpeechAudioBytesInput(Uint8List.fromList(<int>[1])),
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );

      backend.releaseSynthesis();
      await synthesis.done;
    });

    test('cancels active synthesis idempotently', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockSynthesis = true;
      final task = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Cancel me.'),
      );
      await backend.synthesisStarted.future;

      task.cancel();
      task.cancel();
      final completion = await task.done;

      expect(backend.cancelCalls, 1);
      expect(completion.state, TextToSpeechCompletionState.cancelled);
      expect(await task.events.toList(), isEmpty);
      await expectLater(
        task.result,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Speech synthesis was cancelled.',
          ),
        ),
      );
    });

    test('frees the engine lease before the task reports done', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockSynthesis = true;
      final cancelled = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Cancel me.'),
      );
      await backend.synthesisStarted.future;

      cancelled.cancel();
      expect(
        (await cancelled.done).state,
        TextToSpeechCompletionState.cancelled,
      );

      backend.blockSynthesis = false;
      final next = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Next.'),
      );
      expect((await next.done).state, TextToSpeechCompletionState.completed);
    });

    for (final call in <String>['unloadModel', 'dispose']) {
      test('$call cancels an active synthesis', () async {
        await _loadTextToSpeechModel(llamaEngine);
        backend
          ..blockSynthesis = true
          ..contextFreeAwaitsSynthesis = true;
        final task = await speechEngine.synthesize(
          const TextToSpeechRequest(text: 'Cancel me.'),
        );
        await backend.synthesisStarted.future;

        final returned = call == 'unloadModel'
            ? llamaEngine.unloadModel()
            : llamaEngine.dispose();
        await returned.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            backend.releaseSynthesis();
            fail('$call waited for the synthesis instead of cancelling it.');
          },
        );

        expect(backend.cancelCalls, 1);
        expect(task.isCancellationRequested, isTrue);
        expect((await task.done).state, TextToSpeechCompletionState.cancelled);
        expect(await task.events.toList(), isEmpty);
        await expectLater(task.result, throwsA(isA<LlamaStateException>()));
      });
    }

    test('unloadModel after a synthesis completes cancels nothing', () async {
      await _loadTextToSpeechModel(llamaEngine);
      final first = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'First.'),
      );
      expect((await first.done).state, TextToSpeechCompletionState.completed);

      await llamaEngine.unloadModel();
      await _loadTextToSpeechModel(llamaEngine);
      final next = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Next.'),
      );

      expect((await next.done).state, TextToSpeechCompletionState.completed);
      expect(backend.cancelCalls, 0);
    });

    test('the backend hooks report or reject a disposed engine', () async {
      await _loadTextToSpeechModel(llamaEngine);
      await llamaEngine.dispose();

      final capabilities = await llamaEngine.backendTextToSpeechCapabilities;
      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('disposed'));
      expect(
        () => llamaEngine.synthesizeTextToSpeechBackend(
          const BackendTextToSpeechRequest(text: 'Hello.'),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
      expect(backend.lastRequest, isNull);
      expect(llamaEngine.modelHandle, isNull);
      expect(llamaEngine.contextHandle, isNull);
    });

    test('a synthesizer disposed during preflight starts no task', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockCapabilities = true;

      final pending = speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Hello.'),
      );
      await backend.capabilityProbeStarted.future;
      await speechEngine.dispose();
      backend.releaseCapabilities();

      await expectLater(pending, throwsA(isA<LlamaStateException>()));
      expect(backend.synthesisStarted.isCompleted, isFalse);
    });

    test(
      'a disposed attached LlamaEngine rejects synthesis as disposed',
      () async {
        await _loadTextToSpeechModel(llamaEngine);
        await llamaEngine.dispose();

        final capabilities = await speechEngine.capabilities;
        expect(capabilities.isSupported, isFalse);
        expect(
          capabilities.unsupportedReason,
          'The attached LlamaEngine is disposed. Create a new LlamaEngine and '
          'attach a new TextToSpeechEngine.',
        );
        await expectLater(
          speechEngine.synthesize(const TextToSpeechRequest(text: 'Hello.')),
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('The attached LlamaEngine is disposed.'),
            ),
          ),
        );
        expect(backend.synthesisStarted.isCompleted, isFalse);
      },
    );

    test('a LlamaEngine disposed during preflight starts no task', () async {
      await _loadTextToSpeechModel(llamaEngine);
      backend.blockCapabilities = true;

      final pending = speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Hello.'),
      );
      await backend.capabilityProbeStarted.future;
      final disposal = llamaEngine.dispose();
      backend.releaseCapabilities();

      await expectLater(pending, throwsA(isA<LlamaStateException>()));
      await disposal;
      expect(backend.synthesisStarted.isCompleted, isFalse);
    });

    test(
      'a disposed synthesizer rejects a request before validating it',
      () async {
        await _loadTextToSpeechModel(llamaEngine);
        await speechEngine.dispose();

        await expectLater(
          speechEngine.synthesize(const TextToSpeechRequest(text: '   ')),
          throwsA(isA<LlamaStateException>()),
        );
      },
    );

    test('validates input and sampling before capability lookup', () async {
      await _loadTextToSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.synthesize(const TextToSpeechRequest(text: '   ')),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
      await expectLater(
        speechEngine.synthesize(
          TextToSpeechRequest(
            text: 'Speaker.',
            speakerReference: SpeechAudioBytesInput(Uint8List(0)),
          ),
        ),
        throwsA(isA<LlamaAudioFormatException>()),
      );
      await expectLater(
        speechEngine.synthesize(
          const TextToSpeechRequest(text: 'Bad.', topP: 2),
        ),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
      for (final request in const <TextToSpeechRequest>[
        TextToSpeechRequest(text: 'Bad top p.', topP: double.nan),
        TextToSpeechRequest(text: 'Bad min p.', minP: double.infinity),
        TextToSpeechRequest(
          text: 'Bad temperature.',
          temperature: double.negativeInfinity,
        ),
      ]) {
        await expectLater(
          speechEngine.synthesize(request),
          throwsA(isA<LlamaTextToSpeechException>()),
        );
      }
      await expectLater(
        speechEngine.synthesize(
          const TextToSpeechRequest(
            text: 'Unknown language.',
            language: 'Klingon',
          ),
        ),
        throwsA(
          isA<LlamaTextToSpeechException>().having(
            (error) => error.message,
            'message',
            contains('zh, en'),
          ),
        ),
      );
    });

    test('reports unsupported model capability without starting', () async {
      backend.capabilities = const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'old native bundle',
      );
      await _loadTextToSpeechModel(llamaEngine);

      expect(
        (await speechEngine.capabilities).unsupportedReason,
        'old native bundle',
      );
      await expectLater(
        speechEngine.synthesize(const TextToSpeechRequest(text: 'Hello.')),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.lastRequest, isNull);
    });

    group('voices', () {
      setUp(() {
        backend.capabilities = const BackendTextToSpeechCapabilities(
          isSupported: true,
          model: BackendTextToSpeechModel.lfm3Audio,
          sampleRateHz: 24000,
          channelCount: 1,
          supportsLanguage: true,
          supportsCancellation: true,
          supportsVoice: true,
          voices: <String>['female', 'male'],
        );
        speechEngine = TextToSpeechEngine.attach(
          llamaEngine,
          adapter: const Lfm3AudioTtsAdapter(),
        );
      });

      test('reports the listed voices and passes the selected one', () async {
        await _loadTextToSpeechModel(llamaEngine);

        final capabilities = await speechEngine.capabilities;
        expect(capabilities.supportsVoice, isTrue);
        expect(capabilities.voices, <String>['female', 'male']);
        expect(capabilities.supportsSpeakerReference, isFalse);
        expect(capabilities.supportedLanguages, isEmpty);

        await speechEngine.synthesizeOnce(
          const TextToSpeechRequest(
            text: 'Hello.',
            voice: 'MALE',
            language: 'English',
          ),
        );
        expect(backend.lastRequest?.voice, 'MALE');
        expect(backend.lastRequest?.language, 'English');

        await speechEngine.synthesizeOnce(
          const TextToSpeechRequest(text: 'Hello.'),
        );
        expect(backend.lastRequest?.voice, isNull);
      });

      test('rejects an unlisted voice without starting', () async {
        await _loadTextToSpeechModel(llamaEngine);

        await expectLater(
          speechEngine.synthesize(
            const TextToSpeechRequest(text: 'Hello.', voice: 'alto'),
          ),
          throwsA(
            isA<LlamaTextToSpeechException>().having(
              (error) => error.message,
              'message',
              'Unknown LFM3-Audio voice `alto`. Use one of: female, male.',
            ),
          ),
        );
        expect(backend.lastRequest, isNull);
      });

      test(
        'leaves an unlisted voice to a runtime that cannot list voices',
        () async {
          backend.capabilities = const BackendTextToSpeechCapabilities(
            isSupported: true,
            model: BackendTextToSpeechModel.lfm3Audio,
            sampleRateHz: 24000,
            channelCount: 1,
            supportsVoice: true,
          );
          await _loadTextToSpeechModel(llamaEngine);

          await speechEngine.synthesizeOnce(
            const TextToSpeechRequest(text: 'Hello.', voice: 'alto'),
          );
          expect(backend.lastRequest?.voice, 'alto');
        },
      );

      test('rejects a voice for a model without voices', () async {
        backend.capabilities = const BackendTextToSpeechCapabilities(
          isSupported: true,
          model: BackendTextToSpeechModel.soprano,
          sampleRateHz: 32000,
          channelCount: 1,
          supportsCancellation: true,
          voices: <String>['ignored'],
        );
        speechEngine = TextToSpeechEngine.attach(
          llamaEngine,
          adapter: const SopranoTtsAdapter(),
        );
        await _loadTextToSpeechModel(llamaEngine);

        final capabilities = await speechEngine.capabilities;
        expect(capabilities.supportsVoice, isFalse);
        expect(capabilities.voices, isEmpty);
        await expectLater(
          speechEngine.synthesize(
            const TextToSpeechRequest(text: 'Hello.', voice: 'ignored'),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await expectLater(
          speechEngine.synthesize(
            const TextToSpeechRequest(text: 'Hello.', language: 'en'),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(backend.lastRequest, isNull);
      });

      test('rejects a blank voice and a voice with a speaker reference '
          'before the capability lookup', () async {
        await _loadTextToSpeechModel(llamaEngine);

        await expectLater(
          speechEngine.synthesize(
            const TextToSpeechRequest(text: 'Hello.', voice: '  '),
          ),
          throwsA(isA<LlamaTextToSpeechException>()),
        );
        await expectLater(
          speechEngine.synthesize(
            TextToSpeechRequest(
              text: 'Hello.',
              voice: 'female',
              speakerReference: SpeechAudioBytesInput(
                Uint8List.fromList(<int>[1]),
              ),
            ),
          ),
          throwsA(
            isA<LlamaTextToSpeechException>().having(
              (error) => error.message,
              'message',
              'A voice and a speaker reference cannot be combined.',
            ),
          ),
        );
        expect(backend.lastCapabilitiesContextHandle, isNull);
      });

      test('a Qwen3-TTS adapter refuses an LFM3-Audio projector', () async {
        speechEngine = TextToSpeechEngine.attach(
          llamaEngine,
          adapter: const Qwen3TtsAdapter(),
        );
        await _loadTextToSpeechModel(llamaEngine);

        expect(
          (await speechEngine.capabilities).unsupportedReason,
          'The loaded projector is not a supported Qwen3-TTS projector.',
        );
      });
    });

    test('returns typed task failure and releases the lease', () async {
      backend.synthesisError = StateError('codec failed');
      await _loadTextToSpeechModel(llamaEngine);
      final task = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Fail.'),
      );
      expect(await task.events.toList(), isEmpty);
      final completion = await task.done;
      expect(completion.state, TextToSpeechCompletionState.failed);
      expect(completion.error, isA<LlamaTextToSpeechException>());
      await expectLater(task.result, throwsA(same(completion.error)));

      backend.synthesisError = null;
      final retry = await speechEngine.synthesize(
        const TextToSpeechRequest(text: 'Retry.'),
      );
      expect((await retry.done).state, TextToSpeechCompletionState.completed);
    });
  });

  group('TextToSpeechEngine.load and attach', () {
    late _TextToSpeechBackend backend;
    late Directory directory;
    late String modelPath;
    late String projectorPath;

    setUp(() async {
      backend = _TextToSpeechBackend();
      directory = await Directory.systemTemp.createTemp('llamadart_tts_');
      modelPath = p.join(directory.path, 'tts.gguf');
      projectorPath = p.join(directory.path, 'mmproj-tts.gguf');
      await File(modelPath).writeAsBytes(<int>[1, 2, 3]);
      await File(projectorPath).writeAsBytes(<int>[4, 5]);
    });

    tearDown(() => directory.delete(recursive: true));

    TextToSpeechModel model({
      TextToSpeechAdapter adapter = const Qwen3TtsAdapter(),
    }) => TextToSpeechModel(
      ModelSource.path(modelPath),
      projector: ModelSource.path(projectorPath),
      adapter: adapter,
    );

    test('owns the engine it loads and frees it on dispose', () async {
      final synthesizer = await TextToSpeechEngine.load(
        model(),
        params: const ModelParams(contextSize: 1024),
        backend: backend,
      );

      expect(synthesizer.adapter, isA<Qwen3TtsAdapter>());
      expect(backend.lastModelParams?.contextSize, 1024);
      final capabilities = await synthesizer.capabilities;
      expect(capabilities, isA<EngineCapabilities>());
      expect(capabilities.isSupported, isTrue);
      final result = await synthesizer.synthesizeOnce(
        const TextToSpeechRequest(text: 'Hello.', language: 'English'),
      );
      expect(result.samples, hasLength(5));
      expect(backend.lastRequest?.language, 'en');

      await Future.wait<void>(<Future<void>>[
        synthesizer.dispose(),
        synthesizer.dispose(),
      ]);

      expect(synthesizer.isDisposed, isTrue);
      expect(backend.disposeCalls, 1);
      final disposed = await synthesizer.capabilities;
      expect(disposed.isSupported, isFalse);
      expect(disposed.unsupportedReason, 'The TextToSpeechEngine is disposed.');
      await expectLater(
        synthesizer.synthesize(const TextToSpeechRequest(text: 'Hi.')),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test(
      'disposal publishes terminal state before synchronous synthesis cancellation',
      () async {
        backend.blockSynthesis = true;
        final speechEngine = await TextToSpeechEngine.load(
          model(),
          backend: backend,
        );
        final task = await speechEngine.synthesize(
          const TextToSpeechRequest(text: 'Hello.'),
        );
        await backend.synthesisStarted.future;
        Future<void>? nested;
        bool? stateInHook;
        Future<TextToSpeechCapabilities>? capsInHook;
        backend.onCancel = () {
          backend.onCancel = null;
          stateInHook = speechEngine.isDisposed;
          capsInHook = speechEngine.capabilities;
          nested = speechEngine.dispose();
        };
        final first = speechEngine.dispose();
        await first;
        expect(stateInHook, isTrue);
        expect(nested, same(first));
        expect((await capsInHook!).isSupported, isFalse);
        expect(speechEngine.dispose(), same(first));
        expect((await task.done).state, TextToSpeechCompletionState.cancelled);
        expect(backend.cancelCalls, 1);
        expect(backend.disposeCalls, 1);
      },
    );

    test('dispose cancels a running task before freeing the engine', () async {
      backend.blockSynthesis = true;
      final synthesizer = await TextToSpeechEngine.load(
        model(),
        backend: backend,
      );
      final result = synthesizer.synthesizeOnce(
        const TextToSpeechRequest(text: 'Hello.'),
      );
      await backend.synthesisStarted.future;

      final failure = expectLater(
        result,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Speech synthesis was cancelled.',
          ),
        ),
      );
      await synthesizer.dispose();
      await failure;
      expect(backend.cancelCalls, 1);
      expect(backend.disposeCalls, 1);
    });

    test('synthesizeOnce throws the task failure', () async {
      backend.synthesisError = LlamaTextToSpeechException('native failure');
      final synthesizer = await TextToSpeechEngine.load(
        model(),
        backend: backend,
      );

      await expectLater(
        synthesizer.synthesizeOnce(const TextToSpeechRequest(text: 'Hello.')),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
      await synthesizer.dispose();
    });

    test(
      'a projector the adapter does not drive leaves nothing loaded',
      () async {
        await expectLater(
          TextToSpeechEngine.load(
            model(adapter: const _OtherTtsAdapter()),
            backend: backend,
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              'The loaded projector is not a supported Other-TTS projector.',
            ),
          ),
        );
        expect(backend.disposeCalls, 1);
        expect(backend.isReady, isFalse);
      },
    );

    test('refuses an adapter whose models the runtime cannot drive before '
        'loading anything', () async {
      backend.modelRefusals = {
        BackendTextToSpeechModel.lfm3Audio: 'needs llamadart-native v0.8.0',
      };
      await expectLater(
        TextToSpeechEngine.load(
          model(adapter: const Lfm3AudioTtsAdapter()),
          backend: backend,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'needs llamadart-native v0.8.0',
          ),
        ),
      );
      expect(backend.lastModelParams, isNull);
      expect(backend.disposeCalls, 1);
    });

    test('loads when the runtime drives a model the adapter accepts', () async {
      backend.modelRefusals = {
        BackendTextToSpeechModel.lfm3Audio: 'needs llamadart-native v0.8.0',
      };
      final synthesizer = await TextToSpeechEngine.load(
        model(),
        backend: backend,
      );
      await synthesizer.dispose();
      expect(backend.lastModelParams, isNotNull);
    });

    test('a runtime without text-to-speech leaves nothing loaded', () async {
      backend.capabilities = const BackendTextToSpeechCapabilities(
        isSupported: false,
        unsupportedReason: 'No audio-generation projector.',
      );

      await expectLater(
        TextToSpeechEngine.load(model(), backend: backend),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'No audio-generation projector.',
          ),
        ),
      );
      expect(backend.disposeCalls, 1);
    });

    test('a cancelled load leaves nothing loaded', () async {
      final token = ModelDownloadCancelToken()..cancel();

      await expectLater(
        TextToSpeechEngine.load(
          model(),
          download: ModelLoadOptions(cancelToken: token),
          backend: backend,
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.disposeCalls, 1);
    });

    test('rejects a checksum for the model and projector', () async {
      await expectLater(
        TextToSpeechEngine.load(
          model(),
          download: ModelLoadOptions(sha256: 'a' * 64),
          backend: backend,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            startsWith('TextToSpeechEngine model loading uses 2 files'),
          ),
        ),
      );
      expect(backend.lastModelParams, isNull);
      expect(backend.disposeCalls, 1);
    });

    test('attach borrows the engine and dispose leaves it loaded', () async {
      backend.blockSynthesis = true;
      final llamaEngine = LlamaEngine(backend);
      await _loadTextToSpeechModel(llamaEngine);
      final synthesizer = TextToSpeechEngine.attach(
        llamaEngine,
        adapter: const Qwen3TtsAdapter(),
      );
      final task = await synthesizer.synthesize(
        const TextToSpeechRequest(text: 'Hello.'),
      );
      await backend.synthesisStarted.future;
      var taskDone = false;
      unawaited(task.done.then((_) => taskDone = true));

      await synthesizer.dispose();

      expect(taskDone, isTrue);
      expect((await task.done).state, TextToSpeechCompletionState.cancelled);
      expect(llamaEngine.isReady, isTrue);
      expect(backend.disposeCalls, 0);
      await llamaEngine.dispose();
    });

    test('runs a custom adapter language table', () async {
      final synthesizer = await TextToSpeechEngine.load(
        model(adapter: const _OtherTtsAdapter(acceptsQwen3: true)),
        backend: backend,
      );

      final capabilities = await synthesizer.capabilities;
      expect(capabilities.supportedLanguages, <String>{'xx'});
      await synthesizer.synthesizeOnce(
        const TextToSpeechRequest(text: 'Hello.', language: ' Other '),
      );
      expect(backend.lastRequest?.language, 'xx');
      await expectLater(
        synthesizer.synthesize(
          const TextToSpeechRequest(text: 'Hello.', language: 'en'),
        ),
        throwsA(isA<LlamaTextToSpeechException>()),
      );
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => synthesizer.modelProfile,
        throwsA(isA<LlamaStateException>()),
      );
      await synthesizer.dispose();
    });

    test('the deprecated constructor attaches Qwen3-TTS', () async {
      final llamaEngine = LlamaEngine(backend);
      await _loadTextToSpeechModel(llamaEngine);
      // ignore: deprecated_member_use_from_same_package
      final synthesizer = TextToSpeechEngine(
        llamaEngine,
        // ignore: deprecated_member_use_from_same_package
        modelProfile: TextToSpeechModelProfile.qwen3Tts,
      );

      expect(synthesizer.adapter, isA<Qwen3TtsAdapter>());
      expect(
        // ignore: deprecated_member_use_from_same_package
        synthesizer.modelProfile,
        // ignore: deprecated_member_use_from_same_package
        TextToSpeechModelProfile.qwen3Tts,
      );
      expect((await synthesizer.capabilities).isSupported, isTrue);
      await synthesizer.dispose();
      expect(llamaEngine.isReady, isTrue);
      await llamaEngine.dispose();
    });
  });
}

Future<void> _loadTextToSpeechModel(LlamaEngine engine) async {
  await engine.loadModel('qwen3-tts.gguf');
  await engine.loadMultimodalProjector('qwen3-tts-mmproj.gguf');
}

class _TextToSpeechBackend
    implements
        LlamaBackend,
        BackendMultimodalSupport,
        BackendTextToSpeech,
        BackendTextToSpeechModelSupport {
  bool _ready = false;
  Map<BackendTextToSpeechModel, String> modelRefusals = const {};

  @override
  Future<String?> textToSpeechModelUnsupportedReason(
    BackendTextToSpeechModel model,
  ) async => modelRefusals[model];

  BackendTextToSpeechCapabilities capabilities =
      const BackendTextToSpeechCapabilities(
        isSupported: true,
        model: BackendTextToSpeechModel.qwen3Tts,
        sampleRateHz: 24000,
        channelCount: 1,
        supportsLanguage: true,
        supportsSpeakerReference: true,
        supportsCancellation: true,
      );
  bool blockCapabilities = false;
  bool blockSynthesis = false;
  bool contextFreeAwaitsSynthesis = false;
  Object? synthesisError;
  Completer<void> capabilityProbeStarted = Completer<void>();
  Completer<void> synthesisStarted = Completer<void>();
  final Completer<void> _capabilityRelease = Completer<void>();
  final Completer<void> _synthesisRelease = Completer<void>();
  int cancelCalls = 0;
  void Function()? onCancel;
  int disposeCalls = 0;
  ModelParams? lastModelParams;
  BackendTextToSpeechRequest? lastRequest;
  int? lastSynthesisContextHandle;
  int? lastSynthesisMmContextHandle;
  int? lastCapabilitiesContextHandle;
  int? lastCapabilitiesMmContextHandle;

  @override
  bool get isReady => _ready;

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    lastModelParams = params;
    _ready = true;
    return 1;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 2;

  @override
  Future<int?> multimodalContextCreate(
    int modelHandle,
    String mmProjPath,
  ) async => 3;

  @override
  Future<String> getBackendName() async => 'Metal';

  @override
  Future<BackendTextToSpeechCapabilities> textToSpeechCapabilities(
    int contextHandle,
    int mmContextHandle,
  ) async {
    lastCapabilitiesContextHandle = contextHandle;
    lastCapabilitiesMmContextHandle = mmContextHandle;
    if (!capabilityProbeStarted.isCompleted) {
      capabilityProbeStarted.complete();
    }
    if (blockCapabilities) {
      await _capabilityRelease.future;
    }
    return capabilities;
  }

  @override
  Future<BackendTextToSpeechResult> synthesizeTextToSpeech(
    int contextHandle,
    int mmContextHandle,
    BackendTextToSpeechRequest request, {
    void Function(BackendTextToSpeechProgress progress)? onProgress,
  }) async {
    lastRequest = request;
    lastSynthesisContextHandle = contextHandle;
    lastSynthesisMmContextHandle = mmContextHandle;
    if (!synthesisStarted.isCompleted) {
      synthesisStarted.complete();
    }
    if (blockSynthesis) {
      await _synthesisRelease.future;
    }
    final error = synthesisError;
    if (error != null) {
      throw error;
    }
    onProgress?.call(
      const BackendTextToSpeechProgress(
        phase: BackendTextToSpeechPhase.processingPrompt,
        promptTokensRemaining: 2,
        framesGenerated: 0,
        truncated: false,
      ),
    );
    onProgress?.call(
      const BackendTextToSpeechProgress(
        phase: BackendTextToSpeechPhase.generating,
        promptTokensRemaining: 0,
        framesGenerated: 3,
        truncated: false,
      ),
    );
    return BackendTextToSpeechResult(
      samples: Float32List.fromList(<double>[-1, -0.5, 0, 0.5, 1]),
      sampleRateHz: 24000,
      channelCount: 1,
      framesGenerated: 3,
      truncated: false,
    );
  }

  @override
  void cancelTextToSpeech() {
    onCancel?.call();
    cancelCalls += 1;
    releaseSynthesis();
  }

  @override
  void cancelGeneration() {}

  void releaseCapabilities() {
    if (!_capabilityRelease.isCompleted) {
      _capabilityRelease.complete();
    }
  }

  void releaseSynthesis() {
    if (!_synthesisRelease.isCompleted) {
      _synthesisRelease.complete();
    }
  }

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {
    // The llama.cpp worker frees the context only after synthesis ends.
    if (contextFreeAwaitsSynthesis && blockSynthesis) {
      await _synthesisRelease.future;
    }
  }

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _ready = false;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OtherTtsAdapter extends TextToSpeechAdapter {
  final bool acceptsQwen3;

  const _OtherTtsAdapter({this.acceptsQwen3 = false});

  @override
  String get name => 'Other-TTS';

  @override
  Set<String> get supportedLanguages => const <String>{'xx'};

  @override
  bool supportsModel(BackendTextToSpeechModel? model) => acceptsQwen3;

  @override
  String normalizeLanguage(String language) {
    if (language.toLowerCase() != 'other') {
      throw LlamaTextToSpeechException('Unsupported language $language.');
    }
    return 'xx';
  }
}
