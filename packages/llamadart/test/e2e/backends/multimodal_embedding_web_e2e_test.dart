@TestOn('browser')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show window;

import '../../support/embedding_contract.dart';

// Local assets/reference only; setup and recorded qualification are documented in
// doc/multimodal_embeddings_web.md. No default model or network download.
void main() {
  test('scenario contract compares vector elements in reverse order', () {
    _expectOrderedVectors(
      [
        [3.0, 4.0],
        [1.0, 2.0],
      ],
      [
        [3.0, 4.0],
        [1.0, 2.0],
      ],
    );
    expect(
      () => _expectOrderedVectors(
        [
          [1.0, 2.0],
        ],
        [
          [2.0, 1.0],
        ],
      ),
      throwsA(isA<TestFailure>()),
    );
  });
  test('scenario contract rejects missing or extra vectors', () {
    for (final actual in <List<List<double>>>[
      [],
      [
        [1.0],
        [2.0],
      ],
    ]) {
      expect(
        () => _expectOrderedVectors(actual, [
          [1.0],
        ]),
        throwsA(isA<TestFailure>()),
      );
    }
  });
  test('scenario contract configures memory64 with the bridge API keys', () {
    final config = _bridgeConfig(true, (key) => key);
    expect(
      config.getProperty<JSString>('coreModuleUrlMem64'.toJS).toDart,
      'coreMem64',
    );
    expect(
      config.getProperty<JSString>('wasmUrlMem64'.toJS).toDart,
      'wasmMem64',
    );
    expect(config.getProperty<JSBoolean>('preferMemory64'.toJS).toDart, isTrue);
    expect(config.has('workerRequestTimeoutMs'), isFalse);
  });
  for (final isPending in [true, false]) {
    test(
      'scenario contract interrupts only pending RPCs in its test zone: $isPending',
      () async {
        final testZone = Zone.current;
        final pending = globalContext
            .getProperty<JSFunction>('Map'.toJS)
            .callAsConstructor<JSObject>();
        if (isPending) {
          pending.callMethod<JSAny?>('set'.toJS, 1.toJS, true.toJS);
        }
        var posts = 0;
        final worker = JSObject()
          ..setProperty(
            'postMessage'.toJS,
            ((JSAny? _, JSAny? _) {
              posts++;
            }).toJS,
          );
        final proxy = JSObject()
          ..setProperty('_worker'.toJS, worker)
          ..setProperty('_pending'.toJS, pending);
        final bridge = JSObject()..setProperty('_workerProxy'.toJS, proxy);
        var interrupted = false;
        final fired = _interruptWorkerEmbedding(bridge as LlamaWebGpuBridge, (
          _,
        ) {
          expect(Zone.current, same(testZone));
          interrupted = true;
        });
        final assertion = isPending
            ? expectLater(fired, completes)
            : expectLater(fired, throwsA(isA<TestFailure>()));
        final message = JSObject()
          ..setProperty('method'.toJS, 'embedBatch'.toJS)
          ..setProperty('id'.toJS, 1.toJS);
        // JavaScript invokes exported Dart callbacks outside the test zone.
        Zone.root.run(
          () => worker
              .getProperty<JSFunction>('postMessage'.toJS)
              .callAsFunction(worker, message, null),
        );
        await assertion;
        expect(posts, 1);
        expect(interrupted, isPending);
      },
    );
  }
  final configUrl = Uri.base.resolve(
    '../../../build/webgpu_embeddings_e2e/config.json',
  );
  Future<JSAny?> fetch(String url) async {
    final response = await window.fetch(url.toJS).toDart;
    expect(response.ok, isTrue, reason: 'Local embedding fixture unavailable.');
    return response;
  }

  for (final worker in [true, false]) {
    test(
      '${worker ? 'worker' : 'direct'} local media reference qualification',
      () async {
        final response = await fetch(configUrl.toString());
        final text = await (response as JSObject)
            .callMethod<JSPromise<JSString>>('text'.toJS)
            .toDart;
        final config = jsonDecode(text.toDart) as Map<String, dynamic>;
        String url(String key) =>
            configUrl.resolve(config[key] as String).toString();
        final module = await importModule(url('bridge').toJS).toDart;
        final constructor = module.getProperty<JSFunction>(
          'LlamaWebGpuBridge'.toJS,
        );
        final bridgeConfig = _bridgeConfig(worker, url);
        final bridge = constructor.callAsConstructor<LlamaWebGpuBridge>(
          bridgeConfig,
        );
        final engine = LlamaEngine(
          WebGpuLlamaBackend(bridgeFactory: ([config]) => bridge),
        );
        addTearDown(engine.dispose);
        await engine.loadModelFromUrl(
          url('model'),
          modelParams: const ModelParams(
            contextSize: 4096,
            batchSize: 4096,
            microBatchSize: 4096,
            gpuLayers: 0,
          ),
        );
        final core = (await engine
            .getMetadata())['llamadart.webgpu.core_variant'];
        print('${worker ? 'worker' : 'direct'} embedding core: $core');
        expect(
          core,
          'wasm64',
          reason: 'Repeated media batches are qualified only on memory64.',
        );
        await engine.loadMultimodalProjector(url('projector'));
        expect(
          (bridge as JSObject).getProperty<JSAny?>('_workerProxy'.toJS) != null,
          worker,
          reason: 'Worker fallback must not count as worker qualification.',
        );
        if (worker) {
          final proxy = _expectWorkerState(bridge, true, 'initialization')!;
          final mediaBatch = [
            [
              {'type': 'image'},
            ],
          ].jsify();
          expect(
            proxy
                .callMethod<JSNumber>(
                  '_resolveRequestTimeoutMs'.toJS,
                  'embedBatch'.toJS,
                  [mediaBatch].jsify(),
                )
                .toDartDouble,
            const Duration(minutes: 10).inMilliseconds,
          );
        }
        final caps = await engine.embeddingCapabilities;
        expect([caps.text, caps.image, caps.audio], [true, true, true]);
        Future<Uint8List> bytes(String key) async {
          final response = (await fetch(url(key)))! as JSObject;
          final buffer = await response
              .callMethod<JSPromise<JSArrayBuffer>>('arrayBuffer'.toJS)
              .toDart;
          return buffer.toDart.asUint8List();
        }

        final image = LlamaImageContent(bytes: await bytes('image'));
        final audio = LlamaAudioContent(bytes: await bytes('audio'));
        final inputs = [
          LlamaEmbeddingInput([LlamaTextContent(config['text'] as String)]),
          LlamaEmbeddingInput([image]),
          LlamaEmbeddingInput([audio]),
          LlamaEmbeddingInput([
            const LlamaTextContent('first '),
            image,
            const LlamaTextContent(' between '),
            audio,
            const LlamaTextContent(' last '),
          ]),
        ];
        final actual = await engine.embedContentBatch(inputs);
        print(
          'EMBEDDING_VECTORS ${jsonEncode({'runtime': worker ? 'worker' : 'direct', 'vectors': actual})}',
        );
        final expected = (config['normalizedVectors'] as List)
            .map(
              (row) => (row as List).map((v) => (v as num).toDouble()).toList(),
            )
            .toList();
        expect(expected, hasLength(inputs.length));
        for (var i = 0; i < inputs.length; i++) {
          expect(actual[i], hasLength(expected[i].length));
          double dot = 0, aa = 0, bb = 0;
          for (var j = 0; j < actual[i].length; j++) {
            expect(actual[i][j].isFinite, isTrue);
            dot += actual[i][j] * expected[i][j];
            aa += actual[i][j] * actual[i][j];
            bb += expected[i][j] * expected[i][j];
          }
          expect(math.sqrt(aa), closeTo(1, 1e-5));
          // Qualified CPU wasm/native cosine exceeds 0.99998. Keep a portable
          // gate; changes require exact-artifact evidence.
          expect(dot / math.sqrt(aa * bb), greaterThanOrEqualTo(0.999));
          _recordComparison(actual[i], expected[i], worker, i, 'cpu');
          final metal = config['normalizedMetalVectors'] as List?;
          if (metal != null) {
            _recordComparison(
              actual[i],
              (metal[i] as List).cast<num>().map((v) => v.toDouble()).toList(),
              worker,
              i,
              'metal',
            );
          }
        }
        _expectWorkerState(bridge, worker, 'reference batch');
        if (worker) {
          final cancelled = _interruptWorkerEmbedding(
            bridge,
            (_) => engine.cancelGeneration(),
          );
          await expectLater(
            engine.embedContent(inputs.last),
            throwsA(
              isA<LlamaInferenceException>().having(
                (error) => error.message.toLowerCase(),
                'message',
                contains('cancel'),
              ),
            ),
          );
          await cancelled;
          _expectOrderedVectors(
            [await engine.embedContent(inputs[1])],
            [actual[1]],
          );
          print('worker in-flight cancellation and reuse: PASS');

          _expectWorkerState(bridge, true, 'cancellation and reuse');
        }
        expect(
          await engine.embedContent(inputs.first),
          orderedEquals(actual.first),
        );
        final reversed = await engine.embedContentBatch(
          inputs.reversed.toList(),
        );
        _expectOrderedVectors(reversed, actual.reversed.toList());
        _expectWorkerState(bridge, worker, 'reversed batch');
        final raw = await engine.embedContentBatch(inputs, normalize: false);
        for (var i = 0; i < raw.length; i++) {
          final norm = math.sqrt(raw[i].fold<double>(0, (s, x) => s + x * x));
          for (var j = 0; j < raw[i].length; j++) {
            expect(raw[i][j] / norm, closeTo(actual[i][j], 1e-5));
          }
        }
        _expectWorkerState(bridge, worker, 'raw batch');
        await expectAdjacentTextEmbeddingEquivalence(
          engine.embedContent,
          before: [image],
          after: [audio],
        );
        _expectWorkerState(bridge, worker, 'adjacent text');
        final wav = audio.bytes!;
        // The recorded fixture is mono IEEE float32 WAV at 16 kHz. Check its
        // format before comparing the two public audio source representations.
        final header = ByteData.sublistView(wav);
        expect(header.getUint16(20, Endian.little), 3);
        expect(header.getUint16(22, Endian.little), 1);
        expect(header.getUint32(24, Endian.little), 16000);
        expect(header.getUint16(34, Endian.little), 32);
        expect(ascii.decode(wav.sublist(36, 40)), 'data');
        final pcm = Float32List.fromList([
          for (var offset = 44; offset < wav.length; offset += 4)
            header.getFloat32(offset, Endian.little),
        ]);
        _expectOrderedVectors(
          [
            await engine.embedContent(
              LlamaEmbeddingInput([LlamaAudioContent(samples: pcm)]),
            ),
          ],
          [actual[2]],
        );

        _expectWorkerState(bridge, worker, 'PCM');
        await expectLater(
          engine.embedContent(
            LlamaEmbeddingInput([
              LlamaTextContent(List.filled(5000, 'overflow ').join()),
              image,
            ]),
          ),
          throwsA(
            isA<LlamaInferenceException>().having(
              (error) => error.message,
              'code',
              contains('EMBEDDING_INPUT_TOO_LARGE'),
            ),
          ),
        );
        _expectOrderedVectors(
          [await engine.embedContent(inputs[1])],
          [actual[1]],
        );
        _expectWorkerState(bridge, worker, 'capacity rejection and reuse');
        print(
          '${worker ? 'worker' : 'direct'} capacity rejection and reuse: PASS',
        );

        await engine.unloadMultimodalProjector();
        final unloaded = await engine.embeddingCapabilities;
        expect(
          [unloaded.text, unloaded.image, unloaded.audio],
          [true, false, false],
        );
        await expectLater(
          engine.embedContent(inputs[1]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        await engine.loadMultimodalProjector(url('projector'));
        final reloaded = await engine.embeddingCapabilities;
        expect(
          [reloaded.text, reloaded.image, reloaded.audio],
          [true, true, true],
        );
        _expectOrderedVectors(
          [await engine.embedContent(inputs[1])],
          [actual[1]],
        );
        _expectWorkerState(bridge, worker, 'projector reload');
        print('${worker ? 'worker' : 'direct'} projector unload/reload: PASS');

        if (worker) {
          final terminated = _interruptWorkerEmbedding(bridge, (workerObject) {
            workerObject.callMethod<JSAny?>('terminate'.toJS);
            // Terminate the real worker, then deliver its error notification to
            // the production proxy. Inference and restoration stay unmocked.
            final event = JSObject()
              ..setProperty(
                'message'.toJS,
                'Qualification worker termination'.toJS,
              );
            workerObject
                .getProperty<JSFunction>('onerror'.toJS)
                .callAsFunction(workerObject, event);
          });
          _expectOrderedVectors(
            [await engine.embedContent(inputs[1])],
            [actual[1]],
          );
          await terminated;
          expect(
            (bridge as JSObject).getProperty<JSAny?>('_workerProxy'.toJS),
            isNull,
          );
          final restored = await engine.embeddingCapabilities;
          expect(
            [restored.text, restored.image, restored.audio],
            [true, true, true],
          );
          final metadata = await engine.getMetadata();
          expect(metadata['llamadart.webgpu.core_variant'], 'wasm64');
          expect(metadata['llamadart.webgpu.n_batch'], '4096');
          expect(metadata['llamadart.webgpu.n_ubatch'], '4096');
          print(
            'worker loss, CPU recovery, projector and load-option restoration: PASS',
          );
        }
      },
      // A real run takes up to 45 minutes on a loaded host; the e2e tag's 15
      // minutes stopped a direct run that was still making progress.
      timeout: const Timeout(Duration(minutes: 60)),
    );
  }
}

void _recordComparison(
  List<double> actual,
  List<double> reference,
  bool worker,
  int input,
  String backend,
) {
  expect(actual, hasLength(768));
  expect(reference, hasLength(actual.length));
  double dot = 0, aa = 0, bb = 0, maxAbs = 0;
  for (var i = 0; i < actual.length; i++) {
    dot += actual[i] * reference[i];
    aa += actual[i] * actual[i];
    bb += reference[i] * reference[i];
    maxAbs = math.max(maxAbs, (actual[i] - reference[i]).abs());
  }
  final cosine = dot / math.sqrt(aa * bb);
  expect(cosine, greaterThanOrEqualTo(0.999));
  print(
    'EMBEDDING_METRIC ${jsonEncode({'runtime': worker ? 'worker' : 'direct', 'input': input, 'reference': backend, 'cosine': cosine, 'maxAbs': maxAbs, 'norm': math.sqrt(aa), 'width': actual.length})}',
  );
}

JSObject? _expectWorkerState(
  LlamaWebGpuBridge bridge,
  bool worker,
  String stage,
) {
  final proxy = (bridge as JSObject).getProperty<JSObject?>(
    '_workerProxy'.toJS,
  );
  expect(
    proxy != null,
    worker,
    reason: 'Worker fallback must not count as worker qualification ($stage).',
  );
  return proxy;
}

Future<void> _interruptWorkerEmbedding(
  LlamaWebGpuBridge bridge,
  void Function(JSObject worker) interrupt,
) {
  final proxy = _expectWorkerState(bridge, true, 'fault injection')!;
  final worker = proxy.getProperty<JSObject>('_worker'.toJS);
  final original = worker.getProperty<JSFunction>('postMessage'.toJS);
  final fired = Completer<void>();
  final testZone = Zone.current;
  worker.setProperty(
    'postMessage'.toJS,
    testZone.bindBinaryCallback((JSAny? message, JSAny? transfers) {
      original.callAsFunction(worker, message, transfers);
      final request = message as JSObject;
      if (request.getProperty<JSAny?>('method'.toJS)?.dartify() !=
          'embedBatch') {
        return;
      }
      worker.setProperty('postMessage'.toJS, original);
      Timer(const Duration(milliseconds: 100), () {
        try {
          final pending = proxy.getProperty<JSObject>('_pending'.toJS);
          expect(
            pending
                .callMethod<JSBoolean>(
                  'has'.toJS,
                  request.getProperty<JSAny?>('id'.toJS),
                )
                .toDart,
            isTrue,
            reason: 'Fault must arrive while the real media RPC is pending.',
          );
          interrupt(worker);
          fired.complete();
        } catch (error, stack) {
          fired.completeError(error, stack);
        }
      });
    }).toJS,
  );
  addTearDown(() => worker.setProperty('postMessage'.toJS, original));
  return fired.future;
}

JSObject _bridgeConfig(bool worker, String Function(String) url) {
  return JSObject()
    ..setProperty('disableWorker'.toJS, (!worker).toJS)
    ..setProperty('workerUrl'.toJS, url('worker').toJS)
    ..setProperty('coreModuleUrl'.toJS, url('core').toJS)
    ..setProperty('wasmUrl'.toJS, url('wasm').toJS)
    ..setProperty('coreModuleUrlMem64'.toJS, url('coreMem64').toJS)
    ..setProperty('wasmUrlMem64'.toJS, url('wasmMem64').toJS)
    ..setProperty('preferMemory64'.toJS, true.toJS);
}

void _expectOrderedVectors(
  List<List<double>> actual,
  List<List<double>> expected,
) {
  expect(actual, hasLength(expected.length));
  for (var i = 0; i < actual.length; i++) {
    expect(actual[i], orderedEquals(expected[i]));
  }
}
