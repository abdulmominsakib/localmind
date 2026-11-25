import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether this browser grants a WebGPU adapter: `navigator.gpu` exists and
/// `requestAdapter()` resolves to an adapter.
///
/// `navigator.gpu` alone is not enough: browsers expose it while blocking the
/// adapter, for example without a supported GPU driver.
Future<bool> webGpuAdapterAvailable() async {
  final navigator = globalContext.getProperty<JSAny?>('navigator'.toJS);
  if (navigator == null || !navigator.isA<JSObject>()) {
    return false;
  }
  final gpu = (navigator as JSObject).getProperty<JSAny?>('gpu'.toJS);
  if (gpu == null || !gpu.isA<JSObject>()) {
    return false;
  }
  try {
    final request = (gpu as JSObject).callMethod<JSAny?>('requestAdapter'.toJS);
    if (request == null || !request.isA<JSPromise>()) {
      return false;
    }
    final adapter = await (request as JSPromise<JSAny?>).toDart;
    return adapter != null;
  } catch (_) {
    return false;
  }
}
