@TestOn('vm')
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:test/test.dart';

import '../../../support/recording_exit_teardown.dart';
import '../../../support/synthetic_embedding_gguf.dart';

void main() {
  for (final speculative in [false, true]) {
    test(
      'worker serializes embeddings behind real generation: speculative=$speculative',
      () async {
        final dir = Directory.systemTemp.createTempSync('worker_embedding_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = writeSyntheticLlamaGguf('${dir.path}/model.gguf');
        final flag = calloc<Int8>();
        addTearDown(() => calloc.free(flag));
        final recorder = RecordingExitTeardown(
          ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
        );
        final service = LlamaCppService(
          objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
        );
        final handshake = ReceivePort();
        runLlamaWorkerForTesting(
          handshake.sendPort,
          service,
          exitOnDispose: false,
        );
        final worker = await handshake.first as SendPort;
        handshake.close();
        final port = ReceivePort();
        final responses = StreamIterator<Object?>(port);
        addTearDown(() async {
          await responses.cancel();
          port.close();
          final disposed = ReceivePort();
          worker.send(DisposeRequest(disposed.sendPort));
          await disposed.first;
          disposed.close();
        });
        Future<Object?> next() async {
          expect(await responses.moveNext(), isTrue);
          return responses.current;
        }

        worker.send(WorkerHandshake(LlamaLogLevel.warn, port.sendPort));
        expect(await next(), isA<DoneResponse>());
        const params = ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          gpuLayers: 0,
          preferredBackend: GpuBackend.cpu,
          contextSize: 128,
        );
        worker.send(ModelLoadRequest(file.path, params, port.sendPort));
        final model = (await next() as HandleResponse).handle;
        worker.send(ContextCreateRequest(model, params, port.sendPort));
        final context = (await next() as HandleResponse).handle;
        final library = reflectClass(LlamaCppService).owner as LibraryMirror;
        Map active() =>
            reflect(service)
                    .getField(
                      MirrorSystem.getSymbol('_generatingContexts', library),
                    )
                    .reflectee
                as Map;
        var queued = false;
        var timerRan = false;
        var overlapped = false;
        var samples = 0;
        recorder.onCall = (name) {
          if (name == 'llama_dart_sampler_sample') samples++;
          if (name != 'llama_dart_decode') return;
          // Send during prompt decode, before either inference loop. Port/timer
          // events must wait even though async* yields to microtasks.
          overlapped |= timerRan && active().containsKey(context);
          if (queued) return;
          queued = true;
          expect(active().containsKey(context), isTrue);
          Timer.run(() {
            timerRan = true;
            overlapped |= active().containsKey(context);
          });
          worker.send(PerformanceContextRequest(context, port.sendPort));
          worker.send(EmbedRequest(context, 'a', true, port.sendPort));
          worker.send(
            EmbedBatchRequest(context, ['a', 'b'], true, port.sendPort),
          );
          worker.send(
            EmbedContentBatchRequest(
              context,
              [
                LlamaEmbeddingInput([const LlamaTextContent('c')]),
              ],
              true,
              flag.address,
              port.sendPort,
            ),
          );
        };
        worker.send(
          GenerateRequest(
            context,
            'abababab',
            GenerationParams(
              maxTokens: 24,
              temp: 0,
              topK: 1,
              penalty: 1,
              preservedTokens: const ['<unk>', '<s>'],
              seed: 1,
              speculativeDecodingConfig: speculative
                  ? const SpeculativeDecodingConfig.ngramSimple(
                      ngramSizeN: 1,
                      ngramSizeM: 4,
                      ngramMinHits: 1,
                    )
                  : null,
            ),
            flag.address,
            port.sendPort,
          ),
        );
        Object? response;
        var chunks = 0;
        do {
          response = await next();
          expect(response, anyOf(isA<TokenResponse>(), isA<DoneResponse>()));
          if (response is TokenResponse) chunks++;
        } while (response is! DoneResponse);
        expect(response.generationUsage?.completionTokens, 24);
        expect(chunks, greaterThan(0));
        expect(samples, greaterThanOrEqualTo(speculative ? 1 : 24));
        expect(queued, isTrue);
        final counters = await next() as PerformanceContextResponse;
        expect(counters.evalTokens, 24);
        if (speculative) {
          expect(counters.speculativeDraftAttempts, greaterThan(0));
        }
        expect(await next(), isA<EmbedResponse>());
        expect(await next(), isA<EmbedBatchResponse>());
        expect(await next(), isA<EmbedBatchResponse>());
        expect(timerRan, isTrue);
        expect(overlapped, isFalse);
        expect(active(), isEmpty);
        expect(
          service.getPerformanceContext(context)?.evalTokens,
          lessThan(24),
        );
      },
    );
  }
}
