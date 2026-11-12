@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart'
    show
        BackendGenerationLimit,
        BackendGenerationLimitReporting,
        BackendModelFormatRouting,
        BackendMultimodalSupport;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('SpeechToTextEngine', () {
    late _SpeechBackend backend;
    late _SpeechLlamaEngine llamaEngine;
    late SpeechToTextEngine speechEngine;

    setUp(() async {
      backend = _SpeechBackend();
      llamaEngine = _SpeechLlamaEngine(backend);
      speechEngine = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );
    });

    tearDown(() => llamaEngine.dispose());

    test('reports the unloaded engine as unsupported', () async {
      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('Load a model'));
    });

    test(
      'reports a disposed attached LlamaEngine, not a missing model',
      () async {
        await _loadSpeechModel(llamaEngine);
        await llamaEngine.dispose();

        final capabilities = await speechEngine.capabilities;
        expect(capabilities.isSupported, isFalse);
        expect(
          capabilities.unsupportedReason,
          'The attached LlamaEngine is disposed. Create a new LlamaEngine and '
          'attach a new SpeechToTextEngine.',
        );
        await expectLater(
          speechEngine.transcribe(
            const SpeechToTextRequest(
              audio: SpeechAudioFileInput('/tmp/a.wav'),
            ),
          ),
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('The attached LlamaEngine is disposed.'),
            ),
          ),
        );
      },
    );

    test('reports exact first-backend capabilities', () async {
      await _loadSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.backendName, 'CPU');
      expect(
        capabilities.implementation,
        SpeechToTextImplementation.multimodalPromptAdapter,
      );
      expect(capabilities.inputKinds, {
        SpeechAudioInputKind.file,
        SpeechAudioInputKind.encodedBytes,
      });
      expect(capabilities.encodedAudioFormats, {'wav', 'mp3', 'flac'});
      expect(capabilities.supportsPartialResults, isFalse);
      expect(capabilities.supportsStreamingInput, isFalse);
      expect(capabilities.supportsTimestamps, isFalse);
      expect(capabilities.supportsSegmentTimestamps, isFalse);
      expect(capabilities.supportsWordTimestamps, isFalse);
      expect(capabilities.supportsConfidence, isFalse);
      expect(capabilities.supportsSpeakerDiarization, isFalse);
      expect(capabilities.supportsLanguageDetection, isFalse);
      expect(capabilities.supportsLanguageHints, isFalse);
      expect(capabilities.supportsCancellation, isTrue);
      expect(capabilities.supportsOutputBackpressure, isFalse);
      expect(capabilities.maxConcurrentTasks, 1);
    });

    test('reports a projector without audio support as unsupported', () async {
      backend.audioSupported = false;
      await _loadSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('does not report audio'));
    });

    test('reports a model without a projector as unsupported', () async {
      await llamaEngine.loadModel('model.gguf');

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'No multimodal projector is loaded. Load the model with its audio '
        'projector, as LlamaModel(source, projector: ...).',
      );
    });

    test('reports no projector after a projector load fails', () async {
      await _loadSpeechModel(llamaEngine);
      backend.projectorLoadError = LlamaModelException('rejected');

      await expectLater(
        llamaEngine.loadMultimodalProjector('other-mmproj.gguf'),
        throwsA(isA<LlamaModelException>()),
      );
      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        startsWith('No multimodal projector is loaded.'),
      );
    });

    test('rejects the dedicated LiteRT-LM profile on a LlamaEngine', () {
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => SpeechToTextEngine(
          llamaEngine,
          // ignore: deprecated_member_use_from_same_package
          modelProfile: SpeechToTextModelProfile.liteRtLmDedicated,
        ),
        throwsA(
          isA<ArgumentError>()
              .having((error) => error.name, 'name', 'modelProfile')
              .having(
                (error) => error.message,
                'message',
                'Use SpeechToTextEngine.liteRtLm for dedicated LiteRT-LM ASR.',
              ),
        ),
      );
    });

    test('a recognizer disposed during preflight starts no task', () async {
      backend.blockAudioProbe = true;
      await _loadSpeechModel(llamaEngine);

      final pending = speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      await backend.audioProbeStarted.future;
      await speechEngine.dispose();
      backend.releaseAudioProbe();

      await expectLater(pending, throwsA(isA<LlamaStateException>()));
      expect(backend.generationStarted.isCompleted, isFalse);
    });

    test('a LlamaEngine disposed during preflight starts no task', () async {
      backend.blockAudioProbe = true;
      await _loadSpeechModel(llamaEngine);

      final pending = speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      await backend.audioProbeStarted.future;
      final disposal = llamaEngine.dispose();
      backend.releaseAudioProbe();

      await expectLater(
        pending,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('The attached LlamaEngine is disposed.'),
          ),
        ),
      );
      await disposal;
      expect(backend.generationStarted.isCompleted, isFalse);
    });

    test(
      'a disposed recognizer rejects a request before validating it',
      () async {
        await _loadSpeechModel(llamaEngine);
        await speechEngine.dispose();

        await expectLater(
          speechEngine.transcribe(
            SpeechToTextRequest(audio: SpeechAudioPcmInput(Float32List(16000))),
          ),
          throwsA(isA<LlamaStateException>()),
        );
      },
    );

    test('rejects PCM input before starting a prompt-adapter task', () async {
      await _loadSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.transcribe(
          SpeechToTextRequest(audio: SpeechAudioPcmInput(Float32List(16000))),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The Qwen3-ASR prompt adapter accepts encoded audio only.',
          ),
        ),
      );
      expect(backend.generationStarted.isCompleted, isFalse);

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      expect((await task.done).state, SpeechToTextCompletionState.completed);
    });

    test('rejects streaming on the prompt adapter', () async {
      await _loadSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.startStream(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The Qwen3-ASR prompt adapter accepts complete encoded audio only.',
          ),
        ),
      );
      expect(backend.audioProbeStarted.isCompleted, isFalse);
    });

    test('turns an audio probe failure into capability diagnostics', () async {
      backend.audioProbeError = StateError('old native symbols');
      await _loadSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('probe failed'));
      expect(capabilities.unsupportedReason, contains('old native symbols'));
    });

    test('reports audio as LlamaEngine.capabilities does when the runtime '
        'cannot probe it', () async {
      backend.audioProbeError = LlamaUnsupportedException('no mtmd audio');
      await _loadSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect((await llamaEngine.capabilities).supportsAudio, isFalse);
      expect(await llamaEngine.supportsAudio, isFalse);
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The loaded multimodal projector does not report audio support.',
      );
    });

    test(
      'normalizes Qwen3-ASR language prefix and emits one final event',
      () async {
        backend.generationChunks = const <String>[
          'language English<asr_text>Local speech ',
          'recognition works.',
        ];
        await _loadSpeechModel(llamaEngine);

        final task = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
            contextPrompt: 'llamadart',
            maxOutputTokens: 64,
          ),
        );
        final events = await task.events.toList();
        final completion = await task.done;

        expect(events, hasLength(1));
        final finalEvent = events.single as SpeechToTextFinalEvent;
        expect(finalEvent.result.text, 'Local speech recognition works.');
        expect(finalEvent.result.language, isNull);
        expect(finalEvent.result.segments.single.text, finalEvent.result.text);
        expect(completion.state, SpeechToTextCompletionState.completed);
        expect(completion.result, same(finalEvent.result));
        expect(await task.result, same(finalEvent.result));
        expect(backend.lastParts, hasLength(2));
        expect(backend.lastParts!.first, isA<LlamaTextContent>());
        expect(
          (backend.lastParts!.first as LlamaTextContent).text,
          'Transcribe this audio accurately. Context: llamadart',
        );
        expect(backend.lastParts![1], isA<LlamaAudioContent>());
        expect(
          (backend.lastParts![1] as LlamaAudioContent).path,
          '/tmp/test.wav',
        );
        expect(backend.lastGenerationPrompt, contains('Context: llamadart'));
        expect(backend.lastGenerationParams?.temp, 0);
        expect(backend.lastGenerationParams?.topK, 1);
        expect(backend.lastGenerationParams?.topP, 1);
        expect(backend.lastGenerationParams?.penalty, 1);
        expect(backend.lastGenerationParams?.seed, 1);
        expect(backend.lastGenerationParams?.maxTokens, 64);
        expect(backend.lastGenerationParams?.streamBatchTokenThreshold, 1);
      },
    );

    test(
      'renders the native audio turn with the model chat template',
      () async {
        await _loadSpeechModel(llamaEngine);

        final task = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
          ),
        );
        await task.done;

        expect(backend.lastGenerationPrompt, startsWith('user: '));
        expect(backend.lastGenerationPrompt, endsWith('assistant: '));
        expect(
          backend.lastGenerationPrompt,
          isNot('Transcribe this audio accurately.'),
        );
      },
    );

    test('accepts encoded bytes and strips a bare transcript marker', () async {
      backend.generationText = ' <asr_text> Byte-backed transcript. ';
      await _loadSpeechModel(llamaEngine);

      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final task = await speechEngine.transcribe(
        SpeechToTextRequest(audio: SpeechAudioBytesInput(bytes)),
      );
      final result = (await task.done).result!;

      expect(result.text, 'Byte-backed transcript.');
      expect(result.language, isNull);
      final audio = backend.lastParts![1] as LlamaAudioContent;
      expect(audio.bytes, same(bytes));
      expect(audio.path, isNull);
      expect(
        backend.lastGenerationPrompt,
        'user: Transcribe this audio accurately.<__media__>assistant: ',
      );
    });

    test('reports an empty transcript as a typed failure', () async {
      backend.generationText = ' <asr_text> ';
      await _loadSpeechModel(llamaEngine);

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      expect(await task.events.toList(), isEmpty);
      final completion = await task.done;

      expect(completion.state, SpeechToTextCompletionState.failed);
      expect(completion.result, isNull);
      expect(
        completion.error,
        isA<LlamaSpeechException>().having(
          (error) => error.message,
          'message',
          contains('empty transcript'),
        ),
      );
      await expectLater(task.result, throwsA(same(completion.error)));

      backend.generationText = 'Recovered transcript.';
      final retry = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      expect((await retry.done).result?.text, 'Recovered transcript.');
    });

    test('rejects unsupported encoded file formats before inference', () async {
      await _loadSpeechModel(llamaEngine);

      expect(
        () => speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/recording.m4a'),
          ),
        ),
        throwsA(
          isA<LlamaAudioFormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('WAV, MP3, or FLAC'),
              )
              .having((error) => error.details, 'details', 'm4a'),
        ),
      );
    });

    test('reports an unsupported explicit encoding', () async {
      await _loadSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput(
              '/tmp/content-addressed-audio',
              format: SpeechAudioFormat(encoding: 'AAC'),
            ),
          ),
        ),
        throwsA(
          isA<LlamaAudioFormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('WAV, MP3, or FLAC'),
              )
              .having((error) => error.details, 'details', 'aac'),
        ),
      );

      await expectLater(
        speechEngine.transcribe(
          SpeechToTextRequest(
            audio: SpeechAudioBytesInput(
              Uint8List.fromList(<int>[1, 2, 3]),
              format: const SpeechAudioFormat(encoding: 'AAC'),
            ),
          ),
        ),
        throwsA(
          isA<LlamaAudioFormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('WAV, MP3, or FLAC'),
              )
              .having((error) => error.details, 'details', 'aac'),
        ),
      );
    });

    test('accepts an extensionless file with an explicit encoding', () async {
      await _loadSpeechModel(llamaEngine);
      backend.generationText = 'Transcript.';

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput(
            '/tmp/content-addressed-audio',
            format: SpeechAudioFormat(encoding: 'wav'),
          ),
        ),
      );

      expect((await task.done).result?.text, 'Transcript.');
      final audio = backend.lastParts![1] as LlamaAudioContent;
      expect(audio.path, '/tmp/content-addressed-audio');
    });

    test('validates empty inputs and token limits synchronously', () async {
      await _loadSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(audio: SpeechAudioFileInput('')),
        ),
        throwsA(isA<LlamaAudioFormatException>()),
      );
      await expectLater(
        speechEngine.transcribe(
          SpeechToTextRequest(audio: SpeechAudioBytesInput(Uint8List(0))),
        ),
        throwsA(isA<LlamaAudioFormatException>()),
      );
      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
            maxOutputTokens: 0,
          ),
        ),
        throwsA(isA<LlamaSpeechException>()),
      );
      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
            languageHint: 'en',
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects current LiteRT-LM runtimes explicitly', () async {
      backend.backendName = 'LiteRT-LM CPU';
      await _loadSpeechModel(llamaEngine);

      final capabilities = await speechEngine.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('not a dedicated ASR'));
      expect(
        () => speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('cancels an active recognition task idempotently', () async {
      backend.blockGeneration = true;
      await _loadSpeechModel(llamaEngine);

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.generationStarted.future;
      task.cancel();
      task.cancel();
      backend.releaseGeneration();

      expect(await task.events.toList(), isEmpty);
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      await expectLater(
        task.result,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Speech recognition was cancelled.',
          ),
        ),
      );
      expect(backend.cancelGenerationCalls, 0);
    });

    test('cancel stops only its own task, and a chat on the same engine '
        'keeps running', () async {
      await _loadSpeechModel(llamaEngine);
      final transcription = StreamController<List<int>>();
      final chat = StreamController<List<int>>();
      addTearDown(() {
        unawaited(transcription.close());
        unawaited(chat.close());
      });
      final chatStarted = Completer<void>();
      backend
        ..generationFor = (prompt) {
          if (!prompt.contains('Hello chat')) {
            return transcription.stream;
          }
          chatStarted.complete();
          return chat.stream;
        }
        // Like llama.cpp, a backend-wide cancel also ends the queued chat.
        ..onCancelGeneration = () => unawaited(chat.close());

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.generationStarted.future;
      final reply = ChatSession(llamaEngine).send('Hello chat');
      await chatStarted.future;

      task.cancel();
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      expect(transcription.hasListener, isFalse);
      expect(chat.isClosed, isFalse);

      chat.add(utf8.encode('still running'));
      await chat.close();
      expect((await reply).text, 'still running');
      expect(backend.cancelGenerationCalls, 0);
    });

    test('frees the engine lease before the task reports done', () async {
      backend.blockGeneration = true;
      await _loadSpeechModel(llamaEngine);

      final cancelled = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.generationStarted.future;
      cancelled.cancel();
      backend.releaseGeneration();
      expect(
        (await cancelled.done).state,
        SpeechToTextCompletionState.cancelled,
      );

      backend.blockGeneration = false;
      final next = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      expect((await next.done).state, SpeechToTextCompletionState.completed);
    });

    test('cancels while the native chat template is being prepared', () async {
      await _loadSpeechModel(llamaEngine);
      backend.blockMetadata = true;

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.metadataStarted.future;

      task.cancel();
      backend.releaseMetadata();

      expect(await task.events.toList(), isEmpty);
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      expect(backend.generationStarted.isCompleted, isFalse);
      expect(backend.cancelGenerationCalls, 0);

      final retry = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      expect((await retry.done).result?.text, 'transcript');
    });

    for (final call in <String>['unloadModel', 'dispose']) {
      test('$call cancels an active transcription', () async {
        await _loadSpeechModel(llamaEngine);
        final partialSent = Completer<void>();
        final backendCancelled = Completer<void>();
        // llama.cpp ends a cancelled generation as a normal end of stream.
        Stream<List<int>> endsAtCancel() async* {
          yield utf8.encode('language English<asr_text>And so, my fellow');
          partialSent.complete();
          await backendCancelled.future;
        }

        backend
          ..generationStream = endsAtCancel()
          ..onCancelGeneration = () {
            if (!backendCancelled.isCompleted) {
              backendCancelled.complete();
            }
          };
        final task = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
          ),
        );
        final events = task.events.toList();
        await partialSent.future;

        await (call == 'unloadModel'
            ? llamaEngine.unloadModel()
            : llamaEngine.dispose());

        final completion = await task.done;
        expect(completion.state, SpeechToTextCompletionState.cancelled);
        expect(completion.result, isNull);
        expect(await events, isEmpty);
        expect(task.isCancellationRequested, isTrue);
        await expectLater(task.result, throwsA(isA<LlamaStateException>()));

        backend
          ..generationStream = null
          ..onCancelGeneration = null;
        if (call == 'dispose') {
          await expectLater(
            speechEngine.transcribe(
              const SpeechToTextRequest(
                audio: SpeechAudioFileInput('/tmp/retry.wav'),
              ),
            ),
            throwsA(isA<LlamaStateException>()),
          );
          return;
        }
        await _loadSpeechModel(llamaEngine);
        final retry = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/retry.wav'),
          ),
        );
        expect((await retry.done).result?.text, 'transcript');
      });
    }

    test('unloadModel before the backend call cancels the task', () async {
      await _loadSpeechModel(llamaEngine);
      backend.blockMetadata = true;
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      final events = task.events.toList();
      await backend.metadataStarted.future;

      await llamaEngine.unloadModel();
      backend.releaseMetadata();

      expect(await events, isEmpty);
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      expect(backend.generationStarted.isCompleted, isFalse);

      await _loadSpeechModel(llamaEngine);
      final retry = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/retry.wav'),
        ),
      );
      expect((await retry.done).result?.text, 'transcript');
    });

    test('awaits stream cleanup before releasing the backend lease', () async {
      await _loadSpeechModel(llamaEngine);
      final cleanupStarted = Completer<void>();
      final cleanupRelease = Completer<void>();
      final generation = StreamController<List<int>>(
        onCancel: () {
          cleanupStarted.complete();
          return cleanupRelease.future;
        },
      );
      addTearDown(() => unawaited(generation.close()));
      backend.generationStream = generation.stream;

      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.generationStarted.future;

      task.cancel();
      await cleanupStarted.future;

      var taskCompleted = false;
      unawaited(task.done.whenComplete(() => taskCompleted = true));
      await Future<void>.delayed(Duration.zero);
      expect(taskCompleted, isFalse);
      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/retry.wav'),
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );

      cleanupRelease.complete();
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);

      backend.generationStream = null;
      final retry = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/retry.wav'),
        ),
      );
      expect((await retry.done).result?.text, 'transcript');
    });

    test('allows only one active task per wrapper', () async {
      backend.blockGeneration = true;
      await _loadSpeechModel(llamaEngine);
      final first = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/first.wav'),
        ),
      );
      await backend.generationStarted.future;

      expect(
        () => speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/second.wav'),
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );

      first.cancel();
      backend.releaseGeneration();
      await first.done;
    });

    test(
      'reserves the engine before asynchronous capability discovery',
      () async {
        backend.blockAudioProbe = true;
        await _loadSpeechModel(llamaEngine);

        final firstFuture = speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/first.wav'),
          ),
        );
        await backend.audioProbeStarted.future;

        await expectLater(
          speechEngine.transcribe(
            const SpeechToTextRequest(
              audio: SpeechAudioFileInput('/tmp/second.wav'),
            ),
          ),
          throwsA(isA<LlamaStateException>()),
        );

        backend.releaseAudioProbe();
        final first = await firstFuture;
        await first.done;
      },
    );

    test('shares the task reservation across wrappers', () async {
      backend.blockGeneration = true;
      await _loadSpeechModel(llamaEngine);
      final otherWrapper = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );
      final first = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/first.wav'),
        ),
      );
      await backend.generationStarted.future;

      await expectLater(
        otherWrapper.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/second.wav'),
          ),
        ),
        throwsA(isA<LlamaStateException>()),
      );

      first.cancel();
      backend.releaseGeneration();
      await first.done;
    });

    test('releases the task reservation after preflight failure', () async {
      backend.audioSupported = false;
      await _loadSpeechModel(llamaEngine);

      await expectLater(
        speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/first.wav'),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );

      backend.audioSupported = true;
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/second.wav'),
        ),
      );
      expect((await task.done).state, SpeechToTextCompletionState.completed);
    });

    for (final (limit, expected)
        in <(BackendGenerationLimit, LlamaSpeechTranscriptLimit)>[
          (
            BackendGenerationLimit.contextSize,
            LlamaSpeechTranscriptLimit.contextSize,
          ),
          (
            BackendGenerationLimit.maxTokens,
            LlamaSpeechTranscriptLimit.maxOutputTokens,
          ),
          (BackendGenerationLimit.runtime, LlamaSpeechTranscriptLimit.runtime),
        ]) {
      test('fails a transcript truncated at $limit', () async {
        backend
          ..generationText = 'language English<asr_text>And so my'
          ..generationLimit = limit;
        await _loadSpeechModel(llamaEngine);
        final task = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/long.wav'),
          ),
        );
        final events = task.events.toList();

        final completion = await task.done;

        expect(completion.state, SpeechToTextCompletionState.failed);
        expect(completion.result, isNull);
        expect(await events, isEmpty);
        final error = completion.error;
        expect(error, isA<LlamaSpeechTranscriptTruncatedException>());
        error as LlamaSpeechTranscriptTruncatedException;
        expect(error.limit, expected);
        expect(error.partialTranscript, 'And so my');
        expect(
          error.message,
          contains(switch (expected) {
            LlamaSpeechTranscriptLimit.contextSize => 'contextSize',
            LlamaSpeechTranscriptLimit.maxOutputTokens => 'maxOutputTokens',
            LlamaSpeechTranscriptLimit.runtime => 'runtime generation limit',
          }),
        );
        await expectLater(task.result, throwsA(same(error)));
      });
    }

    test('fails an empty transcript truncated at a limit', () async {
      backend
        ..generationText = ' <asr_text> '
        ..generationLimit = BackendGenerationLimit.contextSize;
      await _loadSpeechModel(llamaEngine);
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/long.wav')),
      );
      task.events.listen((_) {}, onError: (_) {});

      final completion = await task.done;

      expect(
        completion.error,
        isA<LlamaSpeechTranscriptTruncatedException>()
            .having((error) => error.partialTranscript, 'partial', isEmpty)
            .having(
              (error) => error.limit,
              'limit',
              LlamaSpeechTranscriptLimit.contextSize,
            ),
      );
    });

    test('preserves typed backend failures', () async {
      backend.generationError = LlamaUnsupportedException('missing symbol');
      await _loadSpeechModel(llamaEngine);
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );

      task.events.listen((_) {}, onError: (_) {});
      final completion = await task.done;

      expect(completion.error, isA<LlamaUnsupportedException>());
    });

    test(
      'preserves the generation failure when stream cleanup also fails',
      () async {
        await _loadSpeechModel(llamaEngine);
        late final StreamController<LlamaCompletionChunk> generation;
        generation = StreamController<LlamaCompletionChunk>(
          onListen: () {
            scheduleMicrotask(() {
              generation.addError(
                LlamaUnsupportedException('first generation failure'),
              );
            });
          },
          onCancel: () => Future<void>.error(
            StateError('secondary stream cleanup failure'),
          ),
        );
        llamaEngine.chatCompletionStream = generation.stream;

        final task = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/test.wav'),
          ),
        );
        expect(await task.events.toList(), isEmpty);
        final completion = await task.done;

        expect(
          completion.error,
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'first generation failure',
          ),
        );

        llamaEngine.chatCompletionStream = null;
        final retry = await speechEngine.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/retry.wav'),
          ),
        );
        expect((await retry.done).result?.text, 'transcript');
      },
    );

    test('cancellation wins over a simultaneous backend failure', () async {
      backend
        ..blockGeneration = true
        ..generationError = StateError('late decoder error');
      await _loadSpeechModel(llamaEngine);
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );
      await backend.generationStarted.future;

      task.cancel();
      backend.releaseGeneration();

      expect(await task.events.toList(), isEmpty);
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
    });

    test('reports a failure through done and result, not events', () async {
      backend.generationError = StateError('decoder failed');
      await _loadSpeechModel(llamaEngine);
      final task = await speechEngine.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/test.wav')),
      );

      expect(await task.events.toList(), isEmpty);
      final completion = await task.done;

      expect(completion.state, SpeechToTextCompletionState.failed);
      expect(completion.error, isA<LlamaInferenceException>());
      await expectLater(task.result, throwsA(same(completion.error)));
    });
  });

  group('SpeechToTextEngine.load and attach', () {
    late _SpeechBackend backend;
    late Directory directory;
    late String modelPath;
    late String projectorPath;

    setUp(() async {
      backend = _SpeechBackend();
      directory = await Directory.systemTemp.createTemp('llamadart_stt_');
      modelPath = p.join(directory.path, 'asr.gguf');
      projectorPath = p.join(directory.path, 'mmproj-asr.gguf');
      await File(modelPath).writeAsBytes(<int>[1, 2, 3]);
      await File(projectorPath).writeAsBytes(<int>[4, 5]);
    });

    tearDown(() => directory.delete(recursive: true));

    SpeechToTextModel model({
      SpeechToTextPromptAdapter adapter = const Qwen3AsrAdapter(),
      bool withProjector = true,
    }) => SpeechToTextModel(
      ModelSource.path(modelPath),
      projector: withProjector ? ModelSource.path(projectorPath) : null,
      adapter: adapter,
    );

    test('a model cache directory that cannot be created fails the load '
        'with LlamaModelException', () async {
      final blocker = File(p.join(directory.path, 'not-a-directory'))
        ..writeAsStringSync('');
      ModelSource remote(String name) =>
          ModelSource.url(Uri.parse('http://127.0.0.1:9/models/$name'));

      await expectLater(
        SpeechToTextEngine.load(
          SpeechToTextModel(
            remote('asr.gguf'),
            projector: remote('mmproj-asr.gguf'),
            adapter: const Qwen3AsrAdapter(),
          ),
          download: ModelLoadOptions(
            cacheDirectory: p.join(blocker.path, 'cache'),
            maxRetries: 0,
          ),
          store: ModelFileStore(
            downloadManager: DefaultModelDownloadManager.appPrivate(
              cacheDirectory: p.join(directory.path, 'cache'),
            ),
          ),
          backend: backend,
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Cannot create the model cache directory'),
          ),
        ),
      );
      expect(backend.lastProjectorPath, isNull);
    });

    test('owns the engine it loads and frees it on dispose', () async {
      final recognizer = await SpeechToTextEngine.load(
        model(),
        params: const ModelParams(contextSize: 2048),
        backend: backend,
      );

      expect(recognizer.adapter, isA<Qwen3AsrAdapter>());
      expect(backend.lastModelParams?.contextSize, 2048);
      expect(backend.lastProjectorPath, projectorPath);
      final capabilities = await recognizer.capabilities;
      expect(capabilities, isA<EngineCapabilities>());
      expect(capabilities.isSupported, isTrue);
      final result = await recognizer.transcribeOnce(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      expect(result.text, 'transcript');

      await Future.wait<void>(<Future<void>>[
        recognizer.dispose(),
        recognizer.dispose(),
      ]);
      await recognizer.dispose();

      expect(recognizer.isDisposed, isTrue);
      expect(backend.disposeCalls, 1);
      final disposed = await recognizer.capabilities;
      expect(disposed.isSupported, isFalse);
      expect(disposed.unsupportedReason, 'The SpeechToTextEngine is disposed.');
      await expectLater(
        recognizer.transcribe(
          const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('passes the declared model format to the backend', () async {
      final routing = _FormatRoutingSpeechBackend();
      final recognizer = await SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.path(modelPath, format: ModelFormat.gguf),
          projector: ModelSource.path(projectorPath),
          adapter: const Qwen3AsrAdapter(),
        ),
        backend: routing,
      );

      expect(routing.loadedFormats, [ModelFormat.gguf]);
      await recognizer.dispose();
    });

    test('dispose cancels a running task before freeing the engine', () async {
      backend.blockGeneration = true;
      final recognizer = await SpeechToTextEngine.load(
        model(),
        backend: backend,
      );
      final task = await recognizer.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      await backend.generationStarted.future;

      final disposal = recognizer.dispose();
      backend.releaseGeneration();
      await disposal;

      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      expect(backend.cancelGenerationCalls, greaterThanOrEqualTo(1));
      expect(backend.disposeCalls, 1);
    });

    test('transcribeOnce reports a cancelled task as a state error', () async {
      backend.blockGeneration = true;
      final recognizer = await SpeechToTextEngine.load(
        model(),
        backend: backend,
      );
      final result = recognizer.transcribeOnce(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      await backend.generationStarted.future;

      final disposal = recognizer.dispose();
      backend.releaseGeneration();

      await expectLater(result, throwsA(isA<LlamaStateException>()));
      await disposal;
    });

    test('transcribeOnce throws the task failure', () async {
      backend.generationText = '   ';
      final recognizer = await SpeechToTextEngine.load(
        model(),
        backend: backend,
      );

      await expectLater(
        recognizer.transcribeOnce(
          const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
        ),
        throwsA(isA<LlamaSpeechException>()),
      );
      await recognizer.dispose();
    });

    test(
      'a model that cannot recognize speech leaves nothing loaded',
      () async {
        backend.audioSupported = false;

        await expectLater(
          SpeechToTextEngine.load(model(), backend: backend),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              'The loaded multimodal projector does not report audio support.',
            ),
          ),
        );
        expect(backend.disposeCalls, 1);
        expect(backend.isReady, isFalse);
      },
    );

    test('a model without its projector leaves nothing loaded', () async {
      await expectLater(
        SpeechToTextEngine.load(model(withProjector: false), backend: backend),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            startsWith('No multimodal projector is loaded.'),
          ),
        ),
      );
      expect(backend.disposeCalls, 1);
    });

    test('a projector load failure leaves nothing loaded', () async {
      backend.projectorLoadError = LlamaModelException('rejected');

      await expectLater(
        SpeechToTextEngine.load(model(), backend: backend),
        throwsA(isA<LlamaModelException>()),
      );
      expect(backend.disposeCalls, 1);
      expect(backend.isReady, isFalse);
    });

    test('a missing model file fails before the backend loads', () async {
      await File(modelPath).delete();

      await expectLater(
        SpeechToTextEngine.load(model(), backend: backend),
        throwsA(isA<LlamaException>()),
      );
      expect(backend.lastModelParams, isNull);
      expect(backend.disposeCalls, 1);
    });

    test('a cancelled load leaves nothing loaded', () async {
      final token = ModelDownloadCancelToken()..cancel();

      await expectLater(
        SpeechToTextEngine.load(
          model(),
          download: ModelLoadOptions(cancelToken: token),
          backend: backend,
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.disposeCalls, 1);
    });

    test('rejects a tokenizer and a two-file checksum up front', () async {
      await expectLater(
        SpeechToTextEngine.load(
          SpeechToTextModel(
            ModelSource.path(modelPath),
            projector: ModelSource.path(projectorPath),
            tokenizer: ModelSource.path(projectorPath),
            adapter: const Qwen3AsrAdapter(),
          ),
          backend: backend,
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'model.tokenizer',
          ),
        ),
      );
      expect(backend.disposeCalls, 1);
      await expectLater(
        SpeechToTextEngine.load(
          model(),
          download: ModelLoadOptions(sha256: 'a' * 64),
          backend: backend,
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            startsWith('SpeechToTextEngine model loading uses 2 files'),
          ),
        ),
      );
      expect(backend.lastModelParams, isNull);
      expect(backend.disposeCalls, 2);
    });

    test('attach borrows the engine and dispose leaves it loaded', () async {
      backend.blockGeneration = true;
      final llamaEngine = LlamaEngine(backend);
      await _loadSpeechModel(llamaEngine);
      final recognizer = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );
      final task = await recognizer.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      await backend.generationStarted.future;
      var taskDone = false;
      unawaited(task.done.then((_) => taskDone = true));

      final disposal = recognizer.dispose();
      backend.releaseGeneration();
      await disposal;

      expect(taskDone, isTrue);
      expect((await task.done).state, SpeechToTextCompletionState.cancelled);
      expect(llamaEngine.isReady, isTrue);
      expect(backend.disposeCalls, 0);
      final other = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );
      backend.blockGeneration = false;
      final next = await other.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      expect((await next.done).state, SpeechToTextCompletionState.completed);
      await llamaEngine.dispose();
    });

    test('runs a custom prompt adapter', () async {
      backend.generationText = '[fr] Bonjour.';
      final recognizer = await SpeechToTextEngine.load(
        model(adapter: const _BracketLanguageAdapter()),
        backend: backend,
      );

      final capabilities = await recognizer.capabilities;
      expect(capabilities.supportsLanguageHints, isTrue);
      expect(capabilities.supportsLanguageDetection, isTrue);
      final result = await recognizer.transcribeOnce(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/a.wav'),
          languageHint: 'fr',
        ),
      );

      expect(result.text, 'Bonjour.');
      expect(result.language, 'fr');
      expect(
        backend.lastGenerationPrompt,
        contains('Write down the fr audio.'),
      );
      await expectLater(
        recognizer.transcribe(
          const SpeechToTextRequest(
            audio: SpeechAudioFileInput('/tmp/a.wav'),
            contextPrompt: 'names',
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The Bracket-ASR prompt adapter does not take a context prompt.',
          ),
        ),
      );
      await expectLater(
        recognizer.transcribe(
          SpeechToTextRequest(audio: SpeechAudioPcmInput(Float32List(16))),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The Bracket-ASR prompt adapter accepts encoded audio only.',
          ),
        ),
      );
      expect(
        // ignore: deprecated_member_use_from_same_package
        () => recognizer.modelProfile,
        throwsA(isA<LlamaStateException>()),
      );
      await recognizer.dispose();
    });

    test('the deprecated constructor attaches Qwen3-ASR', () async {
      final llamaEngine = LlamaEngine(backend);
      await _loadSpeechModel(llamaEngine);
      // ignore: deprecated_member_use_from_same_package
      final recognizer = SpeechToTextEngine(
        llamaEngine,
        // ignore: deprecated_member_use_from_same_package
        modelProfile: SpeechToTextModelProfile.qwen3Asr,
      );

      expect(recognizer.adapter, isA<Qwen3AsrAdapter>());
      expect(
        // ignore: deprecated_member_use_from_same_package
        recognizer.modelProfile,
        // ignore: deprecated_member_use_from_same_package
        SpeechToTextModelProfile.qwen3Asr,
      );
      await recognizer.dispose();
      expect(llamaEngine.isReady, isTrue);
      await llamaEngine.dispose();
    });
  });

  group('Qwen3-ASR projector type', () {
    late _SpeechBackend backend;
    late LlamaEngine llamaEngine;
    late SpeechToTextEngine recognizer;
    late Directory directory;

    setUp(() async {
      backend = _SpeechBackend();
      llamaEngine = LlamaEngine(backend);
      recognizer = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const Qwen3AsrAdapter(),
      );
      directory = await Directory.systemTemp.createTemp('llamadart_stt_proj_');
    });

    tearDown(() async {
      await llamaEngine.dispose();
      await directory.delete(recursive: true);
    });

    Future<void> loadWithProjector(Map<String, Object> metadata) async {
      final path = p.join(directory.path, 'mmproj.gguf');
      await File(path).writeAsBytes(_ggufHeader(metadata));
      await llamaEngine.loadModel('model.gguf');
      await llamaEngine.loadMultimodalProjector(path);
    }

    Future<LlamaSpeechException> emptyTranscriptError() async {
      backend.generationText = ' <asr_text> ';
      final task = await recognizer.transcribe(
        const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
      );
      return (await task.done).error! as LlamaSpeechException;
    }

    test('a qwen3a audio projector is supported', () async {
      await loadWithProjector({
        'general.architecture': 'clip',
        'clip.has_audio_encoder': true,
        'clip.audio.projector_type': 'qwen3a',
      });

      expect((await recognizer.capabilities).isSupported, isTrue);
      final error = await emptyTranscriptError();
      expect(error.message, 'Speech recognition produced an empty transcript.');
      expect(error.details, isNull);
    });

    test('a Qwen3-TTS speaker-encoder projector is unsupported', () async {
      await loadWithProjector({
        'general.architecture': 'clip',
        'clip.has_audio_encoder': true,
        'clip.audio.projector_type': 'qwen3tts_spkenc',
        'clip.has_gen_audio_encoder': true,
      });

      final capabilities = await recognizer.capabilities;
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        "The loaded audio projector's type is 'qwen3tts_spkenc', not "
        "Qwen3-ASR's 'qwen3a'. Load a Qwen3-ASR model with its own projector.",
      );
      await expectLater(
        recognizer.transcribe(
          const SpeechToTextRequest(audio: SpeechAudioFileInput('/tmp/a.wav')),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            capabilities.unsupportedReason,
          ),
        ),
      );
    });

    test('clip.projector_type takes precedence, as in llama.cpp', () async {
      await loadWithProjector({
        'general.architecture': 'clip',
        'clip.projector_type': 'qwen3tts_spkenc',
        'clip.audio.projector_type': 'qwen3a',
      });

      expect((await recognizer.capabilities).isSupported, isFalse);
    });

    test('clip.projector_type takes precedence when it comes last', () async {
      await loadWithProjector({
        'general.architecture': 'clip',
        'clip.audio.projector_type': 'qwen3tts_spkenc',
        'clip.projector_type': 'qwen3a',
      });

      expect((await recognizer.capabilities).isSupported, isTrue);
    });

    test('a projector without a projector type stays supported and the '
        'empty-transcript error names a possible mismatch', () async {
      await loadWithProjector({
        'general.architecture': 'clip',
        'clip.has_audio_encoder': true,
      });

      expect((await recognizer.capabilities).isSupported, isTrue);
      final error = await emptyTranscriptError();
      expect(error.message, 'Speech recognition produced an empty transcript.');
      expect(
        error.details,
        'The audio may be silent, or the loaded model may not be a Qwen3-ASR '
        'model: its projector type could not be checked.',
      );
    });

    test('an unreadable projector file stays supported', () async {
      await llamaEngine.loadModel('model.gguf');
      await llamaEngine.loadMultimodalProjector(
        p.join(directory.path, 'missing-mmproj.gguf'),
      );

      expect((await recognizer.capabilities).isSupported, isTrue);
    });

    test('checks the projector loaded now, not an earlier one', () async {
      await loadWithProjector({'clip.audio.projector_type': 'qwen3a'});
      expect((await recognizer.capabilities).isSupported, isTrue);

      final ttsPath = p.join(directory.path, 'mmproj-tts.gguf');
      await File(ttsPath).writeAsBytes(
        _ggufHeader({'clip.audio.projector_type': 'qwen3tts_spkenc'}),
      );
      await llamaEngine.loadMultimodalProjector(ttsPath);
      expect((await recognizer.capabilities).isSupported, isFalse);
    });

    test('reads the header without waiting on the event loop', () async {
      await loadWithProjector({'clip.audio.projector_type': 'qwen3tts_spkenc'});

      SpeechToTextCapabilities? capabilities;
      unawaited(recognizer.capabilities.then((value) => capabilities = value));
      await Future<void>.delayed(Duration.zero);

      expect(capabilities?.isSupported, isFalse);
    });

    test('a projector type past the 1 MiB metadata cap is unknown', () async {
      await loadWithProjector({
        'padding': Uint8List(1 << 20),
        'clip.audio.projector_type': 'qwen3tts_spkenc',
      });

      expect((await recognizer.capabilities).isSupported, isTrue);
      final error = await emptyTranscriptError();
      expect(error.details, contains('could not be checked'));
    });

    test('reads the header once per loaded projector', () async {
      final path = p.join(directory.path, 'mmproj.gguf');
      await loadWithProjector({'clip.audio.projector_type': 'qwen3a'});
      expect((await recognizer.capabilities).isSupported, isTrue);

      await File(path).writeAsBytes(
        _ggufHeader({'clip.audio.projector_type': 'qwen3tts_spkenc'}),
      );
      expect((await recognizer.capabilities).isSupported, isTrue);

      await llamaEngine.loadMultimodalProjector(path);
      expect((await recognizer.capabilities).isSupported, isFalse);
    });

    test(
      'load refuses a Qwen3-TTS projector and disposes the engine',
      () async {
        final modelPath = p.join(directory.path, 'tts.gguf');
        final projectorPath = p.join(directory.path, 'mmproj-tts.gguf');
        await File(modelPath).writeAsBytes(<int>[1, 2, 3]);
        await File(projectorPath).writeAsBytes(
          _ggufHeader({'clip.audio.projector_type': 'qwen3tts_spkenc'}),
        );

        await expectLater(
          SpeechToTextEngine.load(
            SpeechToTextModel(
              ModelSource.path(modelPath),
              projector: ModelSource.path(projectorPath),
              adapter: const Qwen3AsrAdapter(),
            ),
            backend: backend,
          ),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              contains("'qwen3tts_spkenc'"),
            ),
          ),
        );
        expect(backend.disposeCalls, 1);
      },
    );

    test('other prompt adapters are not checked against qwen3a', () async {
      final custom = SpeechToTextEngine.attach(
        llamaEngine,
        adapter: const _BracketLanguageAdapter(),
      );
      await loadWithProjector({'clip.audio.projector_type': 'qwen3tts_spkenc'});

      expect((await custom.capabilities).isSupported, isTrue);
      backend.generationText = '[en] ';
      final task = await custom.transcribe(
        const SpeechToTextRequest(
          audio: SpeechAudioFileInput('/tmp/a.wav'),
          languageHint: 'en',
        ),
      );
      final error = (await task.done).error! as LlamaSpeechException;
      expect(
        error.details,
        'The audio may be silent, or the loaded model may not be a '
        'Bracket-ASR model: its projector type could not be checked.',
      );
    });
  });
}

/// A GGUF header with [metadata] (string, bool and `uint8` array values) and
/// no tensors.
Uint8List _ggufHeader(Map<String, Object> metadata) {
  final bytes = BytesBuilder();
  void u32(int value) => bytes.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u64(int value) => bytes.add(
    (ByteData(8)..setUint64(0, value, Endian.little)).buffer.asUint8List(),
  );
  void string(String value) {
    final encoded = utf8.encode(value);
    u64(encoded.length);
    bytes.add(encoded);
  }

  bytes.add(ascii.encode('GGUF'));
  u32(3);
  u64(0);
  u64(metadata.length);
  for (final MapEntry(:key, :value) in metadata.entries) {
    string(key);
    switch (value) {
      case final String text:
        u32(8);
        string(text);
      case final bool flag:
        u32(7);
        bytes.addByte(flag ? 1 : 0);
      case final Uint8List items:
        u32(9);
        u32(0);
        u64(items.length);
        bytes.add(items);
      default:
        throw ArgumentError.value(value, key);
    }
  }
  return bytes.takeBytes();
}

Future<void> _loadSpeechModel(LlamaEngine engine) async {
  await engine.loadModel('model.gguf');
  await engine.loadMultimodalProjector('mmproj.gguf');
}

class _SpeechBackend
    implements
        LlamaBackend,
        BackendMultimodalSupport,
        BackendGenerationLimitReporting {
  bool _ready = false;
  BackendGenerationLimit? generationLimit;
  final Expando<BackendGenerationLimit> _generationLimits =
      Expando<BackendGenerationLimit>();
  bool audioSupported = true;
  Object? audioProbeError;
  Object? projectorLoadError;
  String backendName = 'CPU';
  String generationText = 'transcript';
  List<String>? generationChunks;
  Object? generationError;
  Stream<List<int>>? generationStream;
  Stream<List<int>> Function(String prompt)? generationFor;
  void Function()? onCancelGeneration;
  bool blockGeneration = false;
  bool blockAudioProbe = false;
  bool blockMetadata = false;
  Completer<void> audioProbeStarted = Completer<void>();
  final Completer<void> _audioProbeRelease = Completer<void>();
  Completer<void> metadataStarted = Completer<void>();
  final Completer<void> _metadataRelease = Completer<void>();
  Completer<void> generationStarted = Completer<void>();
  final Completer<void> _generationRelease = Completer<void>();
  int cancelGenerationCalls = 0;
  int disposeCalls = 0;
  ModelParams? lastModelParams;
  String? lastProjectorPath;
  String? lastGenerationPrompt;
  GenerationParams? lastGenerationParams;
  List<LlamaContentPart>? lastParts;

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
  ) async {
    lastProjectorPath = mmProjPath;
    final error = projectorLoadError;
    if (error != null) {
      throw error;
    }
    return 3;
  }

  @override
  Future<bool> supportsAudio(int mmContextHandle) async {
    if (!audioProbeStarted.isCompleted) {
      audioProbeStarted.complete();
    }
    if (blockAudioProbe) {
      await _audioProbeRelease.future;
    }
    final error = audioProbeError;
    if (error != null) {
      throw error;
    }
    return audioSupported;
  }

  @override
  Future<String> getBackendName() async => backendName;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> getContextSize(int contextHandle) async => 4096;

  @override
  Future<bool> supportsVision(int mmContextHandle) async => false;

  @override
  Future<Map<String, String>> modelMetadata(int modelHandle) async {
    if (!metadataStarted.isCompleted) {
      metadataStarted.complete();
    }
    if (blockMetadata) {
      await _metadataRelease.future;
    }
    return const {
      'llm.context_length': '4096',
      'tokenizer.chat_template':
          '{% for message in messages %}{{ message["role"] + ": " + '
          'message["content"] }}{% endfor %}{% if add_generation_prompt %}'
          '{{ "assistant: " }}{% endif %}',
    };
  }

  @override
  Future<String> applyChatTemplate(
    int modelHandle,
    List<Map<String, dynamic>> messages, {
    String? customTemplate,
    bool addAssistant = true,
  }) async {
    return messages.map((message) => message['content']).join('\n');
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) {
    lastGenerationPrompt = prompt;
    lastGenerationParams = params;
    lastParts = parts;
    if (!generationStarted.isCompleted) {
      generationStarted.complete();
    }
    final stream =
        generationFor?.call(prompt) ??
        generationStream ??
        _defaultGenerationStream();
    final limit = generationLimit;
    if (limit != null) {
      _generationLimits[stream] = limit;
    }
    return stream;
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async => utf8.encode(text);

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) =>
      _generationLimits[generation];

  Stream<List<int>> _defaultGenerationStream() async* {
    if (blockGeneration) {
      await _generationRelease.future;
    }
    final error = generationError;
    if (error != null) {
      throw error;
    }
    final chunks = generationChunks ?? <String>[generationText];
    for (final chunk in chunks) {
      yield utf8.encode(chunk);
    }
  }

  void releaseAudioProbe() {
    if (!_audioProbeRelease.isCompleted) {
      _audioProbeRelease.complete();
    }
  }

  void releaseGeneration() {
    if (!_generationRelease.isCompleted) {
      _generationRelease.complete();
    }
  }

  void releaseMetadata() {
    if (!_metadataRelease.isCompleted) {
      _metadataRelease.complete();
    }
  }

  @override
  void cancelGeneration() {
    cancelGenerationCalls += 1;
    onCancelGeneration?.call();
  }

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> multimodalContextFree(int mmContextHandle) async {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _ready = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FormatRoutingSpeechBackend extends _SpeechBackend
    implements BackendModelFormatRouting {
  final List<ModelFormat> loadedFormats = <ModelFormat>[];

  @override
  Future<int> modelLoadAs(String path, ModelParams params, ModelFormat format) {
    loadedFormats.add(format);
    return modelLoad(path, params);
  }

  @override
  Future<int> modelLoadFromUrlAs(
    String url,
    ModelParams params,
    ModelFormat format, {
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError();
}

class _SpeechLlamaEngine extends LlamaEngine {
  Stream<LlamaCompletionChunk>? chatCompletionStream;

  _SpeechLlamaEngine(super.backend);

  @override
  Stream<LlamaCompletionChunk> create(
    List<LlamaChatMessage> messages, {
    GenerationParams? params,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    bool parallelToolCalls = false,
    bool enableThinking = true,
    Map<String, dynamic>? responseFormat,
    String? sourceLangCode,
    String? targetLangCode,
    Map<String, dynamic>? chatTemplateKwargs,
    DateTime? templateNow,
  }) {
    return chatCompletionStream ??
        super.create(
          messages,
          params: params,
          tools: tools,
          toolChoice: toolChoice,
          parallelToolCalls: parallelToolCalls,
          enableThinking: enableThinking,
          responseFormat: responseFormat,
          sourceLangCode: sourceLangCode,
          targetLangCode: targetLangCode,
          chatTemplateKwargs: chatTemplateKwargs,
          templateNow: templateNow,
        );
  }
}

class _BracketLanguageAdapter extends SpeechToTextPromptAdapter {
  const _BracketLanguageAdapter();

  @override
  String get name => 'Bracket-ASR';

  @override
  bool get supportsLanguageHints => true;

  @override
  bool get supportsContextPrompt => false;

  @override
  bool get supportsLanguageDetection => true;

  @override
  String promptFor(SpeechToTextRequest request) =>
      'Write down the ${request.languageHint} audio.';

  @override
  SpeechToTextTranscript parseTranscript(String output) {
    final match = RegExp(r'^\[(\w+)\]\s*(.*)$').firstMatch(output.trim());
    return match == null
        ? SpeechToTextTranscript(output.trim())
        : SpeechToTextTranscript(match.group(2)!, language: match.group(1));
  }
}
