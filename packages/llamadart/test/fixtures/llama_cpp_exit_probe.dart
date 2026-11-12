// Subprocess fixture: ends the process in one way while llama.cpp objects are
// alive. Arguments: the scenario and a GGUF chat model; `quit-projector` and
// `quit-disposing` also take that model's projector, and `quit-decision`
// takes an encoder GGUF and its decision head instead; `quit-speaking` takes
// a text-to-speech GGUF, its projector and an adapter name (`qwen3-tts`,
// `lfm3-audio`, `soprano`, `chatterbox`, `pocket-tts`) and exits during
// synthesis. `quit-disposing` exits
// `EXIT_PROBE_DISPOSE_DELAY_US` microseconds (default 1000) after the owning
// isolate starts to dispose.
//
// The `host-shutdown-` scenarios dispose engines in a separate owning isolate
// and await its actual exit notification before C exit. The loading scenario
// requests shutdown while a load is pending and awaits that load before disposal.
// The remaining main isolate is a host-control stand-in, not a Flutter engine.
//
// The `quit-` scenarios call C `exit` through FFI from the main isolate while
// the isolate that owns the objects is alive: what a native host that skips
// the Dart shutdown does. They do not model a Flutter macOS quit, which shuts
// the isolates down first, and `dart:io`'s `exit` does not run the static
// destructors that make ggml-metal abort. Each one exits while the owning
// isolate is idle or inside a guarded call; an exit during an unguarded call
// is not covered (doc/llama_cpp_exit_teardown.md).
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';

import '../support/cooperative_exit_probe.dart';

const _messages = [
  LlamaChatMessage.fromText(
    role: LlamaChatRole.user,
    text: 'Count from 1 to 1000, writing each number on a new line.',
  ),
];

Future<void> main(List<String> args) async {
  final [scenario, modelPath, ...extra] = args;
  if (scenario.startsWith('host-shutdown-')) {
    await runCooperativeExitProbe(_cooperativeShutdown, [
      scenario,
      modelPath,
    ], completedMarker: 'EXIT_PROBE_HOST_SHUTDOWN_COMPLETE');
    _quit(scenario);
  }
  switch (scenario) {
    case 'quit-projector':
      final engine = await LlamaEngine.load(
        LlamaModel(
          ModelSource.path(modelPath),
          projector: ModelSource.path(extra.single),
        ),
        params: const ModelParams(contextSize: 2048),
      );
      _reportBackend(await engine.getBackendName());
      _quit(scenario);
    case 'quit-disposing':
      final disposing = ReceivePort();
      await Isolate.spawn(_disposeAfterNotice, (
        disposing.sendPort,
        modelPath,
        extra.single,
      ));
      await disposing.first;
      _reached(scenario);
      final delay = Stopwatch()..start();
      final micros = int.parse(
        Platform.environment['EXIT_PROBE_DISPOSE_DELAY_US'] ?? '1000',
      );
      // A timer is too coarse for the few milliseconds the frees take.
      while (delay.elapsedMicroseconds < micros) {}
      _cExit();
    case 'quit-speaking':
      final [projectorPath, adapter] = extra;
      final synthesizer = await TextToSpeechEngine.load(
        TextToSpeechModel(
          ModelSource.path(modelPath),
          projector: ModelSource.path(projectorPath),
          adapter: switch (adapter) {
            'qwen3-tts' => const Qwen3TtsAdapter(),
            'lfm3-audio' => const Lfm3AudioTtsAdapter(),
            'soprano' => const SopranoTtsAdapter(),
            'chatterbox' => const ChatterboxTtsAdapter(),
            'pocket-tts' => const PocketTtsAdapter(),
            _ => throw ArgumentError.value(adapter, 'adapter'),
          },
        ),
        params: const ModelParams(contextSize: 2048, maxParallelSequences: 2),
      );
      final frame = Completer<void>();
      final task = await synthesizer.synthesize(
        const TextToSpeechRequest(
          text: 'Count from one to twenty, slowly and clearly.',
          maxFrames: 2048,
        ),
      );
      task.events.listen((event) {
        if (event is TextToSpeechProgressEvent &&
            event.framesGenerated > 0 &&
            !frame.isCompleted) {
          frame.complete();
        }
      });
      await frame.future;
      _quit(scenario);
    case 'quit-decision':
      final decisions = await DecisionEngine.load(
        DecisionModel(
          encoder: ModelSource.path(modelPath),
          head: ModelSource.path(extra.single),
        ),
      );
      _reportBackend(decisions.info.deviceName);
      _quit(scenario);
    case 'quit-loaded':
      final engine = await _load(modelPath);
      await engine.create(_messages, params: _tokens(4)).drain<void>();
      _quit(scenario);
    case 'quit-generating':
      await _firstToken(await _load(modelPath));
      _quit(scenario);
    case 'throw-generating':
      await _firstToken(await _load(modelPath));
      _reached(scenario);
      throw StateError('unhandled error with a generation running');
    case 'quit-loading':
      await _insideNativeLoad(modelPath);
      _quit(scenario);
    case 'throw-loading':
      await _insideNativeLoad(modelPath);
      _reached(scenario);
      throw StateError('unhandled error with a model load running');
    case 'kill-loading':
      // The kill lands when the native load returns, before the isolate holds
      // the model for its own shutdown.
      (await _insideNativeLoad(modelPath)).kill(priority: Isolate.immediate);
      _reached(scenario);
    case 'return-loaded':
      await Isolate.run(() => _loadInThisIsolate(modelPath));
      _reached(scenario);
    default:
      throw ArgumentError.value(scenario, 'scenario');
  }
}

Future<void> _cooperativeShutdown((SendPort, List<String>) message) async {
  final (completed, [scenario, modelPath]) = message;
  final loading = _load(modelPath);
  if (scenario == 'host-shutdown-loading') {
    // A shutdown requested during load must await the pending load, then
    // dispose its worker. The native load itself is synchronous.
    stdout.writeln('EXIT_PROBE_HOST_SHUTDOWN_REQUESTED loading');
  }
  final engine = await loading;
  try {
    switch (scenario) {
      case 'host-shutdown-loaded':
        await engine.create(_messages, params: _tokens(4)).drain<void>();
      case 'host-shutdown-generating':
        await disposeAfterProbeGenerationStarts(
          engine.create(_messages, params: _tokens(512)),
          engine.dispose,
        );
      case 'host-shutdown-loading':
        break;
      default:
        throw ArgumentError.value(scenario, 'scenario');
    }
  } finally {
    await engine.dispose();
  }
  completed.send(true);
}

void _reportBackend(String name) => stdout.writeln('EXIT_PROBE_BACKEND $name');

void _reached(String scenario) =>
    stdout.writeln('EXIT_PROBE_REACHED $scenario');

Never _quit(String scenario) {
  _reached(scenario);
  _cExit();
}

Never _cExit() {
  DynamicLibrary.process()
      .lookupFunction<Void Function(Int32), void Function(int)>('exit')(0);
  throw StateError('C exit returned');
}

GenerationParams _tokens(int count) => GenerationParams(
  maxTokens: count,
  streamBatchTokenThreshold: 1,
  streamBatchByteThreshold: 1,
);

Future<LlamaEngine> _load(String modelPath) async {
  final requested =
      Platform.environment['EXIT_TEARDOWN_BACKEND'] ??
      (Platform.isLinux ? 'cpu' : null);
  final engine = await LlamaEngine.load(
    LlamaModel(ModelSource.path(modelPath)),
    params: ModelParams(
      contextSize: 2048,
      preferredBackend: requested == null
          ? GpuBackend.auto
          : GpuBackend.values.byName(requested.toLowerCase()),
      device: requested == null
          ? ComputeDevice.auto
          : requested.toLowerCase() == 'cpu' ||
                requested.toLowerCase() == 'blas'
          ? ComputeDevice.cpu
          : ComputeDevice.gpu,
    ),
  );
  _reportBackend(await engine.getBackendName());
  return engine;
}

// Leaves the generation running: cancelling the subscription would stop it.
Future<void> _firstToken(LlamaEngine engine) {
  final first = Completer<void>();
  engine.create(_messages, params: _tokens(512)).listen((_) {
    if (!first.isCompleted) first.complete();
  });
  return first.future;
}

/// Returns an isolate that is halfway through the native call loading
/// [modelPath], going by how long one load of it just took.
Future<Isolate> _insideNativeLoad(String modelPath) async {
  final loadTime = await Isolate.run(() {
    final service = LlamaCppService()..initializeBackend();
    final load = Stopwatch()..start();
    final model = service.loadModel(modelPath, const ModelParams());
    load.stop();
    service.freeModel(model);
    return load.elapsed;
  });
  stdout.writeln('EXIT_PROBE_LOAD_MS ${loadTime.inMilliseconds}');
  final loading = ReceivePort();
  final isolate = await Isolate.spawn(_loadAfterNotice, (
    loading.sendPort,
    modelPath,
  ));
  await loading.first;
  await Future<void>.delayed(loadTime ~/ 2);
  return isolate;
}

void _loadAfterNotice((SendPort, String) message) {
  final (loading, modelPath) = message;
  final service = LlamaCppService()..initializeBackend();
  loading.send(null);
  service.loadModel(modelPath, const ModelParams());
}

void _disposeAfterNotice((SendPort, String, String) message) {
  final (disposing, modelPath, projectorPath) = message;
  const params = ModelParams(contextSize: 2048);
  final service = LlamaCppService()..initializeBackend();
  final model = service.loadModel(modelPath, params);
  service.createContext(model, params);
  service.createMultimodalContext(model, projectorPath);
  disposing.send(null);
  service.dispose();
}

void _loadInThisIsolate(String modelPath) {
  const params = ModelParams(contextSize: 2048);
  final service = LlamaCppService()..initializeBackend();
  service.createContext(service.loadModel(modelPath, params), params);
}
