import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';

import '../../core/exceptions.dart';
import '../../core/image/generated_image.dart';
import '../../core/image/image_control_net_request.dart';
import '../../core/image/image_editing_request.dart';
import '../../core/image/image_generation_driver.dart';
import '../../core/image/image_generation_request.dart';
import '../../core/image/image_hires_fix_request.dart';
import '../../core/image/image_reference_editing_request.dart';
import '../../core/image/image_model_metal_preflight.dart';
import '../../core/llama_logger.dart';
import '../../core/models/config/log_level.dart';
import '../isolate_shutdown_releases.dart';
import '../worker_log_message.dart';
import 'stable_diffusion_bindings.dart' as sd;
import 'stable_diffusion_calls.dart';
import 'stable_diffusion_log.dart';
import 'stable_diffusion_memory.dart';
import 'stable_diffusion_params.dart';

/// Resolves the native calls of a worker; `null` when the runtime lacks them.
typedef StableDiffusionCallsResolver = StableDiffusionCalls? Function();

/// Starts the timer that polls progress during a generation.
typedef StableDiffusionProgressTimer =
    Timer Function(Duration interval, void Function(Timer timer) poll);

/// One stable-diffusion.cpp context running in a dedicated worker isolate.
///
/// Loading and `generate_image` block, so both run in the worker. The runtime
/// records its progress reports and the calling isolate reads them on a
/// timer: Dart gives stable-diffusion.cpp no callback, because a callback
/// from the generating thread into a VM that is shutting down aborts the
/// process. Cancellation calls `sd_dart_cancel_generation` from the calling
/// isolate, since the worker is blocked inside the generation.
///
/// The runtime's log is read without a callback too, but by the worker: a
/// read can wait 100 ms, which the calling isolate must not. The worker reads
/// what the runtime recorded after its load, after each generation and when
/// it is disposed, and sends it to the calling isolate, which logs it through
/// [LlamaLogger]. On a runtime without [StableDiffusionCalls.log] nothing is
/// read.
///
/// Only a pending reply keeps the calling isolate alive, so a program that
/// ends with a model loaded exits; the worker then frees the model as it shuts
/// down.
final class StableDiffusionImageWorker
    implements
        ImageGenerationSession,
        ImageVaeTilingSession,
        ImageEditingSession,
        ImageControlNetSession,
        ImageHiresFixSession,
        ImageReferenceEditingSession {
  /// How often a running [generate] reads the recorded progress. A cancel
  /// that arrived before the runtime started generating is applied again at
  /// the same rate.
  static const Duration progressPollInterval = Duration(milliseconds: 50);

  /// Reports one read asks for.
  static const int _reportsPerRead = 64;

  /// Reads one poll makes at most, so a runtime that reports faster than the
  /// calling isolate reads cannot keep it in the poll. Together with
  /// [_reportsPerRead] it covers the reports the runtime keeps.
  static const int _readsPerPoll = 64;

  /// Where the workers of this isolate have read the runtime's log to. The
  /// log is the process's, so each read continues where the last one ended.
  static StableDiffusionLogPosition _logPosition = (after: 0, dropped: 0);

  /// Starts reading the log from its beginning again, for a test that
  /// replaces the runtime.
  static void debugResetLogPositionForTesting() =>
      _logPosition = (after: 0, dropped: 0);

  final Isolate _isolate;
  final _Replies _replies;
  final SendPort _commands;
  final StableDiffusionCalls _calls;
  final StableDiffusionProgressTimer _progressTimer;
  final Pointer<sd.sd_ctx_t> _context;
  final ImageGenerationSessionConfig _config;
  bool _cancelRequested = false;
  bool _disposed = false;
  bool _stopped = false;
  bool _backendFailed = false;
  Future<void>? _disposeStart;

  @override
  final String modelVersion;

  @override
  bool get supportsVaeTiling =>
      _config.vaeTilingRecipeVerified && modelVersion == 'SD 2.x';

  @override
  bool get supportsImageEditing =>
      _config.imageEditingRecipeVerified &&
      !_config.flashAttention &&
      !_config.vaeDirectConvolution &&
      modelVersion == 'SD 2.x';

  /// Whether the load named a ControlNet and the runtime reports it built
  /// one. Without the runtime's log a ControlNet compute failure would go
  /// unnoticed, so that is required too.
  @override
  bool get supportsControlNet =>
      _controlNetLoaded &&
      _calls.log != null &&
      _config.controlNetRecipeVerified &&
      !_config.flashAttention &&
      !_config.vaeDirectConvolution &&
      modelVersion == 'SD 1.x';

  @override
  bool get supportsHiresFix =>
      _config.hiresFixRecipeVerified &&
      imageHiresFixModelVersions.contains(modelVersion);

  @override
  bool get supportsReferenceImageEditing =>
      _config.referenceEditingRecipeVerified && modelVersion == 'Flux';

  final bool _controlNetLoaded;

  StableDiffusionImageWorker._(
    this._isolate,
    this._replies,
    this._commands,
    this._calls,
    this._progressTimer,
    this._context,
    this._config,
    this.modelVersion,
    this._controlNetLoaded,
  );

  /// Spawns a worker and loads [config] in it.
  ///
  /// [resolveCalls] runs once in the calling isolate and once in the worker;
  /// [progressTimer] starts the progress poll of each [generate]. Tests
  /// replace both.
  ///
  /// The runtime records its messages from [logLevel] up, and the worker
  /// forwards them to this isolate's [LlamaLogger]; at [LlamaLogLevel.none]
  /// nothing is recorded or read. The level is the process's: the worker
  /// started last sets it.
  ///
  /// Throws [LlamaModelException] when the runtime cannot load the files as
  /// an image model, with the runtime's reason when it gives one, and
  /// [LlamaUnsupportedException] when the runtime does not export the
  /// functions of [StableDiffusionCalls], or FP8 weights would reach Metal on
  /// a runtime without [StableDiffusionCalls.loadsFp8AsF16OnMetal]. On Apple
  /// platforms an unspecified backend may select Metal; use `cpu` explicitly
  /// for FP8 weights there. That preflight inspects every regular file before
  /// any native context is constructed.
  static Future<StableDiffusionImageWorker> start(
    ImageGenerationSessionConfig config, {
    StableDiffusionCallsResolver resolveCalls = StableDiffusionCalls.tryResolve,
    StableDiffusionProgressTimer progressTimer = Timer.periodic,
    LlamaLogLevel logLevel = LlamaLogLevel.none,
  }) async {
    final calls = resolveCalls();
    if (calls == null) {
      throw stableDiffusionWrapperUnsupported();
    }
    if (config.requiresIntrinsicTinyDecoderV1 &&
        calls.newContextIntrinsicTinyV1 == null) {
      throw _intrinsicTinyDecoderUnsupported();
    }
    if ((Platform.isMacOS || Platform.isIOS) &&
        !calls.loadsFp8AsF16OnMetal &&
        !{'cpu', 'blas'}.contains(config.backend?.toLowerCase())) {
      for (final role in const [
        'model',
        'diffusionModel',
        'vae',
        'taesd',
        'clipL',
        'clipG',
        't5xxl',
        'llm',
        'controlNet',
      ]) {
        final path = config.files[role];
        if (path == null) continue;
        // Missing files still get the runtime's existing load failure.
        if (FileSystemEntity.typeSync(path) == FileSystemEntityType.directory) {
          throw LlamaUnsupportedException(
            'Cannot verify directory model tensor dtypes before Metal context '
            'creation on a stable_diffusion runtime older than '
            '${StableDiffusionCalls.fp8MetalNativeRelease}. Use individual '
            'GGUF or Safetensors components, or ComputeDevice.cpu '
            '(https://github.com/leehack/llamadart/issues/1446).',
          );
        }
        if (!File(path).existsSync()) continue;
        await validateImageModelMetalDtypes(
          (offset, length) =>
              readStableDiffusionFileRange(path, offset, length),
          name: role == 'model' ? 'the checkpoint' : 'the $role component',
          isJsonIndex: path.endsWith('.json'),
        );
      }
    }
    // Registers the runtime's recorders, which is not synchronized with a
    // load: they have to be in place before the worker starts one. The log
    // recorder is registered at every level, because the reason of a failed
    // load comes from it.
    final log = calls.log;
    if (log != null) {
      recordStableDiffusionLog(log, logLevel);
    }
    calls.progressEnable();
    final replies = _Replies();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        (replies.sendPort, config, resolveCalls, logLevel, _logPosition),
        debugName: 'llamadart-image-generation',
        onExit: replies.sendPort,
        onError: replies.sendPort,
      );
      final loaded = _unwrap(await replies.next()) as _Loaded;
      return StableDiffusionImageWorker._(
        isolate,
        replies,
        loaded.commands,
        calls,
        progressTimer,
        Pointer.fromAddress(loaded.context),
        config,
        loaded.modelVersion,
        loaded.controlNetLoaded,
      );
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      if (isolate != null) await replies.waitForExit();
      await replies.close();
      rethrow;
    }
  }

  @override
  Future<List<GeneratedImage>?> generate(
    ImageGenerationSessionRequest request,
    void Function(int step, int steps) onProgress,
  ) async {
    if (_stopped) {
      throw LlamaStateException(
        'The image-generation worker stopped; load the model again.',
      );
    }
    if (_backendFailed) {
      throw stableDiffusionBackendFailure();
    }
    validateSeamlessImageGenerationRecipe(request, _config, modelVersion);
    validateImageVaeTilingRecipe(request, _config, modelVersion);
    validateImageEditingRecipe(request, _config, modelVersion);
    validateImageControlNetRecipe(request, _config, modelVersion);
    validateImageHiresFixRecipe(request, _config, modelVersion);
    validateImageReferenceEditingRecipe(request, _config, modelVersion);
    if (request.controlImage != null && !supportsControlNet) {
      throw LlamaUnsupportedException(
        'This image-generation worker cannot honor a ControlNet control image: '
        'the load did not build a ControlNet, or the stable_diffusion runtime '
        'does not report its errors (stable-diffusion-native '
        '${StableDiffusionCalls.optionalNativeRelease} or later).',
      );
    }
    final reports = calloc<sd.sd_dart_progress_t>(_reportsPerRead);
    final latest = calloc<Uint64>();
    // Reports are process-wide and numbered: everything after the newest one
    // recorded so far belongs to this generation.
    _calls.progressRead(0, nullptr, 0, latest);
    var after = latest.value;
    var dropped = 0;
    void readProgress() {
      for (var reads = 0; reads < _readsPerPoll; reads++) {
        final count = _calls.progressRead(
          after,
          reports,
          _reportsPerRead,
          latest,
        );
        if (count == 0) {
          return;
        }
        // The runtime dropped its oldest reports when the first one it
        // returns does not follow the last one read.
        dropped += reports[0].sequence - after - 1;
        for (var i = 0; i < count; i++) {
          final report = reports[i];
          after = report.sequence;
          onProgress(report.step, report.steps);
        }
        if (after >= latest.value) {
          return;
        }
      }
    }

    _cancelRequested = false;
    final timer = _progressTimer(progressPollInterval, (_) {
      if (_cancelRequested) {
        // stable-diffusion.cpp clears a cancel request when a generation
        // starts, so one that arrived before then is applied again.
        _calls.cancelGeneration(_context);
      }
      readProgress();
    });
    try {
      _commands.send(_Generate(request, _logPosition));
      final reply = await _reply() as _Generated;
      // The runtime recorded the last reports before the reply was sent.
      readProgress();
      if (reply.backendFailed) {
        _backendFailed = true;
        throw stableDiffusionBackendFailure();
      }
      if (reply.controlNetFailed) {
        throw LlamaInferenceException(
          'stable-diffusion.cpp could not compute the ControlNet conditioning, '
          'so the image would have ignored the control image; it was '
          'discarded. The model stays loaded; causes include running out of '
          'memory.',
        );
      }
      return reply.images == null
          ? null
          : [
              for (final image in reply.images!)
                GeneratedImage(
                  width: image.width,
                  height: image.height,
                  channels: image.channels,
                  pixels: image.pixels.materialize().asUint8List(),
                ),
            ];
    } finally {
      timer.cancel();
      calloc.free(reports);
      calloc.free(latest);
      if (dropped > 0) {
        LlamaLogger.instance.warning(
          'The stable_diffusion runtime dropped $dropped image-generation '
          'progress reports: it keeps the '
          '${StableDiffusionCalls.progressHistory} most recent ones, and more '
          'than that were recorded between two reads. Progress events of '
          'this generation can be missing or mislabelled.',
        );
      }
    }
  }

  @override
  void cancel() {
    // A stopped worker's shutdown already freed the context.
    if (_disposed || _stopped) {
      return;
    }
    _cancelRequested = true;
    _calls.cancelGeneration(_context);
  }

  @override
  Future<void> dispose() => _disposeStart ??= _disposeWorker();

  Future<void> _disposeWorker() async {
    _disposed = true;
    try {
      if (!_stopped) {
        _commands.send(_Dispose(_logPosition));
        await _reply();
      }
    } finally {
      _isolate.kill(priority: Isolate.immediate);
      await _replies.waitForExit();
      await _replies.close();
    }
  }

  /// The next worker reply, unwrapped. Marks the worker stopped when it has
  /// exited, so later calls fail at once instead of waiting for a reply.
  Future<Object?> _reply() async {
    try {
      return _unwrap(await _replies.next());
    } on LlamaStateException {
      _stopped = true;
      rethrow;
    }
  }

  static Object? _unwrap(Object? reply) => switch (reply) {
    _LoadFailure(:final error) => throw error,
    null => throw LlamaStateException(
      'The image-generation worker exited unexpectedly.',
    ),
    [final error, _] => throw LlamaStateException(
      'The image-generation worker failed.',
      error,
    ),
    _ => reply,
  };
}

/// The error for stable-diffusion.cpp rejecting [files], keyed by runtime
/// role as in `ImageGenerationSessionConfig.files`. Its message and details
/// name the files by their `ImageModelRole`, never by path.
///
/// [reason] is what the runtime logged as errors during the load, already
/// free of paths (`stableDiffusionFailureReason`); `null` when it logged
/// none, or when the runtime cannot report it, which [runtimeReportsReason]
/// tells apart. The runtime's reason for a file in the wrong role says
/// little, so the message also names the file roles a split checkpoint is
/// missing, with or without a reason.
LlamaModelException stableDiffusionModelLoadFailure(
  Map<String, String> files, {
  String? reason,
  bool runtimeReportsReason = false,
}) {
  final hints = <String>[
    if (!files.containsKey('model')) ...[
      if (!files.containsKey('vae') && !files.containsKey('taesd'))
        'Standalone diffusion weights (ImageModelRole.diffusionModel) need a '
            'vae or taesd file; a single file that includes its VAE, such as '
            'an SD 3.5 Medium GGUF, is an ImageModelRole.checkpoint.',
      if (!_textEncoderRoles.any(files.containsKey))
        'Standalone diffusion weights need their text encoders: clipL, '
            'clipG and t5xxl for SD 3.5, clipL and t5xxl for FLUX, and llm '
            'for Z-Image and Qwen-Image.',
    ],
  ];
  final message = [
    'stable-diffusion.cpp could not load the image model files.',
    if (reason != null) 'The runtime reported: "$reason".',
    ...hints,
    if (reason == null && hints.isEmpty)
      'Check that they form a model the runtime supports, that each file has '
          'its role (ImageModelRole.checkpoint for a single file with '
          'diffusion weights, ImageModelRole.diffusionModel for standalone '
          'ones; set one with ImageModelComponent(source, role: ...)), and '
          'that the device has enough memory.',
    if (reason == null)
      runtimeReportsReason
          ? 'The runtime logged no reason.'
          : 'This stable_diffusion runtime does not report its reason: that '
                'needs stable-diffusion-native '
                '${StableDiffusionCalls.optionalNativeRelease} or later.',
  ].join(' ');
  final roles = [
    for (final role in files.keys) role == 'model' ? 'checkpoint' : role,
  ];
  return LlamaModelException(message, 'files: ${roles.join(', ')}');
}

const List<String> _textEncoderRoles = ['clipL', 'clipG', 't5xxl', 'llm'];

/// The worker's replies, which keep the calling isolate alive only while one
/// is awaited.
final class _Replies {
  _Replies() {
    _port = RawReceivePort((Object? message) {
      if (message == null && !_exited.isCompleted) _exited.complete();
      // The worker sends what it read of the log before the reply of the
      // operation that recorded it.
      if (message is _LogBatch) {
        message.deliver();
      } else {
        _messages.add(message);
      }
    }, 'llamadart-image-generation-replies')..keepIsolateAlive = false;
  }

  final StreamController<Object?> _messages = StreamController();
  final Completer<void> _exited = Completer<void>();
  late final StreamIterator<Object?> _iterator = StreamIterator(
    _messages.stream,
  );
  late final RawReceivePort _port;
  int _waiting = 0;

  SendPort get sendPort => _port.sendPort;

  Future<void> waitForExit() async {
    _waiting++;
    _port.keepIsolateAlive = true;
    try {
      await _exited.future;
    } finally {
      if (--_waiting == 0) _port.keepIsolateAlive = false;
    }
  }

  Future<Object?> next() async {
    _waiting++;
    _port.keepIsolateAlive = true;
    try {
      if (!await _iterator.moveNext()) {
        throw LlamaStateException('The image-generation worker stopped.');
      }
      return _iterator.current;
    } finally {
      if (--_waiting == 0) {
        _port.keepIsolateAlive = false;
      }
    }
  }

  Future<void> close() async {
    _port.close();
    await _iterator.cancel();
  }
}

final class _Loaded {
  final SendPort commands;
  final int context;
  final String modelVersion;
  final bool controlNetLoaded;

  const _Loaded(
    this.commands,
    this.context,
    this.modelVersion,
    this.controlNetLoaded,
  );
}

final class _LoadFailure {
  final LlamaException error;

  const _LoadFailure(this.error);
}

final class _Generate {
  final ImageGenerationSessionRequest request;
  final StableDiffusionLogPosition logPosition;

  const _Generate(this.request, this.logPosition);
}

final class _Dispose {
  final StableDiffusionLogPosition logPosition;

  const _Dispose(this.logPosition);
}

/// Messages the worker read from the runtime's log, for the calling isolate.
final class _LogBatch {
  final List<WorkerLogMessage> records;
  final StableDiffusionLogPosition position;
  final int dropped;

  const _LogBatch(this.records, this.position, this.dropped);

  void deliver() {
    final known = StableDiffusionImageWorker._logPosition;
    // Two workers that read at once can finish out of order, and the
    // dropped count can rise with no new message to read.
    StableDiffusionImageWorker._logPosition = (
      after: max(position.after, known.after),
      dropped: max(position.dropped, known.dropped),
    );
    // No caller awaits these records, so `emit` prints an error of the log
    // handler instead of throwing it into the port.
    for (final record in records) {
      record.emit();
    }
    if (dropped > 0) {
      WorkerLogMessage(
        LlamaLogLevel.warn,
        'The stable_diffusion runtime dropped $dropped log messages: it '
        'keeps the most recent 256 KiB of them, and more than that were '
        'recorded during one load or generation. Raise '
        'LlamaLogging.nativeLevel to record fewer.',
      ).emit();
    }
  }
}

/// The error for a generation that fails because a Metal command buffer
/// failed, on this or an earlier generation with the same model.
LlamaInferenceException stableDiffusionBackendFailure() =>
    LlamaInferenceException(
      'stable-diffusion.cpp could not generate the image: a GPU command '
      'buffer failed and left the Metal backend in an error state, so every '
      'later generation with this model fails too. Dispose the '
      'ImageGenerationEngine and load the model again to recover.',
    );

/// Whether [lastError], the errors the runtime logged during one call, show
/// that ggml's Metal backend is in its error state: it enters it whenever a
/// command buffer fails, logging the failure, and from then on refuses every
/// graph until the backend is created again.
bool stableDiffusionBackendInErrorState(String lastError) =>
    lastError.contains('backend is in error state') ||
    lastError.contains('ggml_metal_synchronize: error: command buffer');

/// The runtime's log in the worker isolate: nothing on a runtime that has no
/// recorder.
final class _WorkerLog {
  _WorkerLog(this._log, this._level, this._replies, Map<String, String> files)
    : _redact = stableDiffusionPathRedactor(files);

  final StableDiffusionLogCalls? _log;
  final LlamaLogLevel _level;
  final SendPort _replies;
  final String Function(String text) _redact;

  /// The errors the runtime logged during the generation this thread just
  /// ran; empty on a runtime that cannot tell.
  String generationErrors() {
    final log = _log;
    return log == null ? '' : readStableDiffusionLastError(log);
  }

  /// Why the load this thread just made failed, or `null`.
  String? failureReason() {
    final log = _log;
    return log == null
        ? null
        : stableDiffusionFailureReason(
            readStableDiffusionLastError(log),
            _redact,
          );
  }

  /// Sends what the runtime recorded after [position] to the calling
  /// isolate. The reads touch no context, so they are safe whenever the
  /// process exits; calls on a context come before them, inside the time
  /// exit teardown gives a thread after a load.
  void forward(StableDiffusionLogPosition position) {
    final log = _log;
    if (log == null || _level == LlamaLogLevel.none) {
      return;
    }
    final drain = drainStableDiffusionLog(log, position);
    _replies.send(
      _LogBatch(
        [
          for (final (level, text) in drain.messages)
            WorkerLogMessage(level, 'stable_diffusion: ${_redact(text)}'),
        ],
        drain.position,
        drain.dropped,
      ),
    );
  }
}

final class _Disposed {
  const _Disposed();
}

final class _ImagePayload {
  final int width;
  final int height;
  final int channels;
  final TransferableTypedData pixels;

  const _ImagePayload(this.width, this.height, this.channels, this.pixels);
}

final class _Generated {
  final List<_ImagePayload>? images;
  final bool backendFailed;
  final bool controlNetFailed;

  const _Generated(
    this.images, {
    this.backendFailed = false,
    this.controlNetFailed = false,
  });
}

void _workerMain(
  (
    SendPort,
    ImageGenerationSessionConfig,
    StableDiffusionCallsResolver,
    LlamaLogLevel,
    StableDiffusionLogPosition,
  )
  arguments,
) {
  final (replies, config, resolveCalls, logLevel, logPosition) = arguments;
  final calls = resolveCalls();
  if (calls == null) {
    replies.send(_LoadFailure(stableDiffusionWrapperUnsupported()));
    return;
  }
  if (config.requiresIntrinsicTinyDecoderV1 &&
      calls.newContextIntrinsicTinyV1 == null) {
    replies.send(_LoadFailure(_intrinsicTinyDecoderUnsupported()));
    return;
  }
  final log = _WorkerLog(calls.log, logLevel, replies, config.files);

  final context = _newContext(calls, config);
  if (context == nullptr) {
    // The errors of the load belong to this thread until its next load.
    final reason = log.failureReason();
    log.forward(logPosition);
    replies.send(
      _LoadFailure(
        stableDiffusionModelLoadFailure(
          config.files,
          reason: reason,
          runtimeReportsReason: calls.log != null,
        ),
      ),
    );
    return;
  }
  if (!calls.supportsImageGeneration(context)) {
    IsolateShutdownReleases.current.release(context);
    calls.exitFree(context.cast());
    log.forward(logPosition);
    replies.send(
      _LoadFailure(
        LlamaModelException(
          'The loaded model does not support image generation.',
        ),
      ),
    );
    return;
  }

  final commands = ReceivePort('llamadart-image-generation-commands');
  final version = calls.modelVersionName(context);
  final controlNetLoaded =
      config.files.containsKey('controlNet') && calls.hasControlNet(context);
  log.forward(logPosition);
  replies.send(
    _Loaded(
      commands.sendPort,
      context.address,
      version == nullptr ? '' : version.cast<Utf8>().toDartString(),
      controlNetLoaded,
    ),
  );
  commands.listen((command) {
    switch (command) {
      case _Generate(:final request, :final logPosition):
        // An error here ends this isolate with the context still held, so
        // its shutdown frees it; a later cancel from the calling isolate
        // does nothing for a freed context.
        // The generation's errors belong to this thread until its next call.
        final generated = _generate(calls, context, request, log);
        log.forward(logPosition);
        replies.send(generated);
      case _Dispose(:final logPosition):
        IsolateShutdownReleases.current.release(context);
        calls.exitFree(context.cast());
        commands.close();
        log.forward(logPosition);
        replies.send(const _Disposed());
    }
  });
}

LlamaUnsupportedException _intrinsicTinyDecoderUnsupported() =>
    LlamaUnsupportedException(
      'iOS Metal decoding requires the native intrinsic tiny-decoder v1 '
      'context policy. Use ImageModelPlacement(vaeOnCpu: true) or '
      'ComputeDevice.cpu with an older runtime.',
    );

Pointer<sd.sd_ctx_t> _newContext(
  StableDiffusionCalls calls,
  ImageGenerationSessionConfig config,
) {
  return using((arena) {
    final params = arena<sd.sd_ctx_params_t>();
    calls.contextParamsInit(params);
    applyStableDiffusionContextParams(params, config, arena);
    final create = config.requiresIntrinsicTinyDecoderV1
        ? calls.newContextIntrinsicTinyV1
        : calls.newContext;
    final context = create!(params);
    IsolateShutdownReleases.current.hold(
      ShutdownStage.model,
      calls.exitFreeAddress,
      context,
    );
    return context;
  });
}

_Generated _generate(
  StableDiffusionCalls calls,
  Pointer<sd.sd_ctx_t> context,
  ImageGenerationSessionRequest request,
  _WorkerLog log,
) {
  return using((arena) {
    final params = arena<sd.sd_img_gen_params_t>();
    calls.imageGenerationParamsInit(params);
    applyStableDiffusionGenerationParams(params, request, arena);

    final imagesOut = arena<Pointer<sd.sd_image_t>>();
    final countOut = arena<Int>();
    final ok = calls.generateImage(context, params, imagesOut, countOut);
    // Older wrappers can return images after a failed Metal command buffer.
    // Read the calling thread's error window before any further native call,
    // asynchronous gap or pixel copy, independently of display logging.
    final errors = log.generationErrors();
    final backendFailed = stableDiffusionBackendInErrorState(errors);
    // Upstream logs a failed ControlNet pass and samples on without it.
    final controlNetFailed =
        request.controlImage != null &&
        errors.contains('controlnet compute failed');
    final images = imagesOut.value;
    final count = countOut.value;
    try {
      if (!ok || images == nullptr || backendFailed || controlNetFailed) {
        return _Generated(
          null,
          backendFailed: backendFailed,
          controlNetFailed: controlNetFailed,
        );
      }
      return _Generated([
        for (var i = 0; i < count; i++)
          if (images[i].data != nullptr) _copy(images[i]),
      ]);
    } finally {
      if (images != nullptr) {
        calls.freeImages(images, count);
      }
    }
  });
}

_ImagePayload _copy(sd.sd_image_t image) {
  final length = image.width * image.height * image.channel;
  return _ImagePayload(
    image.width,
    image.height,
    image.channel,
    TransferableTypedData.fromList([image.data.asTypedList(length)]),
  );
}
