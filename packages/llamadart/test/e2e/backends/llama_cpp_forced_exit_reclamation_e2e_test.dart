@TestOn('mac-os')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart' as native;
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:test/test.dart';

import '../../test_helper.dart';

/// Loads a model on a llama.cpp worker, kills the worker isolate with
/// `Isolate.kill(priority: Isolate.immediate)` (issue #629), and repeats,
/// checking that the native objects the worker held are freed with its
/// isolate rather than abandoned until the process exits.
///
/// Each cycle samples the tracked object count, `phys_footprint`, the bytes
/// in use in the malloc zones and the Metal device's allocated size before
/// the load, with the model loaded, and after the worker exited. Model,
/// context, KV and Metal buffers that a cycle left behind would show as
/// growth of tens of MiB or more per cycle, and a context's token batch and
/// sampler chain as about 80 KiB of malloc per cycle
/// (`doc/llama_cpp_exit_teardown.md`, "Forced worker exit").
///
/// `FORCED_EXIT_MODEL` sets the GGUF (default: the cached stories15M test
/// model); `FORCED_EXIT_CYCLES` the cycles per case (default 10).
/// `FORCED_EXIT_TTS_MODEL` with `FORCED_EXIT_TTS_MMPROJ`, a Qwen3-TTS model
/// and its projector, enable the speech case. `FORCED_EXIT_KILL_LOADING=1`
/// enables the kill inside a load, which fails until a model whose load the
/// kill interrupted is freed before the process exits.
void main() {
  final environment = Platform.environment;
  final cycles = int.parse(environment['FORCED_EXIT_CYCLES'] ?? '10');
  final ttsModel = environment['FORCED_EXIT_TTS_MODEL'];
  final ttsProjector = environment['FORCED_EXIT_TTS_MMPROJ'];
  late String model;

  setUpAll(() async {
    model =
        environment['FORCED_EXIT_MODEL'] ??
        (await TestHelper.getTestModel()).path;
  });

  // No mmap, so the weights are anonymous memory that phys_footprint counts.
  for (final (device, params) in [
    (
      _Device.cpu,
      const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 2048,
        preferredBackend: GpuBackend.cpu,
        gpuLayers: 0,
        useMmap: false,
      ),
    ),
    (
      _Device.metal,
      const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        contextSize: 2048,
        useMmap: false,
      ),
    ),
  ]) {
    for (final scenario in _TextScenario.values) {
      test(
        '${device.name} ${scenario.name} frees the worker objects',
        () async {
          final cycleSamples = <_Cycle>[];
          for (var cycle = 0; cycle < cycles; cycle++) {
            final before = await _Sample.settled();
            final loaded = await _textCycle(model, params, scenario);
            cycleSamples.add((before, loaded, await _Sample.settled()));
          }
          _report('${device.name} ${scenario.name}', cycleSamples);
          _expectReclaimed(cycleSamples, device);
        },
      );
    }
  }

  test('metal killSynthesizing frees the worker objects', () async {
    if (ttsModel == null || ttsProjector == null) {
      markTestSkipped('Set FORCED_EXIT_TTS_MODEL and FORCED_EXIT_TTS_MMPROJ.');
      return;
    }
    final cycleSamples = <_Cycle>[];
    for (var cycle = 0; cycle < cycles; cycle++) {
      final before = await _Sample.settled();
      final loaded = await _ttsCycle(ttsModel, ttsProjector);
      cycleSamples.add((before, loaded, await _Sample.settled()));
    }
    _report('metal killSynthesizing', cycleSamples);
    _expectReclaimed(cycleSamples, _Device.metal);
  });

  test('metal killLoading frees the model of the interrupted load', () async {
    if (environment['FORCED_EXIT_KILL_LOADING'] != '1') {
      markTestSkipped('Set FORCED_EXIT_KILL_LOADING=1.');
      return;
    }
    const params = ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: 2048,
      useMmap: false,
    );
    final loadTime = await _timedLoad(model, params);
    final cycleSamples = <_Cycle>[];
    for (var cycle = 0; cycle < cycles; cycle++) {
      final before = await _Sample.settled();
      final worker = _KillableWorker();
      final engine = LlamaEngine(
        NativeLlamaBackend(workerEntrypoint: worker.entrypoint),
      );
      final loading = engine
          .setModel(LlamaModel(ModelSource.path(model)), params: params)
          .then<void>((_) {}, onError: (Object _) {});
      await worker.started;
      // Spread the kills over the load.
      await Future<void>.delayed(loadTime * (cycle + 1) ~/ (cycles + 1));
      final atKill = _Sample.now();
      await worker.kill();
      await loading;
      await _settles(engine.dispose());
      cycleSamples.add((before, atKill, await _Sample.settled()));
    }
    _report(
      'metal killLoading, load ${loadTime.inMilliseconds} ms',
      cycleSamples,
    );
    expect(
      [for (final (_, _, after) in cycleSamples) after.tracked],
      [for (var i = 0; i < cycles; i++) 0],
    );
  });
}

enum _Device { cpu, metal }

enum _TextScenario { dispose, killIdle, killGenerating }

/// Samples before the load, with the model loaded, and after the cycle.
typedef _Cycle = (_Sample, _Sample, _Sample);

const _mib = 1 << 20;

/// Allowed median growth per cycle of `phys_footprint`, which moves by whole
/// pages and by memory the GPU driver keeps.
const _growthPerCycle = 8 * _mib;

/// Allowed median growth per cycle of the malloc zones: a kill measured at
/// most 19 KiB, and leaking a context's batch and sampler chain at least
/// 75 KiB.
const _mallocGrowthPerCycle = 48 * 1024;

void _expectReclaimed(List<_Cycle> cycles, _Device device) {
  expect(cycles.length, greaterThanOrEqualTo(3), reason: 'FORCED_EXIT_CYCLES');
  for (final (index, (before, loaded, after)) in cycles.indexed) {
    final cycle = 'cycle ${index + 1}';
    expect(loaded.tracked, greaterThan(0), reason: '$cycle loaded');
    expect(after.tracked, 0, reason: '$cycle tracked objects left');
    // The meters must see the loaded model for their bounds to mean anything.
    expect(
      loaded.footprint - after.footprint,
      greaterThan(_growthPerCycle * 2),
      reason: '$cycle footprint of the loaded model',
    );
    if (device == _Device.metal) {
      expect(loaded.metal, greaterThan(before.metal + _mib), reason: cycle);
      expect(
        after.metal,
        lessThan(cycles.first.$1.metal + _mib),
        reason: '$cycle Metal bytes left',
      );
    }
  }
  expect(
    _medianGrowth(cycles, (s) => s.footprint),
    lessThan(_growthPerCycle),
    reason: 'phys_footprint growth per cycle',
  );
  expect(
    _medianGrowth(cycles, (s) => s.malloc),
    lessThan(_mallocGrowthPerCycle),
    reason: 'malloc growth per cycle',
  );
}

/// The median growth of [read] from one cycle's end to the next. The median
/// ignores one-time growth: the first loads compile Metal pipelines, and
/// libmalloc keeps freed large blocks dirty for reuse.
int _medianGrowth(List<_Cycle> cycles, int Function(_Sample) read) {
  final growth = [
    for (var i = 1; i < cycles.length; i++)
      read(cycles[i].$3) - read(cycles[i - 1].$3),
  ]..sort();
  return growth[growth.length ~/ 2];
}

/// Runs one cycle and returns the sample taken with the model loaded.
Future<_Sample> _textCycle(
  String model,
  ModelParams params,
  _TextScenario scenario,
) async {
  final worker = _KillableWorker();
  final engine = LlamaEngine(
    NativeLlamaBackend(workerEntrypoint: worker.entrypoint),
  );
  await engine.setModel(LlamaModel(ModelSource.path(model)), params: params);
  late final _Sample loaded;
  switch (scenario) {
    case _TextScenario.dispose:
      await engine.generate(_prompt, params: _tokens(8)).drain<void>();
      loaded = _Sample.now();
      await engine.dispose();
    case _TextScenario.killIdle:
      await engine.generate(_prompt, params: _tokens(8)).drain<void>();
      loaded = _Sample.now();
      await worker.kill();
      await _settles(engine.dispose());
    case _TextScenario.killGenerating:
      final first = Completer<void>();
      final done = Completer<void>();
      final subscription = engine
          .generate(_prompt, params: _tokens(400))
          .listen(
            (_) {
              if (!first.isCompleted) first.complete();
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object _) {
              if (!done.isCompleted) done.complete();
            },
          );
      await first.future;
      loaded = _Sample.now();
      await worker.kill();
      await done.future.timeout(const Duration(seconds: 10));
      await subscription.cancel();
      await _settles(engine.dispose());
  }
  return loaded;
}

Future<_Sample> _ttsCycle(String model, String projector) async {
  final worker = _KillableWorker();
  final engine = LlamaEngine(
    NativeLlamaBackend(workerEntrypoint: worker.entrypoint),
  );
  await engine.setModel(
    LlamaModel(ModelSource.path(model), projector: ModelSource.path(projector)),
    params: const ModelParams(
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
      contextSize: 4096,
      useMmap: false,
    ),
  );
  final tts = TextToSpeechEngine(
    engine,
    modelProfile: TextToSpeechModelProfile.qwen3Tts,
  );
  final task = await tts.synthesize(
    const TextToSpeechRequest(
      text: 'Hello from llamadart. The answer is forty two.',
      language: 'English',
      maxFrames: 384,
      seed: 1,
    ),
  );
  final progress = Completer<void>();
  final subscription = task.events.listen((event) {
    if (event is TextToSpeechProgressEvent && !progress.isCompleted) {
      progress.complete();
    }
  }, onError: (Object _) {});
  await progress.future;
  final loaded = _Sample.now();
  await worker.kill();
  await task.done
      .timeout(const Duration(seconds: 10))
      .then<void>((_) {}, onError: (Object _) {});
  await subscription.cancel();
  await _settles(tts.dispose());
  await _settles(engine.dispose());
  return loaded;
}

/// The time from the worker's start to a finished load.
Future<Duration> _timedLoad(String model, ModelParams params) async {
  final worker = _KillableWorker();
  final engine = LlamaEngine(
    NativeLlamaBackend(workerEntrypoint: worker.entrypoint),
  );
  final loading = engine.setModel(
    LlamaModel(ModelSource.path(model)),
    params: params,
  );
  await worker.started;
  final clock = Stopwatch()..start();
  await loading;
  clock.stop();
  await engine.dispose();
  return clock.elapsed;
}

const _prompt = 'Once upon a time';

GenerationParams _tokens(int count) =>
    GenerationParams(maxTokens: count, temp: 0, topK: 1, seed: 1);

/// Awaits disposal, which settles with a stale-handle error after the worker
/// exited.
Future<void> _settles(Future<void> disposal) async {
  try {
    await disposal.timeout(const Duration(seconds: 10));
  } on LlamaStateException {
    return;
  }
}

void _report(String name, List<_Cycle> cycles) {
  String mib(int bytes) => (bytes / _mib).toStringAsFixed(1);
  String row(_Cycle cycle, int Function(_Sample) read) =>
      [cycle.$1, cycle.$2, cycle.$3].map((s) => mib(read(s))).join('/');
  final buffer = StringBuffer('[$name]\n')
    ..writeln(
      'cycle | tracked | footprint MiB | malloc MiB | Metal MiB '
      '(before load/loaded/after exit)',
    );
  for (final (index, cycle) in cycles.indexed) {
    final (before, loaded, after) = cycle;
    buffer.writeln(
      '${index + 1} | ${before.tracked}/${loaded.tracked}/${after.tracked} | '
      '${row(cycle, (s) => s.footprint)} | ${row(cycle, (s) => s.malloc)} | '
      '${row(cycle, (s) => s.metal)}',
    );
  }
  if (cycles.length > 1) {
    String kib(int Function(_Sample) read) =>
        (_medianGrowth(cycles, read) / 1024).toStringAsFixed(1);
    buffer.writeln(
      'median growth per cycle: footprint ${kib((s) => s.footprint)} KiB, '
      'malloc ${kib((s) => s.malloc)} KiB',
    );
  }
  stdout.write(buffer);
}

class _KillableWorker {
  _KillableWorker() {
    _isolate = _control.first.then((message) {
      final [controlPort, terminate] = message as List<Object?>;
      return Isolate(
        controlPort! as SendPort,
        terminateCapability: terminate! as Capability,
      );
    });
  }

  final ReceivePort _control = ReceivePort();
  late final Future<Isolate> _isolate;

  /// Completes when the worker isolate runs.
  Future<void> get started => _isolate;

  /// The production worker, which first sends what [kill] needs.
  LlamaWorkerEntrypoint get entrypoint {
    final control = _control.sendPort;
    return (SendPort initial) {
      final self = Isolate.current;
      control.send(<Object?>[self.controlPort, self.terminateCapability]);
      llamaWorkerEntry(initial);
    };
  }

  /// Kills the worker and returns once its exit is observed.
  Future<void> kill() async {
    final isolate = await _isolate;
    final exited = ReceivePort();
    isolate.addOnExitListener(exited.sendPort);
    isolate.kill(priority: Isolate.immediate);
    await exited.first;
    exited.close();
  }
}

class _Sample {
  _Sample(this.tracked, this.footprint, this.malloc, this.metal);

  factory _Sample.now() => _Sample(
    native.llama_dart_exit_tracked_count(),
    _physFootprint(),
    _mallocInUse(),
    _metalAllocated(),
  );

  /// Gives the VM up to two seconds to finish freeing the tracked objects.
  static Future<_Sample> settled() async {
    for (var i = 0; i < 100; i++) {
      if (native.llama_dart_exit_tracked_count() == 0) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _Sample.now();
  }

  /// Objects in libllamadart's exit-teardown registry.
  final int tracked;

  /// `task_vm_info.phys_footprint`.
  final int footprint;

  /// Bytes in use in every malloc zone.
  final int malloc;

  /// The Metal device's `currentAllocatedSize`.
  final int metal;
}

const _taskVmInfo = 22;
const _physFootprintOffset = 144;

final _taskInfo = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Uint32, Int32, Pointer<Int32>, Pointer<Uint32>),
      int Function(int, int, Pointer<Int32>, Pointer<Uint32>)
    >('task_info');
final _machTaskSelf = DynamicLibrary.process().lookup<Uint32>(
  'mach_task_self_',
);
final _mallocZoneStatistics = DynamicLibrary.process()
    .lookupFunction<
      Void Function(Pointer<Void>, Pointer<Uint64>),
      void Function(Pointer<Void>, Pointer<Uint64>)
    >('malloc_zone_statistics');

int _physFootprint() => using((arena) {
  const words = 128;
  final info = arena<Int32>(words);
  final count = arena<Uint32>()..value = words;
  final status = _taskInfo(_machTaskSelf.value, _taskVmInfo, info, count);
  if (status != 0) {
    throw StateError('task_info(TASK_VM_INFO) failed: $status');
  }
  return (info.cast<Uint8>() + _physFootprintOffset).cast<Uint64>().value;
});

int _mallocInUse() => using((arena) {
  // malloc_statistics_t: blocks_in_use (padded), size_in_use,
  // max_size_in_use, size_allocated.
  final statistics = arena<Uint64>(4);
  _mallocZoneStatistics(nullptr, statistics);
  return statistics[1];
});

/// ggml-metal reports the device's free memory as its recommended working
/// set minus `currentAllocatedSize`.
int _metalAllocated() => using((arena) {
  for (var i = 0; i < native.ggml_backend_dev_count(); i++) {
    final device = native.ggml_backend_dev_get(i);
    final name = native.ggml_backend_dev_name(device).cast<Utf8>();
    if (!name.toDartString().startsWith('MTL')) {
      continue;
    }
    final free = arena<Size>();
    final total = arena<Size>();
    native.ggml_backend_dev_memory(device, free, total);
    return total.value - free.value;
  }
  return 0;
});
