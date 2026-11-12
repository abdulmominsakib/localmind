/// Real-asset check of the bridge runtime fixes in the pinned bridge assets,
/// through both the worker and the direct runtime:
///
/// - a model and a chat image URL relative to the document load without
///   leaving the worker
///   ([llama-web-bridge#113](https://github.com/leehack/llama-web-bridge/issues/113));
/// - a missing state file throws `LlamaStateException` and leaves the runtime
///   usable instead of aborting it
///   ([#116](https://github.com/leehack/llama-web-bridge/issues/116));
/// - a truncated state snapshot rejects and leaves the runtime usable instead
///   of aborting it
///   ([#169](https://github.com/leehack/llama-web-bridge/issues/169));
/// - unloading, reloading and disposing a model still work now that bridge
///   teardown awaits the WebGPU shutdown
///   ([#150](https://github.com/leehack/llama-web-bridge/issues/150)). The
///   backend gives each load a new bridge, so the same-bridge reload that
///   #150 broke is not reachable from here;
/// - string embeddings of a rank-pooled reranker throw
///   `LlamaUnsupportedException`, and an encoder input over the micro-batch
///   throws `LlamaEmbeddingInputTooLongException`, instead of returning
///   an invalid vector built from classifier scores or a vector of part of the input (`v0.1.73+`,
///   [#121](https://github.com/leehack/llama-web-bridge/issues/121));
/// - llama.cpp `v0.8.0` refuses a grammar chained past 256 levels with a typed
///   error and keeps the runtime, and generated schema grammars with more than
///   128 optional properties stay below that limit;
/// - a lazy grammar without triggers reports a typed argument rejection;
/// - a llama.cpp `v0.8.0` Soprano or LFM3 Audio projector is not reported as
///   text-to-speech.
///
/// The test runner serves the package root, so the files must sit under
/// `build/webgpu_bridge_fixes_e2e/` (gitignored), hard-linked or copied there
/// because the runner does not serve symbolic links to files outside it, with
/// this `config.json`, whose paths are relative to it:
///
/// ```json
/// {
///   "assets": "assets/<tag>/",
///   "model": "models/stories15M.gguf",
///   "visionModel": "models/LFM2-VL-450M-Q4_0.gguf",
///   "visionProjector": "models/mmproj-LFM2-VL-450M-Q8_0.gguf",
///   "image": "media/red_square.png",
///   "rerankerModel": "models/qwen3-reranker-0.6b-q8_0.gguf",
///   "encoderModel": "models/modernbert-mean-pooled.gguf",
///   "sopranoModel": "models/Soprano-1.1-80M-F16.gguf",
///   "sopranoProjector": "models/mmproj-Soprano-1.1-80M-F16.gguf",
///   "lfm3AudioModel": "models/LFM3-Audio-2B-Q4_K_M.gguf",
///   "lfm3AudioProjector": "models/mmproj-LFM3-Audio-2B-Q8_0.gguf",
///   "gpuLayers": 0
/// }
/// ```
///
/// Fetch `assets` with `WEBGPU_BRIDGE_OUT_DIR=<dir>`
/// `./scripts/fetch_webgpu_bridge_assets.sh`. Keep it at a different directory
/// depth from this test, so a URL relative to the document does not also
/// resolve against the worker script; the test checks this. `model` is any
/// small text GGUF, such as `stories15M`; `visionModel` and `visionProjector`
/// are `LiquidAI/LFM2-VL-450M-GGUF`, and `image` is any small PNG.
/// `rerankerModel` is a rank-pooled GGUF such as Qwen3-Reranker-0.6B, and
/// `encoderModel` a MEAN-pooled ModernBERT embedding GGUF. Set
/// `gpuLayers` above 0 to run on WebGPU; the test then requires a WebGPU
/// backend.
///
/// The bridge core's threads need SharedArrayBuffer, so point
/// `CHROME_EXECUTABLE` at a wrapper that starts Chrome with
/// `--enable-features=SharedArrayBuffer,SharedArrayBufferUnrestrictedAccessAllowed`.
/// For WebGPU on macOS it also adds `--enable-unsafe-webgpu --use-angle=metal`
/// and replaces the runner's `--headless` with `--headless=new`, under which
/// Chrome grants an adapter. Then run `dart test -p chrome --run-skipped -t
/// local-only test/e2e/webgpu/bridge_runtime_fixes_e2e_test.dart`.
@TestOn('browser')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 20))
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Response, document, window;

const String _configPath = '../../../build/webgpu_bridge_fixes_e2e/config.json';

const GenerationParams _greedy = GenerationParams(
  maxTokens: 24,
  temp: 0,
  topK: 1,
  seed: 7,
);

void main() {
  final configUrl = Uri.base.resolve(_configPath);
  late Map<String, Object?> config;
  late JSFunction bridgeConstructor;

  Uri fixture(String key) => configUrl.resolve(config[key]! as String);
  Uri asset(String name) => fixture('assets').resolve(name);
  int gpuLayers() => (config['gpuLayers'] as int?) ?? 0;
  ModelParams modelParams() => ModelParams(
    contextSize: 2048,
    gpuLayers: gpuLayers(),
    preferredBackend: gpuLayers() > 0 ? GpuBackend.auto : GpuBackend.cpu,
  );

  setUpAll(() async {
    final response = await _fetch(configUrl);
    expect(response.ok, isTrue, reason: 'Missing $configUrl');
    config =
        jsonDecode((await response.text().toDart).toDart)
            as Map<String, Object?>;
    final module = await importModule(
      asset('llama_webgpu_bridge.js').toString().toJS,
    ).toDart;
    bridgeConstructor = module['LlamaWebGpuBridge']! as JSFunction;
  });

  for (final worker in [true, false]) {
    final runtime = worker ? 'worker' : 'direct';

    group('$runtime runtime', () {
      late LlamaWebGpuBridge bridge;
      late LlamaEngine engine;

      void expectRuntime(String stage) {
        expect(
          (bridge as JSObject)['_workerProxy'] != null,
          worker,
          reason: 'The bridge left the $runtime runtime ($stage).',
        );
      }

      setUp(() {
        // The backend disposes its bridge when it unloads a model and asks
        // for a new one on the next load, as in production.
        engine = LlamaEngine(
          WebGpuLlamaBackend(
            bridgeFactory: ([_]) =>
                bridge = bridgeConstructor.callAsConstructor<LlamaWebGpuBridge>(
                  JSObject()
                    ..['disableWorker'] = (!worker).toJS
                    ..['workerUrl'] = asset(
                      'llama_webgpu_bridge_worker.js',
                    ).toString().toJS
                    ..['coreModuleUrl'] = asset(
                      'llama_webgpu_core.js',
                    ).toString().toJS
                    ..['wasmUrl'] = asset(
                      'llama_webgpu_core.wasm',
                    ).toString().toJS,
                ),
          ),
        );
        addTearDown(engine.dispose);
      });

      Future<String> load(String key, [ModelParams? params]) async {
        final relative = _relativeToDocument(fixture(key));
        await engine.loadModelFromUrl(
          relative,
          modelParams: params ?? modelParams(),
        );
        final backendName = await engine.getBackendName();
        print('[bridge-fixes] $runtime $key backend: $backendName');
        if (gpuLayers() > 0) {
          expect(backendName, contains('WebGPU'));
        }
        expectRuntime('model load');
        return relative;
      }

      Future<String> generate() =>
          engine.generate('Once upon a time', params: _greedy).join();

      test('loads a document-relative model and reloads it', () async {
        await load('model');
        final baseline = await generate();
        expect(baseline, isNotEmpty);

        await engine.unloadModel();
        await load('model');
        expect(await generate(), baseline);
        expectRuntime('reload');
      });

      test('a missing state file throws and keeps the runtime', () async {
        await load('model');
        final baseline = await generate();
        final tokens = await engine.tokenize('Once upon a time');

        final cannotOpen = throwsA(
          isA<LlamaStateException>().having(
            (error) => error.details,
            'details',
            contains('Cannot open state file'),
          ),
        );
        await expectLater(
          engine.stateLoadFile('/missing.state', tokenCapacity: 512),
          cannotOpen,
        );
        await expectLater(
          engine.stateLoadFile('/', tokenCapacity: 512),
          cannotOpen,
        );
        await expectLater(
          engine.stateSaveFile('/missing-dir/a.state', tokens: tokens),
          cannotOpen,
        );
        expectRuntime('state rejections');

        expect(await engine.stateSaveFile('/a.state', tokens: tokens), isTrue);
        final restored = await engine.stateLoadFile(
          '/a.state',
          tokenCapacity: 512,
        );
        expect(restored.tokens, tokens);
        expect(
          await engine
              .generate(
                'Once upon a time',
                params: _greedy.copyWith(reusePromptPrefix: false),
              )
              .join(),
          baseline,
        );
        expectRuntime('state round trip');
      });

      test(
        'a truncated state snapshot rejects and keeps the runtime',
        () async {
          await load('model');
          final baseline = await generate();
          final tokens = await engine.tokenize('Once upon a time');
          final jsBridge = bridge as JSObject;

          final saved = await jsBridge
              .callMethod<JSPromise<JSUint8Array>>(
                'stateSaveBytes'.toJS,
                tokens.map((token) => token.toJS).toList().toJS,
              )
              .toDart;
          final snapshot = saved.toDart;
          expect(snapshot.length, greaterThan(64));

          Future<void> loadBytes(Uint8List bytes) => jsBridge
              .callMethod<JSPromise<JSAny?>>(
                'stateLoadBytes'.toJS,
                bytes.toJS,
                512.toJS,
              )
              .toDart;

          for (final length in [
            12,
            snapshot.length ~/ 2,
            snapshot.length - 1,
          ]) {
            await expectLater(
              loadBytes(Uint8List.sublistView(snapshot, 0, length)),
              throwsA(anything),
              reason: 'A snapshot cut to $length bytes must reject.',
            );
            expectRuntime('truncated state at $length bytes');
          }

          await loadBytes(snapshot);
          expect(
            await engine
                .generate(
                  'Once upon a time',
                  params: _greedy.copyWith(reusePromptPrefix: false),
                )
                .join(),
            baseline,
          );
          expectRuntime('state restore after truncated snapshots');
        },
      );

      test('string embeddings reject a rank-pooled reranker', () async {
        await load('rerankerModel');
        final rejectsRank = throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('rank-pooled'),
          ),
        );
        await expectLater(engine.embed('What is the capital?'), rejectsRank);
        await expectLater(
          engine.embedBatch(const ['a query', 'a document']),
          rejectsRank,
        );
        expect(await engine.tokenize('still usable'), isNotEmpty);
        expectRuntime('rank pooling rejection');
      });

      test(
        'string embeddings reject an encoder input over the micro-batch',
        () async {
          await load(
            'encoderModel',
            modelParams().copyWith(batchSize: 64, microBatchSize: 64),
          );
          expect(
            (await engine.getMetadata())['llamadart.webgpu.n_ubatch'],
            '64',
          );
          const short = 'The Eiffel Tower is in Paris.';
          final baseline = await engine.embed(short);
          expect(baseline, isNotEmpty);
          expect(baseline.every((value) => value.isFinite), isTrue);

          final long = List.filled(120, 'word').join(' ');
          print(
            '[bridge-fixes] $runtime long input tokens: '
            '${await engine.getTokenCount(long)}',
          );
          final tooLong = throwsA(
            isA<LlamaEmbeddingInputTooLongException>()
                .having((error) => error.maxInputTokens, 'maxInputTokens', 64)
                .having(
                  (error) => error.actualTokens,
                  'actualTokens',
                  greaterThan(64),
                ),
          );
          await expectLater(engine.embed(long), tooLong);
          await expectLater(engine.embedBatch([short, long]), tooLong);
          expectRuntime('one-pass overflow rejection');

          expect(await engine.embed(short), baseline);
          expectRuntime('embedding after the rejection');
        },
      );

      test(
        'a grammar chained past 256 levels throws and keeps the runtime',
        () async {
          await load('model');
          const shallow = GenerationParams(maxTokens: 2, seed: 7);
          await expectLater(
            engine
                .generate(
                  'Once',
                  params: shallow.copyWith(grammar: _chainedGrammar(400)),
                )
                .join(),
            throwsA(isA<LlamaInferenceException>()),
          );
          expect(await generate(), isNotEmpty);
          expect(
            await engine
                .generate(
                  'Once',
                  params: shallow.copyWith(grammar: _chainedGrammar(100)),
                )
                .join(),
            isNotEmpty,
          );
          expectRuntime('grammar depth rejection');
        },
      );

      for (final count in [129, 300, 1023]) {
        test('a schema with $count optional properties generates', () async {
          await load('model');
          final grammar = JsonSchemaConverter.convert(<String, dynamic>{
            'type': 'object',
            'properties': {
              for (var i = 0; i < count; i++) 'p$i': {'type': 'integer'},
            },
            'additionalProperties': false,
          });
          final text = await engine
              .generate(
                'Once',
                params: GenerationParams(
                  maxTokens: 8,
                  seed: 7,
                  grammar: grammar,
                ),
              )
              .join();
          expect(text, startsWith('{'));
          expectRuntime('long optional-property grammar');
        });
      }

      test(
        'a lazy grammar without triggers reports an argument error',
        () async {
          await load('model');
          final probe = await bridge.getCompletionCapabilities()!.toDart;
          expect((probe! as JSObject)['lazyGrammar'].dartify(), isTrue);
          await expectLater(
            engine
                .generate(
                  'Once',
                  params: const GenerationParams(
                    maxTokens: 2,
                    grammar: 'root ::= "a"',
                    grammarLazy: true,
                  ),
                )
                .join(),
            throwsA(isA<LlamaArgumentException>()),
          );
        },
      );

      for (final (name, model, projector) in const [
        ('Soprano', 'sopranoModel', 'sopranoProjector'),
        ('LFM3 Audio', 'lfm3AudioModel', 'lfm3AudioProjector'),
      ]) {
        test('$name is not reported as text-to-speech', () async {
          await load(model);
          await engine.loadMultimodalProjector(
            _relativeToDocument(fixture(projector)),
          );
          final capabilities = await engine.backendTextToSpeechCapabilities;
          print(
            '[bridge-fixes] $runtime $name TTS: '
            '${capabilities.unsupportedReason}',
          );
          expect(capabilities.isSupported, isFalse);
          expectRuntime('$name capability probe');
        });
      }

      test('an image URL relative to the document resolves', () async {
        final image = fixture('image');
        final relative = _relativeToDocument(image);
        final workerUrl = asset('llama_webgpu_bridge_worker.js');
        expect(
          (await _fetch(workerUrl.resolve(relative))).ok,
          isFalse,
          reason:
              'Move the assets to another directory depth: $relative also '
              'resolves against the worker script.',
        );

        await load('visionModel');
        await engine.loadMultimodalProjector(
          _relativeToDocument(fixture('visionProjector')),
        );
        final imageBytes = Uint8List.view(
          (await (await _fetch(image)).arrayBuffer().toDart).toDart,
        );

        Future<String> describe(LlamaImageContent part) => engine.create([
          LlamaChatMessage.withContent(
            role: LlamaChatRole.user,
            content: [part, const LlamaTextContent('Describe the image.')],
          ),
        ], params: _greedy).text();

        final fromBytes = await describe(LlamaImageContent(bytes: imageBytes));
        final fromUrl = await describe(LlamaImageContent(url: relative));
        print('[bridge-fixes] $runtime image reply: $fromUrl');
        expect(fromUrl, isNotEmpty);
        expect(fromUrl, fromBytes);
        expectRuntime('image completion');
      });
    });
  }
}

/// A chain where each rule starts with something that can be empty, so
/// llama.cpp's left-recursion check descends one level per rule.
String _chainedGrammar(int depth) {
  final rules = StringBuffer('root ::= r0\n');
  for (var i = 0; i < depth; i++) {
    rules.writeln('r$i ::= "a"? r${i + 1}');
  }
  rules.writeln('r$depth ::= "a"');
  return rules.toString();
}

Future<Response> _fetch(Uri url) => window.fetch(url.toString().toJS).toDart;

/// [target] as a path relative to the document, which the bridge must not
/// resolve against its worker script.
String _relativeToDocument(Uri target) {
  final base = Uri.parse(document.baseURI);
  expect(target.origin, base.origin);
  final from = base.pathSegments.sublist(0, base.pathSegments.length - 1);
  final to = target.pathSegments;
  var shared = 0;
  while (shared < from.length &&
      shared < to.length - 1 &&
      from[shared] == to[shared]) {
    shared++;
  }
  return [
    for (var i = shared; i < from.length; i++) '..',
    ...to.skip(shared),
  ].join('/');
}
