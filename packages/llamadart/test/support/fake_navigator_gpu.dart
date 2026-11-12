import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// What a faked `navigator.gpu` does.
enum FakeWebGpu {
  /// `navigator.gpu` is undefined, as in a browser without WebGPU.
  missing,

  /// `requestAdapter()` resolves to null, as when the browser blocks the GPU.
  noAdapter,

  /// `requestAdapter()` rejects.
  failingAdapter,

  /// `requestAdapter()` resolves to an adapter.
  adapter,
}

/// Shadows `navigator.gpu` with [gpu] and returns a function that restores
/// the browser's own.
void Function() fakeNavigatorGpu(FakeWebGpu gpu) {
  final navigator = globalContext.getProperty<JSObject>('navigator'.toJS);
  final descriptor = JSObject()
    ..setProperty('configurable'.toJS, true.toJS)
    ..setProperty('value'.toJS, switch (gpu) {
      FakeWebGpu.missing => null,
      FakeWebGpu.noAdapter => _gpu(() => Future<JSAny?>.value(null)),
      FakeWebGpu.failingAdapter => _gpu(
        () => Future<JSAny?>.error(StateError('adapter request failed')),
      ),
      FakeWebGpu.adapter => _gpu(() => Future<JSAny?>.value(JSObject())),
    });
  globalContext
      .getProperty<JSObject>('Object'.toJS)
      .callMethod<JSAny?>(
        'defineProperty'.toJS,
        navigator,
        'gpu'.toJS,
        descriptor,
      );
  return () => navigator.delete('gpu'.toJS);
}

JSObject _gpu(Future<JSAny?> Function() requestAdapter) =>
    JSObject()
      ..setProperty('requestAdapter'.toJS, (() => requestAdapter().toJS).toJS);
