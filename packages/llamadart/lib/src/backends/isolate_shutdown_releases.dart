import 'dart:ffi';

import '../core/exceptions.dart';

/// When an object held by [IsolateShutdownReleases] is freed: every object of
/// an earlier stage before any object of a later one, so an object goes before
/// the objects it uses.
enum ShutdownStage {
  /// Native state used with a context: its token batch and sampler chains,
  /// and per-request sessions such as speculative decoding or text-to-speech.
  session,

  /// ggml schedulers.
  scheduler,

  /// llama.cpp contexts.
  context,

  /// Other objects that use a model, such as mtmd contexts and ggml buffers.
  modelUser,

  /// ggml backends.
  backend,

  /// Models, and stable-diffusion.cpp contexts.
  model,
}

/// Native owner integration used by llama.cpp workers. A stable finalizer
/// drains the native registry; raw allocation-to-registration gaps remain.
abstract interface class IsolateShutdownOwner {
  /// Opaque owner identity, never a payload address.
  Pointer<Void> get token;

  /// Native callback that drains registered stages after worker shutdown.
  Pointer<NativeFinalizerFunction> get releaseAddress;

  /// Returns 2 for an existing native entry, 1 for newly adopted raw state.
  int track(
    ShutdownStage stage,
    Pointer<NativeFinalizerFunction> free,
    Pointer<NativeType> object,
  );

  /// Disowns raw state immediately before its ordinary free.
  void untrack(Pointer<NativeType> object);
}

/// Native objects that are freed when the isolate holding them shuts down
/// before freeing them itself.
///
/// A Dart program that returns from `main`, or dies of an unhandled error,
/// while an engine still has a model loaded never runs the engine's Dart
/// cleanup: the VM shuts its worker isolates down, then calls C `exit`, whose
/// static destructors include ggml-metal's device teardown, which aborts while
/// any Metal buffer is still allocated. The VM runs an isolate's native
/// finalizers when it shuts that isolate down, before that `exit`.
///
/// Objects are freed in [ShutdownStage] order. The VM runs an isolate's native
/// finalizers in the order they were created, so [hold] keeps one finalizer
/// per stage and free function, created in stage order, and re-creates the
/// later ones when a new one is needed.
///
/// Every finalizer is attached to an anchor that lives as long as the isolate,
/// so garbage collection never frees a held object.
final class IsolateShutdownReleases {
  IsolateShutdownReleases._();

  /// The releases of the calling isolate.
  static final IsolateShutdownReleases current = IsolateShutdownReleases._();

  final _Anchor _anchor = _Anchor();
  IsolateShutdownOwner? _owner;
  NativeFinalizer? _ownerFinalizer;
  final Map<
    int,
    ({
      Pointer<NativeFinalizerFunction> free,
      ShutdownStage stage,
      bool nativeTracked,
    })
  >
  _owned = {};

  /// Installs exactly one finalizer before the native owner is activated.
  /// It is never detached or recreated while payloads can exist.
  void installOwner(IsolateShutdownOwner owner) {
    if (_owner != null || _held.isNotEmpty) {
      throw LlamaStateException(
        'Install the native owner before holding objects.',
      );
    }
    _owner = owner;
    final finalizer = NativeFinalizer(owner.releaseAddress);
    _ownerFinalizer = finalizer;
    _ownerFinalizer!.attach(_anchor, owner.token);
  }

  final List<_StageFinalizer> _finalizers = [];
  final Map<int, (_StageFinalizer, Object)> _held = {};

  /// Frees [object] with [free] when this isolate shuts down, unless it is
  /// [release]d first.
  ///
  /// Call it right after [object] is created, and [release] right before
  /// freeing it.
  void hold(
    ShutdownStage stage,
    Pointer<NativeFinalizerFunction> free,
    Pointer<NativeType> object,
  ) {
    if (object == nullptr) {
      return;
    }
    final owner = _owner;
    if (owner != null) {
      final previous = _owned[object.address];
      final tracked = owner.track(stage, free, object);
      if (tracked == 0) {
        throw LlamaStateException(
          'Native worker owner refused object registration.',
        );
      }
      _owned[object.address] = (
        free: free,
        stage: stage,
        nativeTracked: previous?.nativeTracked ?? tracked == 2,
      );
      return;
    }
    release(object);
    final finalizer = _finalizerFor(stage, free);
    final key = Object();
    _held[object.address] = (finalizer, key);
    finalizer.attach(_anchor, object.cast(), key);
  }

  /// The free function and stage of each held object, in the order they
  /// were held.
  List<({Pointer<NativeFinalizerFunction> free, ShutdownStage stage})>
  get debugHeldForTesting => [
    for (final (finalizer, _) in _held.values)
      (free: finalizer.free, stage: finalizer.stage),
    for (final held in _owned.values) (free: held.free, stage: held.stage),
  ];

  /// Stops freeing [object] at shutdown; does nothing if it is not held.
  void release(Pointer<NativeType> object) {
    final owned = _owned.remove(object.address);
    if (owned != null) {
      // Existing tracked creators are freed by their wrapper, which claims the
      // same registry entry. Keep ownership through that free's FFI boundary.
      if (!owned.nativeTracked) _owner!.untrack(object);
      return;
    }
    final held = _held.remove(object.address);
    if (held != null) {
      final (finalizer, key) = held;
      finalizer.detach(key);
    }
  }

  _StageFinalizer _finalizerFor(
    ShutdownStage stage,
    Pointer<NativeFinalizerFunction> free,
  ) {
    for (final finalizer in _finalizers) {
      if (finalizer.stage == stage && finalizer.free == free) {
        return finalizer;
      }
    }
    var index = _finalizers.indexWhere((f) => f.stage.index > stage.index);
    if (index < 0) {
      index = _finalizers.length;
    }
    final finalizer = _StageFinalizer(stage, free);
    _finalizers.insert(index, finalizer);
    for (final later in _finalizers.skip(index + 1)) {
      later.recreate(_anchor);
    }
    return finalizer;
  }
}

final class _Anchor implements Finalizable {}

final class _StageFinalizer {
  _StageFinalizer(this.stage, this.free) : _finalizer = NativeFinalizer(free);

  final ShutdownStage stage;
  final Pointer<NativeFinalizerFunction> free;
  NativeFinalizer _finalizer;
  final Map<Object, Pointer<Void>> _objects = {};

  void attach(_Anchor anchor, Pointer<Void> object, Object key) {
    _objects[key] = object;
    _finalizer.attach(anchor, object, detach: key);
  }

  void detach(Object key) {
    _objects.remove(key);
    _finalizer.detach(key);
  }

  /// Moves every object to a new finalizer, so it runs after every finalizer
  /// created so far. Each object is detached before it is attached again: an
  /// isolate killed in between leaks it rather than freeing it twice.
  void recreate(_Anchor anchor) {
    final previous = _finalizer;
    _finalizer = NativeFinalizer(free);
    for (final MapEntry(key: key, value: object) in _objects.entries) {
      previous.detach(key);
      _finalizer.attach(anchor, object, detach: key);
    }
  }
}
