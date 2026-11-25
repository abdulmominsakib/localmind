import '../engine/engine.dart';

/// Package-internal exclusive operation lease for typed speech engines.
class SpeechEngineLease {
  static final Expando<_SpeechEngineLeaseState> _states =
      Expando<_SpeechEngineLeaseState>('llamadart.speechEngineLease');

  final _SpeechEngineLeaseState _state;

  /// Returns the lease shared by all typed speech wrappers over [engine].
  SpeechEngineLease.forEngine(LlamaEngine engine)
    : _state = _states[engine] ??= _SpeechEngineLeaseState();

  /// Whether a typed speech task currently owns the engine.
  bool get isActive => _state.owner != null;

  /// Human-readable owner of the current task, when active.
  String? get activeOwner => _state.owner;

  /// Acquires the engine synchronously before any asynchronous preflight.
  bool acquire(String owner) {
    if (_state.owner != null) {
      return false;
    }
    _state.owner = owner;
    return true;
  }

  /// Sets how [LlamaEngine.unloadModel] cancels [owner]'s running task.
  void onUnload(String owner, void Function() cancel) {
    if (_state.owner == owner) {
      _state.cancel = cancel;
    }
  }

  /// Releases the engine only when [owner] still owns it.
  void release(String owner) {
    if (_state.owner == owner) {
      _state.owner = null;
      _state.cancel = null;
    }
  }

  /// Cancels the task that owns [engine], if it registered [onUnload].
  static void cancelActiveTask(LlamaEngine engine) {
    _states[engine]?.cancel?.call();
  }
}

class _SpeechEngineLeaseState {
  String? owner;
  void Function()? cancel;
}
