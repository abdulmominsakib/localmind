import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../core/cache_policy.dart';
import '../../core/exceptions.dart';
import 'interop.dart';
import 'webgpu_decision.dart';
import 'webgpu_errors.dart';
import 'webgpu_url.dart';

/// LoRA API version that [WebGpuLoraAdapters] speaks.
const int webGpuLoraApiVersion = 1;

/// Runtime LoRA adapters applied through the llama.cpp WebGPU bridge.
///
/// Maps the path-based `setLora`, `removeLora` and `clearLoras` of
/// `LlamaEngine` to bridge adapter handles. The bridge loads each path, a
/// URL, once and keeps it loaded until the next model load or dispose, when
/// the backend calls [forget].
///
/// Each call first probes `getLoraAdapterCapabilities()`. Bridge assets
/// without the LoRA methods, a probe that fails or reports another
/// `apiVersion` or `supported: false`, and a null bridge throw
/// [UnsupportedError], which `LlamaEngine` reports as
/// [LlamaUnsupportedException].
class WebGpuLoraAdapters {
  final Map<String, Future<int>> _handles = <String, Future<int>>{};

  /// Applies the adapter at [path] at [scale], loading it on first use.
  ///
  /// Throws [LlamaArgumentException] for a scale outside finite float32,
  /// [LlamaUnsupportedException] for an aLoRA adapter,
  /// [LlamaModelException] when the adapter cannot be fetched or loaded,
  /// including one made for another base model, [LlamaStateException] when
  /// the bridge refuses the call for its state, and [LlamaContextException]
  /// when it rejects applying the adapter.
  Future<void> set(LlamaWebGpuBridge? bridge, String path, double scale) async {
    webGpuValidateArguments(() {
      if (!scale.isFinite || scale.abs() > 3.4028234663852886e38) {
        throw ArgumentError.value(scale, 'scale', 'must fit a finite float32');
      }
    });
    final active = await _requireSupport(bridge);
    path = webGpuDocumentUrl(path);
    final pending = _handles[path];
    final loading = pending ?? _load(active, path);
    if (pending == null) _handles[path] = loading;
    final int handle;
    try {
      handle = await loading;
    } catch (_) {
      if (identical(_handles[path], loading)) _handles.remove(path);
      rethrow;
    }
    try {
      await _settle(active.setLoraAdapter(handle, scale));
    } catch (error) {
      throw _stateOr(error, path, LlamaContextException.new);
    }
  }

  /// Stops applying the adapter at [path]; a path never set, or whose load
  /// failed, does nothing.
  Future<void> remove(LlamaWebGpuBridge? bridge, String path) async {
    final active = await _requireSupport(bridge);
    path = webGpuDocumentUrl(path);
    final pending = _handles[path];
    if (pending == null) return;
    final int handle;
    try {
      handle = await pending;
    } catch (_) {
      return;
    }
    try {
      await _settle(active.removeLoraAdapter(handle));
    } catch (error) {
      throw _stateOr(error, path, LlamaContextException.new);
    }
  }

  /// Stops applying every adapter.
  Future<void> clear(LlamaWebGpuBridge? bridge) async {
    final active = await _requireSupport(bridge);
    try {
      await _settle(active.clearLoraAdapters());
    } catch (error) {
      throw _stateOr(error, null, LlamaContextException.new);
    }
  }

  /// Forgets every handle; the bridge frees its adapters on a model load or
  /// dispose.
  void forget() => _handles.clear();

  Future<int> _load(LlamaWebGpuBridge bridge, String path) async {
    try {
      final raw = await _settle(
        bridge.loadLoraAdapter(
          path,
          WebGpuLoraAdapterLoadOptions(
            useCache: !hasPersistentCacheSensitiveUrlParts(path),
          ),
        ),
      );
      final handle = raw != null && raw.isA<JSObject>()
          ? _int((raw as WebGpuLoraAdapterInfo).handle)
          : null;
      if (handle == null || handle <= 0) {
        throw LlamaModelException(
          'The Web LoRA runtime returned a malformed adapter handle.',
        );
      }
      return handle;
    } catch (error) {
      if (error is LlamaException) rethrow;
      final message = webGpuBridgeErrorText(error, sourceUrls: <String>[path]);
      if (message.contains('aLoRA adapter')) {
        throw LlamaUnsupportedException(message);
      }
      throw _stateOr(error, path, LlamaModelException.new);
    }
  }

  Future<LlamaWebGpuBridge> _requireSupport(LlamaWebGpuBridge? bridge) async {
    if (bridge == null) {
      throw UnsupportedError(_unsupported('no model is loaded'));
    }
    for (final name in const <String>[
      'getLoraAdapterCapabilities',
      'loadLoraAdapter',
      'setLoraAdapter',
      'removeLoraAdapter',
      'clearLoraAdapters',
    ]) {
      if (!bridge.getProperty<JSAny?>(name.toJS).isA<JSFunction>()) {
        throw UnsupportedError(
          _unsupported('the loaded bridge assets lack the LoRA methods'),
        );
      }
    }
    final JSAny? raw;
    try {
      raw = await _settle(bridge.getLoraAdapterCapabilities());
    } catch (error) {
      throw UnsupportedError(
        _unsupported('the probe failed: ${webGpuBridgeErrorText(error)}'),
      );
    }
    if (raw == null || !raw.isA<JSObject>()) {
      throw UnsupportedError(_unsupported('the probe response is invalid'));
    }
    final capabilities = raw as WebGpuLoraAdapterCapabilities;
    final apiVersion = _int(capabilities.apiVersion);
    if (apiVersion != webGpuLoraApiVersion) {
      throw UnsupportedError(
        _unsupported(
          'the bridge reports LoRA API version ${apiVersion ?? 'unknown'}, '
          'not $webGpuLoraApiVersion',
        ),
      );
    }
    final supported = capabilities.supported;
    if (supported == null ||
        !supported.isA<JSBoolean>() ||
        !(supported as JSBoolean).toDart) {
      final reason = capabilities.reason;
      throw UnsupportedError(
        _unsupported(
          reason != null && reason.isA<JSString>()
              ? (reason as JSString).toDart
              : 'the bridge reports it unsupported',
        ),
      );
    }
    return bridge;
  }

  LlamaException _stateOr(
    Object error,
    String? path,
    LlamaException Function(String message) fallback,
  ) {
    final classified = webGpuBridgeRequestError(
      error,
      sourceUrls: <String>[?path],
    );
    if (classified != null) return classified;
    final message = webGpuBridgeErrorText(error, sourceUrls: <String>[?path]);
    if (message.contains('its model was unloaded or replaced')) {
      if (path != null) _handles.remove(path);
      return LlamaStateException(message);
    }
    if (message.startsWith('No model loaded') ||
        message.contains('Model is not loaded') ||
        message.contains('Bridge has been disposed') ||
        message.contains('during active generation')) {
      return LlamaStateException(message);
    }
    return fallback(message);
  }

  static String _unsupported(String reason) =>
      'WebGPU LoRA adapters need bridge assets whose '
      'getLoraAdapterCapabilities() reports LoRA API version '
      '$webGpuLoraApiVersion as supported (v0.1.54+); $reason. Use a native '
      'llama.cpp backend for LoRA adapters.';

  static Future<JSAny?> _settle(JSAny? value) async {
    if (value != null && value.isA<JSPromise>()) {
      return (value as JSPromise<JSAny?>).toDart;
    }
    return value;
  }

  static int? _int(JSAny? value) {
    if (value == null || !value.isA<JSNumber>()) return null;
    final number = (value as JSNumber).toDartDouble;
    if (!number.isFinite || number != number.truncateToDouble()) return null;
    return number.toInt();
  }
}
