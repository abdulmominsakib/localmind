import 'engine_capabilities.dart';

/// Shared lifecycle for text, decision, image and speech engines.
///
/// Use this interface to own engines with different request types together.
/// [C] retains each engine's specific capability fields when the caller knows
/// its type. Loading and inference stay on the concrete engine API.
///
/// Implementations expose a snapshot of their current capabilities and make
/// disposal final and idempotent. Attaching an engine to another engine does
/// not transfer ownership unless its concrete API explicitly says so.
abstract interface class LlamadartEngine<C extends EngineCapabilities> {
  /// A snapshot of the engine's current support and runtime capabilities.
  ///
  /// An unloaded, unavailable or disposed engine reports [EngineCapabilities.isSupported]
  /// as false with an explanation in [EngineCapabilities.unsupportedReason].
  Future<C> get capabilities;

  /// Whether disposal has started, including while cleanup is still pending.
  bool get isDisposed;

  /// Starts final cleanup and returns the same future on subsequent calls.
  ///
  /// Terminal state and the shared future are published before cleanup hooks
  /// can reenter. Cleanup failures complete that future with the error and
  /// are not retried by a later call.
  ///
  /// Await this before releasing resources the engine depends on. Concrete
  /// engines document how in-flight requests and attached engines are handled.
  Future<void> dispose();
}
