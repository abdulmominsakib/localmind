import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/engine/generation_cancellation.dart';
import 'package:test/test.dart';

void main() {
  late LlamaEngine engine;
  late GenerationCancellation cancellation;

  /// Returns a request stream over [source] and its request.
  (Stream<int>, GenerationRequest) requestOf(Stream<int> Function() source) {
    late GenerationRequest made;
    final stream = cancellation.request((request) {
      made = request;
      return source();
    });
    return (stream, made);
  }

  setUp(() {
    engine = LlamaEngine(LlamaBackend());
    cancellation = GenerationCancellation.forEngine(engine);
  });

  tearDown(() => engine.dispose());

  /// Returns a request stream and a reader of its check.
  (Stream<int>, bool Function()) request() {
    final (stream, made) = requestOf(
      () => Stream<int>.fromIterable(const <int>[1, 2]),
    );
    return (stream, made.isCancelled);
  }

  test('is shared by every caller of one engine', () {
    expect(GenerationCancellation.forEngine(engine), same(cancellation));
    final other = LlamaEngine(LlamaBackend());
    addTearDown(other.dispose);
    expect(GenerationCancellation.forEngine(other), isNot(same(cancellation)));
  });

  test('reports a cancel issued after listen', () async {
    final (stream, isCancelled) = request();
    final events = stream.toList();
    expect(isCancelled(), isFalse);

    cancellation.cancel();

    expect(isCancelled(), isTrue);
    expect(await events, <int>[1, 2]);
  });

  test('ignores a cancel issued before listen', () async {
    final (stream, isCancelled) = request();
    cancellation.cancel();

    final events = stream.toList();

    expect(isCancelled(), isFalse);
    expect(await events, <int>[1, 2]);
  });

  test('passes an inherited check to requests made inside inherit', () async {
    final source = StreamController<int>();
    addTearDown(source.close);
    final (outer, parent) = requestOf(() => source.stream);
    final subscription = outer.listen(null);
    late bool Function() inner;
    cancellation.inherit(parent, () {
      final (stream, isCancelled) = request();
      stream.listen(null);
      inner = isCancelled;
    });
    final (outside, outsideCancelled) = request();
    outside.listen(null);

    expect(inner(), isFalse);
    await subscription.cancel();
    expect(inner(), isTrue);
    expect(outsideCancelled(), isFalse);
  });

  test('a subscription cancel runs the request stops once and waits for '
      'them', () async {
    final source = StreamController<int>();
    addTearDown(source.close);
    final (stream, made) = requestOf(() => source.stream);
    final stopped = Completer<void>();
    var stops = 0;
    made.onSubscriptionCancel(() {
      stops += 1;
      return stopped.future;
    });
    final subscription = stream.listen(null);
    var cancelReturned = false;

    final cancelled = subscription.cancel().then((_) => cancelReturned = true);

    expect(stops, 1);
    expect(made.isCancelled(), isTrue);
    await pumpEventQueue();
    expect(cancelReturned, isFalse);
    stopped.complete();
    await cancelled;
    await subscription.cancel();
    expect(stops, 1);
  });

  test('a subscription cancel cancels the source before running the '
      'stops', () async {
    final order = <String>[];
    final source = StreamController<int>(onCancel: () => order.add('source'));
    final (stream, made) = requestOf(() => source.stream);
    made.onSubscriptionCancel(() async => order.add('stop'));
    final subscription = stream.listen(null);
    await pumpEventQueue();

    await subscription.cancel();

    expect(order, ['source', 'stop']);
  });

  test('a stop that throws still runs the other stops and fails the '
      'cancel', () async {
    final source = StreamController<int>();
    addTearDown(source.close);
    final (stream, made) = requestOf(() => source.stream);
    final failure = StateError('stop failed');
    var laterStops = 0;
    made
      ..onSubscriptionCancel(() => throw failure)
      ..onSubscriptionCancel(() async => laterStops += 1);
    final subscription = stream.listen(null);

    final cancelled = subscription.cancel();

    expect(laterStops, 1);
    await expectLater(cancelled, throwsA(same(failure)));
  });

  test('a parent subscription cancel runs the stops of inherited requests '
      'only', () async {
    final source = StreamController<int>();
    addTearDown(source.close);
    final (outer, parent) = requestOf(() => source.stream);
    final subscription = outer.listen(null);
    late GenerationRequest child;
    cancellation.inherit(parent, () {
      final (stream, made) = requestOf(
        () => Stream<int>.fromIterable(const <int>[1]),
      );
      stream.listen(null);
      child = made;
    });
    final (outside, other) = requestOf(
      () => Stream<int>.fromIterable(const <int>[1]),
    );
    outside.listen(null);
    final stopped = <String>[];
    child.onSubscriptionCancel(() async => stopped.add('child'));
    other.onSubscriptionCancel(() async => stopped.add('other'));

    await subscription.cancel();

    expect(stopped, ['child']);
  });

  test('cancel runs no stops', () {
    final (stream, made) = requestOf(
      () => Stream<int>.fromIterable(const <int>[1]),
    );
    stream.listen(null);
    var stops = 0;
    made.onSubscriptionCancel(() async => stops += 1);

    cancellation.cancel();

    expect(made.isCancelled(), isTrue);
    expect(stops, 0);
  });

  test('forwards errors and pause to the source stream', () async {
    final source = StreamController<int>();
    addTearDown(source.close);
    final stream = cancellation.request((_) => source.stream);
    final errors = <Object>[];

    final subscription = stream.listen(null, onError: errors.add);
    source.addError(StateError('boom'));
    await Future<void>.delayed(Duration.zero);
    subscription.pause();

    expect(errors.single, isA<StateError>());
    expect(source.isPaused, isTrue);
    await subscription.cancel();
    expect(source.hasListener, isFalse);
  });
}
