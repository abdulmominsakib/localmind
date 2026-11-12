import 'dart:async';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import 'engine_test.dart';

class _Backend extends MockLlamaBackend implements BackendReranking {
  @override
  Future<int> createRerankingContext(
    int modelHandle,
    ModelParams params,
  ) async => 3;

  LlamaRerankingCapabilities support = LlamaRerankingCapabilities(
    isSupported: true,
    classifierLabels: ['yes', 'no'],
    maxInputTokens: 128,
    maxParallelSequences: 2,
  );
  BackendRerankingOutput output = BackendRerankingOutput(
    scores: [
      [0.2, 0.8],
      [0.9, 0.1],
      [0.9, 0.1],
    ],
    classifierLabels: ['yes', 'no'],
  );
  int calls = 0;
  String? query;
  List<String>? documents;
  Completer<LlamaRerankingCapabilities>? pendingProbe;
  Completer<BackendRerankingOutput>? pendingOutput;
  @override
  Future<LlamaRerankingCapabilities> getRerankingCapabilities(
    int contextHandle,
  ) async => pendingProbe == null ? support : pendingProbe!.future;
  @override
  Future<BackendRerankingOutput> rerank(
    int contextHandle,
    String query,
    List<String> documents,
  ) async {
    calls++;
    this.query = query;
    this.documents = documents;
    return pendingOutput == null ? output : pendingOutput!.future;
  }
}

void main() {
  Future<LlamaEngine> load(MockLlamaBackend backend) async {
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel('fake.gguf');
    return engine;
  }

  test('disposing a borrowed wrapper leaves its engine usable', () async {
    final backend = _Backend();
    final engine = await load(backend);
    final helper = LlamaReranker(engine);
    await helper.dispose();
    expect(engine.isDisposed, isFalse);
    expect(await helper.rerank('q', ['a', 'b', 'c']), hasLength(3));
  });
  test(
    'sorts native scores, preserves ties, duplicates, labels and input bytes',
    () async {
      final backend = _Backend();
      final helper = LlamaReranker(await load(backend));
      final results = await helper.rerank('  query\n한글 ', [
        ' x ',
        'same',
        'same',
      ]);
      expect(results.map((r) => r.index), [1, 2, 0]);
      expect(results.first.classifierScores, [0.9, 0.1]);
      expect(results.first.classifierLabels, ['yes', 'no']);
      expect(backend.query, '  query\n한글 ');
      expect(backend.documents, [' x ', 'same', 'same']);
      expect(
        (await helper.rerank(
          'q',
          ['x', 'y', 'y'],
          scoreIndex: 1,
          topN: 1,
        )).single.index,
        0,
      );
      expect(await helper.rerank('q', ['x', 'y', 'y'], topN: 0), isEmpty);
    },
  );
  test(
    'accepts raw unbounded outputs without sigmoid or normalization',
    () async {
      final backend = _Backend()
        ..support = LlamaRerankingCapabilities(
          isSupported: true,
          classifierLabels: [null],
        )
        ..output = BackendRerankingOutput(
          scores: [
            [-7],
            [3],
          ],
          classifierLabels: [null],
        );
      final results = await LlamaReranker(
        await load(backend),
      ).rerank('q', ['a', 'b']);
      expect(results.map((r) => r.score), [3, -7]);
    },
  );
  test(
    'old backend implementations remain supported and reject reranking explicitly',
    () async {
      final helper = LlamaReranker(await load(MockLlamaBackend()));
      expect((await helper.capabilities).isSupported, isFalse);
      await expectLater(
        helper.rerank('q', ['d']),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'probe must support actual model, not just implement the interface',
    () async {
      final backend = _Backend()
        ..support = LlamaRerankingCapabilities(
          isSupported: false,
          unsupportedReason: 'not rank pooled',
        );
      final helper = LlamaReranker(await load(backend));
      await expectLater(
        helper.rerank('q', ['d']),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(backend.calls, 0);
    },
  );
  test('validates options and empty input without inference', () async {
    final backend = _Backend();
    final helper = LlamaReranker(await load(backend));
    for (final index in [-1, 2]) {
      await expectLater(
        helper.rerank('q', ['d'], scoreIndex: index),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
    await expectLater(
      helper.rerank('q', ['d'], topN: -1),
      throwsA(isA<LlamaArgumentException>()),
    );
    expect(await helper.rerank('q', []), isEmpty);
    expect(backend.calls, 0);
  });
  test(
    'unloaded and disposed engines return unsupported probe and typed state errors',
    () async {
      final engine = LlamaEngine(_Backend());
      final helper = LlamaReranker(engine);
      expect((await helper.capabilities).isSupported, isFalse);
      await expectLater(
        helper.rerank('q', []),
        throwsA(isA<LlamaContextException>()),
      );
      await engine.dispose();
      expect((await helper.capabilities).isSupported, isFalse);
      await expectLater(
        helper.rerank('q', []),
        throwsA(isA<LlamaStateException>()),
      );
    },
  );
  test('snapshots caller documents before capability await', () async {
    final backend = _Backend()..pendingProbe = Completer();
    final helper = LlamaReranker(await load(backend));
    final documents = ['a', 'b', 'c'];
    final pending = helper.rerank('q', documents);
    documents.clear();
    backend.pendingProbe!.complete(backend.support);
    expect(await pending, hasLength(3));
    expect(backend.documents, ['a', 'b', 'c']);
  });
  test('cancellation during probe never dispatches and allows reuse', () async {
    final backend = _Backend()..pendingProbe = Completer();
    final helper = LlamaReranker(await load(backend));
    final pending = helper.rerank('q', ['a', 'b', 'c']);
    helper.cancel();
    backend.pendingProbe!.complete(backend.support);
    await expectLater(pending, throwsA(isA<LlamaInferenceException>()));
    expect(backend.calls, 0);
    backend.pendingProbe = null;
    expect(await helper.rerank('q', ['a', 'b', 'c']), hasLength(3));
  });
  test('cancellation after dispatch discards a full returned output', () async {
    final backend = _Backend()..pendingOutput = Completer();
    final helper = LlamaReranker(await load(backend));
    final pending = helper.rerank('q', ['a', 'b', 'c']);
    await Future<void>.delayed(Duration.zero);
    helper.cancel();
    backend.pendingOutput!.complete(backend.output);
    await expectLater(pending, throwsA(isA<LlamaInferenceException>()));
  });
  test(
    'model replacement during a capability probe prevents dispatch',
    () async {
      final backend = _Backend()..pendingProbe = Completer();
      final engine = await load(backend);
      final pending = LlamaReranker(engine).rerank('q', ['a', 'b', 'c']);
      await engine.unloadModel();
      backend.pendingProbe!.complete(backend.support);
      await expectLater(pending, throwsA(isA<LlamaStateException>()));
      expect(backend.calls, 0);
    },
  );
  test(
    'model unload during dispatched scoring discards stale results',
    () async {
      final backend = _Backend()..pendingOutput = Completer();
      final engine = await load(backend);
      final pending = LlamaReranker(engine).rerank('q', ['a', 'b', 'c']);
      await Future<void>.delayed(Duration.zero);
      await engine.unloadModel();
      backend.pendingOutput!.complete(backend.output);
      await expectLater(pending, throwsA(isA<LlamaStateException>()));
    },
  );
  for (final output in [
    BackendRerankingOutput(scores: [], classifierLabels: ['yes']),
    BackendRerankingOutput(
      scores: [
        [1],
      ],
      classifierLabels: ['yes', 'no'],
    ),
    BackendRerankingOutput(
      scores: [
        [double.nan, 1],
      ],
      classifierLabels: ['yes', 'no'],
    ),
  ]) {
    test(
      'rejects invalid output shape or nonfinite score without partial results: ${output.scores}',
      () async {
        final backend = _Backend()..output = output;
        await expectLater(
          LlamaReranker(await load(backend)).rerank('q', ['d']),
          throwsA(isA<LlamaInferenceException>()),
        );
      },
    );
  }
}
