@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/decision/decision_engine.dart';
import 'package:test/test.dart';

import '../../../support/decision_fixture.dart';
import '../../../support/engine_lifecycle_contract.dart';

const _headHandle = 7;
const _headPath = 'laya-head.safetensors';

void main() {
  final fixture = DecisionFixture.load();
  final cases = <String, List<DecisionFixtureRow>>{};
  for (final row in fixture.rows) {
    (cases[row.caseId] ??= []).add(row);
  }

  DecisionRequest requestOf(List<DecisionFixtureRow> rows) => DecisionRequest(
    state: rows.first.state,
    questions: {
      for (final row in rows)
        row.questionId: DecisionQuestion.fromJson(row.question),
    },
  );

  late _DecisionBackend backend;
  late _Downloads engineDownloads;
  late LlamaEngine engine;

  setUp(() {
    backend = _DecisionBackend(fixture);
    engineDownloads = _Downloads();
    engine = LlamaEngine(backend, modelDownloadManager: engineDownloads);
  });

  tearDown(() => engine.dispose());

  Future<DecisionEngine> loadDecisions() async {
    await engine.loadModel('laya-Q8_0.gguf');
    return DecisionEngine.attach(engine, head: ModelSource.path(_headPath));
  }

  group('end to end on the Laya reference fixture', () {
    test('answers all 24 rows in one backend call', () async {
      final decisions = await loadDecisions();
      final caseRows = cases.values.toList();

      final results = await decisions.systemOneBatch([
        for (final rows in caseRows) requestOf(rows),
      ]);

      final sent = backend.runs.single;
      final expectedRows = caseRows.expand((rows) => rows).toList();
      expect(sent, hasLength(24));
      for (var i = 0; i < sent.length; i++) {
        final row = expectedRows[i];
        final question = DecisionQuestion.fromJson(row.question);
        expect(sent[i].tokens, row.ids, reason: row.id);
        expect(sent[i].markers, row.markers, reason: row.id);
        expect(sent[i].questionType, question.type, reason: row.id);
      }
      expect(backend.runHandles, [_headHandle]);
      expect(results, hasLength(caseRows.length));
      for (var c = 0; c < caseRows.length; c++) {
        final rows = caseRows[c];
        final result = results[c];
        expect(result.model, 'laya-rl-agent');
        expect(result.answers.keys, [for (final row in rows) row.questionId]);
        for (final row in rows) {
          expectDecisionJsonClose(
            result.answers[row.questionId]!.toJson(),
            row.answer,
            row.id,
          );
        }
        expect(
          result.usage.inputTokens,
          rows.fold<int>(0, (total, row) => total + row.ids.length),
        );
        expect(result.usage.outputTokens, 0);
      }
    });

    test('tokenizes each distinct text once without special tokens', () async {
      final decisions = await loadDecisions();

      await decisions.systemOneBatch([
        requestOf(cases['readme']!),
        requestOf(cases['readme']!),
      ]);

      expect(backend.tokenized, isNotEmpty);
      expect(backend.tokenized.toSet(), hasLength(backend.tokenized.length));
      expect(backend.addSpecialFlags, everyElement(isFalse));
      expect(backend.runs.single, hasLength(8));
    });

    test('systemOne answers one request in the Laya response shape', () async {
      final decisions = await loadDecisions();
      final rows = cases['readme']!;

      final result = await decisions.systemOne(
        state: rows.first.state,
        questions: requestOf(rows).questions,
      );

      expect(result.choices['department']!.choice, 'billing');
      final json = result.toJson();
      expect(json['model'], 'laya-rl-agent');
      expect(json['usage'], {
        'input_tokens': rows.fold<int>(
          0,
          (total, row) => total + row.ids.length,
        ),
        'output_tokens': 0,
      });
      for (final row in rows) {
        expectDecisionJsonClose(
          (json['answers'] as Map)[row.questionId],
          row.answer,
          row.id,
        );
      }
    });
  });

  group('load', () {
    test('passes the head and config paths and reports model info', () async {
      backend.config = {'max_len': 256, 'head_max_len': 96};
      await engine.loadModel('laya-Q8_0.gguf');

      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path('model.safetensors'),
        config: ModelSource.path('rl_agent_config.json'),
      );

      expect(backend.headLoads, [
        (engine.modelHandle, 'model.safetensors', 'rl_agent_config.json'),
      ]);
      expect(decisions.info.hiddenSize, 1024);
      expect(decisions.info.maxTokens, 256);
      expect(decisions.info.headMaxTokens, 96);
      expect(decisions.info.deviceName, 'Metal');
      expect(decisions.isDisposed, isFalse);
    });

    test('limits sequences to the head config max_len', () async {
      backend.config = {'max_len': 64, 'head_max_len': 32};
      final decisions = await loadDecisions();

      await decisions.systemOne(
        state: 'x' * 500,
        questions: {'q': DecisionQuestion.noul('Is it long?')},
      );

      expect(backend.runs.single.single.tokens, hasLength(64));
    });

    test('limits options to the head config head_max_len', () async {
      backend.config = {'max_len': 512, 'head_max_len': 40};
      final decisions = await loadDecisions();
      final request = DecisionRequest(
        state: 'A long ticket about a duplicate charge.',
        questions: {
          'pick': DecisionQuestion.choice(
            'Which option fits best?',
            criteria: {
              for (var i = 0; i < 8; i++)
                'option $i': 'a long description of option number $i',
            },
          ),
        },
      );

      await decisions.systemOneBatch([request]);

      final markers = backend.runs.single.single.markers;
      expect(markers, hasLength(8));
      expect([
        for (var i = 1; i < markers.length; i++) markers[i] - markers[i - 1],
      ], everyElement(4));
    });

    test('strips the head mask text from every tokenized text', () async {
      backend.maskText = '<mask>';
      final decisions = await loadDecisions();

      await decisions.systemOne(
        state: 'a <mask> b',
        questions: {
          'q': DecisionQuestion.choice(
            'Is <mask> here?',
            criteria: {'x<mask>y': 'the <mask> case', 'other': null},
          ),
        },
      );

      expect(backend.tokenized, isNotEmpty);
      expect(backend.tokenized, everyElement(isNot(contains('<mask>'))));
      expect(backend.tokenized, contains('a   b'));
    });

    test('frees a head that reports no mask text', () async {
      backend.maskText = '';
      await engine.loadModel('laya-Q8_0.gguf');

      await expectLater(
        DecisionEngine.attach(engine, head: ModelSource.path(_headPath)),
        throwsA(
          isA<LlamaDecisionException>().having(
            (error) => error.message,
            'message',
            contains('empty mask token text'),
          ),
        ),
      );
      expect(backend.freed, [_headHandle]);
    });

    test('rejects an unloaded engine without probing the backend', () async {
      await expectLater(
        DecisionEngine.attach(engine, head: ModelSource.path(_headPath)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'Load a model first.',
          ),
        ),
      );
      expect(backend.probedModels, isEmpty);
      expect(backend.headLoads, isEmpty);
    });

    test('rejects an unsupported model with the backend reason', () async {
      backend.capabilities = const BackendDecisionCapabilities(
        isSupported: false,
        unsupportedReason: 'The loaded model is not a modern-bert encoder.',
      );
      await engine.loadModel('gemma.gguf');

      await expectLater(
        DecisionEngine.attach(engine, head: ModelSource.path(_headPath)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The loaded model is not a modern-bert encoder.',
          ),
        ),
      );
      expect(backend.probedModels, [engine.modelHandle]);
      expect(backend.headLoads, isEmpty);
    });

    for (final (name, configJson, message) in [
      ('invalid JSON', 'not json', 'not valid JSON'),
      ('a non-object', '[512]', 'not a JSON object'),
      ('invalid fields', '{"max_len": 0}', '"max_len" must be a positive'),
    ]) {
      test('frees the head when the config is $name', () async {
        backend.configJson = configJson;
        await engine.loadModel('laya-Q8_0.gguf');

        await expectLater(
          DecisionEngine.attach(engine, head: ModelSource.path(_headPath)),
          throwsA(
            isA<LlamaDecisionException>().having(
              (error) => error.message,
              'message',
              contains(message),
            ),
          ),
        );
        expect(backend.freed, [_headHandle]);
      });
    }

    test('frees a head whose model was unloaded while it loaded', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      final gate = backend.headLoadGate = Completer<void>();

      final loading = DecisionEngine.attach(
        engine,
        head: ModelSource.path(_headPath),
      );
      await backend.headLoadStarted.future;
      await engine.unloadModel();
      gate.complete();

      await expectLater(
        loading,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('unloaded while its decision head was loading'),
          ),
        ),
      );
      expect(backend.freed, [_headHandle]);
    });

    test(
      'reports an unload during the capability probe as a state error',
      () async {
        await engine.loadModel('laya-Q8_0.gguf');
        final gate = backend.capabilityGate = Completer<void>();

        final loading = DecisionEngine.attach(
          engine,
          head: ModelSource.path(_headPath),
        );
        await backend.capabilityStarted.future;
        await engine.unloadModel();
        gate.complete();

        await expectLater(
          loading,
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('unloaded while the DecisionEngine was loading'),
            ),
          ),
        );
        expect(backend.headLoads, isEmpty);
      },
    );

    for (final (handle, reuseModelHandle) in [
      ('a new', false),
      ('the', true),
    ]) {
      test('rejects a model swapped in under $handle handle during the '
          'capability probe', () async {
        backend.reuseModelHandle = reuseModelHandle;
        await engine.loadModel('laya-Q8_0.gguf');
        final loadedHandle = engine.modelHandle;
        final gate = backend.capabilityGate = Completer<void>();

        final loading = DecisionEngine.attach(
          engine,
          head: ModelSource.path(_headPath),
        );
        await backend.capabilityStarted.future;
        await engine.unloadModel();
        await engine.loadModel('laya-F16.gguf');
        expect(engine.modelHandle == loadedHandle, reuseModelHandle);
        gate.complete();

        await expectLater(
          loading,
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('unloaded while the DecisionEngine was loading'),
            ),
          ),
        );
        expect(backend.headLoads, isEmpty);
      });
    }
  });

  group('capabilitiesFor', () {
    test('reports an unloaded engine as unsupported', () async {
      final capabilities = await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, 'Load a model first.');
      expect(capabilities.backendName, 'Metal');
      expect(capabilities.runtime, isNull);
      expect(backend.probedModels, isEmpty);
    });

    test('reports a disposed engine as unsupported', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      await engine.dispose();

      final EngineCapabilities capabilities =
          await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('disposed'));
      expect(backend.probedModels, isEmpty);
    });

    test('reports the backend probe for the loaded model', () async {
      await engine.loadModel('laya-Q8_0.gguf');

      final capabilities = await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.unsupportedReason, isNull);
      expect(capabilities.runtime, LlamaRuntime.llamaCpp);
      expect(backend.probedModels, [engine.modelHandle]);
    });

    test('reports a failed probe as unsupported', () async {
      backend.capabilityError = LlamaModelException('probe crashed');
      await engine.loadModel('laya-Q8_0.gguf');

      final capabilities = await DecisionEngine.capabilitiesFor(engine);

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        allOf(contains('probe failed'), contains('probe crashed')),
      );
      expect(capabilities.runtime, LlamaRuntime.llamaCpp);
    });

    test(
      'reports no backend name when the backend cannot name itself',
      () async {
        backend.backendNameError = StateError('no name');
        await engine.loadModel('laya-Q8_0.gguf');

        final capabilities = await DecisionEngine.capabilitiesFor(engine);

        expect(capabilities.isSupported, isTrue);
        expect(capabilities.backendName, isNull);
      },
    );
  });

  group('backend without decision support', () {
    test('reports unsupported before model readiness', () async {
      final plainEngine = LlamaEngine(_PlainBackend());
      addTearDown(plainEngine.dispose);

      final capabilities = await DecisionEngine.capabilitiesFor(plainEngine);

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The active backend does not expose decision models.',
      );
    });

    test('load throws without calling the backend', () async {
      final plain = _PlainBackend();
      final plainEngine = LlamaEngine(plain);
      addTearDown(plainEngine.dispose);
      await plainEngine.loadModel('gemma.gguf');
      plain.calls.clear();

      await expectLater(
        DecisionEngine.attach(plainEngine, head: ModelSource.path(_headPath)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'The active backend does not expose decision models.',
          ),
        ),
      );
      await expectLater(
        plainEngine.loadDecisionHeadBackend(_headPath),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(plain.calls, isEmpty);
    });
  });

  group('validation', () {
    test('rejects an empty question id before tokenizing', () async {
      final decisions = await loadDecisions();

      await expectLater(
        decisions.systemOne(
          state: 'hi',
          questions: {'': DecisionQuestion.noul('Is it?')},
        ),
        throwsA(
          isA<LlamaDecisionException>().having(
            (error) => error.message,
            'message',
            contains('non-empty'),
          ),
        ),
      );
      expect(backend.tokenized, isEmpty);
      expect(backend.runs, isEmpty);
    });

    test('rejects a request without questions before tokenizing', () async {
      final decisions = await loadDecisions();

      await expectLater(
        decisions.systemOne(state: 'hi', questions: const {}),
        throwsA(isA<LlamaDecisionException>()),
      );
      expect(backend.tokenized, isEmpty);
      expect(backend.runs, isEmpty);
    });

    test(
      'rejects options that do not fit before running any request',
      () async {
        final decisions = await loadDecisions();

        await expectLater(
          decisions.systemOneBatch([
            requestOf(cases['readme']!),
            DecisionRequest(
              state: 'hi',
              questions: {
                'many': DecisionQuestion.choice(
                  'Pick one.',
                  criteria: {for (var i = 0; i < 200; i++) 'option $i': null},
                ),
              },
            ),
          ]),
          throwsA(
            isA<LlamaDecisionException>().having(
              (error) => error.message,
              'message',
              contains('"many" options exceed'),
            ),
          ),
        );
        expect(backend.runs, isEmpty);
      },
    );

    for (final (name, request) in [
      (
        'state',
        DecisionRequest(
          state: 'Status report\u0000 Please refund the charge.',
          questions: {'refund': DecisionQuestion.noul('Is a refund asked?')},
        ),
      ),
      (
        'instructions',
        DecisionRequest(
          state: 'Please refund the charge.',
          questions: {'refund': DecisionQuestion.noul('Refund?\u0000 Yes?')},
        ),
      ),
      (
        'choice label',
        DecisionRequest(
          state: 'Please refund the charge.',
          questions: {
            'dept': DecisionQuestion.choice(
              'Which department?',
              criteria: {'bill\u0000ing': null, 'other': null},
            ),
          },
        ),
      ),
    ]) {
      test('rejects U+0000 in the $name before running', () async {
        final decisions = await loadDecisions();

        await expectLater(
          decisions.systemOneBatch([request]),
          throwsA(
            isA<LlamaDecisionException>().having(
              (error) => error.message,
              'message',
              contains('U+0000'),
            ),
          ),
        );
        expect(backend.tokenized, everyElement(isNot(contains('\u0000'))));
        expect(backend.runs, isEmpty);
      });
    }

    test('escapes U+0000 inside a JSON state', () async {
      final decisions = await loadDecisions();

      await decisions.systemOne(
        state: {'body': 'Status report\u0000 Please refund.'},
        questions: {'refund': DecisionQuestion.noul('Is a refund asked?')},
      );

      expect(backend.tokenized, contains(contains(r'\u0000')));
      expect(backend.runs, hasLength(1));
    });

    test('answers an empty batch without calling the backend', () async {
      final decisions = await loadDecisions();

      expect(await decisions.systemOneBatch(const []), isEmpty);
      expect(backend.tokenized, isEmpty);
      expect(backend.runs, isEmpty);
    });

    test('rejects a backend output count that does not match', () async {
      backend.dropOutputs = 1;
      final decisions = await loadDecisions();

      await expectLater(
        decisions.systemOneBatch([requestOf(cases['readme']!)]),
        throwsA(
          isA<LlamaDecisionException>().having(
            (error) => error.message,
            'message',
            contains('3 outputs for 4 sequences'),
          ),
        ),
      );
    });
  });

  group('lifecycle', () {
    test('generic lifecycle ownership frees an attached head once', () async {
      final decisions = await loadDecisions();
      final before = await checkEngineLifecycle(decisions);
      expect(before.isSupported, isTrue);
      expect(backend.freed, [_headHandle]);
      expect(engine.isReady, isTrue);
      expect(engine.isDisposed, isFalse);
    });

    for (final fails in [false, true]) {
      test(
        'disposal publishes terminal state before head cleanup (fails=$fails)',
        () async {
          final decisions = await loadDecisions();
          Future<void>? nested;
          bool? stateInHook;
          Future<DecisionCapabilities>? capsInHook;
          final error = StateError('head cleanup');
          backend.onHeadFree = () {
            backend.onHeadFree = null;
            stateInHook = decisions.isDisposed;
            capsInHook = decisions.capabilities;
            nested = decisions.dispose();
          };
          if (fails) backend.freeError = error;
          final first = decisions.dispose();
          if (fails) {
            await expectLater(first, throwsA(same(error)));
            await expectLater(nested, throwsA(same(error)));
          } else {
            await first;
            await nested;
          }
          expect(stateInHook, isTrue);
          expect(nested, same(first));
          expect((await capsInHook!).isSupported, isFalse);
          expect(decisions.dispose(), same(first));
          expect(backend.freed, [_headHandle]);
        },
      );
    }

    test('dispose is idempotent and frees the head once', () async {
      final decisions = await loadDecisions();

      final first = decisions.dispose();
      final second = decisions.dispose();
      await Future.wait([first, second]);
      await decisions.dispose();

      expect(decisions.isDisposed, isTrue);
      expect(backend.freed, [_headHandle]);
      expect(engine.isReady, isTrue);
    });

    test('calls after dispose throw LlamaStateException', () async {
      final decisions = await loadDecisions();
      await decisions.dispose();

      await expectLater(
        decisions.systemOne(
          state: 'hi',
          questions: {'q': DecisionQuestion.noul('Is it?')},
        ),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        decisions.systemOneBatch(const []),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.tokenized, isEmpty);
      expect(backend.runs, isEmpty);
    });

    test('dispose waits for in-flight calls before freeing', () async {
      final decisions = await loadDecisions();
      final gate = backend.runGate = Completer<void>();
      final rows = cases['readme']!;

      final call = decisions.systemOneBatch([requestOf(rows)]);
      await backend.runStarted.future;
      final disposal = decisions.dispose();
      await pumpEventQueue();

      expect(decisions.isDisposed, isTrue);
      expect(backend.freed, isEmpty);
      gate.complete();
      final results = await call;
      await disposal;

      expect(results.single.answers, hasLength(rows.length));
      expect(backend.freed, [_headHandle]);
    });

    test('a batch answers its requests as they were when it started', () async {
      final decisions = await loadDecisions();
      final gate = backend.runGate = Completer<void>();
      final readme = requestOf(cases['readme']!);
      final requests = [readme];

      final call = decisions.systemOneBatch(requests);
      await backend.runStarted.future;
      requests[0] = DecisionRequest(
        state: 'replaced',
        questions: {'replaced': NoulQuestion('Replaced?')},
      );
      gate.complete();
      final results = await call;

      expect(results.single.answers.keys, readme.questions.keys);
      expect(results.single.questions, readme.questions);
    });

    test('dispose called twice during a call completes both futures', () async {
      final decisions = await loadDecisions();
      final gate = backend.runGate = Completer<void>();

      final call = decisions.systemOneBatch([requestOf(cases['readme']!)]);
      await backend.runStarted.future;
      final first = decisions.dispose();
      final second = decisions.dispose();
      gate.complete();
      await call;

      await Future.wait([first, second]).timeout(const Duration(seconds: 5));
      expect(backend.freed, [_headHandle]);
    });

    test('dispose waits for every in-flight call', () async {
      final decisions = await loadDecisions();
      final firstGate = Completer<void>();
      final secondGate = Completer<void>();
      backend.runGateQueue.addAll([firstGate, secondGate]);

      final firstCall = decisions.systemOneBatch([requestOf(cases['readme']!)]);
      final secondCall = decisions.systemOneBatch([
        requestOf(cases['readme']!),
      ]);
      for (var i = 0; i < 10 && backend.runs.length < 2; i++) {
        await pumpEventQueue();
      }
      expect(backend.runs, hasLength(2));
      final disposal = decisions.dispose();
      firstGate.complete();
      await firstCall;
      await pumpEventQueue();

      expect(backend.freed, isEmpty);
      secondGate.complete();
      await secondCall;
      await disposal;
      expect(backend.freed, [_headHandle]);
    });

    test('concurrent calls all complete', () async {
      final decisions = await loadDecisions();
      final caseRows = cases.values.toList();

      final results = await Future.wait([
        for (final rows in caseRows)
          decisions.systemOne(
            state: rows.first.state,
            questions: requestOf(rows).questions,
          ),
      ]);

      expect(backend.runs, hasLength(caseRows.length));
      for (var c = 0; c < caseRows.length; c++) {
        for (final row in caseRows[c]) {
          expectDecisionJsonClose(
            results[c].answers[row.questionId]!.toJson(),
            row.answer,
            row.id,
          );
        }
      }
    });

    test('engine unload makes calls throw LlamaStateException', () async {
      final decisions = await loadDecisions();
      await engine.unloadModel();

      await expectLater(
        decisions.systemOne(
          state: 'hi',
          questions: {'q': DecisionQuestion.noul('Is it?')},
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('Load the DecisionEngine again'),
          ),
        ),
      );
      expect(backend.runs, isEmpty);
    });

    test('an unload during tokenization throws LlamaStateException', () async {
      final decisions = await loadDecisions();
      final gate = backend.tokenizeGate = Completer<void>();

      final call = decisions.systemOne(
        state: 'hi',
        questions: {'q': DecisionQuestion.noul('Is it?')},
      );
      await backend.tokenizeStarted.future;
      await engine.unloadModel();
      gate.complete();

      await expectLater(
        call,
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('Load the DecisionEngine again'),
          ),
        ),
      );
      expect(backend.runs, isEmpty);
    });

    test('a run error while the model is loaded passes through', () async {
      final decisions = await loadDecisions();
      backend.runError = LlamaInferenceException('head compute failed');

      await expectLater(
        decisions.systemOne(
          state: 'hi',
          questions: {'q': DecisionQuestion.noul('Is it?')},
        ),
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message,
            'message',
            'head compute failed',
          ),
        ),
      );
      expect(backend.runs, hasLength(1));
    });

    for (final (handle, reuseModelHandle) in [
      ('a new', false),
      ('the', true),
    ]) {
      test('a model reloaded under $handle handle is not tokenized', () async {
        backend.reuseModelHandle = reuseModelHandle;
        final decisions = await loadDecisions();
        final loadedHandle = engine.modelHandle;
        await engine.unloadModel();
        await engine.loadModel('laya-Q8_0.gguf');
        expect(engine.modelHandle == loadedHandle, reuseModelHandle);

        await expectLater(
          decisions.systemOne(
            state: 'hi',
            questions: {'q': DecisionQuestion.noul('Is it?')},
          ),
          throwsA(isA<LlamaStateException>()),
        );
        expect(backend.tokenized, isEmpty);
        expect(backend.runs, isEmpty);
      });
    }

    test(
      'a stale engine cannot reach a head that reuses its handles',
      () async {
        backend.reuseModelHandle = true;
        final stale = await loadDecisions();
        await engine.unloadModel();
        await engine.loadModel('laya-Q8_0.gguf');
        final current = await DecisionEngine.attach(
          engine,
          head: ModelSource.path(_headPath),
        );
        expect(backend.headLoads.map((load) => load.$1), [1, 1]);

        await expectLater(
          stale.systemOne(
            state: 'hi',
            questions: {'q': DecisionQuestion.noul('Is it?')},
          ),
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('Load the DecisionEngine again'),
            ),
          ),
        );
        await stale.dispose();

        expect(backend.freed, isEmpty);
        expect(backend.runs, isEmpty);
        final result = await current.systemOne(
          state: 'hi',
          questions: {'q': DecisionQuestion.noul('Is it?')},
        );
        expect(result.nouls['q'], isNotNull);
        expect(backend.runHandles, [_headHandle]);
        await current.dispose();
        expect(backend.freed, [_headHandle]);
      },
    );

    test('dispose after engine unload does not call the backend', () async {
      final decisions = await loadDecisions();
      await engine.unloadModel();

      await decisions.dispose();

      expect(decisions.isDisposed, isTrue);
      expect(backend.freed, isEmpty);
    });

    test('dispose after engine dispose does not call the backend', () async {
      final decisions = await loadDecisions();
      await engine.dispose();

      await decisions.dispose();

      expect(backend.freed, isEmpty);
    });
  });

  group('engine hooks', () {
    test('loadDecisionHeadBackend needs a loaded model', () async {
      await expectLater(
        engine.loadDecisionHeadBackend(_headPath),
        throwsA(isA<LlamaContextException>()),
      );
      expect(backend.headLoads, isEmpty);
    });

    test('hand out engine handles that are never reused', () async {
      backend.reuseModelHandle = true;
      await engine.loadModel('laya-Q8_0.gguf');
      final first = await engine.loadDecisionHeadBackend(_headPath);
      await engine.unloadModel();
      await engine.loadModel('laya-Q8_0.gguf');
      final second = await engine.loadDecisionHeadBackend(_headPath);

      expect(second.handle, isNot(first.handle));
      expect(second.maskText, '[MASK]');
      await engine.runDecisionBackend(second.handle, const []);
      expect(backend.runHandles, [_headHandle]);
    });

    test('freeDecisionHeadBackend forgets the handle', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      final head = await engine.loadDecisionHeadBackend(_headPath);

      await engine.freeDecisionHeadBackend(head.handle);
      await engine.freeDecisionHeadBackend(head.handle);

      await expectLater(
        engine.runDecisionBackend(head.handle, const []),
        throwsA(isA<LlamaStateException>()),
      );
      expect(backend.freed, [_headHandle]);
      expect(backend.runs, isEmpty);
    });

    test(
      'throw LlamaStateException or do nothing on a disposed engine',
      () async {
        await engine.loadModel('laya-Q8_0.gguf');
        final head = await engine.loadDecisionHeadBackend(_headPath);
        await engine.dispose();

        await expectLater(
          engine.loadDecisionHeadBackend(_headPath),
          throwsA(
            isA<LlamaStateException>().having(
              (error) => error.message,
              'message',
              contains('disposed'),
            ),
          ),
        );
        await expectLater(
          engine.runDecisionBackend(head.handle, const []),
          throwsA(isA<LlamaStateException>()),
        );
        await engine.freeDecisionHeadBackend(head.handle);
        expect(
          (await engine.backendDecisionCapabilities).unsupportedReason,
          contains('disposed'),
        );
        expect(engine.modelHandle, isNull);
        expect(engine.contextHandle, isNull);
        expect(backend.headLoads, hasLength(1));
        expect(backend.runs, isEmpty);
        expect(backend.freed, isEmpty);
      },
    );
  });

  group('load with a DecisionModel', () {
    late _DecisionBackend owned;
    late _Downloads downloads;
    var backendsCreated = 0;

    setUp(() {
      backendsCreated = 0;
      downloads = _Downloads();
      debugDecisionBackendFactory = () {
        backendsCreated++;
        return owned = _DecisionBackend(fixture);
      };
    });

    tearDown(() => debugDecisionBackendFactory = null);

    final laya = DecisionModel(
      encoder: ModelSource.parse('https://example.com/laya-Q8_0.gguf'),
      head: ModelSource.parse('https://example.com/laya-head.safetensors'),
      config: ModelSource.path('/models/rl_agent_config.json'),
    );

    Future<DecisionEngine> loadLaya({
      DecisionModelParams params = const DecisionModelParams(),
      ModelLoadOptions download = ModelLoadOptions.defaults,
      ModelDownloadProgressCallback? onProgress,
    }) => DecisionEngine.load(
      laya,
      params: params,
      download: download,
      onProgress: onProgress,
      store: ModelFileStore(downloadManager: downloads),
    );

    test('downloads every file, then loads the encoder for decisions and '
        'the head on it', () async {
      final decisions = await loadLaya(
        params: const DecisionModelParams(
          device: ComputeDevice.cpu,
          threads: 3,
        ),
      );
      addTearDown(decisions.dispose);

      expect(downloads.calls.map((call) => call.$1.fileName), [
        'laya-Q8_0.gguf',
        'laya-head.safetensors',
        'rl_agent_config.json',
      ]);
      final (path, params) = owned.modelLoads.single;
      expect(path, '/cache/laya-Q8_0.gguf');
      expect(params.contextSize, 512);
      expect(params.device, ComputeDevice.cpu);
      expect(params.numberOfThreadsBatch, 3);
      expect(owned.headLoads.single, (
        1,
        '/cache/laya-head.safetensors',
        '/models/rl_agent_config.json',
      ));
    });

    test('a model cache directory that cannot be created fails the load '
        'with LlamaModelException', () async {
      final directory = await Directory.systemTemp.createTemp(
        'llamadart_decision_cache_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final blocker = File('${directory.path}/not-a-directory')
        ..writeAsStringSync('');

      await expectLater(
        DecisionEngine.load(
          DecisionModel(
            encoder: ModelSource.parse('http://127.0.0.1:9/laya-Q8_0.gguf'),
            head: ModelSource.parse('http://127.0.0.1:9/laya-head.safetensors'),
            config: ModelSource.path('/models/rl_agent_config.json'),
          ),
          download: ModelLoadOptions(
            cacheDirectory: '${blocker.path}/cache',
            maxRetries: 0,
          ),
          store: ModelFileStore(
            downloadManager: DefaultModelDownloadManager.appPrivate(
              cacheDirectory: '${directory.path}/cache',
            ),
          ),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Cannot create the model cache directory'),
          ),
        ),
      );
      expect(owned.modelLoads, isEmpty);
    });

    test('reports progress over every file', () async {
      final progress = <(int, int?)>[];

      final decisions = await loadLaya(
        onProgress: (p) => progress.add((p.receivedBytes, p.totalBytes)),
      );
      addTearDown(decisions.dispose);

      expect(progress.first, (50, null));
      expect(progress.last, (210, 210));
      final received = [for (final (bytes, _) in progress) bytes];
      expect(received, orderedEquals([...received]..sort()));
    });

    test('owns the engine: dispose frees the head and the engine', () async {
      final decisions = await loadLaya();

      await Future.wait([decisions.dispose(), decisions.dispose()]);

      expect(owned.freed, [_headHandle]);
      expect(owned.modelFrees, 1);
      expect(owned.disposeCalls, 1);
      expect(
        (await decisions.capabilities).unsupportedReason,
        'The DecisionEngine is disposed.',
      );
    });

    test('capabilities report the backend and runtime', () async {
      final decisions = await loadLaya();
      addTearDown(decisions.dispose);

      final EngineCapabilities capabilities = await decisions.capabilities;

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.unsupportedReason, isNull);
      expect(capabilities.backendName, 'Metal');
      expect(
        (capabilities as DecisionCapabilities).runtime,
        LlamaRuntime.llamaCpp,
      );
    });

    test('an unsupported encoder leaves nothing loaded', () async {
      debugDecisionBackendFactory = () => owned = _DecisionBackend(fixture)
        ..capabilities = const BackendDecisionCapabilities(
          isSupported: false,
          unsupportedReason: 'Not an encoder.',
        );

      await expectLater(
        loadLaya(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            'Not an encoder.',
          ),
        ),
      );
      expect(owned.headLoads, isEmpty);
      expect(owned.modelFrees, 1);
      expect(owned.disposeCalls, 1);
    });

    test('a head that fails to load leaves nothing loaded', () async {
      debugDecisionBackendFactory = () =>
          owned = _DecisionBackend(fixture)
            ..headLoadError = LlamaModelException('Bad head.');

      await expectLater(loadLaya(), throwsA(isA<LlamaModelException>()));
      expect(owned.modelLoads, hasLength(1));
      expect(owned.modelFrees, 1);
      expect(owned.disposeCalls, 1);
    });

    test('a failed download loads nothing', () async {
      downloads.failOn = 'laya-head.safetensors';

      await expectLater(loadLaya(), throwsA(isA<LlamaModelException>()));
      expect(owned.modelLoads, isEmpty);
      expect(owned.disposeCalls, 1);
    });

    test('a cancel after the downloads leaves nothing loaded', () async {
      final cancelToken = ModelDownloadCancelToken();
      downloads.onEnsure = (source) {
        if (source.fileName == 'rl_agent_config.json') cancelToken.cancel();
      };

      await expectLater(
        loadLaya(download: ModelLoadOptions(cancelToken: cancelToken)),
        throwsA(isA<LlamaStateException>()),
      );
      expect(owned.modelLoads, isEmpty);
      expect(owned.disposeCalls, 1);
    });

    test('a cancel during the head load frees everything', () async {
      final cancelToken = ModelDownloadCancelToken();
      debugDecisionBackendFactory = () =>
          owned = _DecisionBackend(fixture)..headLoadGate = Completer<void>();

      final loading = loadLaya(
        download: ModelLoadOptions(cancelToken: cancelToken),
      );
      await owned.headLoadStarted.future;
      cancelToken.cancel();
      owned.headLoadGate!.complete();

      await expectLater(loading, throwsA(isA<LlamaStateException>()));
      expect(owned.modelFrees, 1);
      expect(owned.disposeCalls, 1);
    });

    test('a cancel during the encoder load loads no head', () async {
      final cancelToken = ModelDownloadCancelToken();
      debugDecisionBackendFactory = () =>
          owned = _DecisionBackend(fixture)..onModelLoad = cancelToken.cancel;

      await expectLater(
        loadLaya(download: ModelLoadOptions(cancelToken: cancelToken)),
        throwsA(isA<LlamaStateException>()),
      );
      expect(owned.modelLoads, hasLength(1));
      expect(owned.probedModels, isEmpty);
      expect(owned.headLoads, isEmpty);
      expect(owned.modelFrees, 1);
      expect(owned.disposeCalls, 1);
    });

    test('a cancel from the last progress report loads nothing', () async {
      final cancelToken = ModelDownloadCancelToken();

      await expectLater(
        loadLaya(
          download: ModelLoadOptions(cancelToken: cancelToken),
          onProgress: (progress) {
            if (progress.receivedBytes == progress.totalBytes) {
              cancelToken.cancel();
            }
          },
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            'Decision model loading was cancelled.',
          ),
        ),
      );
      expect(downloads.calls, hasLength(3));
      expect(owned.modelLoads, isEmpty);
      expect(owned.disposeCalls, 1);
    });

    test('rejects credentials for files on two hosts before contacting the '
        'second, naming the hosts but not the credentials', () async {
      final split = DecisionModel(
        encoder: ModelSource.parse('https://a.example.com/laya-Q8_0.gguf'),
        head: ModelSource.parse('https://b.example.com/laya-head.safetensors'),
      );
      for (final download in [
        ModelLoadOptions(bearerToken: 'hf_secret'),
        ModelLoadOptions(headers: const {'X-Key': 'hf_secret'}),
      ]) {
        await expectLater(
          DecisionEngine.load(
            split,
            download: download,
            store: ModelFileStore(downloadManager: downloads),
          ),
          throwsA(
            isA<LlamaArgumentException>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('https://a.example.com:443'),
                contains('https://b.example.com:443'),
                isNot(contains('hf_secret')),
              ),
            ),
          ),
        );
        expect(owned.modelLoads, isEmpty);
        expect(owned.disposeCalls, 1);
      }
      expect(downloads.calls, isEmpty);

      await expectLater(
        DecisionEngine.load(
          laya,
          download: ModelLoadOptions(bearerToken: 'hf_secret'),
          store: ModelFileStore(
            resolver: _MirrorSecondResolver(),
            downloadManager: downloads,
          ),
        ),
        throwsA(isA<LlamaArgumentException>()),
      );
      expect(downloads.calls.map((call) => call.$1.fileName), [
        'laya-Q8_0.gguf',
      ]);
      expect(owned.modelLoads, isEmpty);
    });

    test(
      'rejects settings it cannot apply before creating an engine',
      () async {
        for (final (load, matcher) in [
          (
            () => loadLaya(
              params: const DecisionModelParams(device: ComputeDevice.npu),
            ),
            isA<LlamaUnsupportedException>(),
          ),
          (
            () => loadLaya(params: const DecisionModelParams(threads: -1)),
            isA<LlamaArgumentException>().having(
              (error) => error.name,
              'name',
              'threads',
            ),
          ),
          (
            () => loadLaya(download: ModelLoadOptions(sha256: 'a' * 64)),
            isA<LlamaUnsupportedException>(),
          ),
          (
            () => DecisionEngine.load(
              DecisionModel(
                encoder: ModelSource.path(
                  'laya.litertlm',
                  format: ModelFormat.liteRtLm,
                ),
                head: ModelSource.path('laya-head.safetensors'),
              ),
            ),
            isA<LlamaUnsupportedException>(),
          ),
        ]) {
          await expectLater(load(), throwsA(matcher));
        }
        expect(backendsCreated, 0);
        expect(downloads.calls, isEmpty);
      },
    );

    test('ComputeDevice.gpu reaches the encoder load as ModelParams.device, '
        'without a pre-load GPU query', () async {
      final decisions = await loadLaya(
        params: const DecisionModelParams(device: ComputeDevice.gpu),
      );
      addTearDown(decisions.dispose);

      expect(owned.modelLoads.single.$2.device, ComputeDevice.gpu);
      expect(owned.gpuSupportQueries, 0);
    });

    test('ComputeDevice.gpu the encoder load rejects loads nothing', () async {
      debugDecisionBackendFactory = () =>
          owned = _DecisionBackend(fixture)..gpuSupported = false;

      await expectLater(
        loadLaya(params: const DecisionModelParams(device: ComputeDevice.gpu)),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(owned.headLoads, isEmpty);
      expect(owned.disposeCalls, 1);
    });

    test('on a URL-loading backend the backend fetches every file', () async {
      debugDecisionBackendFactory = () =>
          owned = _DecisionBackend(fixture)..urlLoading = true;
      final progress = <double?>[];

      final decisions = await DecisionEngine.load(
        DecisionModel(
          encoder: ModelSource.parse('https://example.com/laya-Q8_0.gguf'),
          head: ModelSource.path('models/laya-head.safetensors'),
        ),
        onProgress: (p) => progress.add(p.fraction),
        store: ModelFileStore(downloadManager: downloads),
      );
      addTearDown(decisions.dispose);

      expect(downloads.calls, isEmpty);
      expect(owned.urlModelLoads, ['https://example.com/laya-Q8_0.gguf']);
      expect(owned.headLoads.single, (1, 'models/laya-head.safetensors', null));
      expect(progress, [0.5]);
    });

    test(
      'on a URL-loading backend options it cannot apply load nothing',
      () async {
        debugDecisionBackendFactory = () =>
            owned = _DecisionBackend(fixture)..urlLoading = true;

        await expectLater(
          loadLaya(download: ModelLoadOptions(bearerToken: 'secret')),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (error) => error.message,
              'message',
              allOf(contains('decision model'), isNot(contains('secret'))),
            ),
          ),
        );
        expect(owned.urlModelLoads, isEmpty);
        expect(owned.disposeCalls, 1);
      },
    );
  });

  group('attach', () {
    late _Downloads downloads;

    setUp(() => downloads = engineDownloads);

    test('resolves the head and config through the engine store', () async {
      await engine.loadModel('laya-Q8_0.gguf');

      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.parse('https://example.com/laya-head.safetensors'),
        config: ModelSource.path('/models/rl_agent_config.json'),
      );

      expect(backend.headLoads.single, (
        1,
        '/cache/laya-head.safetensors',
        '/models/rl_agent_config.json',
      ));
      expect(decisions.info.maxTokens, 512);
    });

    test('throws LlamaStateException on a disposed engine before resolving '
        'files', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      await engine.dispose();

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.parse('https://example.com/laya-head.safetensors'),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
      expect(backend.headLoads, isEmpty);
    });

    test('borrows the engine: dispose frees only the head', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path(_headPath),
      );

      await decisions.dispose();

      expect(backend.freed, [_headHandle]);
      expect(backend.modelFrees, 0);
      expect(backend.disposeCalls, 0);
      expect(engine.isReady, isTrue);
    });

    test('attaches several heads to one engine', () async {
      await engine.loadModel('laya-Q8_0.gguf');

      final first = await DecisionEngine.attach(
        engine,
        head: ModelSource.path('a.safetensors'),
      );
      final second = await DecisionEngine.attach(
        engine,
        head: ModelSource.path('b.safetensors'),
      );
      await first.dispose();

      expect(backend.headLoads.map((load) => load.$2), [
        'a.safetensors',
        'b.safetensors',
      ]);
      expect((await second.capabilities).isSupported, isTrue);
    });

    test('probes the model before downloading', () async {
      backend.capabilities = const BackendDecisionCapabilities(
        isSupported: false,
        unsupportedReason: 'Not an encoder.',
      );
      await engine.loadModel('laya-Q8_0.gguf');

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.parse('https://example.com/laya-head.safetensors'),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(downloads.calls, isEmpty);
      expect(engine.isReady, isTrue);
    });

    test(
      'applies sha256 to the head alone and rejects it with a config',
      () async {
        await engine.loadModel('laya-Q8_0.gguf');
        final checked = ModelLoadOptions(sha256: 'a' * 64);

        await DecisionEngine.attach(
          engine,
          head: ModelSource.parse('https://example.com/laya-head.safetensors'),
          download: checked,
        );
        await expectLater(
          DecisionEngine.attach(
            engine,
            head: ModelSource.parse(
              'https://example.com/laya-head.safetensors',
            ),
            config: ModelSource.path('rl_agent_config.json'),
            download: checked,
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );

        expect(downloads.calls.single.$2, same(checked));
      },
    );

    test(
      'a model unloaded during the download throws LlamaStateException',
      () async {
        await engine.loadModel('laya-Q8_0.gguf');
        downloads.onEnsure = (_) => engine.unloadModel();

        await expectLater(
          DecisionEngine.attach(
            engine,
            head: ModelSource.parse(
              'https://example.com/laya-head.safetensors',
            ),
          ),
          throwsA(isA<LlamaStateException>()),
        );
        expect(backend.headLoads, isEmpty);
      },
    );

    test('a model reloaded during the download gets no head', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      downloads.onEnsure = (_) async {
        await engine.unloadModel();
        await engine.loadModel('laya-Q8_0.gguf');
      };

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.parse('https://example.com/laya-head.safetensors'),
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('unloaded while the DecisionEngine was loading'),
          ),
        ),
      );
      expect(engine.isReady, isTrue);
      expect(backend.headLoads, isEmpty);
    });

    test('a cancel from the last progress report loads no head', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      final cancelToken = ModelDownloadCancelToken();

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.parse('https://example.com/laya-head.safetensors'),
          download: ModelLoadOptions(cancelToken: cancelToken),
          onProgress: (progress) {
            if (progress.receivedBytes == progress.totalBytes) {
              cancelToken.cancel();
            }
          },
        ),
        throwsA(isA<LlamaStateException>()),
      );
      expect(downloads.calls, hasLength(1));
      expect(backend.headLoads, isEmpty);
      expect(engine.isReady, isTrue);
    });

    test('verifies a local head against sha256', () async {
      final directory = await Directory.systemTemp.createTemp(
        'llamadart_decision_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final head = File('${directory.path}/head.safetensors')
        ..writeAsBytesSync([1, 2, 3]);
      final checkedEngine = LlamaEngine(
        backend,
        modelDownloadManager: DefaultModelDownloadManager.appPrivate(
          cacheDirectory: '${directory.path}/cache',
        ),
      );
      await checkedEngine.loadModel('laya-Q8_0.gguf');

      await expectLater(
        DecisionEngine.attach(
          checkedEngine,
          head: ModelSource.path(head.path),
          download: ModelLoadOptions(sha256: '0' * 64),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Checksum mismatch'),
          ),
        ),
      );
      expect(backend.headLoads, isEmpty);

      final decisions = await DecisionEngine.attach(
        checkedEngine,
        head: ModelSource.path(head.path),
        download: ModelLoadOptions(
          sha256:
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
      );
      await decisions.dispose();
      expect(backend.headLoads, hasLength(1));
    });

    test('rejects credentials for a head and config on two hosts before '
        'contacting either', () async {
      await engine.loadModel('laya-Q8_0.gguf');

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.parse(
            'https://a.example.com/laya-head.safetensors',
          ),
          config: ModelSource.parse(
            'https://b.example.com/rl_agent_config.json',
          ),
          download: ModelLoadOptions(headers: const {'X-Key': 'hf_secret'}),
        ),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.message,
            'message',
            allOf(contains('b.example.com'), isNot(contains('hf_secret'))),
          ),
        ),
      );
      expect(downloads.calls, isEmpty);
      expect(backend.headLoads, isEmpty);
      expect(engine.isReady, isTrue);
    });

    test('capabilities turn unsupported once the model is unloaded', () async {
      await engine.loadModel('laya-Q8_0.gguf');
      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path(_headPath),
      );

      await engine.unloadModel();
      final capabilities = await decisions.capabilities;

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.unsupportedReason, contains('was unloaded'));
    });
  });
}

class _DecisionBackend
    implements LlamaBackend, BackendDecision, BackendRuntimeIdentity {
  _DecisionBackend(this.fixture)
    : config = {
        'max_len': 512,
        'head_max_len': 192,
        'temperature': fixture.temperature,
        'temperature_by_options': fixture.temperatureByOptions,
      },
      _rowsByIds = {for (final row in fixture.rows) jsonEncode(row.ids): row};

  final DecisionFixture fixture;
  final Map<String, DecisionFixtureRow> _rowsByIds;
  bool _ready = false;
  int _nextModelHandle = 1;
  bool reuseModelHandle = false;
  BackendDecisionCapabilities capabilities = const BackendDecisionCapabilities(
    isSupported: true,
  );
  Object? capabilityError;
  Object? backendNameError;
  Object? runError;
  Map<String, Object?> config;
  String? configJson;
  String maskText = '[MASK]';
  int dropOutputs = 0;
  Completer<void>? capabilityGate;
  Completer<void>? headLoadGate;
  Completer<void>? tokenizeGate;
  Completer<void>? runGate;
  final List<Completer<void>> runGateQueue = [];
  final Completer<void> capabilityStarted = Completer<void>();
  final Completer<void> headLoadStarted = Completer<void>();
  final Completer<void> tokenizeStarted = Completer<void>();
  final Completer<void> runStarted = Completer<void>();
  final List<int> probedModels = [];
  final List<(int, String, String?)> headLoads = [];
  final List<String> tokenized = [];
  final List<bool> addSpecialFlags = [];
  final List<int> runHandles = [];
  final List<List<BackendDecisionSequence>> runs = [];
  final List<int> freed = [];
  void Function()? onHeadFree;
  Object? freeError;
  final List<(String, ModelParams)> modelLoads = [];
  final List<String> urlModelLoads = [];
  Object? headLoadError;
  void Function()? onModelLoad;
  bool urlLoading = false;
  bool gpuSupported = true;
  int gpuSupportQueries = 0;
  int modelFrees = 0;
  int disposeCalls = 0;

  @override
  bool get isReady => _ready;

  @override
  bool get supportsUrlLoading => urlLoading;

  @override
  LlamaRuntime? get runtime => _ready ? LlamaRuntime.llamaCpp : null;

  @override
  Future<bool> isGpuSupported() async {
    gpuSupportQueries++;
    return gpuSupported;
  }

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {}

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    modelLoads.add((path, params));
    if (params.device == ComputeDevice.gpu && !gpuSupported) {
      throw LlamaUnsupportedException('No GPU device for llama.cpp.');
    }
    onModelLoad?.call();
    _ready = true;
    return reuseModelHandle ? 1 : _nextModelHandle++;
  }

  @override
  Future<int> modelLoadFromUrl(
    String url,
    ModelParams params, {
    void Function(double progress)? onProgress,
  }) async {
    urlModelLoads.add(url);
    onProgress?.call(0.5);
    _ready = true;
    return _nextModelHandle++;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async => 100;

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {
    modelFrees++;
    _ready = false;
  }

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<String> getBackendName() async {
    final error = backendNameError;
    if (error != null) throw error;
    return 'Metal';
  }

  @override
  Future<List<int>> tokenize(
    int modelHandle,
    String text, {
    bool addSpecial = true,
  }) async {
    tokenized.add(text);
    addSpecialFlags.add(addSpecial);
    if (!tokenizeStarted.isCompleted) tokenizeStarted.complete();
    await tokenizeGate?.future;
    return fixture.pieces[text] ?? text.codeUnits;
  }

  @override
  Future<BackendDecisionCapabilities> decisionCapabilities(
    int modelHandle,
  ) async {
    probedModels.add(modelHandle);
    if (!capabilityStarted.isCompleted) capabilityStarted.complete();
    await capabilityGate?.future;
    final error = capabilityError;
    if (error != null) throw error;
    return capabilities;
  }

  @override
  Future<BackendDecisionHeadInfo> decisionHeadLoad(
    int modelHandle,
    String headPath, {
    String? configPath,
  }) async {
    headLoads.add((modelHandle, headPath, configPath));
    if (!headLoadStarted.isCompleted) headLoadStarted.complete();
    await headLoadGate?.future;
    final error = headLoadError;
    if (error != null) throw error;
    return BackendDecisionHeadInfo(
      handle: _headHandle,
      hiddenSize: 1024,
      clsToken: fixture.clsToken,
      sepToken: fixture.sepToken,
      maskToken: fixture.maskToken,
      maskText: maskText,
      configJson: configJson ?? jsonEncode(config),
      deviceName: 'Metal',
    );
  }

  @override
  Future<List<BackendDecisionOutput>> decisionRun(
    int headHandle,
    List<BackendDecisionSequence> sequences,
  ) async {
    runHandles.add(headHandle);
    runs.add(sequences);
    if (!runStarted.isCompleted) runStarted.complete();
    await (runGateQueue.isEmpty ? runGate : runGateQueue.removeAt(0))?.future;
    final error = runError;
    if (error != null) throw error;
    return [
      for (final sequence in sequences.skip(dropOutputs)) _outputFor(sequence),
    ];
  }

  @override
  Future<void> decisionHeadFree(int headHandle) async {
    onHeadFree?.call();
    freed.add(headHandle);
    if (freeError case final error?) throw error;
  }

  BackendDecisionOutput _outputFor(BackendDecisionSequence sequence) {
    final row = _rowsByIds[jsonEncode(sequence.tokens)];
    return BackendDecisionOutput(
      logits: Float32List.fromList(
        row?.rawLogits ?? List.filled(sequence.markers.length, 0.0),
      ),
      actLogits: Float32List.fromList(row?.rawActLogits ?? const [0.0, 0.0]),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlainBackend implements LlamaBackend {
  final List<Symbol> calls = [];

  @override
  bool get supportsUrlLoading => false;

  @override
  Future<void> setLogLevel(LlamaLogLevel level) async {
    calls.add(#setLogLevel);
  }

  @override
  Future<int> modelLoad(String path, ModelParams params) async {
    calls.add(#modelLoad);
    return 1;
  }

  @override
  Future<int> contextCreate(int modelHandle, ModelParams params) async {
    calls.add(#contextCreate);
    return 2;
  }

  @override
  Future<void> contextFree(int contextHandle) async {}

  @override
  Future<void> modelFree(int modelHandle) async {}

  @override
  void cancelGeneration() {}

  @override
  Future<void> dispose() async {}

  @override
  Future<String> getBackendName() async => 'CPU';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

final class _Downloads extends ThrowingModelDownloadManager {
  final List<(ModelSource, ModelLoadOptions)> calls = [];
  String? failOn;
  FutureOr<void> Function(ModelSource source)? onEnsure;

  @override
  Future<ModelCacheEntry> ensureModel(
    ModelSource source, {
    ModelLoadOptions options = ModelLoadOptions.defaults,
    ModelDownloadProgressCallback? onProgress,
  }) async {
    calls.add((source, options));
    await onEnsure?.call(source);
    if (source.fileName == failOn) {
      throw LlamaModelException('Cannot download ${source.fileName}.');
    }
    final size = source.isRemote ? 100 : 10;
    if (source.isRemote) {
      onProgress?.call(
        ModelDownloadProgress(receivedBytes: size ~/ 2, totalBytes: size),
      );
    }
    final now = DateTime.utc(2026);
    return ModelCacheEntry(
      sourceCanonicalKey: source.canonicalKey,
      cacheKey: source.cacheKey,
      fileName: source.fileName,
      filePath: source.isLocal ? source.path! : '/cache/${source.fileName}',
      bytes: size,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Resolves the second remote source it sees to another host.
final class _MirrorSecondResolver implements ModelResolver {
  int _remotes = 0;

  @override
  Future<ModelLoadTarget> resolve(
    ModelSource source,
    ModelResolveRequest request,
  ) async {
    if (source.isLocal) return LocalModelFile(source.path!);
    _remotes += 1;
    return RemoteModelUrl(
      _remotes == 1
          ? source.resolvedUri!
          : Uri.parse('https://mirror.example.com/${source.fileName}'),
    );
  }
}
