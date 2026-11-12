@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

const _modelPathKey = 'LLAMADART_TTS_MODEL_PATH';
const _mmprojPathKey = 'LLAMADART_TTS_MMPROJ_PATH';
const _outputPathKey = 'LLAMADART_TTS_OUTPUT_PATH';
const _serviceRequest = BackendTextToSpeechRequest(
  text: 'Hello from llamadart.',
  language: 'english',
  maxFrames: 64,
  seed: 1,
);
final _cancelled = throwsA(
  isA<LlamaTextToSpeechException>().having(
    (error) => error.message,
    'message',
    'Text-to-speech synthesis was cancelled.',
  ),
);

void main() {
  test('loads the model from sources and owns it until dispose', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final mmprojPath = _requiredFile(_mmprojPathKey);
    if (modelPath == null || mmprojPath == null) {
      return;
    }

    final backend = LlamaBackend();
    final synthesizer = await TextToSpeechEngine.load(
      TextToSpeechModel(
        ModelSource.path(modelPath),
        projector: ModelSource.path(mmprojPath),
        adapter: const Qwen3TtsAdapter(),
      ),
      params: const ModelParams(
        contextSize: 4096,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      ),
      backend: backend,
    );
    expect(backend.isReady, isTrue);
    try {
      final result = await synthesizer.synthesizeOnce(
        const TextToSpeechRequest(
          text: 'Hello from llamadart.',
          language: 'English',
          maxFrames: 128,
          seed: 1,
        ),
      );
      expect(result.sampleRateHz, 24000);
      expect(result.samples, isNotEmpty);
      expect(result.toWavBytes().length, greaterThan(44));
    } finally {
      await synthesizer.dispose();
    }
    expect(synthesizer.isDisposed, isTrue);
    expect(backend.isReady, isFalse);
    final disposed = await synthesizer.capabilities;
    expect(disposed.isSupported, isFalse);
    expect(disposed.unsupportedReason, 'The TextToSpeechEngine is disposed.');
  });

  test('load disposes a model it cannot use and its backend', () async {
    final modelPath = _requiredFile(_modelPathKey);
    if (modelPath == null) {
      return;
    }

    final backend = LlamaBackend();
    await expectLater(
      TextToSpeechEngine.load(
        TextToSpeechModel(
          ModelSource.path(modelPath),
          adapter: const Qwen3TtsAdapter(),
        ),
        params: const ModelParams(
          contextSize: 4096,
          preferredBackend: GpuBackend.cpu,
          gpuLayers: 0,
        ),
        backend: backend,
      ),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(backend.isReady, isFalse);
  });

  test('synthesizes a playable WAV through the public API', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final mmprojPath = _requiredFile(_mmprojPathKey);
    final outputPath = Platform.environment[_outputPathKey]?.trim();
    if (modelPath == null || mmprojPath == null) {
      return;
    }
    if (outputPath == null || outputPath.isEmpty) {
      markTestSkipped('Set $_outputPathKey to write the synthesized WAV.');
      return;
    }

    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: const ModelParams(
          contextSize: 4096,
          preferredBackend: GpuBackend.cpu,
          gpuLayers: 0,
        ),
      );
      await engine.loadMultimodalProjector(mmprojPath);

      final synthesizer = TextToSpeechEngine.attach(
        engine,
        adapter: const Qwen3TtsAdapter(),
      );
      final capabilities = await synthesizer.capabilities;
      expect(
        capabilities.isSupported,
        isTrue,
        reason: capabilities.unsupportedReason,
      );
      expect(capabilities.sampleRateHz, 24000);
      expect(capabilities.channelCount, 1);

      final task = await synthesizer.synthesize(
        const TextToSpeechRequest(
          text:
              'Hello from llamadart. This audio was generated locally on your device.',
          language: 'English',
          maxFrames: 384,
          seed: 1,
        ),
      );
      final events = await task.events.toList();
      final completion = await task.done;

      expect(completion.state, TextToSpeechCompletionState.completed);
      expect(events.whereType<TextToSpeechProgressEvent>(), isNotEmpty);
      expect(events.whereType<TextToSpeechFinalEvent>(), hasLength(1));
      final result = completion.result!;
      expect(result.samples, isNotEmpty);
      expect(result.sampleRateHz, 24000);
      expect(result.channelCount, 1);
      expect(result.duration, greaterThan(Duration.zero));

      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(result.toWavBytes(), flush: true);
      expect(output.lengthSync(), greaterThan(44));

      print(
        'RESULT text_to_speech '
        'sampleRate=${result.sampleRateHz} channels=${result.channelCount} '
        'samples=${result.samples.length} frames=${result.framesGenerated} '
        'truncated=${result.truncated}',
      );
    } finally {
      await engine.dispose();
    }
  });

  // https://github.com/leehack/llamadart/issues/632: the code predictor that
  // samples codebooks 1-15 ignored the seed and continued the previous
  // synthesis's random stream, so only the first synthesis after a load was
  // reproducible.
  test('a fixed seed gives the same PCM on every synthesis of one engine, '
      'including after another seed and a cancelled task', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final mmprojPath = _requiredFile(_mmprojPathKey);
    if (modelPath == null || mmprojPath == null) {
      return;
    }

    final synthesizer = await TextToSpeechEngine.load(
      TextToSpeechModel(
        ModelSource.path(modelPath),
        projector: ModelSource.path(mmprojPath),
        adapter: const Qwen3TtsAdapter(),
      ),
      params: const ModelParams(
        contextSize: 4096,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
      ),
      backend: LlamaBackend(),
    );
    TextToSpeechRequest request(int seed) => TextToSpeechRequest(
      text: 'Hello from llamadart. The answer is forty two.',
      language: 'English',
      maxFrames: 384,
      seed: seed,
    );
    Future<TextToSpeechResult> synthesize(int seed) =>
        synthesizer.synthesizeOnce(request(seed));
    try {
      final first = await synthesize(1);
      expect(first.samples, isNotEmpty);

      final repeated = await synthesize(1);
      final otherSeed = await synthesize(2);

      final cancelled = await synthesizer.synthesize(request(1));
      await cancelled.events.firstWhere(
        (event) => event is TextToSpeechProgressEvent,
      );
      cancelled.cancel();
      expect(
        (await cancelled.done).state,
        TextToSpeechCompletionState.cancelled,
      );
      final afterCancel = await synthesize(1);

      expect(repeated.framesGenerated, first.framesGenerated);
      expect(repeated.samples, orderedEquals(first.samples));
      expect(afterCancel.framesGenerated, first.framesGenerated);
      expect(afterCancel.samples, orderedEquals(first.samples));
      expect(otherSeed.samples, isNot(orderedEquals(first.samples)));
    } finally {
      await synthesizer.dispose();
    }
  });

  test('a cancel flag raised before synthesis starts cancels it', () async {
    await _withTextToSpeechService((service, context, projector) async {
      final flag = calloc<Int8>()..value = 1;
      try {
        final progress = <BackendTextToSpeechProgress>[];
        await expectLater(
          service.synthesizeTextToSpeech(
            context,
            projector,
            _serviceRequest,
            flag.address,
            onProgress: progress.add,
          ),
          _cancelled,
        );
        expect(progress, isEmpty);
      } finally {
        calloc.free(flag);
      }
    });
  });

  test('a cancel flag raised between steps stops the next step only when the '
      'runtime can attach it', () async {
    await _withTextToSpeechService((service, context, projector) async {
      final attachable =
          service.debugTtsCancelExportsForTesting()?.setCancelFlag ?? false;
      final flag = calloc<Int8>();
      try {
        var steps = 0;
        final synthesis = service.synthesizeTextToSpeech(
          context,
          projector,
          _serviceRequest,
          flag.address,
          onProgress: (_) {
            steps += 1;
            flag.value = 1;
          },
        );
        if (attachable) {
          await expectLater(synthesis, _cancelled);
          expect(steps, 1);
        } else {
          expect((await synthesis).samples, isNotEmpty);
          expect(steps, greaterThan(1));
        }
      } finally {
        calloc.free(flag);
      }
    });
  });
}

Future<void> _withTextToSpeechService(
  Future<void> Function(LlamaCppService service, int context, int projector)
  body,
) async {
  final modelPath = _requiredFile(_modelPathKey);
  final mmprojPath = _requiredFile(_mmprojPathKey);
  if (modelPath == null || mmprojPath == null) {
    return;
  }
  final service = LlamaCppService()..setLogLevel(LlamaLogLevel.none);
  try {
    service.initializeBackend();
    const modelParams = ModelParams(
      contextSize: 4096,
      preferredBackend: GpuBackend.cpu,
      gpuLayers: 0,
    );
    final model = service.loadModel(modelPath, modelParams);
    final context = service.createContext(model, modelParams);
    final projector = service.createMultimodalContext(model, mmprojPath);
    await body(service, context, projector);
  } finally {
    service.dispose();
  }
}

String? _requiredFile(String environmentKey) {
  final value = Platform.environment[environmentKey];
  if (value == null || value.isEmpty) {
    markTestSkipped('Set $environmentKey to run the text-to-speech E2E.');
    return null;
  }
  if (!File(value).existsSync()) {
    throw StateError('$environmentKey does not exist.');
  }
  return value;
}
