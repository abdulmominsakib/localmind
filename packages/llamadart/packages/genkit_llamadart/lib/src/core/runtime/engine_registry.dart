import 'dart:async';

import 'package:llamadart/llamadart.dart' as llama;

import '../../api/model_definition.dart';
import 'llama_engine_runtime.dart';
import 'llama_runtime.dart';
import 'operation_usage.dart';

class EngineRegistry {
  EngineRegistry({
    required Iterable<LlamaModelDefinition> models,
    LlamaRuntimeFactory? runtimeFactory,
    Iterable<llama.LlamaEngineObserver> observers = const [],
  }) : _definitions = {for (final model in models) model.name: model},
       _runtimeFactory = runtimeFactory ?? _defaultFactory(observers);

  static LlamaRuntimeFactory _defaultFactory(
    Iterable<llama.LlamaEngineObserver> observers,
  ) {
    final snapshot = List<llama.LlamaEngineObserver>.unmodifiable(observers);
    return () => LlamaEngineRuntime(observers: snapshot);
  }

  final Map<String, LlamaModelDefinition> _definitions;
  final LlamaRuntimeFactory _runtimeFactory;
  final Map<String, _EngineEntry> _entries = {};
  final Map<String, List<void Function()>> _capabilityListeners = {};
  Future<void>? _disposeFuture;

  llama.LlamaEngineCapabilities? capabilitiesFor(String modelName) =>
      _entries[modelName]?.capabilities;

  llama.LlamaEmbeddingCapabilities? embeddingCapabilitiesFor(
    String modelName,
  ) => _entries[modelName]?.embeddingCapabilities;

  // Call only inside this model's withRuntime operation, after initialization.
  Future<llama.LlamaEmbeddingCapabilities?> probeEmbeddingCapabilities(
    String modelName,
    LlamaRuntime runtime,
  ) async {
    if (runtime is! LlamaRuntimeEmbeddingProvider) return null;
    final llama.LlamaEmbeddingCapabilities snapshot;
    try {
      snapshot = await (runtime as LlamaRuntimeEmbeddingProvider)
          .embeddingCapabilities;
    } catch (_) {
      throw llama.LlamaStateException('Unable to verify embedding modalities.');
    }
    _entries[modelName]!.embeddingCapabilities = snapshot;
    _notifyCapabilities(modelName);
    return snapshot;
  }

  String capabilityStateFor(String modelName) {
    final entry = _entries[modelName];
    if (entry == null || !entry.capabilitiesChecked) return 'unloaded';
    return entry.capabilities == null ? 'unverified' : 'verified';
  }

  void onCapabilitiesChanged(String modelName, void Function() listener) {
    (_capabilityListeners[modelName] ??= []).add(listener);
  }

  void _notifyCapabilities(String modelName) {
    for (final listener in _capabilityListeners[modelName] ?? []) {
      listener();
    }
  }

  Future<T> withRuntime<T>(
    String modelName,
    Future<T> Function(LlamaRuntime runtime) operation, {
    void Function()? beforeInitialize,
  }) {
    if (_disposeFuture != null) {
      throw StateError('The llamadart engine registry has been disposed.');
    }

    final definition = _definitions[modelName];
    if (definition == null) {
      throw StateError('Unknown llamadart model: $modelName');
    }

    final entry = _entries.putIfAbsent(
      modelName,
      () => _EngineEntry(
        definition,
        _runtimeFactory,
        () => _notifyCapabilities(modelName),
      ),
    );
    return entry.run(operation, beforeInitialize: beforeInitialize);
  }

  /// Cancels generation or typed embedding for [modelName] without queueing behind
  /// it. Throws [StateError] for a model name that was never registered
  /// (consistent with [withRuntime]); a no-op for a registered model whose
  /// runtime hasn't loaded yet or has no cancellable backend work.
  void cancelActiveGeneration(String modelName) {
    if (!_definitions.containsKey(modelName)) {
      throw StateError('Unknown llamadart model: $modelName');
    }
    _entries[modelName]?.cancelGeneration();
  }

  /// Cancels generation and typed embedding across loaded runtimes, bypassing the
  /// per-model operation queue so a cancel never waits behind the run it stops.
  void cancelActiveGenerations() {
    for (final entry in _entries.values) {
      entry.cancelGeneration();
    }
  }

  Future<void> dispose() {
    return _disposeFuture ??= _disposeEntries();
  }

  Future<void> _disposeEntries() async {
    final entries = _entries.values.toList(growable: false);
    try {
      await entries.map((entry) => entry.dispose()).wait;
    } finally {
      _entries.clear();
    }
  }
}

class _EngineEntry {
  _EngineEntry(
    this._definition,
    this._runtimeFactory,
    this._onCapabilitiesChanged,
  );

  final LlamaModelDefinition _definition;
  final LlamaRuntimeFactory _runtimeFactory;
  final void Function() _onCapabilitiesChanged;

  llama.LlamaEngineCapabilities? capabilities;
  llama.LlamaEmbeddingCapabilities? embeddingCapabilities;
  bool capabilitiesChecked = false;

  Future<void> _tail = Future<void>.value();
  Future<LlamaRuntime>? _loading;
  LlamaRuntime? _runtime;
  bool _initializationCleanupFailed = false;

  /// Cancels the runtime's in-flight generation directly, without going through
  /// the operation queue. Reads the loaded runtime field, so it is a no-op while
  /// the model is still loading or idle.
  void cancelGeneration() {
    if (_initializationCleanupFailed) return;
    _runtime?.cancelGeneration();
  }

  Future<T> run<T>(
    Future<T> Function(LlamaRuntime runtime) operation, {
    void Function()? beforeInitialize,
  }) {
    final completer = Completer<T>();
    final capture = Zone.current[operationUsageKey] as OperationUsage?;
    final queued = capture == null ? null : (Stopwatch()..start());

    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        capture?.queueMs = queued!.elapsedMicroseconds / 1000;
        beforeInitialize?.call();
        final loading = capture == null ? null : (Stopwatch()..start());
        final runtime = await _ensureRuntime();
        capture?.initializationMs = loading!.elapsedMicroseconds / 1000;
        await _readCapabilities(runtime);
        final result = await operation(runtime);
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<void> dispose() async {
    await _tail.catchError((Object _) {});

    if (_initializationCleanupFailed) throw _failedInitializationCleanup();

    final runtime = _runtime;
    _runtime = null;
    _loading = null;
    capabilities = null;
    embeddingCapabilities = null;
    capabilitiesChecked = false;
    _onCapabilitiesChanged();

    if (runtime != null) {
      await runtime.dispose();
    }
  }

  Future<void> _readCapabilities(LlamaRuntime runtime) async {
    // Never reuse a snapshot if a custom runtime changes or unloads its model.
    capabilities = null;
    embeddingCapabilities = null;
    capabilitiesChecked = true;
    _onCapabilitiesChanged();
    if (runtime is! LlamaRuntimeCapabilityProvider) return;
    try {
      capabilities =
          await (runtime as LlamaRuntimeCapabilityProvider).capabilities;
    } catch (_) {
      throw llama.LlamaStateException(
        'Unable to verify runtime capabilities. Retry the request or check '
        'the LlamaRuntimeCapabilityProvider implementation.',
      );
    }
    _onCapabilitiesChanged();
  }

  Future<LlamaRuntime> _ensureRuntime() async {
    if (_initializationCleanupFailed) throw _failedInitializationCleanup();
    if (_runtime != null) {
      return _runtime!;
    }

    final existingLoad = _loading;
    if (existingLoad != null) {
      return existingLoad;
    }

    final loadFuture = () async {
      final runtime = _runtimeFactory();
      try {
        await runtime.initialize(_definition);
        _runtime = runtime;
        return runtime;
      } catch (_) {
        _runtime = null;
        try {
          await runtime.dispose();
        } catch (_) {
          // Cleanup may have partially released native resources. Retain the
          // uncertain runtime and failure; neither retry nor admission release
          // can be justified by a later no-op dispose.
          _runtime = runtime;
          _initializationCleanupFailed = true;
          throw _failedInitializationCleanup();
        }
        rethrow;
      } finally {
        _loading = null;
      }
    }();

    _loading = loadFuture;
    return loadFuture;
  }
}

llama.LlamaStateException
_failedInitializationCleanup() => llama.LlamaStateException(
  'Runtime initialization cleanup failed. The context cannot be reused or replaced until native resources are checked.',
);
