@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/decision_head.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/ggml_graph_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/native_barrier_api.dart';
import 'package:llamadart/src/backends/llama_cpp/safetensors.dart';
import 'package:llamadart/src/core/decision/decision_decoder.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../../../support/fake_native_barrier.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_decision_head.dart';

void main() {
  late Directory dir;

  setUpAll(() => LlamaCppService().initializeBackend());

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_decision_head_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  SafetensorsFile writeHead(
    SyntheticDecisionHead head, [
    String file = 'head',
  ]) {
    final path = '${dir.path}${Platform.pathSeparator}$file.safetensors';
    head.write(path);
    final opened = SafetensorsFile.open(path);
    addTearDown(opened.close);
    return opened;
  }

  DecisionHeadRuntime createRuntime(SyntheticDecisionHead head) {
    final weights = DecisionHeadWeights.read(
      writeHead(head),
      hiddenSize: head.d,
      layers: head.layers,
    );
    final runtime = DecisionHeadRuntime.create(
      weights,
      cpuThreads: 2,
      opOffload: false,
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  void expectMatchesReference(
    DecisionHeadRuntime runtime,
    SyntheticDecisionHead head, {
    required int tokens,
    required DecisionQuestionType questionType,
    required List<int> markers,
  }) {
    final hidden = head.randomHidden(tokens);
    final output = runtime.run(
      hidden,
      tokens,
      questionType,
      Int32List.fromList(markers),
    );
    final (logits, actLogits) = head.reference(hidden, questionType, markers);

    expect(output.logits, hasLength(markers.length));
    expect(output.actLogits, hasLength(SyntheticDecisionHead.actClasses));
    for (var i = 0; i < logits.length; i++) {
      expect(output.logits[i], closeTo(logits[i], 1e-4), reason: 'logit $i');
    }
    for (var i = 0; i < actLogits.length; i++) {
      expect(
        output.actLogits[i],
        closeTo(actLogits[i], 1e-4 * math.max(1, actLogits[i].abs())),
        reason: 'act logit $i',
      );
    }
  }

  group('DecisionHeadRuntime', () {
    test('matches a pure-Dart reference with one attention head', () {
      final head = SyntheticDecisionHead(d: 64, layers: 2, seed: 1);
      final runtime = createRuntime(head);

      expect(runtime.deviceName, 'CPU');
      for (final type in DecisionQuestionType.values) {
        expectMatchesReference(
          runtime,
          head,
          tokens: 12,
          questionType: type,
          markers: [3, 5, 8],
        );
      }
    });

    test('matches the reference with two heads, one layer and one option', () {
      final head = SyntheticDecisionHead(d: 128, layers: 1, seed: 2);
      final runtime = createRuntime(head);

      expectMatchesReference(
        runtime,
        head,
        tokens: 7,
        questionType: DecisionQuestionType.noul,
        markers: [4],
      );
      expectMatchesReference(
        runtime,
        head,
        tokens: 1,
        questionType: DecisionQuestionType.choice,
        markers: [0],
      );
    });

    test('runs on an explicitly passed CPU device', () {
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 4);
      final weights = DecisionHeadWeights.read(
        writeHead(head),
        hiddenSize: 64,
        layers: 1,
      );
      final cpu = GgmlGraphApi.current.devByType(
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
      );
      final runtime = DecisionHeadRuntime.create(
        weights,
        device: cpu,
        cpuThreads: 1,
        opOffload: true,
      );
      addTearDown(runtime.dispose);

      expect(runtime.deviceName, 'CPU');
      expectMatchesReference(
        runtime,
        head,
        tokens: 5,
        questionType: DecisionQuestionType.score,
        markers: [1, 2, 3],
      );
    });

    test('rejects inputs outside the run contract', () {
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 5);
      final runtime = createRuntime(head);
      final hidden = head.randomHidden(4);
      const choice = DecisionQuestionType.choice;

      expect(
        () => runtime.run(hidden, 5, choice, Int32List.fromList([1])),
        throwsArgumentError,
      );
      expect(
        () => runtime.run(hidden, 4, choice, Int32List(0)),
        throwsArgumentError,
      );
      expect(
        () => runtime.run(hidden, 4, choice, Int32List.fromList([1, 4])),
        throwsArgumentError,
      );
      expect(
        () => runtime.run(hidden, 4, choice, Int32List.fromList([-1])),
        throwsArgumentError,
      );
    });

    test('rejects fewer than one CPU thread', () {
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 6);
      final weights = DecisionHeadWeights.read(
        writeHead(head),
        hiddenSize: 64,
        layers: 1,
      );

      expect(
        () => DecisionHeadRuntime.create(
          weights,
          cpuThreads: 0,
          opOffload: false,
        ),
        throwsArgumentError,
      );
    });

    test('fails runs after dispose and disposes idempotently', () {
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 7);
      final runtime = createRuntime(head)
        ..dispose()
        ..dispose();

      expect(
        () => runtime.run(
          head.randomHidden(2),
          2,
          DecisionQuestionType.choice,
          Int32List.fromList([1]),
        ),
        throwsA(isA<LlamaStateException>()),
      );
    });
  });

  group('DecisionHeadRuntime native resources', () {
    DecisionHeadWeights weightsOf(SyntheticDecisionHead head) =>
        DecisionHeadWeights.read(
          writeHead(head),
          hiddenSize: head.d,
          layers: head.layers,
        );

    test('dispose frees everything create made, scheduler first', () {
      final ledger = _GgmlLedger();
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 20);
      final runtime = DecisionHeadRuntime.create(
        weightsOf(head),
        cpuThreads: 1,
        opOffload: false,
        api: ledger.api,
      );
      runtime.run(
        head.randomHidden(3),
        3,
        DecisionQuestionType.choice,
        Int32List.fromList([1, 2]),
      );
      expect(ledger.live, hasLength(4));
      final beforeDispose = ledger.events.length;

      runtime
        ..dispose()
        ..dispose();

      expect(ledger.live, isEmpty);
      expect(ledger.events.sublist(beforeDispose).map((e) => e.$1), [
        'schedSynchronize',
        'schedFree',
        'bufferFree',
        'free',
        'backendFree',
      ]);
    });

    test('holds what create made for isolate shutdown until dispose', () {
      final releases = IsolateShutdownReleases.current;
      final before = releases.debugHeldForTesting.length;
      final runtime = DecisionHeadRuntime.create(
        weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 27)),
        cpuThreads: 1,
        opOffload: false,
      );

      // The CPU backend, the weights buffer and the scheduler.
      expect(releases.debugHeldForTesting.length, before + 3);
      runtime.dispose();
      expect(releases.debugHeldForTesting.length, before);
    });

    test('create releases what it held when the scheduler fails', () {
      final releases = IsolateShutdownReleases.current;
      final before = releases.debugHeldForTesting.length;

      expect(
        () => DecisionHeadRuntime.create(
          weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 28)),
          cpuThreads: 1,
          opOffload: false,
          api: _GgmlLedger(failSched: true).api,
        ),
        throwsA(isA<LlamaModelException>()),
      );
      expect(releases.debugHeldForTesting.length, before);
    });

    test('create frees what it made when the scheduler fails', () {
      final ledger = _GgmlLedger(failSched: true);

      expect(
        () => DecisionHeadRuntime.create(
          weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 21)),
          cpuThreads: 1,
          opOffload: false,
          api: ledger.api,
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('scheduler'),
          ),
        ),
      );
      expect(ledger.events.map((e) => e.$1), contains('bufferFree'));
      expect(ledger.live, isEmpty);
    });

    test('create frees what it made when the weights cannot be allocated', () {
      final ledger = _GgmlLedger(failAlloc: true);

      expect(
        () => DecisionHeadRuntime.create(
          weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 26)),
          cpuThreads: 1,
          opOffload: false,
          api: ledger.api,
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('Could not allocate decision head weights on CPU'),
          ),
        ),
      );
      expect(ledger.events.map((e) => e.$1), contains('bufferAlloc'));
      expect(ledger.live, isEmpty);
    });

    test('create reads the head file and frees what it made if it cannot', () {
      final ledger = _GgmlLedger();
      final file = writeHead(SyntheticDecisionHead(d: 64, layers: 1, seed: 25));
      final weights = DecisionHeadWeights.read(file, hiddenSize: 64, layers: 1);
      file.close();

      expect(
        () => DecisionHeadRuntime.create(
          weights,
          cpuThreads: 1,
          opOffload: false,
          api: ledger.api,
        ),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains(file.path),
          ),
        ),
      );
      expect(
        ledger.events.map((e) => e.$1),
        containsAllInOrder(['bufferAlloc', 'bufferFree']),
      );
      expect(ledger.live, isEmpty);
    });

    test('sets the CPU thread count through the CPU registry', () {
      final ledger = _GgmlLedger();
      final runtime = DecisionHeadRuntime.create(
        weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 22)),
        cpuThreads: 3,
        opOffload: false,
        api: ledger.api,
      );
      addTearDown(runtime.dispose);

      expect(ledger.threadCounts, [3]);
    });

    test('starts one backend for an explicitly passed CPU device', () {
      final ledger = _GgmlLedger();
      final cpu = GgmlGraphApi.current.devByType(
        ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
      );
      final runtime = DecisionHeadRuntime.create(
        weightsOf(SyntheticDecisionHead(d: 64, layers: 1, seed: 23)),
        device: cpu,
        cpuThreads: 1,
        opOffload: true,
        api: ledger.api,
      );
      addTearDown(runtime.dispose);

      expect(ledger.events.where((e) => e.$1 == 'devInit'), hasLength(1));
      expect(ledger.schedulerBackends.single, hasLength(1));
    });

    test('schedules the device backend first and the CPU backend last', () {
      final ledger = _GgmlLedger(deviceStandIn: true);
      final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 24);
      final runtime = DecisionHeadRuntime.create(
        weightsOf(head),
        device: _GgmlLedger.standInDevice,
        cpuThreads: 1,
        opOffload: true,
        api: ledger.api,
      );
      final backends = ledger.events
          .where((e) => e.$1 == 'devInit')
          .map((e) => e.$2)
          .toList();

      expect(backends, hasLength(2));
      expect(ledger.allocBackends, [backends[1]]);
      expect(ledger.schedulerBackends.single, [backends[1], backends[0]]);
      runtime.dispose();
      expect(ledger.live, isEmpty);
    });
  });

  group('DecisionHeadRuntime with the exception barrier', () {
    late _GgmlLedger ledger;
    late FakeNativeBarrier barrier;
    late RecordingExitTeardown exit;
    late SyntheticDecisionHead head;

    const devInit = 'llama_dart_ggml_backend_dev_init';
    const allocTensors = 'llama_dart_ggml_backend_alloc_ctx_tensors';
    const tensorSet = 'llama_dart_ggml_backend_tensor_set';
    const tensorGet = 'llama_dart_ggml_backend_tensor_get';
    const allocGraph = 'llama_dart_ggml_backend_sched_alloc_graph';
    const synchronize = 'llama_dart_ggml_backend_sched_synchronize';
    const compute = 'llama_dart_ggml_backend_sched_graph_compute';

    setUp(() {
      ledger = _GgmlLedger();
      final pinned = NativeBarrierApi.tryResolve(
        isWindows: Platform.isWindows,
      )!;
      final api = ledger.api;
      // The barrier's ggml functions create through the ledger, so it sees
      // what a failed call leaves behind.
      barrier = FakeNativeBarrier(
        real: NativeBarrierApi(
          lastError: pinned.lastError,
          clearLastError: pinned.clearLastError,
          samplerAccept: pinned.samplerAccept,
          samplerInitGrammarLazyPatterns: pinned.samplerInitGrammarLazyPatterns,
          tokenize: pinned.tokenize,
          tokenToPiece: pinned.tokenToPiece,
          memoryClear: pinned.memoryClear,
          mtmdBitmapInitFromAudio: pinned.mtmdBitmapInitFromAudio,
          mtmdBitmapInitFromBuf: pinned.mtmdBitmapInitFromBuf,
          mtmdBitmapInitFromFile: pinned.mtmdBitmapInitFromFile,
          ggmlBackendDevInit: api.devInit,
          ggmlBackendDevMemory: pinned.ggmlBackendDevMemory,
          ggmlBackendDevGetProps: pinned.ggmlBackendDevGetProps,
          ggmlBackendAllocCtxTensors: api.allocCtxTensors,
          ggmlBackendTensorSet: pinned.ggmlBackendTensorSet,
          ggmlBackendTensorGet: pinned.ggmlBackendTensorGet,
          ggmlBackendSchedAllocGraph: pinned.ggmlBackendSchedAllocGraph,
          ggmlBackendSchedSynchronize: pinned.ggmlBackendSchedSynchronize,
        ),
      )..message = 'boom';
      addTearDown(barrier.dispose);
      exit = RecordingExitTeardown(
        ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      );
      head = SyntheticDecisionHead(d: 64, layers: 1, seed: 31);
    });

    DecisionHeadRuntime create() => DecisionHeadRuntime.create(
      DecisionHeadWeights.read(
        writeHead(head),
        hiddenSize: head.d,
        layers: head.layers,
      ),
      cpuThreads: 1,
      opOffload: false,
      api: ledger.api,
      exitTeardown: exit.api,
      failures: NativeCallFailures(barrier.api, isWindows: false),
    );

    BackendDecisionOutput run(DecisionHeadRuntime runtime) => runtime.run(
      head.randomHidden(3),
      3,
      DecisionQuestionType.choice,
      Int32List.fromList([1, 2]),
    );

    // What create made and nothing freed: tracked objects are freed through
    // the exit API, the rest through the ggml functions.
    Set<int> leaked() => ledger.live.difference(exit.freed.toSet());

    Matcher caught<T extends LlamaException>(String call) => isA<T>()
        .having(
          (e) => e.message,
          'message',
          'llama.cpp raised an exception in $call.',
        )
        .having((e) => e.details, 'details', 'boom');

    test('reaches the backends through the barrier and matches the '
        'reference', () {
      final runtime = create();
      addTearDown(runtime.dispose);

      expectMatchesReference(
        runtime,
        head,
        tokens: 3,
        questionType: DecisionQuestionType.choice,
        markers: [1, 2],
      );
      runtime.dispose();

      expect(barrier.calls.toSet(), {
        devInit,
        allocTensors,
        tensorSet,
        allocGraph,
        tensorGet,
        synchronize,
      });
      expect(leaked(), isEmpty);
    });

    for (final call in [devInit, allocTensors, tensorSet]) {
      test('create throws the typed error of an exception in $call and '
          'frees what it made', () {
        barrier.throwing.add(call);

        expect(
          create,
          throwsA(
            caught<LlamaModelException>(call.replaceFirst('llama_dart_', '')),
          ),
        );
        expect(leaked(), isEmpty);
      });
    }

    for (final call in [allocGraph, tensorSet, tensorGet]) {
      test('a run that catches an exception in $call throws the typed error '
          'and leaves the head unusable', () {
        final runtime = create();
        addTearDown(runtime.dispose);
        barrier.throwing.add(call);
        final native = call.replaceFirst('llama_dart_', '');

        expect(
          () => run(runtime),
          throwsA(caught<LlamaInferenceException>(native)),
        );

        barrier.throwing.clear();
        expect(
          () => run(runtime),
          throwsA(
            isA<LlamaStateException>().having(
              (e) => e.message,
              'message',
              'The decision head is unusable after a llama.cpp exception in '
                  '$native. Load it again.',
            ),
          ),
        );
        runtime.dispose();
        expect(leaked(), isEmpty);
      });
    }

    test('a graph compute that catches an exception throws the typed '
        'error', () {
      final runtime = create();
      addTearDown(runtime.dispose);
      exit.fail = (name) {
        if (name != compute) return false;
        barrier.catchException('boom');
        return true;
      };

      expect(
        () => run(runtime),
        throwsA(
          caught<LlamaInferenceException>('ggml_backend_sched_graph_compute'),
        ),
      );
      exit.fail = null;
      expect(() => run(runtime), throwsA(isA<LlamaStateException>()));
    });

    test('a failure that caught nothing fails as before and leaves the head '
        'usable', () {
      final runtime = create();
      addTearDown(runtime.dispose);
      barrier.failing.add(allocGraph);

      expect(
        () => run(runtime),
        throwsA(
          isA<LlamaInferenceException>().having(
            (e) => e.message,
            'message',
            contains('Could not allocate decision head compute buffers'),
          ),
        ),
      );

      barrier.failing.clear();
      expect(run(runtime).logits, hasLength(2));
    });
  });

  group('DecisionHeadWeights.read', () {
    Matcher modelError(List<String> parts) => throwsA(
      isA<LlamaModelException>().having(
        (error) => error.message,
        'message',
        allOf([for (final part in parts) contains(part)]),
      ),
    );

    test('reports dimensions and ignores unrelated tensors', () {
      final head = SyntheticDecisionHead(d: 128, layers: 2, seed: 8)
        ..tensors['encoder.embeddings.weight'] = SyntheticTensor(
          [2, 2],
          [1, 2, 3, 4],
        )
        ..tensors['temperature'] = SyntheticTensor([3], [1, 1, 1]);

      final weights = DecisionHeadWeights.read(
        writeHead(head),
        hiddenSize: 128,
        layers: 2,
      );

      expect(weights.hiddenSize, 128);
      expect(weights.heads, 2);
      expect(weights.layers, 2);
      expect(weights.ffnSize, 512);
      expect(weights.actHiddenSize, 8);
      expect(weights.actClasses, 2);
    });

    test('names a missing tensor', () {
      final head = SyntheticDecisionHead(d: 64, layers: 2, seed: 9)
        ..tensors.remove('head.layers.1.norm2.bias');
      final file = writeHead(head);

      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 64, layers: 2),
        modelError([file.path, '"head.layers.1.norm2.bias"']),
      );
    });

    test('names a mis-shaped tensor with expected and found shapes', () {
      final cases = [
        (
          'scorer.1.weight',
          SyntheticTensor([64, 63], List.filled(64 * 63, 0.0)),
          ['[64, 63]', 'expected [64, 64]'],
        ),
        (
          'type_emb.weight',
          SyntheticTensor([2, 64], List.filled(128, 0.0)),
          ['[2, 64]', 'expected [3, 64]'],
        ),
        (
          'head.layers.0.linear1.weight',
          SyntheticTensor([256, 32], List.filled(256 * 32, 0.0)),
          ['[256, 32]', 'expected [ffn, 64]'],
        ),
        (
          'act_head.0.weight',
          SyntheticTensor([8, 64], List.filled(8 * 64, 0.0)),
          ['[8, 64]', 'expected [act hidden, 68]'],
        ),
        (
          'act_head.0.weight',
          SyntheticTensor([0, 68], const []),
          ['[0, 68]', 'act hidden >= 1'],
        ),
        (
          'act_head.2.bias',
          SyntheticTensor([3], [0, 0, 0]),
          ['[3]', 'expected [2]'],
        ),
      ];
      for (final (index, (name, tensor, parts)) in cases.indexed) {
        final head = SyntheticDecisionHead(d: 64, layers: 1, seed: 10)
          ..tensors[name] = tensor;
        final file = writeHead(head, 'case_$index');

        expect(
          () => DecisionHeadWeights.read(file, hiddenSize: 64, layers: 1),
          modelError(['"$name"', ...parts]),
          reason: '$name $parts',
        );
      }
    });

    test('names the encoder width a head of another width needs', () {
      final file = writeHead(SyntheticDecisionHead(d: 64, layers: 1, seed: 11));

      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 128, layers: 1),
        modelError([
          '"type_emb.weight"',
          '[3, 64]; expected [3, 128]',
          'The encoder has hidden size 128; use the head trained for this '
              'encoder.',
        ]),
      );
    });

    test('rejects extra layers and unusable hidden sizes', () {
      final file = writeHead(SyntheticDecisionHead(d: 64, layers: 2, seed: 12));

      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 64, layers: 1),
        modelError(['more than the 1 layers']),
      );
      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 64, layers: 0),
        throwsArgumentError,
      );
      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 0, layers: 2),
        modelError(['must be positive']),
      );
      expect(
        () => DecisionHeadWeights.read(file, hiddenSize: 129, layers: 2),
        modelError(['129', '2 attention heads']),
      );
    });
  });

  test('decisionErf stays within 1.4e-7 of erf', () {
    const bound = 1.4e-7;
    final values = {
      0.0: 0.0,
      1e-10: 1.128379167095512573892398e-10,
      0.04514032: 0.05090082167749478,
      0.1: 0.1124629160182848922032751,
      0.2223196: 0.2467883585347393630150919,
      -0.3: -0.328626759459127427638914,
      0.5: 0.5204998778130465376827467,
      0.5076081: 0.5271602462979924799102928,
      0.84375: 0.7672256612323416334589782,
      0.8957377: 0.7947604563424987203942600,
      1.0: 0.8427007929497148693412206,
      -1.0: -0.8427007929497148693412206,
      1.25: 0.9229001282564582301365235,
      1.400375: 0.9523446916195365956666261,
      2.0: 0.9953222650189527341620693,
      2.1303769: 0.9974115729421083315849639,
      2.857142857142857: 0.9999466876886116771394024,
      3.0: 0.9999779095030014145586272,
      -3.0: -0.9999779095030014145586272,
      4.0: 0.9999999845827420997199811,
      5.9: 0.9999999999999999280959022,
    };
    for (final MapEntry(key: x, value: erf) in values.entries) {
      expect(decisionErf(x), closeTo(erf, bound), reason: 'erf($x)');
    }
    expect(decisionErf(6.0), closeTo(1.0, bound));
    expect(decisionErf(-40.0), closeTo(-1.0, bound));
    expect(decisionErf(5e-324), closeTo(0.0, bound));
    expect(decisionErf(double.infinity), 1.0);
    expect(decisionErf(double.negativeInfinity), -1.0);
    expect(decisionErf(double.nan).isNaN, isTrue);
  });
}

extension on SyntheticDecisionHead {
  List<double> _t(String name) => tensors[name]!.values;

  (List<double>, List<double>) reference(
    Float32List hidden,
    DecisionQuestionType questionType,
    List<int> markers,
  ) {
    final n = hidden.length ~/ d;
    final type = questionType.index;
    final typeRow = _t('type_emb.weight').sublist(type * d, (type + 1) * d);
    var x = [
      for (var i = 0; i < n; i++)
        [for (var j = 0; j < d; j++) hidden[i * d + j] + typeRow[j]],
    ];
    final heads = math.max(1, d ~/ 64);
    final size = d ~/ heads;
    for (var l = 0; l < layers; l++) {
      final p = 'head.layers.$l';
      final inW = _t('$p.self_attn.in_proj_weight');
      final inB = _t('$p.self_attn.in_proj_bias');
      final a = [
        for (final row in x)
          _layerNorm(row, _t('$p.norm1.weight'), _t('$p.norm1.bias')),
      ];
      final qkv = [for (final row in a) _linear(row, inW, inB)];
      final attended = [for (var i = 0; i < n; i++) List.filled(d, 0.0)];
      for (var h = 0; h < heads; h++) {
        for (var i = 0; i < n; i++) {
          final scores = [
            for (var j = 0; j < n; j++)
              [
                    for (var c = 0; c < size; c++)
                      qkv[i][h * size + c] * qkv[j][d + h * size + c],
                  ].reduce((s, v) => s + v) /
                  math.sqrt(size),
          ];
          final p = decisionSoftmax(scores);
          for (var j = 0; j < n; j++) {
            for (var c = 0; c < size; c++) {
              attended[i][h * size + c] += p[j] * qkv[j][2 * d + h * size + c];
            }
          }
        }
      }
      x = [
        for (var i = 0; i < n; i++)
          _add(
            x[i],
            _linear(
              attended[i],
              _t('$p.self_attn.out_proj.weight'),
              _t('$p.self_attn.out_proj.bias'),
            ),
          ),
      ];
      x = [
        for (final row in x)
          _add(
            row,
            _linear(
              _linear(
                _layerNorm(row, _t('$p.norm2.weight'), _t('$p.norm2.bias')),
                _t('$p.linear1.weight'),
                _t('$p.linear1.bias'),
              ).map((v) => math.max(0.0, v)).toList(),
              _t('$p.linear2.weight'),
              _t('$p.linear2.bias'),
            ),
          ),
      ];
    }
    final logits = [
      for (final m in markers)
        _linear(
          _linear(
            _layerNorm(x[m], _t('scorer.0.weight'), _t('scorer.0.bias')),
            _t('scorer.1.weight'),
            _t('scorer.1.bias'),
          ).map(_gelu).toList(),
          _t('scorer.3.weight'),
          _t('scorer.3.bias'),
        ).single,
    ];
    final actInput = [...x[0], ...decisionActFeatures(logits)];
    final actLogits = _linear(
      _linear(
        actInput,
        _t('act_head.0.weight'),
        _t('act_head.0.bias'),
      ).map(_gelu).toList(),
      _t('act_head.2.weight'),
      _t('act_head.2.bias'),
    );
    return (logits, actLogits);
  }
}

double _gelu(double x) => 0.5 * x * (1 + decisionErf(x / math.sqrt2));

List<double> _add(List<double> a, List<double> b) => [
  for (var i = 0; i < a.length; i++) a[i] + b[i],
];

List<double> _linear(List<double> x, List<double> weight, List<double> bias) {
  final columns = x.length;
  return [
    for (var o = 0; o < bias.length; o++)
      bias[o] +
          [
            for (var i = 0; i < columns; i++) weight[o * columns + i] * x[i],
          ].reduce((s, v) => s + v),
  ];
}

List<double> _layerNorm(
  List<double> x,
  List<double> weight,
  List<double> bias,
) {
  final mean = x.reduce((s, v) => s + v) / x.length;
  final variance =
      x.map((v) => (v - mean) * (v - mean)).reduce((s, v) => s + v) / x.length;
  final scale = 1 / math.sqrt(variance + 1e-5);
  return [
    for (var i = 0; i < x.length; i++)
      (x[i] - mean) * scale * weight[i] + bias[i],
  ];
}

/// Records the ggml resources a [DecisionHeadRuntime] creates and frees.
final class _GgmlLedger {
  _GgmlLedger({
    bool failSched = false,
    bool failAlloc = false,
    bool deviceStandIn = false,
  }) {
    final real = GgmlGraphApi.current;
    final cpu = real.devByType(
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
    );
    T made<T extends Pointer>(String kind, T pointer) {
      events.add((kind, pointer.address));
      if (pointer != nullptr) live.add(pointer.address);
      return pointer;
    }

    void freed(String kind, Pointer pointer) {
      events.add((kind, pointer.address));
      live.remove(pointer.address);
    }

    _threads = NativeCallable<Void Function(ggml_backend_t, Int)>.isolateLocal(
      (ggml_backend_t backend, int threads) => threadCounts.add(threads),
    );
    api = _withOverrides(real, {
      #init: (ggml_init_params params) => made('init', real.init(params)),
      #free: (Pointer<ggml_context> context) {
        freed('free', context);
        real.free(context);
      },
      #devInit: (ggml_backend_dev_t device, Pointer<Char> params) => made(
        'devInit',
        real.devInit(
          deviceStandIn && device == standInDevice ? cpu : device,
          params,
        ),
      ),
      #backendFree: (ggml_backend_t backend) {
        freed('backendFree', backend);
        real.backendFree(backend);
      },
      #regGetProcAddress: (ggml_backend_reg_t registry, Pointer<Char> name) =>
          name.cast<Utf8>().toDartString() == 'ggml_backend_set_n_threads'
          ? _threads.nativeFunction.cast<Void>()
          : real.regGetProcAddress(registry, name),
      #allocCtxTensors: (Pointer<ggml_context> ctx, ggml_backend_t backend) {
        allocBackends.add(backend.address);
        return made(
          'bufferAlloc',
          failAlloc
              ? Pointer<ggml_backend_buffer>.fromAddress(0)
              : real.allocCtxTensors(ctx, backend),
        );
      },
      #bufferFree: (ggml_backend_buffer_t buffer) {
        freed('bufferFree', buffer);
        real.bufferFree(buffer);
      },
      #schedNew:
          (
            Pointer<ggml_backend_t> backends,
            Pointer<ggml_backend_buffer_type_t> types,
            int count,
            int graphSize,
            bool parallel,
            bool opOffload,
          ) {
            schedulerBackends.add([
              for (var i = 0; i < count; i++) backends[i].address,
            ]);
            return made(
              'schedNew',
              failSched
                  ? Pointer<ggml_backend_sched>.fromAddress(0)
                  : real.schedNew(
                      backends,
                      types,
                      count,
                      graphSize,
                      parallel,
                      opOffload,
                    ),
            );
          },
      #schedSynchronize: (ggml_backend_sched_t sched) {
        events.add(('schedSynchronize', sched.address));
        real.schedSynchronize(sched);
      },
      #schedFree: (ggml_backend_sched_t sched) {
        freed('schedFree', sched);
        real.schedFree(sched);
      },
    });
    addTearDown(_threads.close);
  }

  /// A device pointer that the ledger starts as a second CPU backend.
  static final ggml_backend_dev_t standInDevice = Pointer.fromAddress(8);

  late final GgmlGraphApi api;
  late final NativeCallable<Void Function(ggml_backend_t, Int)> _threads;
  final List<(String, int)> events = [];
  final Set<int> live = {};
  final List<int> threadCounts = [];
  final List<int> allocBackends = [];
  final List<List<int>> schedulerBackends = [];

  static GgmlGraphApi _withOverrides(
    GgmlGraphApi base,
    Map<Symbol, Function> overrides,
  ) {
    final type = reflectClass(GgmlGraphApi);
    final instance = reflect(base);
    return type.newInstance(
          MirrorSystem.getSymbol('_', type.owner as LibraryMirror),
          const [],
          {
            for (final field
                in type.declarations.values.whereType<VariableMirror>())
              if (!field.isStatic)
                field.simpleName:
                    overrides[field.simpleName] ??
                    instance.getField(field.simpleName).reflectee,
          },
        ).reflectee
        as GgmlGraphApi;
  }
}
