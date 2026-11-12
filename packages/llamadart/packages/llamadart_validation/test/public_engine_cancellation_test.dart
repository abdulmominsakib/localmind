import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

/// Mirrors the public engine's listen-time cancellation and the native
/// backend's single running generation: a request issued after a cancel waits
/// for the cancelled run, and one issued beside a running request fails.
class ScriptedEngine implements LlamaEngine {
  ScriptedEngine({this.eofGated = false});
  final bool eofGated;
  int decodedTokens = 0;
  final events = <String>[];
  final requests = <GenerationParams>[];
  var _epoch = 0;
  _Run? _active;

  @override
  void cancelGeneration() {
    _epoch++;
    events.add('cancel');
    _active?.cancelled = true;
  }

  @override
  Stream<String> generate(
    String prompt, {
    GenerationParams params = const GenerationParams(),
    List<LlamaContentPart>? parts,
  }) {
    requests.add(params);
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        final listenedAt = _epoch;
        events.add('listen:$prompt');
        unawaited(() async {
          await Future<void>.delayed(Duration.zero);
          if (_epoch != listenedAt) {
            events.add('skipped:$prompt');
            await controller.close();
            return;
          }
          final running = _active;
          if (running != null && !running.cancelled) {
            events.add('rejected:$prompt');
            controller.addError(
              LlamaStateException('llama.cpp generation is already running'),
            );
            await controller.close();
            return;
          }
          if (running != null) await running.done.future;
          final run = _active = _Run();
          final pending = StringBuffer();
          decodedTokens = 0;
          for (var i = 0; i < params.maxTokens && !run.cancelled; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
            if (!run.cancelled) {
              decodedTokens++;
              if (eofGated) {
                pending.write('$prompt$i ');
              } else {
                controller.add('$prompt$i ');
              }
            }
          }
          if (eofGated && !run.cancelled) controller.add(pending.toString());
          _active = null;
          events.add('end:$prompt');
          await controller.close();
          run.done.complete();
        }());
      },
    );
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Run {
  bool cancelled = false;
  final done = Completer<void>();
}

void main() {
  final profile = ValidationProfile.fromJson(
    jsonDecode(File('assets/profiles/chat-gguf-cpu.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test(
    'cancel on listen is issued after listening and before output',
    () async {
      final engine = ScriptedEngine();
      final adapter = PublicValidationEngine(engineFactory: () => engine);
      final cancelled = await adapter.generate(
        'a',
        profile,
        raw: true,
        cancelOnListen: true,
      );
      expect(engine.events, ['listen:a', 'cancel', 'skipped:a']);
      expect(cancelled['content'], '');
      expect(cancelled['chunks'], 0);
      expect(cancelled['cancel_requested'], true);
      expect(cancelled['chunks_before_cancel'], 0);
      expect(cancelled['cancel_to_done_ms'], isNonNegative);
      final control = await adapter.generate('a', profile, raw: true);
      expect(control['content'], isNotEmpty);
      expect(control['cancel_requested'], false);
    },
  );

  test('restart issues the second request after the cancel, before the '
      'cancelled stream ends', () async {
    final engine = ScriptedEngine();
    final pair = await PublicValidationEngine(engineFactory: () => engine)
        .generateOverlapping(
          'long',
          'short',
          profile,
          raw: true,
          firstMaxTokens: 256,
          cancelFirst: true,
        );
    expect(engine.events.take(3), ['listen:long', 'cancel', 'listen:short']);
    expect(
      engine.events.indexOf('end:long'),
      lessThan(engine.events.indexOf('end:short')),
    );
    expect(pair['second_issued'], true);
    expect(pair['first_cancelled_before_second_issued'], true);
    expect(pair['first_ended_before_second_issued'], false);
    final first = pair['first'] as Map;
    final second = pair['second'] as Map;
    expect(first['content'], 'long0 ');
    expect(second['content'], startsWith('short0 '));
    expect(
      (second['timeline_ms'] as Map)['first_delta'] as num,
      greaterThanOrEqualTo((pair['timeline_ms'] as Map)['first_ended'] as num),
    );
  });

  test('overlap records the typed rejection and cancels the first request '
      'at its next delta', () async {
    final engine = ScriptedEngine();
    final pair = await PublicValidationEngine(engineFactory: () => engine)
        .generateOverlapping(
          'long',
          'short',
          profile,
          raw: true,
          firstMaxTokens: 256,
          cancelFirst: false,
        );
    expect(engine.events.take(3), [
      'listen:long',
      'listen:short',
      'rejected:short',
    ]);
    expect(engine.events.sublist(3), ['cancel', 'end:long']);
    final second = pair['second'] as Map;
    expect(second['state_exception'], true);
    expect(second['error_type'], 'LlamaStateException');
    expect(pair['first_cancelled_before_second_issued'], false);
    expect(pair['first_deltas_after_second_ended'], greaterThanOrEqualTo(1));
    final timeline = pair['timeline_ms'] as Map;
    expect(
      timeline['second_ended'] as num,
      lessThanOrEqualTo(timeline['first_cancel'] as num),
    );
    expect((pair['first'] as Map)['stream_completed'], true);
  });

  test(
    'timed cancel interrupts EOF-gated work before any visible delta',
    () async {
      final engine = ScriptedEngine(eofGated: true);
      final adapter = PublicValidationEngine(engineFactory: () => engine);
      final cancelled = await adapter.generate(
        'long',
        profile,
        raw: true,
        maxTokens: 100,
        cancelAfterMs: 30,
      );
      expect(engine.decodedTokens, inExclusiveRange(0, 100));
      expect(cancelled['cancel_requested'], true);
      expect(cancelled['chunks_before_cancel'], 0);
      expect(cancelled['content'], '');
      expect(cancelled['stream_completed'], true);
      final recovery = await adapter.generate(
        'short',
        profile,
        raw: true,
        maxTokens: 2,
      );
      expect(recovery['content'], 'short0 short1 ');
      expect(recovery['cancel_requested'], false);
    },
  );

  test(
    'timed overlap rejects before EOF and the first stream continues',
    () async {
      final engine = ScriptedEngine(eofGated: true);
      final pair = await PublicValidationEngine(engineFactory: () => engine)
          .generateOverlapping(
            'long',
            'short',
            profile,
            raw: true,
            firstMaxTokens: 100,
            cancelFirst: false,
            secondAfterMs: 20,
          );
      expect((pair['second'] as Map)['state_exception'], true);
      expect(pair['first_ended_before_second_issued'], false);
      expect(pair['first_cancelled_before_second_issued'], false);
      expect(pair['first_deltas_after_second_ended'], greaterThanOrEqualTo(1));
      expect((pair['first'] as Map)['content'], startsWith('long0 '));
      expect(
        engine.events.indexOf('rejected:short'),
        lessThan(engine.events.indexOf('end:long')),
      );
    },
  );

  test('completed streams disarm timers before recovery', () async {
    final engine = ScriptedEngine(eofGated: true);
    final adapter = PublicValidationEngine(engineFactory: () => engine);
    final first = await adapter.generate(
      'a',
      profile,
      raw: true,
      maxTokens: 1,
      cancelAfterMs: 30,
    );
    expect(first['cancel_requested'], false);
    final pair = await adapter.generateOverlapping(
      'b',
      'missed',
      profile,
      raw: true,
      firstMaxTokens: 1,
      cancelFirst: false,
      secondAfterMs: 30,
    );
    expect(pair['second_issued'], false);
    final recovery = await adapter.generate(
      'recovery',
      profile,
      raw: true,
      maxTokens: 100,
    );
    expect(recovery['content'], endsWith('recovery99 '));
    expect(engine.events, isNot(contains('cancel')));
    expect(engine.events, isNot(contains('listen:missed')));
  });

  test('grammar reaches the generation parameters', () async {
    final engine = ScriptedEngine();
    await PublicValidationEngine(
      engineFactory: () => engine,
    ).generate('a', profile, raw: true, grammar: 'root ::= "a"');
    expect(engine.requests.single.grammar, 'root ::= "a"');
  });
}
