import 'dart:async';

import 'engine.dart';

/// Package-internal record of generation cancellation from
/// [LlamaEngine.cancelGeneration], model unload/replacement, disposal and
/// generation subscription cancels.
///
/// A generation stream runs setup (template rendering, media checks) before
/// it reaches the backend, and the backend can only cancel work it has
/// started. This lets a request honour a cancel issued after its stream was
/// listened to but before it reached the backend. It also lets a subscription
/// cancel reach the backend at once, instead of at the generator's next
/// `yield`.
class GenerationCancellation {
  static final Expando<GenerationCancellation> _instances =
      Expando<GenerationCancellation>('llamadart.generationCancellation');

  int _epoch = 0;
  GenerationRequest? _inherited;

  GenerationCancellation._();

  /// Returns the record shared by every caller of [engine].
  factory GenerationCancellation.forEngine(LlamaEngine engine) =>
      _instances[engine] ??= GenerationCancellation._();

  /// Cancels every request whose stream has been listened to.
  void cancel() {
    _epoch += 1;
  }

  /// Returns the stream [start] builds for one request.
  ///
  /// The request passed to [start] belongs to the returned stream. A request
  /// made inside [inherit] also inherits the cancels of the request passed to
  /// [inherit].
  Stream<T> request<T>(Stream<T> Function(GenerationRequest request) start) {
    final request = GenerationRequest._(this, _inherited);
    return _RequestStream<T>(start(request), request);
  }

  /// Calls [create], making [parent] the parent of every [request] it makes.
  R inherit<R>(GenerationRequest parent, R Function() create) {
    final previous = _inherited;
    _inherited = parent;
    try {
      return create();
    } finally {
      _inherited = previous;
    }
  }
}

/// One request made by [GenerationCancellation.request].
final class GenerationRequest {
  final GenerationCancellation _owner;
  final GenerationRequest? _parent;
  final List<Future<void> Function()> _stops = <Future<void> Function()>[];
  int? _listenedAt;
  bool _subscriptionCancelled = false;

  GenerationRequest._(this._owner, this._parent);

  /// Whether this request or an ancestor is cancelled: its subscription was
  /// cancelled, or [GenerationCancellation.cancel] ran after its stream was
  /// listened to.
  bool isCancelled() =>
      _subscriptionCancelled ||
      (_listenedAt != null && _listenedAt != _owner._epoch) ||
      (_parent?.isCancelled() ?? false);

  /// Calls [stop] when the subscription of this request or of any ancestor
  /// is cancelled, before that cancel returns.
  void onSubscriptionCancel(Future<void> Function() stop) {
    for (GenerationRequest? request = this; request != null;) {
      request._stops.add(stop);
      request = request._parent;
    }
  }

  List<Future<void>> _cancelSubscription() {
    if (_subscriptionCancelled) {
      return const <Future<void>>[];
    }
    _subscriptionCancelled = true;
    return <Future<void>>[
      for (final stop in List.of(_stops)) Future<void>.sync(stop),
    ];
  }
}

class _RequestStream<T> extends Stream<T> {
  final Stream<T> _source;
  final GenerationRequest _request;

  _RequestStream(this._source, this._request);

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _request._listenedAt ??= _request._owner._epoch;
    return _RequestSubscription<T>(
      _source.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      _request,
    );
  }
}

class _RequestSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _source;
  final GenerationRequest _request;

  _RequestSubscription(this._source, this._request);

  /// Cancels the source before running the stops. A stop can let the
  /// generator finish synchronously, and a source still listened to would
  /// then deliver its last events and done inside this cancel.
  @override
  Future<void> cancel() {
    final sourceCancelled = _source.cancel();
    final stops = _request._cancelSubscription();
    return Future.wait<void>(<Future<void>>[
      sourceCancelled,
      ...stops,
    ]).then<void>((_) {});
  }

  @override
  void onData(void Function(T data)? handleData) => _source.onData(handleData);

  @override
  void onError(Function? handleError) => _source.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _source.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _source.pause(resumeSignal);

  @override
  void resume() => _source.resume();

  @override
  bool get isPaused => _source.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _source.asFuture<E>(futureValue);
}
