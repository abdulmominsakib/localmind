@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late LlamaBackend backend;
  late int model;
  late int context;

  setUpAll(() async {
    backend = LlamaBackend();
    final file = await TestHelper.getTestModel();
    const params = ModelParams(
      contextSize: 512,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
    );
    model = await backend.modelLoad(file.path, params);
    context = await backend.contextCreate(model, params);
  });
  tearDownAll(() async {
    await backend.contextFree(context);
    await backend.modelFree(model);
    await backend.dispose();
  });

  group('ordinary GGUF stops', () {
    GenerationParams params(String text, List<String> stops) =>
        GenerationParams(
          maxTokens: 128,
          temp: 0,
          seed: 1,
          penalty: 1,
          grammar: 'root ::= ${jsonEncode(text)}',
          stopSequences: stops,
          streamBatchTokenThreshold: 1,
          streamBatchByteThreshold: 1,
        );

    Future<String> run(String text, List<String> stops) async {
      final chunks = await backend
          .generate(context, 'Once upon a time', params(text, stops))
          .toList();
      return utf8.decode(chunks.expand((chunk) => chunk).toList());
    }

    test('control, marker suppression, and next generation recovery', () async {
      const text = 'alpha cedar17 omega';
      expect(await run(text, []), text);
      expect(await run(text, ['cedar17']), 'alpha ');
      expect(await run(text, []), text);
      // The first sampled piece is subject to suppression too.
      expect(await run(text, ['a']), isEmpty);
    });

    test('matches inside a token and ignores empty markers', () async {
      const text = 'Once upon a time';
      final tokens = await backend.tokenize(model, text, addSpecial: false);
      final pieces = <String>[];
      for (final token in tokens) {
        pieces.add(await backend.detokenize(model, [token]));
      }
      final piece = pieces.firstWhere((piece) => piece.trim().length >= 3);
      final stop = piece.substring(1, 2);
      expect(
        await run(text, ['', stop, stop]),
        text.substring(0, text.indexOf(stop)),
      );
    });

    test('Unicode, overlap, and unfinished prefix at EOG', () async {
      expect(await run('café 🦊終 omega', ['🦊終']), 'café ');
      expect(await run('alpha cedar', ['cedar17']), 'alpha cedar');
      expect(await run('alpha abc omega', ['bc', 'abc']), 'alpha ');
      expect(await run('alpha cedar17 omega', ['']), 'alpha cedar17 omega');
    });

    test('preserved parser tokens are not consumed as caller stops', () async {
      const text = 'alpha cedar17 omega';
      final chunks = await backend
          .generate(
            context,
            'Once upon a time',
            params(text, ['cedar17']).copyWith(preservedTokens: ['cedar17']),
          )
          .toList();
      expect(utf8.decode(chunks.expand((chunk) => chunk).toList()), text);
    });

    test('unfinished prefix at token limit is retained', () async {
      final limited = params('alpha cedar17 omega', []).copyWith(maxTokens: 2);
      Future<String> generate(GenerationParams value) async => utf8.decode(
        (await backend.generate(context, 'Once upon a time', value).toList())
            .expand((chunk) => chunk)
            .toList(),
      );
      final control = await generate(limited);
      expect(control, isNotEmpty);
      expect(
        await generate(limited.copyWith(stopSequences: ['$control suffix'])),
        control,
      );
    });

    test('cancel with pending marker then regenerate', () async {
      final text = List.filled(60, 'alpha cedar17 omega ').join();
      var chunks = 0;
      await for (final _ in backend.generate(
        context,
        'Once upon a time',
        params(text, ['cedar17-not-present']),
      )) {
        chunks++;
        backend.cancelGeneration();
      }
      expect(chunks, greaterThan(0));
      expect(await run('alpha cedar17 omega', ['cedar17']), 'alpha ');
    });
  });

  group('speculative GGUF stops without unsupported grammar sampling', () {
    const prompt =
        'Once upon a time there was a little girl. '
        'Once upon a time there was a little girl. '
        'Once upon a time there was a';
    const params = GenerationParams(
      maxTokens: 80,
      temp: 0,
      seed: 1,
      penalty: 1,
      streamBatchTokenThreshold: 1,
      streamBatchByteThreshold: 1,
      speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
        ngramSizeN: 1,
        ngramSizeM: 4,
        ngramMinHits: 1,
      ),
    );
    Future<String> run(GenerationParams value) async => utf8.decode(
      (await backend.generate(context, prompt, value).toList())
          .expand((chunk) => chunk)
          .toList(),
    );

    test('sampled and accepted pieces suppress stops and recover', () async {
      final control = await run(params);
      final perf = await (backend as BackendPerformanceDiagnostics)
          .getPerformanceContext(context);
      expect(perf!.speculativeAcceptedDraftTokens, greaterThan(0));
      expect(control.length, greaterThan(40));
      // Derive markers from an unrestricted deterministic control rather than
      // asking a tiny base model to follow chat instructions. Exact prefixes
      // remain the oracle for every stopped request.
      for (final start in [0, 5, 20, control.length ~/ 2]) {
        final stop = control.substring(start, start + 5);
        final stopped = await run(params.copyWith(stopSequences: [stop]));
        expect(stopped, control.substring(0, control.indexOf(stop)));
      }
      expect(await run(params), control);
      expect(await run(params.copyWith(stopSequences: [''])), control);
      expect(
        await run(params.copyWith(stopSequences: ['$control unfinished'])),
        control,
      );
      final marker = control.substring(10, 20);
      expect(
        await run(
          params.copyWith(stopSequences: [marker], preservedTokens: [marker]),
        ),
        control,
      );
    });

    test('rejected speculative request releases generation state', () async {
      final control = await run(params);
      await expectLater(
        run(params.copyWith(grammar: 'root ::= "alpha"')),
        throwsA(isA<LlamaException>()),
      );
      expect(await run(params), control);
    });

    test('cancellation and subsequent generation recover', () async {
      final control = await run(params);
      var chunks = 0;
      await for (final _ in backend.generate(
        context,
        prompt,
        params.copyWith(stopSequences: ['not a matching stop']),
      )) {
        chunks++;
        backend.cancelGeneration();
      }
      expect(chunks, greaterThan(0));
      expect(await run(params), control);
    });
  });
}
