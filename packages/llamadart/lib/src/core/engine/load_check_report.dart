import '../exceptions.dart';
import '../models/config/compute_device.dart';
import '../models/model_format.dart';
import 'engine_observer.dart';

/// The outcome of `LlamaEngine.checkLoad`.
///
/// Later versions may add statuses, so a `switch` over them needs a default
/// case.
enum LlamaLoadCheckStatus {
  /// Every check `LlamaEngine.setModel` runs before it resolves a file
  /// passed. Like `collectLlamaRuntimeSetupReport`, this is policy, not a
  /// load. Not checked: the runtime's native library or browser assets, the
  /// device an [ComputeDevice.auto] load picks, LoRA adapter limits (checked
  /// once the model file resolves), the file and its memory, and
  /// `ModelLoadOptions`, which `checkLoad` does not take.
  supported,

  /// `LlamaEngine.setModel` would throw [LlamaLoadCheckReport.error] before
  /// it resolves or downloads a file.
  unsupported,

  /// Neither `ModelSource.format` nor the file name names the model's
  /// format, so its runtime is checked only once the load reads the file,
  /// after any download.
  deferred,

  /// The engine's own checks passed, but the backend cannot tell before the
  /// load whether this platform runs the model: it does not implement
  /// `BackendLoadCheck`, as with `LlamaEngine(LiteRtLmBackend())`, or it runs
  /// one runtime and the file name names another format, which it loads
  /// anyway. [LlamaLoadCheckReport.reason] says which.
  unknown,
}

/// What `LlamaEngine.checkLoad` found about loading a model, before any file
/// resolves or downloads and without starting a runtime.
final class LlamaLoadCheckReport {
  const LlamaLoadCheckReport._({
    required this.status,
    required this.format,
    required this.runtime,
    required this.device,
    this.error,
    this.reason,
  });

  /// The outcome.
  final LlamaLoadCheckStatus status;

  /// The format the checks used: `ModelSource.format`, otherwise the one the
  /// file name's extension names. Null when neither names one: always for
  /// [LlamaLoadCheckStatus.deferred], and for
  /// [LlamaLoadCheckStatus.unsupported] when a backend rejects the load
  /// without knowing the format.
  final ModelFormat? format;

  /// The runtime that would load the model, or null when the status is
  /// [LlamaLoadCheckStatus.deferred] or the backend does not report one.
  final LlamaRuntime? runtime;

  /// The device the load would ask [runtime] for: `ModelParams.device`.
  /// [ComputeDevice.auto] is the runtime's own choice, which it makes when it
  /// loads the model.
  final ComputeDevice device;

  /// The exception `LlamaEngine.setModel` would throw before any file
  /// resolves, naming the missing capability and the platform or runtime
  /// condition; non-null exactly when the status is
  /// [LlamaLoadCheckStatus.unsupported].
  final LlamaUnsupportedException? error;

  /// Why the load is not [LlamaLoadCheckStatus.supported]: the message of
  /// [error], or what is left unchecked; null when supported.
  final String? reason;

  /// Whether every check before the load passed.
  bool get isSupported => status == LlamaLoadCheckStatus.supported;

  @override
  String toString() {
    final fields = [
      status.name,
      if (format case final format?) 'format: ${format.name}',
      if (runtime case final runtime?) 'runtime: ${runtime.name}',
      'device: ${device.name}',
      if (reason case final reason?) 'reason: $reason',
    ];
    return 'LlamaLoadCheckReport(${fields.join(', ')})';
  }
}

/// Internal construction boundary for `LlamaEngine`, outside the app export.
LlamaLoadCheckReport buildLoadCheckReport({
  required ModelFormat? format,
  required LlamaRuntime? runtime,
  required ComputeDevice device,
  LlamaUnsupportedException? error,
  String? backendUncheckedReason,
}) {
  if (error != null) {
    return LlamaLoadCheckReport._(
      status: LlamaLoadCheckStatus.unsupported,
      format: format,
      runtime: runtime,
      device: device,
      error: error,
      reason: error.message,
    );
  }
  if (format == null) {
    return LlamaLoadCheckReport._(
      status: LlamaLoadCheckStatus.deferred,
      format: null,
      runtime: null,
      device: device,
      reason:
          'Neither ModelSource.format nor the file name names the model '
          'format, so its runtime is checked when the load reads the file. '
          'Set ModelSource.format to check it before loading.',
    );
  }
  if (backendUncheckedReason != null) {
    return LlamaLoadCheckReport._(
      status: LlamaLoadCheckStatus.unknown,
      format: format,
      runtime: runtime,
      device: device,
      reason: backendUncheckedReason,
    );
  }
  return LlamaLoadCheckReport._(
    status: LlamaLoadCheckStatus.supported,
    format: format,
    runtime: runtime,
    device: device,
  );
}
