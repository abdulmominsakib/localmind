import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/src/backends/webgpu/interop.dart';

@JS('Promise.reject')
external JSPromise<JSAny?> _rejectPromise(JSAny? reason);

/// A promise rejected with a JS error object carrying [message].
JSPromise<JSAny?> rejectWithMessage(String message) =>
    _rejectPromise(JSObject()..setProperty('message'.toJS, message.toJS));

@JS('DOMException')
extension type _DomException._(JSObject _) implements JSObject {
  external _DomException(String message, String name);
}

@JS('Object.defineProperty')
external void _defineProperty(
  JSObject target,
  String name,
  JSObject descriptor,
);

/// A promise rejected like a bridge decision API failure.
///
/// [code] becomes an own `code` property, as the bridge's error helper sets
/// it. With [abort] the error is a DOMException named `AbortError`, whose
/// legacy `code` is the number 20 unless [code] replaces it.
JSPromise<JSAny?> rejectWithCode(
  String message, {
  JSAny? code,
  bool abort = false,
}) {
  final error = abort
      ? _DomException(message, 'AbortError')
      : (JSObject()..setProperty('message'.toJS, message.toJS));
  if (code != null) {
    _defineProperty(
      error,
      'code',
      JSObject()
        ..setProperty('value'.toJS, code)
        ..setProperty('configurable'.toJS, true.toJS),
    );
  }
  return _rejectPromise(error);
}

/// One `runDecision` sequence as the fake bridge received it.
typedef FakeDecisionSequence = ({
  List<int> tokens,
  List<int> markers,
  int questionType,
  bool typedArrays,
});

/// A fake llama-web-bridge instance with the decision API.
///
/// Follows the bridge's documented behavior: handles are never reused,
/// `freeDecisionHead` ignores unknown handles, and `dispose` or a model load
/// frees every head. Handles start at 7, so tests can tell them from backend
/// handles. While an `*Error` field is set, matching calls reject with it.
class FakeDecisionBridge {
  /// Creates the fake. Without [withDecisionApi] it models bridge assets that
  /// predate the decision API; [withModelApi] adds the model-load, tokenizer
  /// and lifecycle methods `WebGpuLlamaBackend` needs.
  FakeDecisionBridge({bool withDecisionApi = true, bool withModelApi = false}) {
    if (withDecisionApi) _installDecisionApi();
    if (withModelApi) _installModelApi();
  }

  /// The JS object handed to the backend.
  final JSObject object = JSObject();

  /// [object] as the interop type.
  LlamaWebGpuBridge get bridge => object as LlamaWebGpuBridge;

  /// `apiVersion` reported by `getDecisionCapabilities`.
  int capabilitiesApiVersion = 1;

  /// `supported` reported by `getDecisionCapabilities`.
  bool supported = true;

  /// `reason` reported by `getDecisionCapabilities`, when set.
  String? reason;

  /// Replaces the whole `getDecisionCapabilities` result when set.
  JSAny? capabilitiesResult;

  /// Fields that replace or, when null, remove head info fields.
  Map<String, Object?> headInfoOverrides = <String, Object?>{};

  /// Replaces the `runDecision` result when set.
  JSAny? Function()? runResult;

  /// Rejection messages for matching calls.
  String? capabilitiesError, loadError, runError, freeError;

  /// `code` and AbortError shape of every `*Error` rejection, when set.
  JSAny? errorCode;
  bool errorAsAbort = false;

  /// Every decision call, in order.
  final List<String> calls = <String>[];

  /// `configJson` of each `loadDecisionHead` call, null when absent.
  final List<String?> loadedConfigs = <String?>[];

  /// Sequences of the last `runDecision` call.
  List<FakeDecisionSequence> lastSequences = const [];

  /// Bridge handles of loaded, unfreed heads.
  final Set<int> liveHandles = <int>{};

  /// Number of `dispose` calls.
  int disposeCalls = 0;

  int _nextHandle = 7;

  JSPromise<JSAny?> _reject(String message) =>
      rejectWithCode(message, code: errorCode, abort: errorAsAbort);

  void _installDecisionApi() {
    object.setProperty(
      'getDecisionCapabilities'.toJS,
      (() {
        calls.add('capabilities');
        final error = capabilitiesError;
        if (error != null) return _reject(error);
        final result =
            capabilitiesResult ??
            (JSObject()
              ..setProperty('apiVersion'.toJS, capabilitiesApiVersion.toJS)
              ..setProperty('supported'.toJS, supported.toJS)
              ..setProperty('reason'.toJS, reason?.toJS));
        return Future<JSAny?>.value(result).toJS;
      }).toJS,
    );
    object.setProperty(
      'loadDecisionHead'.toJS,
      ((JSAny? source, JSObject? options) {
        final url = (source as JSString).toDart;
        final config = options?.getProperty<JSAny?>('configJson'.toJS);
        final configJson = config != null && config.isA<JSString>()
            ? (config as JSString).toDart
            : null;
        calls.add('load $url');
        loadedConfigs.add(configJson);
        final error = loadError;
        if (error != null) return _reject(error);
        final handle = _nextHandle++;
        liveHandles.add(handle);
        final info = <String, Object?>{
          'apiVersion': 1,
          'handle': handle,
          'hiddenSize': 4,
          'clsToken': 1,
          'sepToken': 2,
          'maskToken': 3,
          'maskText': '[MASK]',
          'configJson': configJson ?? '{"max_len": 32, "head_max_len": 16}',
          'deviceName': 'WebGPU',
          ...headInfoOverrides,
        };
        final result = JSObject();
        for (final MapEntry(:key, :value) in info.entries) {
          if (value != null) result.setProperty(key.toJS, value.jsify());
        }
        return Future<JSAny?>.value(result).toJS;
      }).toJS,
    );
    object.setProperty(
      'runDecision'.toJS,
      ((JSNumber rawHandle, JSArray<JSObject> sequences) {
        final handle = rawHandle.toDartInt;
        lastSequences = [
          for (final sequence in sequences.toDart) _sequenceOf(sequence),
        ];
        calls.add('run $handle ${lastSequences.length}');
        final error = runError;
        if (error != null) return _reject(error);
        if (!liveHandles.contains(handle)) {
          return rejectWithMessage(
            'Decision head $handle is not loaded; it was freed, its model '
            'was unloaded, or the bridge runtime restarted. Load the decision '
            'head again.',
          );
        }
        final custom = runResult;
        if (custom != null) return Future<JSAny?>.value(custom()).toJS;
        final outputs = <JSObject>[
          for (final sequence in lastSequences)
            JSObject()
              ..setProperty(
                'logits'.toJS,
                Float32List.fromList([
                  for (var i = sequence.markers.length; i > 0; i--)
                    i.toDouble(),
                ]).toJS,
              )
              ..setProperty(
                'actLogits'.toJS,
                Float32List.fromList([1.5, -0.5]).toJS,
              ),
        ];
        return Future<JSAny?>.value(outputs.toJS).toJS;
      }).toJS,
    );
    object.setProperty(
      'freeDecisionHead'.toJS,
      ((JSNumber rawHandle) {
        final handle = rawHandle.toDartInt;
        calls.add('free $handle');
        final error = freeError;
        if (error != null) return _reject(error);
        liveHandles.remove(handle);
        return Future<JSAny?>.value().toJS;
      }).toJS,
    );
  }

  void _installModelApi() {
    object.setProperty(
      'loadModelFromUrl'.toJS,
      ((String url, JSObject? options) {
        calls.add('loadModel $url');
        liveHandles.clear();
        return Future<JSAny?>.value().toJS;
      }).toJS,
    );
    object.setProperty(
      'tokenize'.toJS,
      ((String text, bool? addSpecial) {
        final ids = Uint32List.fromList([
          for (final unit in text.codeUnits.take(3)) 10 + unit % 90,
        ]);
        return Future<JSAny?>.value(ids.toJS).toJS;
      }).toJS,
    );
    object.setProperty(
      'dispose'.toJS,
      (() {
        disposeCalls++;
        liveHandles.clear();
        return Future<JSAny?>.value().toJS;
      }).toJS,
    );
    object.setProperty('cancel'.toJS, (() {}).toJS);
    object.setProperty('setLogLevel'.toJS, ((JSAny? level) {}).toJS);
    object.setProperty('getBackendName'.toJS, (() => 'WebGPU (Fake)').toJS);
    object.setProperty('getContextSize'.toJS, (() => 512).toJS);
    object.setProperty('isGpuActive'.toJS, (() => true).toJS);
    object.setProperty(
      'getModelMetadata'.toJS,
      (() => JSObject()
            ..setProperty('general.architecture'.toJS, 'modern-bert'.toJS))
          .toJS,
    );
  }

  static FakeDecisionSequence _sequenceOf(JSObject sequence) {
    final tokens = sequence.getProperty<JSAny?>('tokens'.toJS);
    final markers = sequence.getProperty<JSAny?>('markers'.toJS);
    final typed =
        tokens != null &&
        markers != null &&
        tokens.isA<JSInt32Array>() &&
        markers.isA<JSInt32Array>();
    return (
      tokens: typed ? (tokens as JSInt32Array).toDart.toList() : const [],
      markers: typed ? (markers as JSInt32Array).toDart.toList() : const [],
      questionType: sequence
          .getProperty<JSNumber>('questionType'.toJS)
          .toDartInt,
      typedArrays: typed,
    );
  }
}
