import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_calls.dart';

const _workerIsolateName = 'llamadart-image-generation';

// Byte offsets into the state block both isolates share.
const _enabled = 0;
const _cancelled = 1;
const _resume = 2;
const _missingInWorker = 3;
const _rejectLoad = 4;
const _videoOnly = 5;
const _throwInGenerate = 6;
const _holdStart = 7;
const _pauseAfter = 8;
const _loadReports = 12;
const _decodeReports = 16;
const _reportsPerRead = 20;
const _olderRelease = 24;
const _logEnabled = 25;
const _quietReject = 26;
const _holdLogDrain = 27;
const _racingReads = 28;
const _returnImagesDespiteError = 29;
const _controlNetLoaded = 30;
const _hideControlNet = 31;
const _latest = 32;
const _modelVersion = 40;
const _ring = 64;
const _ringSlots = 16384;
const _logState = _ring + _ringSlots * 8;
const _logThreshold = _logState;
const _logHistory = _logState + 4;
const _logLatest = _logState + 8;
const _logReadTo = _logState + 16;
const _logDropped = _logState + 24;
const _gpuCount = _logState + 32;
const _freeDelay = _logState + 36;
const _lastErrorLength = _logState + 56;
const _lastError = _logState + 64;
const _lastErrorBytes = 1024;
const _modelPath = _lastError + _lastErrorBytes;
const _modelPathBytes = 512;
const _fileRoles = [
  'model',
  'diffusionModel',
  'vae',
  'taesd',
  'clipL',
  'clipG',
  't5xxl',
  'llm',
  'controlNet',
];
const _logSlots = _modelPath + _modelPathBytes * 9;
const _logSlotCount = 256;
const _logSlotBytes = 512;
// One GPU: status and type as Int32, then total and free as Int64.
const _gpus = _logSlots + _logSlotCount * _logSlotBytes;
const _gpuBytes = 24;
const _maxGpus = 4;
const _generationErrorLength = _gpus + _maxGpus * _gpuBytes;
const _generationError = _generationErrorLength + 8;
const _generationErrorBytes = 1024;
const _conditioningCacheSize = _generationError + _generationErrorBytes;
const _vaeTiling = _conditioningCacheSize + 4;
const _imageInput = (_vaeTiling + 39) & ~7;
const _imageInputBytes = 96;
const _controlInput = _imageInput + _imageInputBytes * 2;
const _controlInputBytes = 48;
const _loadsFp8AsF16OnMetal = _controlInput + _controlInputBytes * 2;
const _intrinsicTinyPolicy = _loadsFp8AsF16OnMetal + 1;
const _intrinsicTinyMissingWorker = _loadsFp8AsF16OnMetal + 2;
// Hires: enabled and ignore flags as bytes, then upscaler, target width and
// height and steps as Int32, strength and scale as Float, the custom sigma
// count as Int32 and the upscaler model path address as Int64.
const _hires = _loadsFp8AsF16OnMetal + 8;
const _hiresBytes = 40;
// References at entry and after the held start: the count, then width,
// height, channels, sum and position-weighted sum of the first
// [_recordedReferences] references, all as Int64.
const _referenceInput = _hires + _hiresBytes;
const _recordedReferences = 2;
const _referenceInputBytes = 8 + _recordedReferences * 5 * 8;
// `ref_image_args`: its length as Int32 (-1 for a null pointer), then up to
// [_referenceArgsBytes] UTF-8 bytes.
const _referenceArgs = _referenceInput + _referenceInputBytes * 2;
const _referenceArgsBytes = 64;
const _stateBytes = _referenceArgs + 4 + _referenceArgsBytes;

// sd_log_level_t.
const _sdLogDebug = 0;
const _sdLogInfo = 2;
const _sdLogError = 4;

/// A stand-in for the stable_diffusion runtime, shared by the two isolates of
/// a `StableDiffusionImageWorker`.
///
/// It records every call made through [resolver] with the isolate that made
/// it, and reports progress the way stable-diffusion.cpp does: a generation
/// clears a pending cancel when it starts, samples every image of a batch
/// (`0/steps` when a pass starts, `k/steps` after step `k`) and only then
/// decodes, and looks at a cancel before each step and before each decode.
/// Like the real recorder it numbers reports from 1 for the whole process and
/// keeps the [history] most recent ones.
///
/// It logs the way the runtime of `StableDiffusionCalls.optionalNativeRelease`
/// does once its recorder is enabled: a load logs the file it loads at
/// `SD_LOG_INFO` and why it failed at `SD_LOG_ERROR`, and a generation logs
/// one `SD_LOG_DEBUG` and one `SD_LOG_INFO` message. Messages below the level
/// set are not recorded, and the oldest ones leave when more than
/// `logHistory` are kept.
final class FakeStableDiffusionRuntime {
  /// Creates a runtime that keeps [history] progress reports and [logHistory]
  /// log messages.
  FakeStableDiffusionRuntime({
    this.history = StableDiffusionCalls.progressHistory,
    int logHistory = 64,
  }) : _state = calloc<Uint8>(_stateBytes) {
    _state.cast<Int32>()[_pauseAfter ~/ 4] = -1;
    _state.cast<Int32>()[_logThreshold ~/ 4] = _sdLogInfo;
    _state.cast<Int32>()[_logHistory ~/ 4] = logHistory;
    _state.cast<Int32>()[_gpuCount ~/ 4] = -2;
    _state.cast<Int32>()[_generationErrorLength ~/ 4] = -1;
    final version = 'SD 2.x'.codeUnits;
    for (var i = 0; i < version.length; i++) {
      _state[_modelVersion + i] = version[i];
    }
    _port = RawReceivePort(_received, 'fake-stable-diffusion-calls');
  }

  /// Reports the runtime keeps.
  final int history;

  /// Last tiling tuple received by the guarded native generation call.
  (bool, int, int, double, double, double) get lastVaeTiling => (
    _state[_vaeTiling] != 0,
    _state.cast<Int32>()[(_vaeTiling + 4) ~/ 4],
    _state.cast<Int32>()[(_vaeTiling + 8) ~/ 4],
    (_state + _vaeTiling + 12).cast<Float>().value,
    (_state + _vaeTiling + 16).cast<Float>().value,
    (_state + _vaeTiling + 20).cast<Float>().value,
  );

  final Pointer<Uint8> _state;
  late final RawReceivePort _port;
  final List<(String, String)> _calls = [];

  /// Input dimensions and checksums at entry and after the held native start.
  /// Values are read in the worker from native pointers, not the Dart request.
  List<num> imageInputSnapshot({bool afterHold = false}) {
    final offset = _imageInput + (afterHold ? _imageInputBytes : 0);
    return [
      for (var i = 0; i < 10; i++)
        (_state + offset + i * 8).cast<Int64>().value,
      (_state + offset + 80).cast<Double>().value,
    ];
  }

  /// ControlNet image dimensions, checksums and strength at entry and after
  /// the held native start, read in the worker from the native struct.
  List<num> controlInputSnapshot({bool afterHold = false}) {
    final offset = _controlInput + (afterHold ? _controlInputBytes : 0);
    return [
      for (var i = 0; i < 5; i++) (_state + offset + i * 8).cast<Int64>().value,
      (_state + offset + 40).cast<Double>().value,
    ];
  }

  /// The reference count, then width, height, channels, checksum and
  /// position-weighted checksum of each of the first two references, at
  /// entry and after the held native start, read in the worker from the
  /// native array.
  List<int> referenceInputSnapshot({bool afterHold = false}) {
    final offset = _referenceInput + (afterHold ? _referenceInputBytes : 0);
    return [
      for (var i = 0; i < _referenceInputBytes ~/ 8; i++)
        (_state + offset + i * 8).cast<Int64>().value,
    ];
  }

  /// The `ref_image_args` the guarded generation received last, or `null`
  /// for a null pointer.
  String? get lastReferenceArgs {
    final length = _state.cast<Int32>()[_referenceArgs ~/ 4];
    return length < 0
        ? null
        : utf8.decode((_state + _referenceArgs + 4).asTypedList(length));
  }

  /// Makes `sd_ctx_has_control_net` answer false although the load named a
  /// ControlNet, as a runtime that skipped it would.
  set hideControlNet(bool value) => _state[_hideControlNet] = value ? 1 : 0;

  /// The hires-fix fields the guarded generation received last: enabled,
  /// upscaler, target width and height, steps, denoising strength, scale,
  /// custom sigma count and model path address.
  (bool, int, int, int, int, double, double, int, int) get lastHires => (
    _state[_hires] != 0,
    _state.cast<Int32>()[(_hires + 4) ~/ 4],
    _state.cast<Int32>()[(_hires + 8) ~/ 4],
    _state.cast<Int32>()[(_hires + 12) ~/ 4],
    _state.cast<Int32>()[(_hires + 16) ~/ 4],
    (_state + _hires + 20).cast<Float>().value,
    (_state + _hires + 24).cast<Float>().value,
    _state.cast<Int32>()[(_hires + 28) ~/ 4],
    (_state + _hires + 32).cast<Int64>().value,
  );

  /// Makes a generation skip an enabled hires pass and return first-pass
  /// images as success, as the runtime does after disabling a hires fix it
  /// cannot apply.
  set ignoreHires(bool value) => _state[_hires + 1] = value ? 1 : 0;

  /// What `sd_get_model_version_name` answers; `SD 2.x` at first.
  set modelVersion(String value) {
    final bytes = utf8.encode(value);
    (_state + _modelVersion).asTypedList(24)
      ..fillRange(0, 24, 0)
      ..setAll(0, bytes);
  }

  /// Completes when the native stand-in has copied its entry observation.
  Future<void> imageInputHeld() => _next('image-input-held');

  final List<(String, Completer<void>)> _waiting = [];
  final List<String> _arrived = [];
  int _flushes = 0;

  /// What a worker resolves its native calls with, in either isolate.
  StableDiffusionCalls? Function() get resolver =>
      _FakeCalls(_state.address, _port.sendPort, history).resolve;

  /// Makes [resolver] return `null` in the worker isolate only.
  set missingInWorker(bool value) => _state[_missingInWorker] = value ? 1 : 0;

  /// Makes the load fail.
  set rejectLoad(bool value) => _state[_rejectLoad] = value ? 1 : 0;

  /// Makes a failed load log no error.
  set quietReject(bool value) => _state[_quietReject] = value ? 1 : 0;

  /// Holds the next drain of the log in the worker isolate that reads it
  /// once it has read its messages, before it sends them, until
  /// [releaseLogDrain]. [logDrainHeld] completes when it is held.
  void holdNextLogDrain() => _state[_holdLogDrain] = 1;

  /// Completes when the drain [holdNextLogDrain] asked for is held.
  Future<void> logDrainHeld() => _next('log-drain-held');

  /// Lets the held drain send what it read.
  void releaseLogDrain() => _state[_holdLogDrain] = 0;

  /// Makes [resolver] return the calls of a runtime older than
  /// `StableDiffusionCalls.optionalNativeRelease`: no log and no device
  /// memory.
  set olderRelease(bool value) => _state[_olderRelease] = value ? 1 : 0;

  /// Makes [resolver] return the calls of a runtime that loads FP8 weights
  /// as F16 on Metal, as `StableDiffusionCalls.fp8MetalNativeRelease` does.
  set supportsIntrinsicTinyDecoderV1(bool value) =>
      _state[_intrinsicTinyPolicy] = value ? 1 : 0;
  set intrinsicTinyMissingInWorker(bool value) =>
      _state[_intrinsicTinyMissingWorker] = value ? 1 : 0;

  set loadsFp8AsF16OnMetal(bool value) =>
      _state[_loadsFp8AsF16OnMetal] = value ? 1 : 0;

  /// The GPUs the runtime lists: device `i` is `Vulkan<i>`, a `Fake GPU <i>`,
  /// with its total and free bytes, and `sd_dart_gpu_device_memory` answers
  /// its status when that is not 0. Past the last one it answers
  /// `SD_DART_GPU_NO_DEVICE`.
  set gpus(List<({int total, int free, bool integrated, int status})> devices) {
    _state.cast<Int32>()[_gpuCount ~/ 4] = devices.length;
    for (final (index, device) in devices.indexed) {
      final entry = _state + _gpus + index * _gpuBytes;
      entry.cast<Int32>()[0] = device.status;
      entry.cast<Int32>()[1] = device.integrated ? 2 : 1;
      entry.cast<Int64>()[1] = device.total;
      entry.cast<Int64>()[2] = device.free;
    }
  }

  /// What `sd_dart_gpu_device_count` answers instead of a count:
  /// `SD_DART_GPU_NO_BACKEND` at first.
  set gpuCountStatus(int status) =>
      _state.cast<Int32>()[_gpuCount ~/ 4] = status;

  /// One GPU, as [gpus].
  void setGpuMemory({
    int status = 0,
    int total = 0,
    int free = 0,
    bool integrated = false,
  }) => gpus = [
    (total: total, free: free, integrated: integrated, status: status),
  ];

  /// Adds [count] to the messages the runtime dropped without recording
  /// one, as a recorder that could not take its buffer in time does.
  void dropUnrecorded(int count) =>
      _state.cast<Int64>()[_logDropped ~/ 8] += count;

  /// The model path the last load read from its context parameters, or an
  /// empty string when they had none.
  String get loadedModelPath =>
      Pointer<Utf8>.fromAddress(_state.address + _modelPath).toDartString();

  /// Conditioning capacity read by the worker's native load.
  int get loadedConditioningCacheSize =>
      _state.cast<Int32>()[_conditioningCacheSize ~/ 4];

  /// Non-null file paths read from the last load's native parameters.
  Map<String, String> get loadedFiles => {
    for (final (index, role) in _fileRoles.indexed)
      if (Pointer<Utf8>.fromAddress(
            _state.address + _modelPath + index * _modelPathBytes,
          ).toDartString()
          case final path when path.isNotEmpty)
        role: path,
  };

  /// Records [bytes] as a log message at `sd_log_level_t` [level], as a
  /// thread of the runtime does.
  void log(int level, List<int> bytes) => _FakeCalls(
    _state.address,
    _port.sendPort,
    history,
  )._logMessage(level, bytes);

  /// Makes the loaded model one that cannot generate images.
  set videoOnly(bool value) => _state[_videoOnly] = value ? 1 : 0;

  /// Makes a generation throw a Dart error in the worker. The worker records
  /// `uncaught generation error`, with how it holds its context, when the
  /// error ends it.
  set throwInGenerate(bool value) => _state[_throwInGenerate] = value ? 1 : 0;

  /// Makes every generation fail after logging [errors] at `SD_LOG_ERROR`,
  /// which `sd_dart_last_error` then returns, as the runtime does for the
  /// errors of a call; `null` lets generations succeed again.
  set generationErrors(String? errors) {
    final bytes = utf8.encode(errors ?? '');
    _state.cast<Int32>()[_generationErrorLength ~/ 4] = errors == null
        ? -1
        : bytes.length;
    (_state + _generationError).asTypedList(bytes.length).setAll(0, bytes);
  }

  /// Returns an image even after recording [generationErrors], as an older
  /// native runtime can when upstream ignores a failed Metal command buffer.
  set returnImagesDespiteError(bool value) =>
      _state[_returnImagesDespiteError] = value ? 1 : 0;

  /// Keeps a generation from starting, so from clearing a pending cancel,
  /// while it is set.
  set holdStart(bool value) => _state[_holdStart] = value ? 1 : 0;

  /// Pauses a generation once it has reported this many times (0 pauses it
  /// right after it starts), until [resume]; `-1` never pauses.
  set pauseAfter(int reports) =>
      _state.cast<Int32>()[_pauseAfter ~/ 4] = reports;

  /// Reports a load records.
  set loadReports(int count) => _state.cast<Int32>()[_loadReports ~/ 4] = count;

  /// Tile reports the decode of a batch records.
  set decodeReports(int count) =>
      _state.cast<Int32>()[_decodeReports ~/ 4] = count;

  /// Reports recorded during each of the next 200 reads that ask for some,
  /// as a runtime that reports faster than its reader reads does.
  set reportsPerRead(int count) {
    _state.cast<Int32>()[_reportsPerRead ~/ 4] = count;
    _state.cast<Int32>()[_racingReads ~/ 4] = 200;
  }

  /// Whether a cancel is pending.
  bool get cancelPending => _state[_cancelled] != 0;

  /// Lets a paused generation continue.
  void resume() => _state[_resume] = 1;

  /// How long the worker's explicit context free takes.
  set freeDelay(Duration delay) =>
      _state.cast<Int32>()[_freeDelay ~/ 4] = delay.inMilliseconds;

  /// Names of the calls [isolate] (`caller` or `worker`) made so far that
  /// have arrived here; await [flush] first.
  List<String> calls(String isolate) => [
    for (final (from, name) in _calls)
      if (from == isolate) name,
  ];

  /// Forgets the calls recorded so far.
  void clearCalls() => _calls.clear();

  /// Completes when the worker reports that [generation] is paused, and
  /// fails when it ends without pausing.
  Future<void> pausedIn(Future<Object?> generation) => Future.any([
    _next('paused'),
    generation.then(
      (_) => throw StateError('The generation ended without pausing.'),
    ),
  ]);

  /// Completes once every call made before this one has arrived.
  Future<void> flush() {
    final marker = 'flush-${_flushes++}';
    final arrived = _next(marker);
    _port.sendPort.send(('signal', marker));
    return arrived;
  }

  /// Frees the state. Call after the worker is disposed.
  void close() {
    _port.close();
    calloc.free(_state);
  }

  Future<void> _next(String name) {
    if (_arrived.remove(name)) {
      return Future.value();
    }
    final completer = Completer<void>();
    _waiting.add((name, completer));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  void _received(Object? message) {
    final (isolate, name) = message! as (String, String);
    if (isolate != 'signal') {
      _calls.add((isolate, name));
      return;
    }
    final waiting = _waiting.indexWhere((entry) => entry.$1 == name);
    if (waiting >= 0) {
      _waiting.removeAt(waiting).$2.complete();
    } else {
      _arrived.add(name);
    }
  }
}

final class _FakeCalls {
  const _FakeCalls(this._stateAddress, this._log, this._history);

  final int _stateAddress;
  final SendPort _log;
  final int _history;

  Pointer<Uint8> get _state => Pointer.fromAddress(_stateAddress);
  Pointer<Int32> get _ints => _state.cast();
  Pointer<Uint64> get _latestSequence =>
      Pointer.fromAddress(_stateAddress + _latest);

  bool get _inWorker => Isolate.current.debugName == _workerIsolateName;

  void _record(String name) =>
      _log.send((_inWorker ? 'worker' : 'caller', name));

  /// How the worker isolate holds its context for its own shutdown.
  String get _held {
    final held = IsolateShutdownReleases.current.debugHeldForTesting;
    if (held.isEmpty) {
      return '';
    }
    final expected =
        held.length == 1 &&
        held.single.free == malloc.nativeFree &&
        held.single.stage == ShutdownStage.model;
    return expected ? '+held' : '+held-wrong';
  }

  Pointer<Int64> get _longs => _state.cast();

  Pointer<Uint8> _logSlot(int sequence) =>
      _state + _logSlots + (sequence % _logSlotCount) * _logSlotBytes;

  /// Records a message when the recorder is enabled and [level] reaches the
  /// level set. The oldest message kept leaves when there are too many, and
  /// counts as dropped when no read had reached it.
  void _logMessage(int level, List<int> bytes) {
    if (_state[_logEnabled] == 0 || level < _ints[_logThreshold ~/ 4]) {
      return;
    }
    final sequence = ++_longs[_logLatest ~/ 8];
    final slot = _logSlot(sequence);
    slot.cast<Int32>()[0] = level;
    slot.cast<Int32>()[1] = bytes.length;
    (slot + 8).asTypedList(bytes.length).setAll(0, bytes);
    final gone = sequence - _ints[_logHistory ~/ 4];
    if (gone > _longs[_logReadTo ~/ 8]) {
      _longs[_logDropped ~/ 8]++;
    }
  }

  void _logText(int level, String text) =>
      _logMessage(level, utf8.encode(text));

  int _logRead(
    int after,
    Pointer<Char> text,
    int capacity,
    Pointer<Int32> level,
    Pointer<Size> length,
  ) {
    _record('sd_dart_log_read');
    final newest = _longs[_logLatest ~/ 8];
    final oldest = newest - _ints[_logHistory ~/ 4] + 1;
    final sequence = after + 1 > oldest ? after + 1 : oldest;
    if (sequence > newest) {
      return 0;
    }
    final slot = _logSlot(sequence);
    final size = slot.cast<Int32>()[1];
    final copied = size < capacity ? size : capacity - 1;
    text.cast<Uint8>().asTypedList(capacity)
      ..setRange(0, copied, (slot + 8).asTypedList(copied))
      ..[copied] = 0;
    level.value = slot.cast<Int32>()[0];
    if (length != nullptr) {
      length.value = size;
    }
    if (sequence > _longs[_logReadTo ~/ 8]) {
      _longs[_logReadTo ~/ 8] = sequence;
    }
    return sequence;
  }

  int _readLastError(Pointer<Char> text, int capacity) {
    _record('sd_dart_last_error');
    final size = _ints[_lastErrorLength ~/ 4];
    text.cast<Uint8>().asTypedList(capacity)
      ..setRange(0, size, (_state + _lastError).asTypedList(size))
      ..[size] = 0;
    return size;
  }

  int _gpuDeviceMemory(
    int deviceIndex,
    Pointer<sd.sd_dart_gpu_device_memory_t> out,
  ) {
    _record(
      _state[_logEnabled] != 0
          ? 'sd_dart_gpu_device_memory:$deviceIndex'
          : 'sd_dart_gpu_device_memory:$deviceIndex:before-log-enable',
    );
    if (deviceIndex < 0 || deviceIndex >= _ints[_gpuCount ~/ 4]) {
      return -3;
    }
    final entry = _state + _gpus + deviceIndex * _gpuBytes;
    final status = entry.cast<Int32>()[0];
    if (status != 0) {
      return status;
    }
    out.ref
      ..total_bytes = entry.cast<Int64>()[1]
      ..free_bytes = entry.cast<Int64>()[2]
      ..type = entry.cast<Int32>()[1];
    for (final (index, unit) in 'Vulkan$deviceIndex\x00'.codeUnits.indexed) {
      out.ref.name[index] = unit;
    }
    for (final (index, unit) in 'Fake GPU $deviceIndex\x00'.codeUnits.indexed) {
      out.ref.description[index] = unit;
    }
    return 0;
  }

  int _gpuDeviceCount() {
    _record(
      _state[_logEnabled] != 0
          ? 'sd_dart_gpu_device_count'
          : 'sd_dart_gpu_device_count:before-log-enable',
    );
    return _ints[_gpuCount ~/ 4];
  }

  Pointer<sd.sd_ctx_t> _newContext(Pointer<sd.sd_ctx_params_t> params) {
    _record(
      _state[_enabled] != 0
          ? 'sd_dart_new_sd_ctx'
          : 'sd_dart_new_sd_ctx:before-enable',
    );
    _ints[_conditioningCacheSize ~/ 4] = params.ref.conditioning_cache_size;
    final modelPath = params.ref.model_path == nullptr
        ? ''
        : params.ref.model_path.cast<Utf8>().toDartString();
    final paths = [
      params.ref.model_path,
      params.ref.diffusion_model_path,
      params.ref.vae_path,
      params.ref.taesd_path,
      params.ref.clip_l_path,
      params.ref.clip_g_path,
      params.ref.t5xxl_path,
      params.ref.llm_path,
      params.ref.control_net_path,
    ];
    _state[_controlNetLoaded] = params.ref.control_net_path == nullptr ? 0 : 1;
    for (final (index, path) in paths.indexed) {
      (_state + _modelPath + index * _modelPathBytes).asTypedList(
          _modelPathBytes,
        )
        ..fillRange(0, _modelPathBytes, 0)
        ..setAll(
          0,
          path == nullptr
              ? const <int>[]
              : utf8.encode(path.cast<Utf8>().toDartString()),
        );
    }
    _ints[_lastErrorLength ~/ 4] = 0;
    _logText(
      _sdLogInfo,
      "stable-diffusion.cpp:262 - loading model from '$modelPath'",
    );
    if (_state[_rejectLoad] != 0) {
      if (_state[_quietReject] == 0 && _state[_logEnabled] != 0) {
        final error = utf8.encode(
          "model_loader.cpp:1061 - cannot inspect model source '$modelPath': "
          'No such file or directory',
        );
        _logMessage(_sdLogError, error);
        _ints[_lastErrorLength ~/ 4] = error.length;
        (_state + _lastError).asTypedList(error.length).setAll(0, error);
      }
      return nullptr;
    }
    final reports = _ints[_loadReports ~/ 4];
    for (var i = 1; i <= reports; i++) {
      _report(i, reports);
    }
    return malloc<Uint8>(16).cast();
  }

  void _report(int step, int steps) {
    final sequence = _latestSequence.value + 1;
    final slot = Pointer<Int32>.fromAddress(
      _stateAddress + _ring + (sequence % _ringSlots) * 8,
    );
    slot[0] = step;
    slot[1] = steps;
    _latestSequence.value = sequence;
  }

  StableDiffusionCalls? resolve() {
    if (_inWorker && _state[_missingInWorker] != 0) {
      return null;
    }
    return StableDiffusionCalls(
      progressEnable: () {
        _record('sd_dart_progress_enable');
        _state[_enabled] = 1;
      },
      progressRead: _progressRead,
      newContext: _newContext,
      newContextIntrinsicTinyV1:
          _state[_intrinsicTinyPolicy] != 0 &&
              !(_inWorker && _state[_intrinsicTinyMissingWorker] != 0)
          ? (params) {
              _record('sd_dart_new_sd_ctx_intrinsic_tiny_v1');
              return _newContext(params);
            }
          : null,
      generateImage: _generateImage,
      cancelGeneration: (context) {
        _record('sd_dart_cancel_generation');
        _state[_cancelled] = 1;
      },
      exitFree: (context) {
        _record('sd_dart_exit_free$_held');
        sleep(Duration(milliseconds: _ints[_freeDelay ~/ 4]));
        malloc.free(context);
      },
      exitFreeAddress: malloc.nativeFree,
      contextParamsInit: (params) {
        _record('sd_ctx_params_init');
        // What sd_ctx_params_init leaves, whatever the caller wrote before.
        params.ref.model_path = nullptr;
        params.ref.conditioning_cache_size = 4;
      },
      supportsImageGeneration: (context) {
        _record('sd_ctx_supports_image_generation$_held');
        return _state[_videoOnly] == 0;
      },
      hasControlNet: (context) {
        _record('sd_ctx_has_control_net$_held');
        return _state[_controlNetLoaded] != 0 && _state[_hideControlNet] == 0;
      },
      modelVersionName: (context) {
        _record('sd_get_model_version_name$_held');
        return Pointer.fromAddress(_stateAddress + _modelVersion);
      },
      imageGenerationParamsInit: (params) =>
          _record('sd_img_gen_params_init$_held'),
      freeImages: (images, count) {
        _record('free_sd_images$_held');
        for (var i = 0; i < count; i++) {
          malloc.free(images[i].data);
        }
        malloc.free(images);
      },
      loadsFp8AsF16OnMetal: _state[_loadsFp8AsF16OnMetal] != 0,
      log: _state[_olderRelease] != 0
          ? null
          : StableDiffusionLogCalls(
              enable: () {
                _record('sd_dart_log_enable');
                _state[_logEnabled] = 1;
              },
              setLevel: (level) {
                _record('sd_dart_log_set_level:$level');
                _ints[_logThreshold ~/ 4] = level;
              },
              read: _logRead,
              dropped: () {
                _record('sd_dart_log_dropped');
                final dropped = _longs[_logDropped ~/ 8];
                // The last call of a drain, so what it read is settled.
                if (_inWorker && _state[_holdLogDrain] == 1) {
                  _state[_holdLogDrain] = 2;
                  _log.send(('signal', 'log-drain-held'));
                  _waitWhile(() => _state[_holdLogDrain] == 2);
                }
                return dropped;
              },
              lastError: _readLastError,
            ),
      gpu: _state[_olderRelease] != 0
          ? null
          : StableDiffusionGpuCalls(
              deviceCount: _gpuDeviceCount,
              deviceMemory: _gpuDeviceMemory,
            ),
    );
  }

  int _progressRead(
    int after,
    Pointer<sd.sd_dart_progress_t> reports,
    int capacity,
    Pointer<Uint64> latest,
  ) {
    if (capacity == 0) {
      _record('sd_dart_progress_read:mark');
    } else {
      _record('sd_dart_progress_read');
      final racing = _ints[_reportsPerRead ~/ 4];
      if (racing > 0 && _ints[_racingReads ~/ 4]-- > 0) {
        for (var i = 1; i <= racing; i++) {
          _report(i, racing);
        }
      }
    }
    final newest = _latestSequence.value;
    if (latest != nullptr) {
      latest.value = newest;
    }
    final oldest = newest - _history + 1;
    var sequence = after + 1 > oldest ? after + 1 : oldest;
    var count = 0;
    while (count < capacity && sequence <= newest) {
      final slot = Pointer<Int32>.fromAddress(
        _stateAddress + _ring + (sequence % _ringSlots) * 8,
      );
      reports[count]
        ..sequence = sequence
        ..step = slot[0]
        ..steps = slot[1]
        ..time = 0;
      count++;
      sequence++;
    }
    return count;
  }

  void _waitWhile(bool Function() blocked) {
    final waited = Stopwatch()..start();
    while (blocked()) {
      if (waited.elapsed > const Duration(seconds: 10)) {
        throw StateError('The fake generation was never released.');
      }
      sleep(const Duration(milliseconds: 1));
    }
  }

  bool _generateImage(
    Pointer<sd.sd_ctx_t> context,
    Pointer<sd.sd_img_gen_params_t> params,
    Pointer<Pointer<sd.sd_image_t>> imagesOut,
    Pointer<Int> countOut,
  ) {
    _record('sd_dart_generate_image$_held');
    final tiling = params.ref.vae_tiling_params;
    _state[_vaeTiling] = tiling.enabled ? 1 : 0;
    _ints[(_vaeTiling + 4) ~/ 4] = tiling.tile_size_w;
    _ints[(_vaeTiling + 8) ~/ 4] = tiling.tile_size_h;
    (_state + _vaeTiling + 12).cast<Float>().value = tiling.target_overlap;
    (_state + _vaeTiling + 16).cast<Float>().value = tiling.rel_size_w;
    (_state + _vaeTiling + 20).cast<Float>().value = tiling.rel_size_h;
    final hires = params.ref.hires;
    _state[_hires] = hires.enabled ? 1 : 0;
    _ints[(_hires + 4) ~/ 4] = hires.upscalerAsInt;
    _ints[(_hires + 8) ~/ 4] = hires.target_width;
    _ints[(_hires + 12) ~/ 4] = hires.target_height;
    _ints[(_hires + 16) ~/ 4] = hires.steps;
    (_state + _hires + 20).cast<Float>().value = hires.denoising_strength;
    (_state + _hires + 24).cast<Float>().value = hires.scale;
    _ints[(_hires + 28) ~/ 4] = hires.custom_sigmas_count;
    (_state + _hires + 32).cast<Int64>().value = hires.model_path.address;
    _logText(_sdLogDebug, 'stable-diffusion.cpp:3120 - sampling');
    _logText(_sdLogInfo, 'stable-diffusion.cpp:3391 - generating');
    imagesOut.value = nullptr;
    countOut.value = 0;
    _ints[_lastErrorLength ~/ 4] = 0;
    void recordImageInput(bool afterHold) {
      final offset = _imageInput + (afterHold ? _imageInputBytes : 0);
      var field = 0;
      for (final image in [params.ref.init_image, params.ref.mask_image]) {
        var sum = 0;
        var weighted = 0;
        if (image.data != nullptr) {
          final length = image.width * image.height * image.channel;
          final bytes = image.data.asTypedList(length);
          for (var i = 0; i < length; i++) {
            sum += bytes[i];
            weighted += bytes[i] * (i + 1);
          }
        }
        for (final value in [
          image.width,
          image.height,
          image.channel,
          sum,
          weighted,
        ]) {
          (_state + offset + field++ * 8).cast<Int64>().value = value;
        }
      }
      (_state + offset + 80).cast<Double>().value = params.ref.strength;
      final controlOffset =
          _controlInput + (afterHold ? _controlInputBytes : 0);
      final control = params.ref.control_image;
      var sum = 0;
      var weighted = 0;
      if (control.data != nullptr) {
        final length = control.width * control.height * control.channel;
        final bytes = control.data.asTypedList(length);
        for (var i = 0; i < length; i++) {
          sum += bytes[i];
          weighted += bytes[i] * (i + 1);
        }
      }
      for (final (index, value) in [
        control.width,
        control.height,
        control.channel,
        sum,
        weighted,
      ].indexed) {
        (_state + controlOffset + index * 8).cast<Int64>().value = value;
      }
      (_state + controlOffset + 40).cast<Double>().value =
          params.ref.control_strength;
      final referenceOffset =
          _referenceInput + (afterHold ? _referenceInputBytes : 0);
      final count = params.ref.ref_images_count;
      (_state + referenceOffset).cast<Int64>().value = count;
      for (var index = 0; index < _recordedReferences; index++) {
        var values = const [0, 0, 0, 0, 0];
        if (index < count) {
          final image = params.ref.ref_images[index];
          final length = image.width * image.height * image.channel;
          final bytes = image.data.asTypedList(length);
          var sum = 0;
          var weighted = 0;
          for (var i = 0; i < length; i++) {
            sum += bytes[i];
            weighted += bytes[i] * (i + 1);
          }
          values = [image.width, image.height, image.channel, sum, weighted];
        }
        for (final (field, value) in values.indexed) {
          (_state + referenceOffset + 8 + (index * 5 + field) * 8)
                  .cast<Int64>()
                  .value =
              value;
        }
      }
    }

    final args = params.ref.ref_image_args;
    if (args == nullptr) {
      _ints[_referenceArgs ~/ 4] = -1;
    } else {
      final bytes = utf8.encode(args.cast<Utf8>().toDartString());
      final length = bytes.length.clamp(0, _referenceArgsBytes);
      _ints[_referenceArgs ~/ 4] = length;
      (_state + _referenceArgs + 4)
          .asTypedList(length)
          .setAll(0, bytes.take(length));
    }
    recordImageInput(false);
    if (_state[_holdStart] != 0) _log.send(('signal', 'image-input-held'));
    _waitWhile(() => _state[_holdStart] != 0);
    recordImageInput(true);
    _state[_cancelled] = 0;
    if (_state[_throwInGenerate] != 0) {
      throw _GenerationFailure(this);
    }
    final errorLength = _ints[_generationErrorLength ~/ 4];
    if (errorLength >= 0) {
      final errors = (_state + _generationError).asTypedList(errorLength);
      for (final line in utf8.decode(errors).split('\n')) {
        _logText(_sdLogError, line);
      }
      if (_state[_logEnabled] != 0) {
        _ints[_lastErrorLength ~/ 4] = errorLength;
        (_state + _lastError).asTypedList(errorLength).setAll(0, errors);
      }
      if (_state[_returnImagesDespiteError] == 0) return false;
    }
    final steps = params.ref.sample_params.sample_steps;
    final images = params.ref.batch_count;
    final pauseAfter = _ints[_pauseAfter ~/ 4];
    var reported = 0;
    void pauseAt(int count) {
      if (count != pauseAfter) {
        return;
      }
      _log.send(('signal', 'paused'));
      _waitWhile(() => _state[_resume] == 0);
      _state[_resume] = 0;
    }

    void report(int step, int total) {
      _report(step, total);
      pauseAt(++reported);
    }

    pauseAt(0);
    for (var image = 0; image < images; image++) {
      report(0, steps);
      for (var step = 1; step <= steps; step++) {
        if (_state[_cancelled] != 0) {
          return false;
        }
        report(step, steps);
      }
    }
    final refines = hires.enabled && _state[_hires + 1] == 0;
    if (refines) {
      for (var image = 0; image < images; image++) {
        if (_state[_cancelled] != 0) {
          return false;
        }
        report(0, hires.steps);
        for (var step = 1; step <= hires.steps; step++) {
          if (_state[_cancelled] != 0) {
            return false;
          }
          report(step, hires.steps);
        }
      }
    }
    if (_state[_cancelled] != 0) {
      return false;
    }
    final tiles = _ints[_decodeReports ~/ 4];
    for (var tile = 1; tile <= tiles; tile++) {
      report(tile, tiles);
    }

    final width = refines ? hires.target_width : params.ref.width;
    final height = refines ? hires.target_height : params.ref.height;
    final result = malloc<sd.sd_image_t>(images);
    for (var image = 0; image < images; image++) {
      final length = width * height * 3;
      final data = malloc<Uint8>(length);
      data.asTypedList(length).fillRange(0, length, image + 1);
      result[image]
        ..width = width
        ..height = height
        ..channel = 3
        ..data = data;
    }
    imagesOut.value = result;
    countOut.value = images;
    return true;
  }
}

/// Records how the worker holds its context when the VM reports this error
/// as uncaught, which is after any handler of the worker ran.
final class _GenerationFailure extends Error {
  _GenerationFailure(this._calls);

  final _FakeCalls _calls;

  @override
  String toString() {
    _calls._record('uncaught generation error${_calls._held}');
    return 'The fake generation failed.';
  }
}

/// The progress timers a worker started, which a test fires by hand.
final class ManualProgressTimers {
  /// Intervals of the timers started so far.
  final List<Duration> intervals = [];

  final List<_ManualTimer> _timers = [];

  /// Timers started and not cancelled.
  int get active => _timers.where((timer) => timer.isActive).length;

  /// Starts a timer that fires only on [poll].
  Timer start(Duration interval, void Function(Timer timer) poll) {
    intervals.add(interval);
    final timer = _ManualTimer(poll);
    _timers.add(timer);
    return timer;
  }

  /// Fires the one active timer once.
  void poll() {
    final timer = _timers.singleWhere((timer) => timer.isActive);
    timer._poll(timer);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this._poll);

  final void Function(Timer timer) _poll;

  @override
  bool isActive = true;

  @override
  int get tick => 0;

  @override
  void cancel() => isActive = false;
}
