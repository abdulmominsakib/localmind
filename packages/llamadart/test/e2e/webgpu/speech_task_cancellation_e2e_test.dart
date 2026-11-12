/// Real pinned-bridge task cancellation with another request in flight.
///
/// Stage config.json and read-only model/audio files under the gitignored
/// build/web_speech_task_cancel/ directory. Config keys are assets (a relative
/// directory), asrModel, asrProjector, audio, expectedText, ttsModel,
/// ttsProjector, manifestSha256 and sha256 (the input file hash map). Run the
/// web-speech-task-cancel scenario with the chrome-webgpu platform.
@TestOn('browser')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 25))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show window;

const String _configPath = '../../../build/web_speech_task_cancel/config.json';
const GenerationParams _greedy = GenerationParams(
  maxTokens: 256,
  temp: 0,
  topK: 1,
  topP: 1,
  penalty: 1,
  seed: 1,
  streamBatchTokenThreshold: 1,
);

void main() {
  final configUrl = Uri.base.resolve(_configPath);
  late Map<String, dynamic> config;
  late JSFunction constructor;
  Uri fixture(String key) => configUrl.resolve(config[key] as String);
  String asset(String name) => fixture('assets').resolve(name).toString();

  setUpAll(() async {
    config =
        jsonDecode(utf8.decode(await _bytes(configUrl)))
            as Map<String, dynamic>;
    final manifest = await _bytes(Uri.parse(asset('manifest.json')));
    expect(sha256.convert(manifest).toString(), config['manifestSha256']);
    final module = await importModule(
      asset('llama_webgpu_bridge.js').toJS,
    ).toDart;
    constructor = module['LlamaWebGpuBridge']! as JSFunction;
    print('RESULT speech_task_cancel_inputs ${jsonEncode(config['sha256'])}');
  });

  test('staged WAV matches its declared hash', () async {
    final audio = await _bytes(fixture('audio'));
    final expected = (config['sha256'] as Map<String, dynamic>)['audio'];
    expect(sha256.convert(audio).toString(), expected);
  });

  for (final worker in [false, true]) {
    final mode = worker ? 'worker' : 'direct';
    group(mode, () {
      late LlamaEngine engine;
      late LlamaWebGpuBridge bridge;
      late _CompletionProbe probe;

      setUp(() {
        engine = LlamaEngine(
          WebGpuLlamaBackend(
            promptSpeechToTextSupported: true,
            bridgeFactory: ([_]) {
              bridge = constructor.callAsConstructor<LlamaWebGpuBridge>(
                JSObject()
                  ..['disableWorker'] = (!worker).toJS
                  ..['preferMemory64'] = true.toJS
                  ..['workerUrl'] = asset('llama_webgpu_bridge_worker.js').toJS
                  ..['coreModuleUrl'] = asset('llama_webgpu_core.js').toJS
                  ..['wasmUrl'] = asset('llama_webgpu_core.wasm').toJS
                  ..['coreModuleUrlMem64'] = asset(
                    'llama_webgpu_core_mem64.js',
                  ).toJS
                  ..['wasmUrlMem64'] = asset(
                    'llama_webgpu_core_mem64.wasm',
                  ).toJS,
              );
              probe = _CompletionProbe(bridge);
              return bridge;
            },
          ),
        );
        addTearDown(engine.dispose);
      });

      Future<void> expectRuntime(String stage) async {
        final metadata = await engine.getMetadata();
        expect(
          metadata['llamadart.webgpu.execution'],
          worker ? 'worker' : 'main-thread',
          reason: '$mode $stage',
        );
        expect(
          metadata['llamadart.webgpu.worker_fallback_reason'],
          isNull,
          reason: 'A worker fallback cannot qualify $mode ($stage).',
        );
        if (((config['gpuLayers'] as int?) ?? 0) > 0) {
          expect(await engine.getBackendName(), contains('WebGPU'));
        }
      }

      Future<void> load(String model, String projector) async {
        final layers = (config['gpuLayers'] as int?) ?? 0;
        final ttsBatch = (config['ttsBatchSize'] as int?) ?? 512;
        final ttsMicroBatch = (config['ttsMicroBatchSize'] as int?) ?? 256;
        if (model == 'ttsModel') {
          expect(ttsBatch, inInclusiveRange(1, 4096));
          expect(ttsMicroBatch, inInclusiveRange(1, ttsBatch));
        }
        print('speech-task-cancel $mode loading $model');
        await engine.loadModelFromUrl(
          fixture(model).toString(),
          modelParams: ModelParams(
            contextSize: 4096,
            gpuLayers: layers,
            preferredBackend: layers > 0 ? GpuBackend.auto : GpuBackend.cpu,
            preferMemory64: true,
            numberOfThreads: 4,
            batchSize: model == 'ttsModel' ? ttsBatch : 0,
            microBatchSize: model == 'ttsModel' ? ttsMicroBatch : 0,
          ),
        );
        await engine.loadMultimodalProjector(fixture(projector).toString());
        await expectRuntime('load');
        if (model == 'ttsModel') {
          final metadata = await engine.getMetadata();
          expect(metadata['llamadart.webgpu.core_variant'], 'wasm64');
          expect(metadata['llamadart.webgpu.n_batch'], '$ttsBatch');
          expect(metadata['llamadart.webgpu.n_ubatch'], '$ttsMicroBatch');
        }
        print('speech-task-cancel $mode loaded $model and $projector');
      }

      test(
        'cancelling queued STT leaves an active audio request intact',
        () async {
          await load('asrModel', 'asrProjector');
          final audio = await _bytes(fixture('audio'));
          final adapter = Qwen3AsrAdapter();
          final request = SpeechToTextRequest(
            audio: SpeechAudioBytesInput(
              audio,
              format: const SpeechAudioFormat(encoding: 'wav'),
            ),
            maxOutputTokens: 256,
          );
          final speech = SpeechToTextEngine.attach(engine, adapter: adapter);
          addTearDown(speech.dispose);
          Future<String> otherRequest() => engine
              .generate(
                adapter.promptFor(request),
                params: _greedy,
                parts: [LlamaAudioContent(bytes: audio)],
              )
              .join();

          final baseline = await otherRequest();
          expect(
            adapter.parseTranscript(baseline).text,
            config['expectedText'],
          );
          final activeCall = probe.calls;
          final active = otherRequest();
          await probe.firstToken(activeCall);
          expect((bridge as JSObject)['_activeOperation'], isNotNull);
          final cancelled = await speech.transcribe(request);
          final events = cancelled.events.toList();
          await probe.started(activeCall + 1);
          cancelled.cancel();
          expect(
            (await cancelled.done).state,
            SpeechToTextCompletionState.cancelled,
          );
          expect((await events).whereType<SpeechToTextFinalEvent>(), isEmpty);
          expect(
            await active,
            baseline,
            reason: 'A task cancel must not stop the other active request.',
          );
          expect(await otherRequest(), baseline);
          await expectRuntime('STT cancel and reuse');
          print('RESULT speech_task_cancel $mode stt isolated');
        },
      );

      test('cancelling pending TTS leaves an active generation intact', () async {
        await load('ttsModel', 'ttsProjector');
        final speech = TextToSpeechEngine.attach(
          engine,
          adapter: const Qwen3TtsAdapter(),
        );
        addTearDown(speech.dispose);
        Future<String> otherRequest() => engine
            .generate(
              'Hello from llamadart.',
              params: const GenerationParams(
                maxTokens: 64,
                temp: 0,
                topK: 1,
                topP: 1,
                penalty: 1,
                seed: 1,
                streamBatchTokenThreshold: 1,
              ),
            )
            .join();
        final baseline = await otherRequest();
        expect(
          baseline,
          isNotEmpty,
          reason:
              'This fixture needs observable raw generation for the control.',
        );
        print(
          'RESULT speech_task_cancel $mode raw_tts_generation '
          'length=${baseline.length} sha256=${sha256.convert(utf8.encode(baseline))}',
        );
        final capabilities = _TtsCapabilityProbe(bridge);
        addTearDown(capabilities.releaseFirst);
        final taskFuture = speech.synthesize(
          const TextToSpeechRequest(text: 'Cancelled before synthesis.'),
        );
        await capabilities.firstResolved;
        final activeCall = probe.calls;
        final active = otherRequest();
        await probe.firstToken(activeCall);
        capabilities.releaseFirst();
        final task = await taskFuture;
        final events = task.events.toList();
        await capabilities.secondStarted;
        final operation = (bridge as JSObject)['_activeOperation']! as JSObject;
        expect((operation['kind']! as JSString).toDart, 'generation');
        task.cancel();
        expect((await task.done).state, TextToSpeechCompletionState.cancelled);
        expect((await events).whereType<TextToSpeechFinalEvent>(), isEmpty);
        expect(
          await active,
          baseline,
          reason:
              'A pending TTS cancel must not stop the other active generation.',
        );
        expect(await otherRequest(), baseline);
        final retry = await speech.synthesize(
          const TextToSpeechRequest(text: 'Ready.', maxFrames: 1, seed: 1),
        );
        final retryEvents = retry.events.toList();
        final completion = await retry.done;
        expect(
          completion.state,
          TextToSpeechCompletionState.completed,
          reason: '${completion.error}',
        );
        expect(
          (await retryEvents).whereType<TextToSpeechFinalEvent>(),
          hasLength(1),
        );
        expect(completion.result!.samples, isNotEmpty);
        await expectRuntime('pending TTS cancel and reuse');
        print('RESULT speech_task_cancel $mode pending_tts isolated');
      });

      for (final frames in [1, 8]) {
        test('TTS $frames-frame baseline without cancellation', () async {
          await load('ttsModel', 'ttsProjector');
          final speech = TextToSpeechEngine.attach(
            engine,
            adapter: const Qwen3TtsAdapter(),
          );
          addTearDown(speech.dispose);
          final task = await speech.synthesize(
            TextToSpeechRequest(
              text: 'Hello.',
              language: 'en',
              maxFrames: frames,
              seed: 1,
            ),
          );
          final events = task.events.toList();
          final completion = await task.done;
          print(
            'RESULT speech_task_cancel $mode tts baseline$frames '
            '${completion.state} ${completion.error}',
          );
          print(
            'RESULT speech_task_cancel $mode metadata '
            '${jsonEncode(_runtimeEvidence(await engine.getMetadata()))}',
          );
          expect(
            completion.state,
            TextToSpeechCompletionState.completed,
            reason: '${completion.error}',
          );
          expect(
            (await events).whereType<TextToSpeechFinalEvent>(),
            hasLength(1),
          );
          expect(completion.result!.samples, isNotEmpty);
          expect(
            completion.result!.samples.every((value) => value.isFinite),
            isTrue,
          );
          await expectRuntime('TTS $frames-frame baseline');
        });
      }

      for (final afterFrame in [false, true]) {
        final point = afterFrame ? 'after first frame' : 'at first progress';
        final retryFrames = afterFrame ? 8 : 1;
        test('cancelling TTS $point leaves a queued tokenizer intact '
            'with a $retryFrames-frame retry', () async {
          await load('ttsModel', 'ttsProjector');
          final speech = TextToSpeechEngine.attach(
            engine,
            adapter: const Qwen3TtsAdapter(),
          );
          addTearDown(speech.dispose);
          const text = 'Hello from llamadart. The answer is forty two.';
          final baseline = await engine.tokenize(text);
          final task = await speech.synthesize(
            const TextToSpeechRequest(
              text: text,
              language: 'en',
              maxFrames: 128,
              seed: 1,
            ),
          );
          final progress = Completer<void>();
          final events = <TextToSpeechEvent>[];
          final subscription = task.events.listen((event) {
            events.add(event);
            if (event is TextToSpeechProgressEvent &&
                !progress.isCompleted &&
                (!afterFrame ||
                    (event.phase == TextToSpeechProgressPhase.generating &&
                        event.framesGenerated >= 1))) {
              print(
                'RESULT speech_task_cancel $mode $point cancel_progress '
                '${event.phase.name} frames=${event.framesGenerated} '
                'promptRemaining=${event.promptTokensRemaining}',
              );
              progress.complete();
            }
          });
          addTearDown(subscription.cancel);
          await Future.any<void>([
            progress.future,
            task.done.then((completion) {
              if (!progress.isCompleted) {
                fail(
                  'Synthesis ended before real progress: '
                  '${completion.state} ${completion.error}',
                );
              }
            }),
          ]);
          final other = engine.tokenize(text);
          task.cancel();
          expect(
            (await task.done).state,
            TextToSpeechCompletionState.cancelled,
          );
          expect(events.whereType<TextToSpeechFinalEvent>(), isEmpty);
          expect(await other, baseline);
          print(
            'RESULT speech_task_cancel $mode after_cancel '
            '${jsonEncode(_runtimeEvidence(await engine.getMetadata()))}',
          );
          final retry = await speech.synthesize(
            TextToSpeechRequest(
              text: 'Hello.',
              language: 'en',
              maxFrames: retryFrames,
              seed: 1,
            ),
          );
          final retryEvents = retry.events.toList();
          final result = await retry.done;
          print(
            'RESULT speech_task_cancel $mode retry$retryFrames '
            '${result.state} ${result.error}',
          );
          print(
            'RESULT speech_task_cancel $mode after_retry '
            '${jsonEncode(_runtimeEvidence(await engine.getMetadata()))}',
          );
          expect(
            result.state,
            TextToSpeechCompletionState.completed,
            reason: '${result.error}',
          );
          expect(
            (await retryEvents).whereType<TextToSpeechFinalEvent>(),
            hasLength(1),
          );
          expect(result.result!.samples, isNotEmpty);
          expect(
            result.result!.samples.every((value) => value.isFinite),
            isTrue,
          );
          await expectRuntime('TTS cancel and reuse');
          print('RESULT speech_task_cancel $mode tts isolated');
        });
      }
    });
  }
}

Map<String, String> _runtimeEvidence(Map<String, String> metadata) => {
  for (final field in [
    'execution',
    'core_variant',
    'n_batch',
    'n_ubatch',
    'n_threads',
    'n_threads_batch',
    'n_gpu_layers',
    'worker_fallback_reason',
    'runtime_notes',
  ])
    field: ?metadata['llamadart.webgpu.$field'],
};

Future<Uint8List> _bytes(Uri url) async {
  final response = await window.fetch(url.toString().toJS).toDart;
  expect(response.ok, isTrue, reason: 'Missing real fixture $url');
  return (await response.arrayBuffer().toDart).toDart.asUint8List();
}

/// Holds delivery of one real capability result to expose startup concurrency.
final class _TtsCapabilityProbe {
  final Completer<void> _firstResolved = Completer<void>();
  final Completer<void> _releaseFirst = Completer<void>();
  final Completer<void> _secondStarted = Completer<void>();

  Future<void> get firstResolved => _firstResolved.future;
  Future<void> get secondStarted => _secondStarted.future;

  _TtsCapabilityProbe(LlamaWebGpuBridge bridge) {
    final object = bridge as JSObject;
    final original = object['getTextToSpeechCapabilities']! as JSFunction;
    var calls = 0;
    object['getTextToSpeechCapabilities'] = (() {
      final result = original.callMethod<JSPromise<JSAny?>>(
        'call'.toJS,
        object,
      );
      calls++;
      if (calls == 1) {
        return (() async {
          final value = await result.toDart;
          _firstResolved.complete();
          await _releaseFirst.future;
          return value;
        })().toJS;
      }
      if (calls == 2) _secondStarted.complete();
      return result;
    }).toJS;
  }

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) _releaseFirst.complete();
  }
}

/// Observes the real bridge dispatch/token callbacks without replacing work.
final class _CompletionProbe {
  final List<Completer<void>> _started = [];
  final List<Completer<void>> _tokens = [];
  int get calls => _started.length;

  _CompletionProbe(LlamaWebGpuBridge bridge) {
    final object = bridge as JSObject;
    final original = object['createCompletion']! as JSFunction;
    object['createCompletion'] = ((JSAny? prompt, JSObject options) {
      final started = Completer<void>();
      final token = Completer<void>();
      _started.add(started);
      _tokens.add(token);
      final onToken = options['onToken']! as JSFunction;
      options['onToken'] = ((JSAny? piece, JSAny? current) {
        onToken.callAsFunction(null, piece, current);
        if (!token.isCompleted) token.complete();
      }).toJS;
      final result = original.callMethod<JSAny?>(
        'call'.toJS,
        object,
        prompt,
        options,
      );
      started.complete();
      return result;
    }).toJS;
  }

  Future<void> started(int index) async {
    while (_started.length <= index) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await _started[index].future;
  }

  Future<void> firstToken(int index) async {
    await started(index);
    await _tokens[index].future;
  }
}
