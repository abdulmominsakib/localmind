import 'dart:async';
import 'dart:math';

import '../../backends/stable_diffusion/stable_diffusion_runtime_status.dart';
import '../engine/engine_capabilities.dart';
import '../engine/llamadart_engine.dart';
import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/config/compute_device.dart';
import '../models/download/model_download_manager.dart';
import '../models/model_format.dart';
import '../models/model_load_options.dart';
import '../models/model_resolver.dart';
import '../models/model_source.dart';
import '../models/model_file_store.dart';
import '../models/model_target_file.dart';
import 'generated_image.dart';
import 'image_control_net_request.dart';
import 'image_editing_request.dart';
import 'image_generation_driver.dart';
import 'image_generation_driver_stub.dart'
    if (dart.library.io) 'image_generation_driver_io.dart';
import 'image_generation_events.dart';
import 'image_generation_model.dart';
import 'image_generation_progress.dart';
import 'image_generation_request.dart';
import 'image_hires_fix_request.dart';
import 'image_reference_editing_request.dart';
import 'image_model_classifier.dart';
import 'image_model_metal_preflight.dart';
import 'image_model_params.dart';
import 'image_model_placement.dart';
import 'local_image_set_model.dart';
import 'local_image_set_stub.dart'
    if (dart.library.io) '../../platform/io/local_image_set_io.dart';

/// Image-generation support of the runtime, from
/// `ImageGenerationEngine.checkRuntime`, and of a loaded engine, from
/// `ImageGenerationEngine.capabilities`.
class ImageGenerationCapabilities implements EngineCapabilities {
  /// Whether images can be generated.
  @override
  final bool isSupported;

  /// Actionable reason when [isSupported] is false.
  @override
  final String? unsupportedReason;

  /// Device the engine runs on, such as `MTL0`, `Vulkan0` or `CPU`. For
  /// `ImageGenerationEngine.checkRuntime`, the device `ComputeDevice.auto`
  /// would pick.
  @override
  final String? backendName;

  /// Every device the runtime reports, such as `MTL0`, `BLAS` and `CPU`.
  final List<String> deviceNames;

  /// stable-diffusion.cpp version of the bundled runtime.
  final String? runtimeVersion;

  /// Model family the runtime detected, such as `SD 2.x`; `null` before a
  /// model is loaded.
  final String? modelVersion;

  /// Whether a running generation can be cancelled.
  final bool supportsCancellation;

  /// Whether this engine was admitted using the bounded, verified local
  /// complete-checkpoint set recipe. False before load and after disposal.
  /// This does not imply Diffusers or image-editing support.
  final bool supportsLocalSafetensorsSets;

  /// Whether the loaded model and runtime support [ImageEditingRequest].
  /// False before load and for unqualified model, decoder, host or device
  /// recipes; ordinary text-to-image support is independent.
  final bool supportsImageEditing;

  /// Whether the loaded model holds a ControlNet and the runtime supports
  /// `ControlNetImageGenerationRequest` with it. False before load, for a
  /// model without a ControlNet, and after disposal.
  final bool supportsControlNet;

  /// Whether the loaded model and runtime support
  /// `HiresFixImageGenerationRequest`. False before load, for unqualified
  /// model, decoder, host or device recipes, and after disposal.
  final bool supportsHiresFix;

  /// Whether the loaded model and runtime support
  /// `ReferenceImageEditingRequest`. False before load, for unqualified
  /// model, component, host or device recipes, and after disposal. The
  /// headers cannot tell FLUX.1 Kontext [dev] from FLUX.1 [dev], which has
  /// the same layout.
  final bool supportsReferenceImageEditing;

  /// Maximum concurrent generations: one per process.
  final int maxConcurrentTasks;

  /// Creates a capability snapshot.
  const ImageGenerationCapabilities({
    required this.isSupported,
    this.unsupportedReason,
    this.backendName,
    this.deviceNames = const <String>[],
    this.runtimeVersion,
    this.modelVersion,
    this.supportsCancellation = false,
    this.supportsLocalSafetensorsSets = false,
    this.supportsImageEditing = false,
    this.supportsControlNet = false,
    this.supportsHiresFix = false,
    this.supportsReferenceImageEditing = false,
    this.maxConcurrentTasks = 0,
  });
}

/// A cancellable image generation.
class ImageGenerationTask {
  final StreamController<ImageGenerationEvent> _events =
      StreamController<ImageGenerationEvent>();
  final Completer<ImageGenerationCompletion> _done =
      Completer<ImageGenerationCompletion>();
  final void Function() _onCancel;
  bool _cancelled = false;

  ImageGenerationTask._(this._onCancel);

  /// Progress events followed by one [ImageGenerationFinalEvent].
  ///
  /// Single-subscription. The stream carries progress only and never emits an
  /// error: a failed or cancelled task closes it without a final event, and
  /// [done] and [result] report why.
  Stream<ImageGenerationEvent> get events => _events.stream;

  /// Completes once the task succeeds, is cancelled, or fails. It never
  /// completes with an error.
  Future<ImageGenerationCompletion> get done => _done.future;

  /// The generated images.
  ///
  /// Throws the task's [LlamaException] when it fails, and
  /// [LlamaStateException] when it is cancelled. Await this future or attach
  /// an error handler as soon as you read it: a stored future that fails
  /// before it has a handler reports an uncaught async error.
  Future<ImageGenerationResult> get result => _result;

  late final Future<ImageGenerationResult> _result = done.then(
    (completion) => switch (completion.state) {
      ImageGenerationCompletionState.completed => completion.result!,
      ImageGenerationCompletionState.failed => throw completion.error!,
      ImageGenerationCompletionState.cancelled => throw LlamaStateException(
        'Image generation was cancelled.',
      ),
    },
  );

  /// Whether cancellation has been requested.
  bool get isCancellationRequested => _cancelled;

  /// Requests cancellation of this task. Calling this more than once, or
  /// after the task finished, is safe.
  ///
  /// The runtime stops before its next sampling step or before decoding, so
  /// the task can take up to one step to report
  /// [ImageGenerationCompletionState.cancelled].
  void cancel() {
    if (_cancelled || _done.isCompleted) {
      return;
    }
    _cancelled = true;
    _onCancel();
  }

  void _add(ImageGenerationEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  void _finish(ImageGenerationCompletion completion) {
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
    if (!_done.isCompleted) {
      _done.complete(completion);
    }
  }
}

/// Experimental on-device text-to-image generation through the opt-in
/// stable_diffusion runtime (stable-diffusion.cpp).
///
/// The app must bundle the runtime by setting
/// `hooks.user_defines.llamadart.llamadart_native_runtimes` to `all` or to a
/// list naming `stable_diffusion`; a list replaces the default `llama_cpp`
/// and `litert_lm`. It runs on Android arm64 (CPU), iOS and macOS (Metal), and
/// Linux and Windows (CPU or Vulkan). On the web and other platforms [load]
/// throws [LlamaUnsupportedException].
///
/// The model runs in a worker isolate, so the calling isolate stays
/// responsive. stable-diffusion.cpp reports progress through one
/// process-wide callback, so only one generation or model load can run at a
/// time; a second one throws [LlamaStateException]. The guard covers engines
/// in the same isolate; do not generate from engines in different isolates
/// at the same time.
///
/// The runtime's messages reach the handler of `LlamaLogging.configure` when
/// both of its levels admit them; a load takes the levels it finds. They
/// arrive after each load and generation and at [dispose], not while one
/// runs, and name model files by role. At the default levels the runtime
/// logs nothing, to stderr either.
///
/// ```dart
/// final engine = await ImageGenerationEngine.load(
///   ImageGenerationModel(
///     ModelSource.parse(
///       'hf://concedo/sdxs-512-tinySDdistilled-GGUF/'
///       'sdxs-512-tinySDdistilled_Q8_0.gguf',
///     ),
///   ),
///   onProgress: (progress) => print(progress.fraction),
/// );
/// try {
///   final result = await engine.generateImage(
///     const ImageGenerationRequest(
///       prompt: 'a red fox in autumn leaves',
///       steps: 1,
///       guidanceScale: 1,
///     ),
///   );
///   final png = result.images.first.toPng();
/// } finally {
///   await engine.dispose();
/// }
/// ```
class ImageGenerationEngine
    implements LlamadartEngine<ImageGenerationCapabilities> {
  static Object? _activeOperation;
  static Future<StableDiffusionRuntimeStatus>? _runningProbe;
  static final Random _seedRandom = Random();

  /// The loaded model, as passed to [load].
  final ImageGenerationModel model;

  /// The runtime settings the model was loaded with.
  final ImageModelParams params;

  /// The file in each role, as [load] detected or the model set it.
  final Map<ImageModelRole, ModelSource> roles;

  final ImageGenerationSession _session;
  final StableDiffusionRuntimeStatus _runtime;
  final String _backendName;
  final ImageGenerationSessionConfig _config;
  ImageGenerationTask? _activeTask;
  Future<void>? _disposal;
  final bool _managedLocalSet;

  ImageGenerationEngine._(
    this.model,
    this.params,
    this.roles,
    this._session,
    this._runtime,
    this._backendName,
    this._config,
    this._managedLocalSet,
  );

  /// Probes the bundled runtime without loading a model.
  ///
  /// Reports unsupported when the runtime is not bundled, the platform or CPU
  /// is not supported, or on the web.
  ///
  /// The first probe in a process initializes the GPU backend. With an empty
  /// Metal shader cache that compiles ggml's Metal library: about 16 s on an
  /// M4 Max. macOS keeps the result in its shader cache, so later launches
  /// take under 0.5 s, and later probes in the process return at once. On
  /// native platforms the probe runs in a short-lived isolate, so it does not
  /// freeze a UI isolate; the calling isolate can still pause once for up to
  /// about 0.5 s while the probe isolate loads the runtime library. Calls on
  /// this isolate, including [load], share a probe that is still running,
  /// and all of them get its result or its error.
  static Future<ImageGenerationCapabilities> checkRuntime() async =>
      _capabilitiesOf(
        await _probeRuntime(_driver),
        isMacosX64: _driver.isMacosX64,
      );

  static ImageGenerationCapabilities _capabilitiesOf(
    StableDiffusionRuntimeStatus status, {
    required bool isMacosX64,
  }) {
    final reason = status.unavailableReason;
    if (reason != null) {
      return ImageGenerationCapabilities(
        isSupported: false,
        unsupportedReason: reason.message,
      );
    }
    return ImageGenerationCapabilities(
      isSupported: true,
      backendName: _backendNameFor(
        ComputeDevice.auto,
        status.devices,
        isMacosX64: isMacosX64,
      ),
      deviceNames: [for (final device in status.devices) device.name],
      runtimeVersion: status.version,
      supportsCancellation: true,
      maxConcurrentTasks: 1,
    );
  }

  static Future<StableDiffusionRuntimeStatus> _probeRuntime(
    ImageGenerationDriver driver,
  ) {
    final running = _runningProbe;
    if (running != null) {
      return running;
    }
    late final Future<StableDiffusionRuntimeStatus> probe;
    probe = driver.probeInBackground().whenComplete(() {
      if (identical(_runningProbe, probe)) {
        _runningProbe = null;
      }
    });
    return _runningProbe = probe;
  }

  /// Loads [model] and returns a ready engine.
  ///
  /// Every file of [model] comes from its `ModelSource`, resolved like
  /// `LlamaEngine.load`: [store]'s resolver (by default
  /// [DefaultModelResolver]) resolves it, and its download manager (by
  /// default [DefaultModelDownloadManager]) checks a local file, or
  /// downloads a remote one into the model cache, resuming an interrupted
  /// download and reusing a cached file. Files resolve one at a time, main
  /// file first. [download] applies to every remote file: cache policy and
  /// directory, authentication, resume, retries and the cancel token. Local
  /// files take only the cancel token. Its bearer token and headers are never
  /// sent across hosts: when they are set and the remote files span more than
  /// one origin (scheme, host and port), the load throws
  /// [LlamaArgumentException] naming the origins before downloading from a
  /// second host.
  ///
  /// Each file's role then comes from its header (GGUF metadata and tensor
  /// names, or the safetensors header), unless the model sets it, so files
  /// can be listed in any order. The set needs exactly one checkpoint or
  /// diffusion model, at most one file per role, and a VAE or tiny
  /// autoencoder that decodes the diffusion model's latent channels.
  ///
  /// GGUF and Safetensors load directly, including mixed components. See
  /// [ImageGenerationModel] for explicit PyTorch roles and layout limits;
  /// detecting a role does not qualify a model or its dtype for this device.
  ///
  /// [onProgress] reports the files together: `receivedBytes` counts every
  /// file resolved so far, including cached and local ones, plus the bytes
  /// of the current download; `totalBytes` is the combined size of all files
  /// once every size is known (from the start for local files, otherwise
  /// when each download starts), and `null` before.
  ///
  /// Weights load eagerly, so the first [generate] does not pay for them. The
  /// first GPU generation in a process still compiles GPU pipelines; see
  /// [warmUp].
  ///
  /// The runtime probe that comes first runs off the calling isolate, as in
  /// [checkRuntime]. It, the [params] checks and a check that every local
  /// file exists run before anything downloads.
  ///
  /// Before loading, when [ImageModelParams.checkMemory] is set and the
  /// device's memory is known, the model's estimated memory (a quarter more
  /// than its file sizes, plus 512 MiB) is compared with the memory
  /// available: on Android the larger of `MemAvailable` and half of physical
  /// memory less what the app already holds, `MemAvailable` on Linux, the
  /// app's remaining memory limit on iOS, and physical memory on macOS,
  /// capped on Metal by the GPU's recommended working set. A model that
  /// does not fit throws [LlamaModelException] naming both figures, instead
  /// of letting the system kill the app.
  ///
  /// A Vulkan GPU does not bound a model by itself: the runtime keeps the
  /// weights that do not fit it in host memory, or on another GPU. A GPU's
  /// figure, asked off the calling isolate, is its free memory when its
  /// driver reports that and its total memory otherwise. A model above the
  /// figure of the GPU it computes on (with [ComputeDevice.auto] the
  /// discrete GPU with the most free memory, with [ComputeDevice.gpu] the
  /// first) loads, generates more slowly, and one `LlamaLogger` warning says
  /// so; on Linux it is refused only above the figures of all discrete GPUs
  /// plus `MemAvailable`. An integrated GPU on Linux gets `MemAvailable`
  /// alone. Windows, a GPU that does not report its
  /// memory and a load with the `SD_VK_DEVICE` environment variable set are
  /// never refused.
  ///
  /// [placement] moves the text encoders or the VAE to the CPU, caps the GPU
  /// memory the runtime uses and turns its automatic fit off; see
  /// [ImageModelPlacement]. The default leaves all of it to the runtime.
  /// The memory check above counts every weight against the device either
  /// way.
  ///
  /// [download]'s cancel token stops a download at once and is checked again
  /// after classification and after the native load; the native load itself
  /// cannot be interrupted, so a cancel during it takes effect when it
  /// returns, and the model it loaded is freed.
  ///
  /// The load is atomic: when it throws, no model stays loaded. Downloaded
  /// files stay in the model cache. Errors name files by position (the main
  /// file, component 1, ...) and role, not by path.
  ///
  /// Throws:
  /// - [LlamaUnsupportedException] when the runtime is unavailable (see
  ///   [checkRuntime]), including on the web; when
  ///   [ComputeDevice.gpu] is requested and the runtime reports no GPU, or
  ///   [ComputeDevice.npu] is requested; when [download] sets
  ///   [ModelLoadOptions.sha256] for a model of more than one file (a
  ///   single file is verified against it); and when a source sets
  ///   [ModelSource.format] to [ModelFormat.liteRtLm]. Image files are
  ///   classified by their headers, so [ModelSource.format] is otherwise
  ///   unused here. Also when
  ///   [ImageModelParams.vaeDirectConvolution] is `true` on iOS with the
  ///   Metal backend, before any file is resolved or loaded. Full-VAE Metal
  ///   decoding on iOS is also refused. Known full-VAEs are rejected before
  ///   native creation; tiny candidates require a native context policy that
  ///   preserves the intrinsic decoder through automatic source refreshes. Use
  ///   [ImageModelPlacement.vaeOnCpu] or [ComputeDevice.cpu] for other recipes,
  ///   including external tiny decoders. Tiling does not bypass this restriction.
  ///   Also, before
  ///   any file is resolved, for a [placement] other than the default on an
  ///   engine that runs on the CPU, and for
  ///   [ImageModelPlacement.maxGpuMemoryGiB] with
  ///   [ImageModelPlacement.autoFit] off, or on a GPU other than Metal when
  ///   the runtime reports no discrete GPU.
  /// - [LlamaImageGenerationException] for invalid [params], including a
  ///   conditioning-cache capacity outside 0 through the signed 32-bit limit,
  ///   and for [ImageModelPlacement.maxGpuMemoryGiB] outside 1 through
  ///   [ImageModelPlacement.largestGpuMemoryGiB], before resolving model
  ///   files.
  /// - [LlamaModelException] when a file is missing, is not an image-model
  ///   component (such as a LoRA), shares a role with another file, or does
  ///   not match the diffusion model; when no file holds diffusion weights
  ///   (including a ControlNet loaded without a checkpoint); when the model
  ///   does not fit; when the runtime
  ///   cannot load it, with the reason the runtime logged when it logged
  ///   one; and what the download manager throws for a failed download.
  /// - [LlamaStateException] when [download]'s cancel token cancels the
  ///   load, and while another generation or load is running.
  /// - [LlamaUnsupportedException] for a ControlNet component outside the
  ///   bounded recipe (pinned runtime, macOS CPU, flash attention and direct
  ///   VAE convolution off, an SD 1.x checkpoint with its embedded full VAE
  ///   plus an original-layout SD 1.x ControlNet and no other component), and
  ///   when the loaded runtime does not report the ControlNet or an SD 1.x
  ///   model.
  /// - [LlamaUnsupportedException] for FP8 GGUF/Safetensors weights on
  ///   Metal (including automatic Metal selection) when the runtime is older
  ///   than stable-diffusion-native v0.3.0-1; v0.3.0-1 and newer load them as
  ///   F16. The refusal comes before native context creation. Use
  ///   [ComputeDevice.cpu] or compatible non-FP8 weights there.
  ///   Uninspectable GGUF/Safetensors headers and ordinary JSON shard
  ///   indexes are also refused on Metal on such an older runtime because
  ///   their tensor dtypes cannot be checked.
  /// - [LlamaArgumentException] when [download] sets a bearer token or
  ///   headers for remote files on more than one origin.
  static Future<ImageGenerationEngine> load(
    ImageGenerationModel model, {
    ImageModelParams params = const ImageModelParams(),
    ImageModelPlacement placement = const ImageModelPlacement(),
    ModelLoadOptions download = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
    ModelFileStore? store,
  }) async {
    final driver = _driver;
    final runtime = await _probeRuntime(driver)
      ..throwIfUnavailable();
    final backendName = _backendNameFor(
      params.device,
      runtime.devices,
      isMacosX64: driver.isMacosX64,
    );
    if (driver.isMacosX64 &&
        params.device == ComputeDevice.gpu &&
        _isMetal(backendName)) {
      LlamaLogger.instance.warning(
        'ComputeDevice.gpu runs image generation on Metal ($backendName) on '
        'macOS x86_64, where upstream ggml-metal can produce garbled output '
        'on Intel Macs with AMD GPUs '
        '(https://github.com/leehack/llamadart-native/issues/116). '
        'ComputeDevice.auto uses the CPU there.',
      );
    }
    if (params.vaeDirectConvolution == true &&
        driver.operatingSystem == 'ios' &&
        _isMetal(backendName)) {
      throw LlamaUnsupportedException(
        'ImageModelParams.vaeDirectConvolution: true is not supported on iOS '
        'with the Metal backend ($backendName): every VAE decode trips the '
        'GPU watchdog and returns a corrupt image '
        '(https://github.com/leehack/llamadart/issues/1044). Leave it null or '
        'set it to false, or load with ComputeDevice.cpu.',
      );
    }
    final conditioningCacheSize = switch (params) {
      ImageConditioningCacheParams(:final capacity) => capacity,
      _ => null,
    };
    if (conditioningCacheSize != null &&
        (conditioningCacheSize < 0 ||
            conditioningCacheSize > ImageConditioningCacheParams.maxCapacity)) {
      throw LlamaImageGenerationException(
        'ImageConditioningCacheParams.capacity must be from 0 to '
        '${ImageConditioningCacheParams.maxCapacity}.',
        conditioningCacheSize,
      );
    }
    if (params.threads < 0) {
      throw LlamaImageGenerationException(
        'ImageModelParams.threads must be 0 or greater.',
        params.threads,
      );
    }
    _checkPlacement(
      placement,
      params.device,
      backendName,
      runtime.devices,
      isMacosX64: driver.isMacosX64,
    );
    List<StableDiffusionGpuMemory>? gpus;
    var readGpus = false;
    if (placement.maxGpuMemoryGiB != null && !_isMetal(backendName)) {
      gpus = await driver.readGpuMemory();
      readGpus = true;
    }
    if (readGpus && gpus?.any((gpu) => !gpu.integrated) != true) {
      // ggml-vulkan reports an integrated GPU as IGPU. With no backend named,
      // the runtime's fit plans only for discrete GPUs, then computes on the
      // integrated one under max_vram without a plan, which aborts like the
      // fit-off case. Metal devices always report the GPU type.
      throw LlamaUnsupportedException(
        'ImageModelPlacement.maxGpuMemoryGiB needs a discrete GPU, and the '
        'stable_diffusion runtime reports $backendName as an integrated GPU '
        'with no discrete one, or does not report the GPU type (for example '
        'with SD_VK_DEVICE set): stable-diffusion-native v0.3.0-1 can abort '
        'the process when it computes there with a budget '
        '(https://github.com/leehack/stable-diffusion-native/issues/34). '
        'Drop maxGpuMemoryGiB.',
      );
    }
    final localSet = model is LocalImageSetModel ? model : null;
    ({String indexPath, int totalBytes, String layoutSha256})? snapshot;
    final effectiveStore = store ?? ModelFileStore();
    if (localSet != null) {
      if (driver.operatingSystem != 'macos' ||
          backendName != 'CPU' ||
          params.device != ComputeDevice.cpu ||
          params.flashAttention != false ||
          params.vaeDirectConvolution != false ||
          !_isQualifiedRuntime(runtime)) {
        throw LlamaUnsupportedException(
          'Local checkpoint sets require the pinned SD v0.3.0-1 runtime on macOS CPU with explicit flash attention and direct VAE convolution off.',
        );
      }
      snapshot = await resolveLocalImageSet(
        localSet,
        store: effectiveStore,
        options: download,
        onProgress: onProgress,
      );
      if (download.cancelToken?.isCancelled ?? false) {
        throw LlamaStateException('Image model loading was cancelled.');
      }
      // A tensor-layout recipe, not a general architecture/completeness detector.
      if (snapshot.layoutSha256 !=
          'e5ae320534104044d4816a818df7129b9fd2d33d1262d18081adac95dee012fd') {
        throw LlamaUnsupportedException(
          'Local checkpoint sets currently require the qualified complete SD-Turbo F16/F32 tensor-layout recipe. Other families, layouts, tensor inventories and dtypes are unqualified.',
        );
      }
    }
    final sources = [
      snapshot == null ? model.source : ModelSource.path(snapshot.indexPath),
      for (final component in model.components) component.source,
    ];
    if (sources.any((source) => source.format == ModelFormat.liteRtLm)) {
      throw LlamaUnsupportedException(
        'ImageGenerationEngine.load cannot load ModelFormat.liteRtLm files. '
        'Leave ModelSource.format unset for image models.',
      );
    }
    final explicitRoles = [
      model.role,
      for (final component in model.components) component.role,
    ];
    final knownSizes = <int, int>{
      for (final (index, source) in sources.indexed)
        if (source.isLocal)
          index: snapshot?.totalBytes ?? _fileSize(driver, index, source.path!),
    };

    final List<String> paths;
    try {
      paths = snapshot != null
          ? [snapshot.indexPath]
          : await resolveModelSourceFiles(
              sources,
              store: effectiveStore,
              download: download,
              onProgress: onProgress,
              operation: 'Image model loading',
              knownSizes: knownSizes,
              assetType: 'image model',
            );
    } on LlamaModelException catch (error) {
      // The download manager names a local file by its path; image errors
      // name files by position. ModelLoadOptions.sha256 applies only to a
      // single (main) file.
      if (download.sha256 == null ||
          !error.message.startsWith('Checksum mismatch')) {
        rethrow;
      }
      throw LlamaModelException(
        'Checksum mismatch for ${describeImageModelFile(0)}: its SHA-256 '
        'does not match ModelLoadOptions.sha256.',
      );
    }
    void throwIfCancelled() {
      if (download.cancelToken?.isCancelled ?? false) {
        throw LlamaStateException('Image model loading was cancelled.');
      }
    }

    throwIfCancelled();
    // Container qualification covers text-to-image; decoder opt-ins need
    // independent evidence even though the snapshot has a full VAE.
    final assignment = snapshot != null
        ? const ImageModelAssignment({
            ImageModelRole.checkpoint: 0,
          }, decodesWithTinyAutoencoder: false)
        : await assignImageModelRoles([
            for (final (index, path) in paths.indexed)
              ImageModelFileInput(
                role: explicitRoles[index],
                read: (offset, length) =>
                    driver.readFileRange(path, offset, length),
              ),
          ]);
    throwIfCancelled();
    final requiresIosTinyDecoder =
        driver.operatingSystem == 'ios' &&
        _isMetal(backendName) &&
        !placement.vaeOnCpu;
    LlamaUnsupportedException
    unsupportedIosDecoder() => LlamaUnsupportedException(
      'Full-VAE decoding on iOS with the Metal backend ($backendName) is '
      'not supported: repeated decodes can trip the GPU watchdog '
      '(https://github.com/leehack/llamadart/issues/1047). GPU decoding '
      'requires an intrinsic SDXS tiny decoder and a selected runtime with '
      'the intrinsic tiny-decoder v1 context policy, so model refresh cannot '
      'switch to a full VAE. External tiny decoders can '
      'fall back to a full VAE. Use ImageModelPlacement(vaeOnCpu: true) '
      'or ComputeDevice.cpu for other recipes. VAE tiling does not '
      'bypass this restriction.',
    );
    if (requiresIosTinyDecoder &&
        (!runtime.supportsIntrinsicTinyDecoderV1 ||
            !assignment.decodesWithTinyAutoencoder ||
            assignment.roles.containsKey(ImageModelRole.taesd) ||
            assignment.roles.containsKey(ImageModelRole.vae) ||
            !_isQualifiedRuntime(runtime))) {
      throw unsupportedIosDecoder();
    }
    if (_isMetal(backendName) && !runtime.loadsFp8AsF16OnMetal) {
      for (final (index, path) in paths.indexed) {
        await validateImageModelMetalDtypes(
          (offset, length) => driver.readFileRange(path, offset, length),
          name: describeImageModelFile(index),
          isJsonIndex: path.endsWith('.json'),
        );
      }
      throwIfCancelled();
    }
    final flashAttention =
        params.flashAttention ?? _flashAttentionByDefault(backendName);
    final vaeDirectConvolution =
        params.vaeDirectConvolution ??
        _vaeDirectConvolutionByDefault(
          backendName,
          tinyAutoencoder: assignment.decodesWithTinyAutoencoder,
        );
    final loadsControlNet = assignment.roles.containsKey(
      ImageModelRole.controlNet,
    );
    final controlNetRecipeVerified =
        loadsControlNet &&
        driver.operatingSystem == 'macos' &&
        backendName == 'CPU' &&
        _isQualifiedRuntime(runtime) &&
        assignment.controlNetRecipeVerified &&
        !flashAttention &&
        !vaeDirectConvolution;
    if (loadsControlNet && !controlNetRecipeVerified) {
      throw LlamaUnsupportedException(
        'Loading a ControlNet requires the pinned stable_diffusion v0.3.0-1 '
        'runtime on macOS with ComputeDevice.cpu, flashAttention: false and '
        'vaeDirectConvolution: false, and exactly an SD 1.x checkpoint with '
        'its embedded full VAE plus an SD 1.x ControlNet in the original '
        '(lllyasviel) layout whose header shows a 768-wide text context and '
        'a three-channel hint. Other families, Diffusers or .pth ControlNets, '
        'extra components, devices and platforms are not qualified.',
      );
    }
    var weightBytes = snapshot?.totalBytes ?? 0;
    if (snapshot == null) {
      for (final (index, path) in paths.indexed) {
        weightBytes += _fileSize(driver, index, path);
        if (params.checkMemory &&
            _isMetal(backendName) &&
            runtime.loadsFp8AsF16OnMetal) {
          weightBytes += await imageModelFp8AsF16ExtraBytes(
            (offset, length) => driver.readFileRange(path, offset, length),
          );
        }
      }
    }
    if (params.checkMemory) {
      final memoryDevice = switch (backendName) {
        _ when _isMetal(backendName) => ImageGenerationComputeDevice.metal,
        _ when _isGpu(backendName) => ImageGenerationComputeDevice.otherGpu,
        _ => ImageGenerationComputeDevice.cpu,
      };
      // The budget read predates any download, so refresh free memory then.
      if (memoryDevice == ImageGenerationComputeDevice.otherGpu &&
          (!readGpus || sources.any((source) => !source.isLocal))) {
        gpus = await driver.readGpuMemory();
      }
      _checkMemory(
        weightBytes,
        await driver.memoryLimits(
          memoryDevice,
          runtimePicksGpu:
              params.device == ComputeDevice.auto && placement.autoFit,
          gpus: gpus,
        ),
      );
    }
    final files = <String, String>{
      for (final MapEntry(key: role, value: index) in assignment.roles.entries)
        _runtimeRoleNames[role]!: paths[index],
    };

    final operation = _acquireOperation();
    try {
      final config = ImageGenerationSessionConfig(
        files: files,
        requiresIntrinsicTinyDecoderV1: requiresIosTinyDecoder,
        backend: _backendAssignment(switch (params.device) {
          ComputeDevice.cpu => 'cpu',
          ComputeDevice.gpu => 'gpu',
          ComputeDevice.auto || ComputeDevice.npu =>
            // Preserve the already selected CPU fallback at the worker
            // boundary; FP8 inspection never changes device selection.
            backendName.toUpperCase() == 'CPU' ? 'cpu' : null,
        }, placement),
        threads: params.threads,
        conditioningCacheSize: conditioningCacheSize,
        maxGpuMemoryGiB: placement.maxGpuMemoryGiB,
        autoFit: placement.autoFit,
        controlNetRecipeVerified: controlNetRecipeVerified,
        imageEditingRecipeVerified:
            driver.operatingSystem == 'macos' &&
            backendName == 'CPU' &&
            _isQualifiedRuntime(runtime) &&
            assignment.vaeTilingDecoderVerified &&
            !assignment.decodesWithTinyAutoencoder &&
            assignment.roles.length == 1 &&
            assignment.roles.containsKey(ImageModelRole.checkpoint),
        vaeTilingRecipeVerified:
            // v0.3.0-1 is the runtime whose tiling layout and decode are qualified.
            _isQualifiedRuntime(runtime) &&
            assignment.vaeTilingDecoderVerified &&
            assignment.roles.containsKey(ImageModelRole.checkpoint) &&
            assignment.roles.keys.every(
              (role) =>
                  role == ImageModelRole.checkpoint ||
                  role == ImageModelRole.taesd,
            ) &&
            (backendName == 'CPU' || _isMetal(backendName)),
        hiresFixRecipeVerified:
            driver.operatingSystem == 'macos' &&
            (backendName == 'CPU' || _isMetal(backendName)) &&
            _isQualifiedRuntime(runtime) &&
            assignment.vaeTilingDecoderVerified &&
            !assignment.decodesWithTinyAutoencoder &&
            assignment.roles.length == 1 &&
            assignment.roles.containsKey(ImageModelRole.checkpoint),
        referenceEditingRecipeVerified:
            driver.operatingSystem == 'macos' &&
            _isMetal(backendName) &&
            !placement.textEncoderOnCpu &&
            !placement.vaeOnCpu &&
            _isQualifiedRuntime(runtime) &&
            assignment.fluxKontextRecipeVerified,
        seamlessRecipeVerified:
            assignment.decodesWithTinyAutoencoder &&
            assignment.roles.length == 1 &&
            assignment.roles.containsKey(ImageModelRole.checkpoint) &&
            (backendName == 'CPU' || _isMetal(backendName)),
        flashAttention: flashAttention,
        vaeDirectConvolution: vaeDirectConvolution,
      );
      final session = await driver.start(config);
      // Retain a driver-boundary check in addition to the native context
      // policy, which must remain effective after every source refresh.
      if (requiresIosTinyDecoder &&
          session.modelVersion != 'SDXS (512-DS)' &&
          session.modelVersion != 'SDXS (09)') {
        await session.dispose();
        throw unsupportedIosDecoder();
      }
      if (loadsControlNet &&
          (session.modelVersion != 'SD 1.x' || !_supportsControlNet(session))) {
        await session.dispose();
        throw LlamaUnsupportedException(
          'The model did not load as the qualified SD 1.x ControlNet recipe: '
          'the runtime detected ${session.modelVersion.isEmpty ? 'no model family' : session.modelVersion} '
          'or does not report the loaded ControlNet and its errors.',
        );
      }
      if (snapshot != null && session.modelVersion != 'SD 2.x') {
        await session.dispose();
        throw LlamaUnsupportedException(
          'The verified local checkpoint set did not load as the qualified native SD 2.x recipe.',
        );
      }
      if (download.cancelToken?.isCancelled ?? false) {
        // The native load cannot be interrupted; free what it allocated so
        // a cancelled load leaves nothing loaded.
        await session.dispose();
        throwIfCancelled();
      }
      return ImageGenerationEngine._(
        model,
        params,
        Map<ImageModelRole, ModelSource>.unmodifiable({
          for (final MapEntry(key: role, value: index)
              in assignment.roles.entries)
            role: snapshot == null ? sources[index] : model.source,
        }),
        session,
        runtime,
        backendName,
        config,
        snapshot != null,
      );
    } finally {
      _releaseOperation(operation);
    }
  }

  /// Support of this engine and its loaded model; unsupported once
  /// disposed. Never throws.
  ///
  /// It changes only when the engine is disposed, so a Flutter app can read
  /// it once after [load] and keep it in its state.
  @override
  Future<ImageGenerationCapabilities> get capabilities async {
    if (_disposal != null) {
      return const ImageGenerationCapabilities(
        isSupported: false,
        unsupportedReason: 'The ImageGenerationEngine is disposed.',
      );
    }
    return ImageGenerationCapabilities(
      isSupported: true,
      backendName: _backendName,
      deviceNames: [for (final device in _runtime.devices) device.name],
      runtimeVersion: _runtime.version,
      modelVersion: _session.modelVersion,
      supportsCancellation: true,
      supportsLocalSafetensorsSets: _managedLocalSet,
      supportsImageEditing:
          _config.imageEditingRecipeVerified &&
          !_config.flashAttention &&
          !_config.vaeDirectConvolution &&
          _session.modelVersion == 'SD 2.x' &&
          switch (_session) {
            ImageEditingSession editing => editing.supportsImageEditing,
            _ => false,
          },
      supportsControlNet:
          _config.controlNetRecipeVerified &&
          _session.modelVersion == 'SD 1.x' &&
          _supportsControlNet(_session),
      supportsHiresFix:
          _config.hiresFixRecipeVerified &&
          imageHiresFixModelVersions.contains(_session.modelVersion) &&
          _supportsHiresFix(_session),
      supportsReferenceImageEditing:
          _config.referenceEditingRecipeVerified &&
          _session.modelVersion == 'Flux' &&
          _supportsReferenceImageEditing(_session),
      maxConcurrentTasks: 1,
    );
  }

  /// Whether [dispose] has been called.
  @override
  bool get isDisposed => _disposal != null;

  /// Starts generating the images [request] describes and returns the
  /// running task.
  ///
  /// An unset width and height use
  /// [ImageGenerationRequest.defaultDimension], unset steps
  /// [ImageGenerationRequest.defaultSteps] and an unset guidance
  /// [ImageGenerationRequest.defaultGuidanceScale]; an unset sampler,
  /// scheduler and flow shift leave the runtime's choice for the model, and
  /// an unset seed is picked at random and reported in the result.
  ///
  /// The task's [ImageGenerationTask.events] report each phase and sampling
  /// step, then one [ImageGenerationFinalEvent]. The engine reads the
  /// runtime's progress every 50 ms, so progress events arrive in groups, up
  /// to that long after the runtime reported them. [ImageGenerationTask.cancel]
  /// takes effect before the runtime's next sampling step or before decoding,
  /// so the task can run up to one more step before it reports
  /// [ImageGenerationCompletionState.cancelled]. [dispose] cancels the task.
  ///
  /// A [HiresFixImageGenerationRequest] reports both sampling passes, with
  /// [ImageGenerationProgressEvent.pass] 0 and then 1, before decoding.
  ///
  /// Throws [LlamaImageGenerationException] for an invalid request, including
  /// a [ControlNetImageGenerationRequest] whose control image is not RGB at
  /// the output size or whose strength is outside 0 through 2, and a
  /// [HiresFixImageGenerationRequest] whose sizes, steps, strength or count
  /// break the [ImageHiresFix] limits, and a [ReferenceImageEditingRequest]
  /// whose references are not RGB at the output size within
  /// [ReferenceImageEditingRequest.maxPixels], and
  /// [LlamaUnsupportedException] for an unqualified
  /// [SeamlessImageGenerationRequest] recipe, for a
  /// [ControlNetImageGenerationRequest] when no ControlNet is loaded or the
  /// request combines it with image editing, VAE tiling or circular axes,
  /// for a [HiresFixImageGenerationRequest] when
  /// [ImageGenerationCapabilities.supportsHiresFix] is false, and for a
  /// [ReferenceImageEditingRequest] when
  /// [ImageGenerationCapabilities.supportsReferenceImageEditing] is false or
  /// its reference count is not the recipe's, and
  /// [LlamaStateException] after [dispose] or while another generation or
  /// load is running; these checks run before the returned future completes,
  /// and the one-generation slot is taken when this is called. A runtime
  /// failure after the task starts, such as running out of memory, fails the
  /// task with [LlamaInferenceException], as does a hires fix whose images do
  /// not have the final size; the engine stays usable. A failed
  /// Metal command buffer leaves the backend in an error state instead: from
  /// then on every task fails with a [LlamaInferenceException] that says so,
  /// until the engine is disposed and the model loaded again.
  Future<ImageGenerationTask> generate(ImageGenerationRequest request) async {
    final effective = _resolve(request);
    final hiresFix = request is HiresFixImageGenerationRequest
        ? resolveImageHiresFix(
            request.hiresFix,
            width: effective.width!,
            height: effective.height!,
            steps: effective.steps!,
            count: effective.count,
          )
        : null;
    final resolved = ImageGenerationSessionRequest(
      prompt: effective.prompt,
      negativePrompt: effective.negativePrompt,
      width: effective.width!,
      height: effective.height!,
      steps: effective.steps!,
      guidanceScale: effective.guidanceScale!,
      seed: effective.seed ?? _seedRandom.nextInt(0x7FFFFFFF),
      count: effective.count,
      sampler: effective.sampler,
      scheduler: effective.scheduler,
      flowShift: effective.flowShift,
      vaeTiling: imageRequestVaeTiling(request),
      circularX: request is SeamlessImageGenerationRequest && request.circularX,
      circularY: request is SeamlessImageGenerationRequest && request.circularY,
      initialImage: request is ImageEditingRequest
          ? request.initialImage
          : null,
      mask: request is ImageEditingRequest ? request.mask : null,
      strength: request is ImageEditingRequest ? request.strength : null,
      controlImage: request is ControlNetImageGenerationRequest
          ? request.control.image
          : null,
      controlStrength: request is ControlNetImageGenerationRequest
          ? request.control.strength
          : null,
      hiresFix: hiresFix,
      references: request is ReferenceImageEditingRequest
          ? request.references
          : null,
      referenceRecipe: request is ReferenceImageEditingRequest
          ? request.recipe
          : null,
    );
    validateSeamlessImageGenerationRecipe(
      resolved,
      _config,
      _session.modelVersion,
    );
    validateImageVaeTilingRecipe(resolved, _config, _session.modelVersion);
    validateImageEditingRecipe(resolved, _config, _session.modelVersion);
    validateImageControlNetRecipe(resolved, _config, _session.modelVersion);
    validateImageHiresFixRecipe(resolved, _config, _session.modelVersion);
    validateImageReferenceEditingRecipe(
      resolved,
      _config,
      _session.modelVersion,
    );
    if (resolved.references != null &&
        !_supportsReferenceImageEditing(_session)) {
      throw LlamaUnsupportedException(
        'This image-generation backend does not report support for '
        'reference images. Use the pinned stable_diffusion v0.3.0-1 runtime '
        'with the supported macOS Metal FLUX.1 Kontext recipe.',
      );
    }
    if (resolved.hiresFix != null && !_supportsHiresFix(_session)) {
      throw LlamaUnsupportedException(
        'This image-generation backend does not report support for a hires '
        'fix. Use the pinned stable_diffusion v0.3.0-1 runtime with the '
        'supported macOS CPU or Metal SD 1.x or SD 2.x full-VAE recipe.',
      );
    }
    if (resolved.controlImage != null && !_supportsControlNet(_session)) {
      throw LlamaUnsupportedException(
        'This image-generation backend does not report a loaded ControlNet. '
        'Load an SD 1.x ControlNet with its checkpoint on the pinned '
        'stable_diffusion v0.3.0-1 runtime with the supported macOS CPU recipe.',
      );
    }
    if (resolved.initialImage != null &&
        !switch (_session) {
          ImageEditingSession editing => editing.supportsImageEditing,
          _ => false,
        }) {
      throw LlamaUnsupportedException(
        'This image-generation backend does not report support for '
        'owned RGB/mask image editing. Use the pinned stable_diffusion '
        'v0.3.0-1 runtime with the supported macOS CPU SD 2.x full-VAE recipe.',
      );
    }
    if (resolved.vaeTiling != null &&
        !switch (_session) {
          ImageVaeTilingSession tiling => tiling.supportsVaeTiling,
          _ => false,
        }) {
      throw LlamaUnsupportedException(
        'This image-generation backend does not report support for '
        'per-request VAE tiling. Use the pinned stable_diffusion v0.3.0-1 '
        'runtime with a supported SD 2.x decoder recipe.',
      );
    }
    final operation = _acquireOperation();
    final task = ImageGenerationTask._(_session.cancel);
    _activeTask = task;
    unawaited(_run(task, resolved, operation));
    return task;
  }

  /// Generates the images [request] describes and returns them.
  ///
  /// Throws what [generate] and [ImageGenerationTask.result] throw, such as
  /// [LlamaStateException] when [dispose] cancels the task.
  Future<ImageGenerationResult> generateImage(
    ImageGenerationRequest request,
  ) async => (await generate(request)).result;

  /// Compiles the GPU pipelines a [width] by [height] generation at
  /// [guidanceScale] needs, by running one single-step generation and
  /// discarding its image, so the first real image does not pay for them.
  ///
  /// ggml compiles each GPU pipeline the first time a process uses it. That
  /// made the first image take 12 s on Linux Vulkan and 45 s on Windows
  /// Vulkan (NVIDIA L4) instead of under 0.6 s, and added about 0.5 s on an
  /// M4 Max with an empty Metal shader cache. GPU drivers and macOS cache
  /// compiled shaders on disk, so later launches are faster.
  ///
  /// Use the size the app will generate: ggml picks some pipelines by tensor
  /// size, so another size can still compile more. Unset values fall back
  /// as in [generate]. For a model trained at 1024x1024 the warm-up costs
  /// one sampling step and a decode at that size: about 2 to 4 s for
  /// SDXL-Lightning with TAESDXL on an M4 Max, and the same peak memory as
  /// an image, which the memory check in [load] covers where it runs (not
  /// on the Windows CPU).
  ///
  /// On the CPU there is nothing to compile, so this returns at once.
  ///
  /// The warm-up holds the one-operation slot like [generate]: await it
  /// before the next [generate] or [load]. [dispose] cancels a running
  /// warm-up, which then completes normally.
  ///
  /// Throws [LlamaImageGenerationException] for an invalid size or guidance,
  /// [LlamaStateException] after [dispose] or while another
  /// generation or load is running, and [LlamaInferenceException] when the
  /// runtime fails the generation.
  Future<void> warmUp({int? width, int? height, double? guidanceScale}) async {
    final request = ImageGenerationRequest(
      prompt: 'warm-up',
      width: width,
      height: height,
      guidanceScale: guidanceScale,
      steps: 1,
      seed: 0,
    );
    if (!_isGpu(_backendName)) {
      // Fail where a GPU warm-up would, so callers behave the same on both.
      _resolve(request);
      _releaseOperation(_acquireOperation());
      return;
    }
    final completion = await (await generate(request)).done;
    if (completion.state == ImageGenerationCompletionState.failed) {
      throw completion.error!;
    }
  }

  /// Cancels a running generation, waits for it to stop, and frees the
  /// model. Calling this more than once is safe.
  @override
  Future<void> dispose() {
    final existing = _disposal;
    if (existing != null) return existing;

    // Cleanup hooks can reenter before an async body's first suspension.
    final disposal = Completer<void>();
    _disposal = disposal.future;
    disposal.complete(_dispose());
    return disposal.future;
  }

  Future<void> _dispose() async {
    final task = _activeTask;
    if (task != null) {
      task.cancel();
      await task.done;
    }
    await _session.dispose();
  }

  /// [request] with the fallbacks applied, after checking that it can run.
  ImageGenerationRequest _resolve(ImageGenerationRequest request) {
    if (_disposal != null) {
      throw LlamaStateException('The ImageGenerationEngine is disposed.');
    }
    final effective = ImageGenerationRequest(
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      width: request.width ?? ImageGenerationRequest.defaultDimension,
      height: request.height ?? ImageGenerationRequest.defaultDimension,
      steps: request.steps ?? ImageGenerationRequest.defaultSteps,
      guidanceScale:
          request.guidanceScale ?? ImageGenerationRequest.defaultGuidanceScale,
      seed: request.seed,
      count: request.count,
      sampler: request.sampler,
      scheduler: request.scheduler,
      flowShift: request.flowShift,
    );
    if (imageRequestVaeTiling(request) != null) {
      validateImageGenerationRequest(request);
    }
    validateImageGenerationRequest(effective);
    return effective;
  }

  Future<void> _run(
    ImageGenerationTask task,
    ImageGenerationSessionRequest request,
    Object operation,
  ) async {
    late final ImageGenerationCompletion completion;
    try {
      final hiresFix = request.hiresFix;
      final tracker = ImageGenerationProgressTracker(
        steps: request.steps,
        imageCount: request.count,
        passCount: hiresFix == null ? 1 : 2,
      );
      task._add(tracker.start());
      final stopwatch = Stopwatch()..start();
      final images = await _session.generate(request, (step, steps) {
        if (task.isCancellationRequested) {
          // stable-diffusion.cpp clears the cancel flag when a generation
          // starts, so a cancel that arrived before then is re-applied here.
          _session.cancel();
          return;
        }
        tracker.onNativeProgress(step, steps).forEach(task._add);
      });
      stopwatch.stop();
      if (task.isCancellationRequested) {
        completion = const ImageGenerationCompletion.cancelled();
        return;
      }
      if (images == null || images.isEmpty) {
        throw LlamaInferenceException(
          'stable-diffusion.cpp could not generate the image. It reports no '
          'reason; causes include running out of memory. If every request '
          'fails this way, dispose the ImageGenerationEngine and load the '
          'model again.',
        );
      }
      if (hiresFix != null &&
          (images.length != request.count ||
              images.any(
                (image) =>
                    image.width != hiresFix.width ||
                    image.height != hiresFix.height,
              ))) {
        // The runtime disables a hires fix it cannot apply with only a
        // warning, and would return first-pass images as success.
        throw LlamaInferenceException(
          'stable-diffusion.cpp did not return ${request.count} hires-fix '
          'images of ${hiresFix.width}x${hiresFix.height}; the images were '
          'discarded.',
        );
      }
      final result = ImageGenerationResult(
        images: images,
        seed: request.seed,
        elapsed: stopwatch.elapsed,
      );
      task._add(ImageGenerationFinalEvent(result));
      completion = ImageGenerationCompletion.completed(result);
    } catch (error) {
      if (task.isCancellationRequested) {
        completion = const ImageGenerationCompletion.cancelled();
        return;
      }
      final failure = error is LlamaException
          ? error
          : LlamaInferenceException('Image generation failed.', error);
      completion = ImageGenerationCompletion.failed(failure);
    } finally {
      // Release before `done` completes so a caller awaiting it can start
      // the next generation.
      _releaseOperation(operation);
      if (identical(_activeTask, task)) {
        _activeTask = null;
      }
      task._finish(completion);
    }
  }

  static int _fileSize(ImageGenerationDriver driver, int index, String path) {
    final size = path.trim().isEmpty ? null : driver.fileSize(path);
    if (size == null) {
      final name = describeImageModelFile(index);
      throw LlamaModelException(
        'Image model file not found: no file at the local path of $name.',
      );
    }
    return size;
  }

  /// Runtime names of the roles, as the native context takes them.
  static const Map<ImageModelRole, String> _runtimeRoleNames = {
    ImageModelRole.checkpoint: 'model',
    ImageModelRole.diffusionModel: 'diffusionModel',
    ImageModelRole.vae: 'vae',
    ImageModelRole.taesd: 'taesd',
    ImageModelRole.clipL: 'clipL',
    ImageModelRole.clipG: 'clipG',
    ImageModelRole.t5xxl: 't5xxl',
    ImageModelRole.llm: 'llm',
    ImageModelRole.controlNet: 'controlNet',
  };

  /// Whether [status] is the pinned v0.3.0-1 runtime (upstream
  /// master-1017) the bounded image recipes were qualified on.
  static bool _isQualifiedRuntime(StableDiffusionRuntimeStatus status) =>
      status.commit == 'be48649' ||
      status.commit == 'be486498eadc29dc3cd234d944c2180ed42b1415';

  static bool _supportsReferenceImageEditing(ImageGenerationSession session) =>
      switch (session) {
        ImageReferenceEditingSession editing =>
          editing.supportsReferenceImageEditing,
        _ => false,
      };

  static bool _supportsHiresFix(ImageGenerationSession session) =>
      switch (session) {
        ImageHiresFixSession hires => hires.supportsHiresFix,
        _ => false,
      };

  static bool _supportsControlNet(ImageGenerationSession session) =>
      switch (session) {
        ImageControlNetSession control => control.supportsControlNet,
        _ => false,
      };

  static ImageGenerationDriver get _driver =>
      debugImageGenerationDriverOverride ?? createImageGenerationDriver();

  static Object _acquireOperation() {
    if (_activeOperation != null) {
      throw LlamaStateException(
        'Another image generation or image model load is running. '
        'stable-diffusion.cpp reports progress through one process-wide '
        'callback, so only one can run at a time.',
      );
    }
    return _activeOperation = Object();
  }

  static void _releaseOperation(Object operation) {
    if (identical(_activeOperation, operation)) {
      _activeOperation = null;
    }
  }

  static void _checkMemory(
    int weightBytes,
    ImageGenerationMemoryLimits limits,
  ) {
    final required = estimateImageGenerationMemoryBytes(weightBytes);
    final needs =
        'The image model needs about ${_gib(required)} GiB '
        '(${_gib(weightBytes)} GiB of weights plus working memory)';
    final refuse = limits.refuse;
    if (refuse != null && required > refuse.bytes) {
      throw LlamaModelException(
        '$needs, but only ${_gib(refuse.bytes)} GiB is available '
        '(${refuse.source}). Use a smaller or more quantized model, free '
        'memory, or set ImageModelParams.checkMemory to false to try anyway.',
      );
    }
    final slower = limits.slower;
    if (slower != null && required > slower.bytes) {
      LlamaLogger.instance.warning(
        '$needs, more than the ${_gib(slower.bytes)} GiB available '
        '(${slower.source}). stable-diffusion.cpp keeps the part that does '
        'not fit in system memory, so generation will be slower.',
      );
    }
  }

  static String _gib(int bytes) {
    final gib = bytes / (1 << 30);
    return gib.toStringAsFixed(gib < 10 ? 2 : 1);
  }

  static void _checkPlacement(
    ImageModelPlacement placement,
    ComputeDevice device,
    String backendName,
    List<StableDiffusionDevice> devices, {
    required bool isMacosX64,
  }) {
    final gib = placement.maxGpuMemoryGiB;
    if (gib != null &&
        (gib < 1 || gib > ImageModelPlacement.largestGpuMemoryGiB)) {
      throw LlamaImageGenerationException(
        'ImageModelPlacement.maxGpuMemoryGiB must be from 1 to '
        '${ImageModelPlacement.largestGpuMemoryGiB}.',
        gib,
      );
    }
    if (gib != null && !placement.autoFit) {
      throw LlamaUnsupportedException(
        'ImageModelPlacement.maxGpuMemoryGiB with autoFit: false is not '
        'supported: stable-diffusion-native v0.3.0-1 then keeps every weight '
        'on the GPU and aborts the process (GGML_ASSERT in new_sd_ctx) when '
        'the budget is below them '
        '(https://github.com/leehack/stable-diffusion-native/issues/34). '
        'Leave autoFit on to keep the weights within the budget, or drop '
        'maxGpuMemoryGiB.',
      );
    }
    final moved = [
      if (placement.textEncoderOnCpu) 'textEncoderOnCpu',
      if (placement.vaeOnCpu) 'vaeOnCpu',
      if (gib != null) 'maxGpuMemoryGiB',
      if (!placement.autoFit) 'autoFit: false',
    ];
    if (moved.isEmpty || _isGpu(backendName)) {
      return;
    }
    final why = device == ComputeDevice.cpu
        ? 'ComputeDevice.cpu was requested'
        : isMacosX64 && devices.any((d) => _isGpu(d.name))
        ? 'ComputeDevice.auto runs on the CPU on macOS x86_64; pass '
              'ComputeDevice.gpu to place on Metal'
        : 'the stable_diffusion runtime reports no GPU, only '
              '${devices.map((d) => d.name).join(', ')}';
    throw LlamaUnsupportedException(
      'ImageModelPlacement ${moved.join(', ')} needs an engine on a GPU '
      '(Metal, or Vulkan on Linux and Windows), but it runs on $backendName: '
      '$why. Android and the Linux and Windows CPU builds run on the CPU. '
      'Load with the default ImageModelPlacement, or on a GPU.',
    );
  }

  /// [device] (`cpu`, `gpu`, or `null` for the runtime's choice) with the
  /// module assignments of [placement] appended, as stable-diffusion.cpp's
  /// `--backend` takes them.
  static String? _backendAssignment(
    String? device,
    ImageModelPlacement placement,
  ) {
    final parts = [
      ?device,
      if (placement.textEncoderOnCpu) 'te=cpu',
      if (placement.vaeOnCpu) 'vae=cpu',
    ];
    return parts.isEmpty ? null : parts.join(',');
  }

  static String _backendNameFor(
    ComputeDevice device,
    List<StableDiffusionDevice> devices, {
    required bool isMacosX64,
  }) {
    final gpu = devices.map((d) => d.name).where(_isGpu).firstOrNull;
    final cpu = devices
        .where((d) => d.name.toUpperCase() == 'CPU')
        .firstOrNull
        ?.name;
    return switch (device) {
      // An x86_64 process cannot tell an Intel Mac from Rosetta, so both use
      // the CPU unless the caller asks for the GPU.
      ComputeDevice.auto when isMacosX64 => cpu ?? 'CPU',
      ComputeDevice.auto => gpu ?? cpu ?? 'CPU',
      ComputeDevice.cpu => cpu ?? 'CPU',
      ComputeDevice.gpu =>
        gpu ??
            (throw LlamaUnsupportedException(
              'ComputeDevice.gpu needs a GPU, and the stable_diffusion '
              'runtime reports only ${devices.map((d) => d.name).join(', ')}. '
              'Android runs on the CPU; on Linux and Windows set '
              'hooks.user_defines.llamadart.'
              'llamadart_stable_diffusion_backends to [vulkan]. Use '
              'ComputeDevice.auto or cpu otherwise.',
            )),
      ComputeDevice.npu => throw LlamaUnsupportedException(
        'Image generation has no NPU backend: the stable_diffusion runtime '
        'runs on the CPU, Metal or Vulkan. Use ComputeDevice.auto, cpu or '
        'gpu.',
      ),
    };
  }

  static bool _isGpu(String deviceName) {
    final name = deviceName.toLowerCase();
    return _gpuDevicePrefixes.any(name.startsWith);
  }

  static bool _isMetal(String deviceName) {
    final name = deviceName.toLowerCase();
    return name.startsWith('mtl') || name.startsWith('metal');
  }

  /// Flash attention was measured faster or neutral on the CPU and Metal;
  /// other GPU backends keep the runtime default until measured.
  static bool _flashAttentionByDefault(String backendName) =>
      !_isGpu(backendName) || _isMetal(backendName);

  /// Direct VAE convolutions are much slower on Metal, and cost time for
  /// little memory with a tiny autoencoder.
  static bool _vaeDirectConvolutionByDefault(
    String backendName, {
    required bool tinyAutoencoder,
  }) => !_isMetal(backendName) && !tinyAutoencoder;

  /// ggml registry names of GPU devices. The published runtimes use Metal
  /// (`MTL0`) and Vulkan (`Vulkan0`).
  static const List<String> _gpuDevicePrefixes = [
    'mtl',
    'metal',
    'vulkan',
    'cuda',
    'rocm',
    'gpuopencl',
    'opencl',
    'sycl',
  ];
}

/// Estimated peak memory, in bytes, of an image model whose files total
/// [weightBytes]: the weights plus a quarter for compute buffers, plus
/// 512 MiB for the VAE decode and the runtime.
///
/// Measured process peaks at each model's native size, with the automatic
/// attention and VAE settings, stay under it: SDXS Q8 (0.64 GiB of weights)
/// used 1.30 GiB on Metal and SD-Turbo Q8 (1.88 GiB) 2.66 GiB on the CPU,
/// both on an M4 Max; 1024x1024 SDXL, SD 3.5 Large Turbo, FLUX and Z-Image
/// on Metal stayed 0.5 to 1.6 GiB under it, while SD 3.5 Medium with its
/// full VAE peaked 0.3 GiB above. On five Android phones, loading and
/// generating at 512x512 added at most 1.16 GiB to the app for SDXS, 2.26 GiB
/// for SD-Turbo Q8 with TAESD and 2.64 GiB for SD-Turbo Q8 with its full VAE,
/// against estimates of 1.30, 2.87 and 2.86 GiB. Larger sizes than a model's
/// native one need more, especially on the CPU.
///
/// The Apple peaks are `phys_footprint`, which leaves out Metal compute
/// buffers, so the estimate does not model the Metal working set: SD-Turbo at
/// 512x512 allocates a 1664 MB VAE compute buffer that the footprint does not
/// show.
int estimateImageGenerationMemoryBytes(int weightBytes) =>
    weightBytes + weightBytes ~/ 4 + (512 << 20);
