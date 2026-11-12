@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

import '../test_helper.dart';

void main() {
  late LlamaBackend backend;
  late BackendGenerationLimitReporting limits;
  late BackendPerformanceDiagnostics performance;
  late int model;
  late int context;
  late int contextSize;

  setUpAll(() async {
    backend = LlamaBackend();
    limits = backend as BackendGenerationLimitReporting;
    performance = backend as BackendPerformanceDiagnostics;
    final file = await TestHelper.getTestModel();
    const params = ModelParams(
      contextSize: 256,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
    );
    model = await backend.modelLoad(file.path, params);
    context = await backend.contextCreate(model, params);
    contextSize = await backend.getContextSize(context);
  });
  tearDownAll(() async {
    await backend.contextFree(context);
    await backend.modelFree(model);
    await backend.dispose();
  });

  const prompt = 'Once upon a time';
  const endless = GenerationParams(
    maxTokens: 100000,
    temp: 0,
    seed: 1,
    penalty: 1,
    grammar: 'root ::= "a " root',
  );

  Future<(String, BackendGenerationLimit?)> run(GenerationParams params) async {
    final generation = backend.generate(context, prompt, params);
    final chunks = await generation.toList();
    return (
      utf8.decode(chunks.expand((chunk) => chunk).toList()),
      limits.generationLimitOf(generation),
    );
  }

  group('llama.cpp generation limits', () {
    test('a full context reports contextSize', () async {
      final (_, limit) = await run(endless);
      final perf = (await performance.getPerformanceContext(context))!;

      expect(limit, BackendGenerationLimit.contextSize);
      expect(perf.promptEvalTokens + perf.evalTokens, contextSize);
    });

    test('maxTokens reports maxTokens', () async {
      final (_, limit) = await run(endless.copyWith(maxTokens: 5));
      final perf = (await performance.getPerformanceContext(context))!;

      expect(limit, BackendGenerationLimit.maxTokens);
      expect(perf.evalTokens, 5);
    });

    test('maxTokens equal to the natural length reports no limit', () async {
      const natural = GenerationParams(
        maxTokens: 100000,
        temp: 0,
        seed: 1,
        penalty: 1,
        grammar: 'root ::= "a a a"',
      );
      final (text, _) = await run(natural);
      final length = (await performance.getPerformanceContext(
        context,
      ))!.evalTokens;

      expect(await run(natural.copyWith(maxTokens: length)), (text, null));
      expect(
        (await run(natural.copyWith(maxTokens: length - 1))).$2,
        BackendGenerationLimit.maxTokens,
      );
    });

    test('an end-of-generation token reports no limit', () async {
      final (text, limit) = await run(
        endless.copyWith(grammar: 'root ::= "a a"'),
      );

      expect(text, 'a a');
      expect(limit, isNull);
    });

    test('a stop sequence reports no limit', () async {
      final (text, limit) = await run(
        endless.copyWith(stopSequences: <String>['a a a']),
      );

      expect(text, isEmpty);
      expect(limit, isNull);
    });

    test('cancellation reports no limit', () async {
      final generation = backend.generate(
        context,
        prompt,
        endless.copyWith(streamBatchTokenThreshold: 1),
      );
      var chunks = 0;
      await for (final _ in generation) {
        chunks++;
        backend.cancelGeneration();
      }

      expect(chunks, greaterThan(0));
      expect(limits.generationLimitOf(generation), isNull);
    });
  });

  group('llama.cpp perf token counts', () {
    test('evalTokens counts tokens whose text piece is empty', () async {
      final bos = (await backend.tokenize(model, '')).single;
      final (text, _) = await run(
        endless.copyWith(maxTokens: 4, grammar: 'root ::= <[$bos]>+'),
      );
      final perf = (await performance.getPerformanceContext(context))!;

      expect(text, isEmpty);
      expect(perf.evalTokens, 4);
      expect(perf.sampleCount, 4);
    });
  });

  group('speculative llama.cpp generation limits', () {
    const speculative = GenerationParams(
      maxTokens: 100000,
      temp: 0,
      seed: 1,
      penalty: 1,
      speculativeDecodingConfig: SpeculativeDecodingConfig.ngramSimple(
        ngramSizeN: 1,
        ngramSizeM: 4,
        ngramMinHits: 1,
      ),
    );

    test('a full context reports contextSize', () async {
      final (_, limit) = await run(speculative);

      expect(limit, BackendGenerationLimit.contextSize);
    });

    test('maxTokens reports maxTokens', () async {
      final (_, limit) = await run(speculative.copyWith(maxTokens: 12));

      expect(limit, BackendGenerationLimit.maxTokens);
    });

    test('a stop sequence reports no limit', () async {
      final (control, _) = await run(speculative.copyWith(maxTokens: 40));
      final stop = control.substring(20, 25);

      final (text, limit) = await run(
        speculative.copyWith(stopSequences: <String>[stop]),
      );

      expect(text, control.substring(0, control.indexOf(stop)));
      expect(limit, isNull);
    });
  });

  group('a reply that ends exactly at maxTokens', () {
    const eosParams = ModelParams(
      contextSize: 256,
      gpuLayers: 0,
      preferredBackend: GpuBackend.cpu,
      numberOfThreads: 2,
      numberOfThreadsBatch: 2,
    );
    const ngramSimple = SpeculativeDecodingConfig.ngramSimple(
      ngramSizeN: 1,
      ngramSizeM: 4,
      ngramMinHits: 1,
    );
    late Directory directory;
    late File eosFile;
    late int eosModel;
    late int eosContext;

    // The test model never samples its end-of-generation token, and
    // speculative decoding rejects grammars, so a copy that ends at a newline
    // gives both loops a natural end without a grammar.
    setUpAll(() async {
      directory = Directory.systemTemp.createTempSync('llamadart_eos_');
      final newline = (await backend.tokenize(
        model,
        '\n',
        addSpecial: false,
      )).last;
      eosFile = _copyWithEosToken(
        await TestHelper.getTestModel(),
        '${directory.path}/newline_eos.gguf',
        newline,
      );
      eosModel = await backend.modelLoad(eosFile.path, eosParams);
      eosContext = await backend.contextCreate(eosModel, eosParams);
    });
    tearDownAll(() async {
      await backend.contextFree(eosContext);
      await backend.modelFree(eosModel);
      directory.deleteSync(recursive: true);
    });

    // With ngram-simple, the first reply's last token is sampled after a
    // single-token decode and the second's is the undecoded bonus token of an
    // accepted draft batch.
    const prompts = <String>[
      'Lily and Ben were friends. They liked to play.',
      'He had a truck. He had a truck. He had a truck.',
    ];

    for (final (name, config) in <(String, SpeculativeDecodingConfig?)>[
      ('normal', null),
      ('speculative', ngramSimple),
    ]) {
      test('reports no limit with $name decoding', () async {
        Future<(String, BackendGenerationLimit?)> generate(
          String prompt,
          int maxTokens,
        ) async {
          final generation = backend.generate(
            eosContext,
            prompt,
            GenerationParams(
              maxTokens: maxTokens,
              temp: 0,
              seed: 1,
              penalty: 1,
              speculativeDecodingConfig: config,
            ),
          );
          final chunks = await generation.toList();
          return (
            utf8.decode(chunks.expand((chunk) => chunk).toList()),
            limits.generationLimitOf(generation),
          );
        }

        var acceptedDraftTokens = 0;
        for (final prompt in prompts) {
          final (text, limit) = await generate(prompt, 200);
          final perf = (await performance.getPerformanceContext(eosContext))!;
          final length = perf.evalTokens;
          acceptedDraftTokens += perf.speculativeAcceptedDraftTokens ?? 0;

          expect(limit, isNull, reason: prompt);
          expect(text, isNot(contains('\n')), reason: prompt);
          expect(await generate(prompt, length), (text, null), reason: prompt);
          expect(
            (await generate(prompt, length - 1)).$2,
            BackendGenerationLimit.maxTokens,
            reason: prompt,
          );
        }
        if (config != null) expect(acceptedDraftTokens, greaterThan(0));
      });
    }

    // One token short of the first prompt's natural length, the speculative
    // reply ends on an accepted draft batch, so its last token is decoded only
    // to look ahead. With maxTokens 1 it is decoded in the loop.
    test('a failed decode of the last token reports no limit', () async {
      final prompt = prompts.first;
      int? failAt;
      var failures = 0;
      final service = LlamaCppService(
        objectCalls: LlamaCppObjectCalls.untracked(
          decode: (context, batch) {
            if (batch.n_tokens == 1 && batch.pos[0] == failAt) {
              failures++;
              return 1;
            }
            return llama_decode(context, batch);
          },
        ),
      )..initializeBackend();
      final cancel = calloc<Int8>();
      addTearDown(() {
        calloc.free(cancel);
        service.dispose();
      });
      final model = service.loadModel(eosFile.path, eosParams);
      final context = service.createContext(model, eosParams);
      final promptTokens = service.tokenize(model, prompt, true).length;

      Future<List<BackendGenerationLimit>> generate(
        GenerationParams params,
      ) async {
        final limits = <BackendGenerationLimit>[];
        await service
            .generate(
              context,
              prompt,
              params,
              cancel.address,
              onLimit: limits.add,
            )
            .drain<void>();
        return limits;
      }

      for (final config in [null, ngramSimple]) {
        final params = GenerationParams(
          maxTokens: 200,
          temp: 0,
          seed: 1,
          penalty: 1,
          speculativeDecodingConfig: config,
        );
        failAt = null;
        expect(await generate(params), isEmpty);
        final length = service.getPerformanceContext(context)!.evalTokens;
        final short = params.copyWith(maxTokens: length - 1);
        expect(await generate(short), [BackendGenerationLimit.maxTokens]);

        failAt = promptTokens + length - 2;
        failures = 0;
        expect(await generate(short), isEmpty, reason: '$config');
        expect(failures, 1, reason: '$config');

        failAt = promptTokens;
        failures = 0;
        expect(
          await generate(params.copyWith(maxTokens: 1)),
          isEmpty,
          reason: '$config, maxTokens: 1',
        );
        expect(failures, 1, reason: '$config, maxTokens: 1');
      }
    });
  });

  group('LlamaEngine.create finish reason', () {
    late LlamaEngine engine;

    setUpAll(() async {
      engine = LlamaEngine(LlamaBackend());
      await engine.loadModel(
        (await TestHelper.getTestModel()).path,
        modelParams: const ModelParams(
          contextSize: 256,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
        ),
      );
    });
    tearDownAll(() => engine.dispose());

    Future<String?> finishReason(GenerationParams params) async {
      final chunks = await engine.create(const <LlamaChatMessage>[
        LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt),
      ], params: params).toList();
      return chunks.last.choices.single.finishReason;
    }

    test('is length at a full context or maxTokens', () async {
      expect(await finishReason(endless), 'length');
      expect(await finishReason(endless.copyWith(maxTokens: 3)), 'length');
    });

    test('is stop at an end-of-generation token', () async {
      expect(
        await finishReason(endless.copyWith(grammar: 'root ::= "a a"')),
        'stop',
      );
    });
  });
}

/// Copies [source] to [path] with `tokenizer.ggml.eos_token_id` set to [eos].
File _copyWithEosToken(File source, String path, int eos) {
  const ggufUint32 = 4;
  final bytes = source.readAsBytesSync();
  final key = utf8.encode('tokenizer.ggml.eos_token_id');
  for (var i = 0; i + key.length + 8 <= bytes.length; i++) {
    var j = 0;
    while (j < key.length && bytes[i + j] == key[j]) {
      j++;
    }
    if (j < key.length) continue;
    final value = ByteData.sublistView(bytes, i + key.length);
    if (value.getUint32(0, Endian.little) != ggufUint32) break;
    value.setUint32(4, eos, Endian.little);
    return File(path)..writeAsBytesSync(bytes);
  }
  throw StateError('${source.path} has no uint32 eos_token_id');
}
