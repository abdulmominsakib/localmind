// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  tearDown(LlamaLogging.configure);

  test('configure sets both levels and the handler', () async {
    final records = <LlamaLogRecord>[];
    await LlamaLogging.configure(
      level: LlamaLogLevel.info,
      nativeLevel: LlamaLogLevel.error,
      handler: records.add,
    );

    expect(LlamaLogging.level, LlamaLogLevel.info);
    expect(LlamaLogging.nativeLevel, LlamaLogLevel.error);
    LlamaLogger.instance.debug('dropped');
    LlamaLogger.instance.info('kept');
    expect(records.map((record) => record.message), ['kept']);
  });

  test('nativeLevel defaults to level', () async {
    await LlamaLogging.configure(level: LlamaLogLevel.warn);

    expect(LlamaLogging.nativeLevel, LlamaLogLevel.warn);
  });

  test('configure reaches every live engine until it is disposed', () async {
    final first = _LogLevelBackend();
    final second = _LogLevelBackend();
    final firstEngine = LlamaEngine(first);
    final secondEngine = LlamaEngine(second);
    addTearDown(firstEngine.dispose);

    await LlamaLogging.configure(
      level: LlamaLogLevel.info,
      nativeLevel: LlamaLogLevel.warn,
    );
    await secondEngine.dispose();
    await LlamaLogging.configure(level: LlamaLogLevel.error);

    expect(first.dartLevels, [LlamaLogLevel.info, LlamaLogLevel.error]);
    expect(first.nativeLevels, [LlamaLogLevel.warn, LlamaLogLevel.error]);
    expect(second.dartLevels, [LlamaLogLevel.info]);
    expect(second.nativeLevels, [LlamaLogLevel.warn]);
  });

  test('a backend that never answers does not block configure', () async {
    final warnings = <LlamaLogRecord>[];
    final gate = Completer<void>();
    final stuck = _LogLevelBackend()..gate = gate;
    final healthy = _LogLevelBackend();
    final stuckEngine = LlamaEngine(stuck);
    final healthyEngine = LlamaEngine(healthy);
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      await stuckEngine.dispose();
      await healthyEngine.dispose();
    });

    final stopwatch = Stopwatch()..start();
    await LlamaLogging.configure(
      level: LlamaLogLevel.warn,
      handler: warnings.add,
    ).timeout(const Duration(seconds: 5));

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(healthy.dartLevels, [LlamaLogLevel.warn]);
    expect(stuck.dartLevels, isEmpty);
    expect(
      warnings.single.message,
      contains('did not take the new log levels'),
    );

    gate.complete();
    await pumpEventQueue();
    expect(stuck.dartLevels, [LlamaLogLevel.warn]);
    expect(stuck.nativeLevels, [LlamaLogLevel.warn]);
  });

  test('backends that never answer are waited for together', () async {
    final warnings = <LlamaLogRecord>[];
    final gate = Completer<void>();
    final stuckEngines = [
      for (var i = 0; i < 3; i++) LlamaEngine(_LogLevelBackend()..gate = gate),
    ];
    addTearDown(() async {
      if (!gate.isCompleted) gate.complete();
      for (final engine in stuckEngines) {
        await engine.dispose();
      }
    });

    final stopwatch = Stopwatch()..start();
    await LlamaLogging.configure(
      level: LlamaLogLevel.warn,
      handler: warnings.add,
    ).timeout(const Duration(seconds: 10));

    // One second for all of them; one after another would take three.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(warnings, hasLength(3));
  });

  test('a failing backend warns and does not stop the others', () async {
    final warnings = <LlamaLogRecord>[];
    await LlamaLogging.configure(
      level: LlamaLogLevel.warn,
      handler: warnings.add,
    );
    final failing = _LogLevelBackend()..failure = StateError('worker gone');
    final healthy = _LogLevelBackend();
    final failingEngine = LlamaEngine(failing);
    final healthyEngine = LlamaEngine(healthy);
    addTearDown(failingEngine.dispose);
    addTearDown(healthyEngine.dispose);

    await LlamaLogging.configure(
      level: LlamaLogLevel.warn,
      nativeLevel: LlamaLogLevel.info,
      handler: warnings.add,
    );

    expect(healthy.nativeLevels, [LlamaLogLevel.info]);
    expect(
      warnings.single.message,
      contains('Could not apply log levels to a running backend'),
    );
    expect(warnings.single.error, isA<StateError>());
  });

  group('deprecated LlamaEngine forwarders', () {
    late _LogLevelBackend backend;
    late LlamaEngine engine;

    setUp(() {
      backend = _LogLevelBackend();
      engine = LlamaEngine(backend);
    });

    tearDown(() => engine.dispose());

    test('setDartLogLevel then configureLogging: the last call wins', () async {
      await engine.setDartLogLevel(LlamaLogLevel.info);
      LlamaEngine.configureLogging(level: LlamaLogLevel.error);
      await pumpEventQueue();

      expect(LlamaLogging.level, LlamaLogLevel.error);
      expect(engine.dartLogLevel, LlamaLogLevel.error);
      expect(backend.dartLevels.last, LlamaLogLevel.error);
    });

    test('configureLogging then setDartLogLevel: the last call wins and '
        'the handler is kept', () async {
      final records = <LlamaLogRecord>[];
      LlamaEngine.configureLogging(
        level: LlamaLogLevel.error,
        handler: records.add,
      );
      await engine.setDartLogLevel(LlamaLogLevel.info);
      LlamaLogger.instance.info('kept');

      expect(LlamaLogging.level, LlamaLogLevel.info);
      expect(backend.dartLevels.last, LlamaLogLevel.info);
      expect(records.map((record) => record.message), ['kept']);
    });

    test(
      'configureLogging and setDartLogLevel keep the native level',
      () async {
        await engine.setNativeLogLevel(LlamaLogLevel.warn);
        LlamaEngine.configureLogging(level: LlamaLogLevel.info);
        await engine.setDartLogLevel(LlamaLogLevel.error);
        await pumpEventQueue();

        expect(LlamaLogging.nativeLevel, LlamaLogLevel.warn);
        expect(engine.nativeLogLevel, LlamaLogLevel.warn);
        expect(backend.nativeLevels.toSet(), {LlamaLogLevel.warn});
      },
    );

    test('setNativeLogLevel keeps the Dart level', () async {
      await engine.setDartLogLevel(LlamaLogLevel.info);
      await engine.setNativeLogLevel(LlamaLogLevel.error);

      expect(LlamaLogging.level, LlamaLogLevel.info);
      expect(LlamaLogging.nativeLevel, LlamaLogLevel.error);
    });

    test('setLogLevel sets both levels on every live engine', () async {
      final other = _LogLevelBackend();
      final otherEngine = LlamaEngine(other);
      addTearDown(otherEngine.dispose);

      await engine.setLogLevel(LlamaLogLevel.warn);

      expect(LlamaLogging.level, LlamaLogLevel.warn);
      expect(LlamaLogging.nativeLevel, LlamaLogLevel.warn);
      expect(other.dartLevels, [LlamaLogLevel.warn]);
      expect(other.nativeLevels, [LlamaLogLevel.warn]);
    });
  });
}

class _LogLevelBackend implements LlamaBackend, BackendDartLogLevel {
  final List<LlamaLogLevel> dartLevels = <LlamaLogLevel>[];
  final List<LlamaLogLevel> nativeLevels = <LlamaLogLevel>[];
  Object? failure;
  Completer<void>? gate;

  @override
  bool get isReady => false;

  @override
  Future<void> setDartLogLevel(LlamaLogLevel level) async {
    final error = failure;
    if (error != null) throw error;
    await gate?.future;
    dartLevels.add(level);
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    nativeLevels.add(level);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
