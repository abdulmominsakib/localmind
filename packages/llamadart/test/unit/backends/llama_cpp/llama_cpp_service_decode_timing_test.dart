@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
);
const _greedy = GenerationParams(maxTokens: 8, temp: 0, topK: 1, seed: 1);

// The time the fake backend keeps computing after each llama_decode returns.
const _backendMicros = 5000;
const _backendMs = _backendMicros / 1000;

// Runs the real llama.cpp runtime on the CPU behind a decode that returns
// before its backend has finished, as Metal's does: the backend stays busy
// for _backendMicros after each llama_decode, until a synchronize waits for
// it.
void main() {
  late Directory dir;
  late LlamaCppService service;
  late int model;
  late int context;
  late List<String> calls;
  late int Function(Pointer<llama_context> ctx, llama_batch batch) decode;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_decode_timing_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    calls = [];
    final clock = Stopwatch()..start();
    var busyUntil = 0;
    decode = (ctx, batch) {
      calls.add('decode');
      final status = llama_decode(ctx, batch);
      busyUntil = clock.elapsedMicroseconds + _backendMicros;
      return status;
    };
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.untracked(
        decode: decode,
        synchronize: (ctx) {
          calls.add('synchronize');
          while (clock.elapsedMicroseconds < busyUntil) {}
          llama_synchronize(ctx);
        },
      ),
    )..initializeBackend();
    model = service.loadModel('${dir.path}/model.gguf', _params);
    context = service.createContext(model, _params);
  });

  tearDown(() {
    service.dispose();
    dir.deleteSync(recursive: true);
  });

  Future<void> generate(String prompt, {List<LlamaContentPart>? parts}) async {
    final cancel = calloc<Int8>();
    try {
      await service
          .generate(context, prompt, _greedy, cancel.address, parts: parts)
          .drain<void>();
    } finally {
      calloc.free(cancel);
    }
  }

  for (final (name, params) in [
    (
      'thinking',
      const GenerationParams(
        thinkingBudget: ThinkingBudget(maxTokens: 2147483648),
      ),
    ),
    (
      'speculative',
      const GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(),
      ),
    ),
    (
      'mtp',
      const GenerationParams(
        speculativeDecodingConfig: SpeculativeDecodingConfig.mtp(),
      ),
    ),
  ]) {
    test(
      'validation failure clears previous llama.cpp counters ($name)',
      () async {
        await generate('ab');
        expect(service.getPerformanceContext(context), isNotNull);
        final cancel = calloc<Int8>();
        try {
          await expectLater(
            service.generate(context, 'ab', params, cancel.address),
            emitsError(
              name == 'mtp'
                  ? isA<LlamaUnsupportedException>()
                  : name == 'thinking'
                  ? isA<ArgumentError>()
                  : isA<LlamaArgumentException>(),
            ),
          );
        } finally {
          calloc.free(cancel);
        }
        expect(service.getPerformanceContext(context), isNull);
        final handshake = ReceivePort();
        runLlamaWorkerForTesting(
          handshake.sendPort,
          service,
          exitOnDispose: false,
        );
        final backend = NativeLlamaBackend(
          initialSendPort: await handshake.first as SendPort,
        );
        handshake.close();
        addTearDown(backend.dispose);
        expect(await backend.getPerformanceContext(context), isNull);
        await generate('ab');
        expect(service.getPerformanceContext(context), isNotNull);
        expect(await backend.getPerformanceContext(context), isNotNull);
      },
    );
  }

  test('getPerformanceContext counts the backend work of a decode as '
      'decode time', () async {
    await generate('ab');
    final perf = service.getPerformanceContext(context)!;

    expect(perf.evalTokens, greaterThan(0));
    expect(perf.decodeMs, greaterThanOrEqualTo(perf.evalTokens * _backendMs));
    expect(perf.promptEvalMs, greaterThanOrEqualTo(_backendMs));
    // Every decode waits for its backend before the next call.
    expect(
      calls.join(' '),
      matches(RegExp(r'^synchronize( decode synchronize)+$')),
    );
  });

  for (final chunkEval in [false, true]) {
    test('getPerformanceContext counts the backend work of a media prompt '
        'as prompt time (chunk-level eval: $chunkEval)', () async {
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      // libmtmd decodes the prompt with llama_decode itself.
      final fake = FakeMtmd.install(
        service,
        tokens: service.tokenize(model, 'ab', true),
        chunkEval: chunkEval,
        decode: decode,
      );
      addTearDown(fake.dispose);
      service.createMultimodalContext(model, projectorPath);

      await generate('<__media__>', parts: fake.parts);
      final perf = service.getPerformanceContext(context)!;

      expect(fake.evaluations, 1);
      expect(perf.promptEvalMs, greaterThanOrEqualTo(_backendMs));
    });
  }
}
