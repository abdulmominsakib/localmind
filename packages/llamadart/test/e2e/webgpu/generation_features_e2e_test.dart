/// Real-asset check of the capability-gated WebGPU bridge options: Min-P,
/// presence penalty, thinking budget, runtime LoRA adapters and speculative
/// decoding.
///
/// The test runner serves the package root, so the bridge, its workers and
/// the models are same-origin when they sit under `build/webgpu_features_e2e/`
/// (gitignored) with this `config.json`, whose paths are relative to it. The
/// runner does not serve symbolic links to files outside the package root, so
/// hard-link or copy them there:
///
/// ```json
/// {
///   "expectFeatures": true,
///   "bridge": "bridge/llama_webgpu_bridge.js",
///   "storiesModel": "models/stories15M_MOE-Q8_0.gguf",
///   "loraAdapter": "models/moe_shakespeare15M.gguf",
///   "aloraAdapter": "models/moe_shakespeare15M-alora.gguf",
///   "mismatchModel": "models/llama-2-tiny-random.gguf",
///   "reasoningModel": "models/Qwen3.5-0.8B-Q4_K_M.gguf",
///   "smollm2Model": "models/SmolLM2-360M-Instruct-Q8_0.gguf",
///   "smollm2Draft": "models/SmolLM2-135M-Instruct-Q8_0.gguf",
///   "smollm2NgramCache": "models/smollm2-360m-static.lcs",
///   "eagle3Model": "models/Qwen3-0.6B-Q8_0.gguf",
///   "eagle3Draft": "models/SGLang-EAGLE3-Qwen3-0.6B-SpecForge-F16.gguf",
///   "mtpModel": "models/Qwen3.5-0.8B-MTP-Q4_K_M.gguf",
///   "dflashDraft": "models/Qwen3.5-0.8B-DFlash-Moonlight556-F16.gguf",
///   "dsparkDraft": "models/Qwen3.5-0.8B-DSpark.gguf"
/// }
/// ```
///
/// `bridge` holds the bridge assets, such as a llama-web-bridge
/// `scripts/build_bridge.sh` `OUT_DIR`. The models are `ggml-org/stories15M_MOE`
/// with its `moe_shakespeare15M` adapter, the same adapter with an
/// `adapter.alora.invocation_tokens` array (llama-web-bridge
/// `scripts/lora_adapter_browser_smoke.mjs`, `withAloraInvocationTokens`),
/// `aladar/llama-2-tiny-random-GGUF` and `unsloth/Qwen3.5-0.8B-GGUF`. The
/// speculative decoding models are the files of llama-web-bridge
/// `scripts/speculative_browser_smoke.mjs` `FILES`, which pins each by
/// sha256: `mtpModel` is its `qwen3_5_0_8b_mtp`, and the EAGLE3 and DFlash
/// drafts and the n-gram cache are generated locally as its `CONTRIBUTING.md`
/// describes. Set `expectFeatures` to false for bridge assets without the
/// capabilities: every option must then be rejected, and default generation
/// still works. The speculative groups need only `smollm2Model` then.
/// The test page is not cross-origin isolated, so point `CHROME_EXECUTABLE`
/// at a wrapper that starts Chrome with
/// `--enable-features=SharedArrayBuffer,SharedArrayBufferUnrestrictedAccessAllowed`,
/// which the bridge core's threads need, then run `dart test -p chrome
/// --run-skipped -t local-only
/// test/e2e/webgpu/generation_features_e2e_test.dart`.
@TestOn('browser')
@Tags(['local-only', 'e2e'])
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show window;

const String _configPath = '../../../build/webgpu_features_e2e/config.json';

const String _storiesPrompt = 'Once upon a time';

const String _reasoningPrompt =
    '<|im_start|>user\nWhat is 8 + 9? Answer with a number.<|im_end|>\n'
    '<|im_start|>assistant\n<think>\n';

const GenerationParams _greedy = GenerationParams(
  maxTokens: 32,
  temp: 0,
  topK: 1,
  seed: 7,
);

const GenerationParams _seeded = GenerationParams(maxTokens: 32, seed: 7);

const ModelParams _cpu = ModelParams(
  contextSize: 1024,
  gpuLayers: 0,
  preferredBackend: GpuBackend.cpu,
);

const String _ngramPrompt =
    'Count: one, two, three, four, five. Again: one, two, three, four, five. '
    'Again:';

const String _draftPrompt =
    'Explain in a few sentences why the sky is blue.\n\nAnswer:';

const GenerationParams _speculativeGreedy = GenerationParams(
  maxTokens: 48,
  temp: 0,
  topK: 1,
  topP: 1,
  penalty: 1,
  seed: 42,
);

const ModelParams _speculativeCpu = ModelParams(
  contextSize: 2048,
  batchSize: 512,
  microBatchSize: 512,
  gpuLayers: 0,
  preferredBackend: GpuBackend.cpu,
);

const ModelParams _rollbackCpu = ModelParams(
  contextSize: 2048,
  batchSize: 512,
  microBatchSize: 512,
  gpuLayers: 0,
  preferredBackend: GpuBackend.cpu,
  speculativeRollbackTokenMax: 16,
);

/// Keeps the usage of the last `generate` call the engine reports.
final class _UsageRecorder extends LlamaEngineObserver {
  LlamaGenerationUsage? last;

  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) =>
      operation is LlamaTextCompletionOperation ? _UsageEnd(this) : null;
}

final class _UsageEnd extends LlamaOperationObserver {
  _UsageEnd(this.recorder);

  final _UsageRecorder recorder;

  @override
  void onEnd(LlamaOperationResult result) => recorder.last = result.usage;
}

void main() {
  final configUrl = Uri.base.resolve(_configPath);
  late Map<String, Object?> config;
  late LlamaEngine engine;
  final engineUsage = _UsageRecorder();

  bool expectFeatures() => config['expectFeatures'] == true;
  String url(String key) =>
      configUrl.resolve(config[key]! as String).toString();

  Future<String> generate(String prompt, GenerationParams params) =>
      engine.generate(prompt, params: params).join();

  void report(String name, Object? value) {
    print('[webgpu-features] $name: ${jsonEncode(value)}');
  }

  Map<String, Object?>? lastSpeculativeUsage;

  /// Records the bridge's speculative counters, which llamadart does not
  /// expose, by wrapping the `onUsage` of each `createCompletion` call, which
  /// still reports the usage to llamadart. Bridge assets before
  /// `supportsCompletionUsage` reject a function option in worker mode, so
  /// they are left alone.
  void recordSpeculativeUsage(JSObject bridgeClass) {
    if (bridgeClass['supportsCompletionUsage'] != true.toJS) return;
    final prototype = bridgeClass['prototype']! as JSObject;
    final createCompletion = prototype['createCompletion']! as JSFunction;
    prototype['createCompletion'] =
        ((JSObject self, JSAny? prompt, JSObject? options) {
          lastSpeculativeUsage = null;
          final engineOnUsage = options?['onUsage'];
          options?['onUsage'] = ((JSObject usage) {
            lastSpeculativeUsage = (usage['speculative']?.dartify() as Map?)
                ?.cast<String, Object?>();
            if (engineOnUsage.isA<JSFunction>()) {
              (engineOnUsage as JSFunction).callAsFunction(null, usage);
            }
          }).toJS;
          return createCompletion.callMethod<JSAny?>(
            'call'.toJS,
            self,
            prompt,
            options,
          );
        }).toJSCaptureThis;
  }

  setUpAll(() async {
    final response = await window.fetch(configUrl.toString().toJS).toDart;
    expect(response.ok, isTrue, reason: 'Missing $configUrl');
    config =
        jsonDecode((await response.text().toDart).toDart)
            as Map<String, Object?>;
    final bridgeModule = await importModule(url('bridge').toJS).toDart;
    globalContext['LlamaWebGpuBridge'] = bridgeModule['LlamaWebGpuBridge'];
    recordSpeculativeUsage(bridgeModule['LlamaWebGpuBridge']! as JSObject);
    engine = LlamaEngine(WebGpuLlamaBackend(), observers: [engineUsage]);
  });

  tearDownAll(() => engine.dispose());

  group('stories15M', () {
    setUpAll(
      () => engine.loadModelFromUrl(url('storiesModel'), modelParams: _cpu),
    );
    tearDownAll(() => engine.unloadModel());

    test('reports the probed generation capabilities', () async {
      final capabilities = await engine.backendGenerationCapabilities;
      expect(capabilities.presencePenalty, expectFeatures());
      expect(capabilities.minP, expectFeatures());
      expect(capabilities.thinkingBudget, expectFeatures());
    });

    test('default generation is deterministic', () async {
      final greedy = await generate(_storiesPrompt, _greedy);
      final seeded = await generate(_storiesPrompt, _seeded);
      report('greedy', greedy);
      report('seeded', seeded);
      expect(greedy, isNotEmpty);
      expect(await generate(_storiesPrompt, _greedy), greedy);
      expect(await generate(_storiesPrompt, _seeded), seeded);
      expect(
        await generate(
          _storiesPrompt,
          _seeded.copyWith(minP: 0, presencePenalty: 0),
        ),
        seeded,
      );
    });

    test('Min-P', () async {
      final seeded = await generate(_storiesPrompt, _seeded);
      if (!expectFeatures()) {
        await expectLater(
          generate(_storiesPrompt, _seeded.copyWith(minP: 0.3)),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        return;
      }
      final minP = await generate(_storiesPrompt, _seeded.copyWith(minP: 0.3));
      final minPOne = await generate(_storiesPrompt, _seeded.copyWith(minP: 1));
      report('seeded minP 0.3', minP);
      report('seeded minP 1', minPOne);
      expect(minP, isNot(seeded));
      expect(minPOne, await generate(_storiesPrompt, _greedy));
    });

    test('presence penalty', () async {
      if (!expectFeatures()) {
        await expectLater(
          generate(_storiesPrompt, _greedy.copyWith(presencePenalty: 1.5)),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        return;
      }
      final greedy = await generate(_storiesPrompt, _greedy);
      final penalized = await generate(
        _storiesPrompt,
        _greedy.copyWith(presencePenalty: 1.5),
      );
      report('greedy presencePenalty 1.5', penalized);
      expect(penalized, isNot(greedy));
    });

    test('a stop sequence equal to a preserved token does not stop', () async {
      final greedy = await generate(_storiesPrompt, _greedy);
      expect(greedy, contains('.'));
      final stopped = await generate(
        _storiesPrompt,
        _greedy.copyWith(stopSequences: <String>['.']),
      );
      final preserved = await generate(
        _storiesPrompt,
        _greedy.copyWith(
          stopSequences: <String>['.'],
          preservedTokens: <String>['.'],
        ),
      );
      report('greedy stop "."', stopped);
      report('greedy stop "." preserved "."', preserved);
      expect(stopped, greedy.substring(0, greedy.indexOf('.')));
      expect(preserved, greedy);
    });

    test('LoRA adapters', () async {
      if (!expectFeatures()) {
        for (final call in <Future<void> Function()>[
          () => engine.setLora(url('loraAdapter')),
          () => engine.removeLora(url('loraAdapter')),
          engine.clearLoras,
        ]) {
          await expectLater(call(), throwsA(isA<LlamaUnsupportedException>()));
        }
        return;
      }
      final base = await generate(_storiesPrompt, _greedy);

      await engine.setLora(url('loraAdapter'));
      final adapted = await generate(_storiesPrompt, _greedy);
      report('greedy with adapter', adapted);
      expect(adapted, isNot(base));

      await engine.setLora(url('loraAdapter'), scale: 0);
      expect(await generate(_storiesPrompt, _greedy), base);
      await engine.setLora(url('loraAdapter'), scale: 1);
      expect(await generate(_storiesPrompt, _greedy), adapted);

      await engine.clearLoras();
      expect(await generate(_storiesPrompt, _greedy), base);

      await engine.setLora(url('loraAdapter'));
      await engine.removeLora(url('loraAdapter'));
      expect(await generate(_storiesPrompt, _greedy), base);

      await expectLater(
        engine.setLora(url('aloraAdapter')),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('aLoRA adapter'),
          ),
        ),
      );
      expect(await generate(_storiesPrompt, _greedy), base);
    });

    test('LoRA adapter for another base model', () async {
      if (!expectFeatures()) return;
      await engine.unloadModel();
      await engine.loadModelFromUrl(url('mismatchModel'), modelParams: _cpu);
      await expectLater(
        engine.setLora(url('loraAdapter')),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('wrong base model'),
          ),
        ),
      );
      expect(await generate(_storiesPrompt, _greedy), isNotEmpty);
      await engine.unloadModel();
      await engine.loadModelFromUrl(url('storiesModel'), modelParams: _cpu);
    });
  });

  group('Qwen3.5 thinking budget', () {
    setUpAll(
      () => engine.loadModelFromUrl(url('reasoningModel'), modelParams: _cpu),
    );

    const params = GenerationParams(maxTokens: 24, temp: 0, topK: 1, seed: 7);

    test('caps thinking and forces the end tag', () async {
      final unbudgeted = await generate(_reasoningPrompt, params);
      report('unbudgeted', unbudgeted);
      const budget = ThinkingBudget(
        maxTokens: 8,
        startTag: '<think>',
        endTag: '</think>',
      );
      if (!expectFeatures()) {
        await expectLater(
          generate(_reasoningPrompt, params.copyWith(thinkingBudget: budget)),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        return;
      }
      expect(unbudgeted, isNot(contains('</think>')));

      final budgeted = await generate(
        _reasoningPrompt,
        params.copyWith(thinkingBudget: budget),
      );
      final forced = await generate(
        _reasoningPrompt,
        params.copyWith(
          thinkingBudget: const ThinkingBudget(
            maxTokens: 0,
            startTag: '<think>',
            endTag: '</think>',
            forcedMessage: 'Done.',
          ),
        ),
      );
      report('maxTokens 8', budgeted);
      report('maxTokens 0 forcedMessage Done.', forced);

      final end = budgeted.indexOf('</think>');
      expect(end, greaterThan(0));
      expect(unbudgeted, startsWith(budgeted.substring(0, end)));
      expect(forced, startsWith('Done.</think>'));
    });
  });

  /// Checks that each config gives the loaded model's greedy output of
  /// [prompt] without speculative decoding.
  ///
  /// [drafts] lists the configs whose drafts the target must accept. Returns
  /// the bridge's speculative counters by config.
  Future<Map<String, Map<String, Object?>?>> expectTokenIdentical(
    String prompt,
    Map<String, SpeculativeDecodingConfig> configs, {
    Set<String> drafts = const <String>{},
  }) async {
    final baseline = await generate(prompt, _speculativeGreedy);
    report('speculative baseline', baseline);
    expect(lastSpeculativeUsage, isNull);
    expect(baseline, isNotEmpty);
    final usages = <String, Map<String, Object?>?>{};
    for (final MapEntry(key: name, value: config) in configs.entries) {
      final output = await generate(
        prompt,
        _speculativeGreedy.copyWith(speculativeDecodingConfig: config),
      );
      final usage = usages[name] = lastSpeculativeUsage;
      report('speculative $name', <String, Object?>{
        'identical': output == baseline,
        'usage': usage,
      });
      expect(output, baseline, reason: name);
      expect(usage?['draftAttempts'], greaterThan(0), reason: name);
      expect(engineUsage.last?.completionTokens, greaterThan(0), reason: name);
      if (drafts.contains(name)) {
        expect(usage?['acceptedDraftTokens'], greaterThan(0), reason: name);
      }
    }
    expect(await generate(prompt, _speculativeGreedy), baseline);
    return usages;
  }

  Future<void> load(String key, ModelParams params) async {
    await engine.unloadModel();
    await engine.loadModelFromUrl(url(key), modelParams: params);
  }

  group('speculative decoding, SmolLM2-360M', () {
    setUpAll(() => load('smollm2Model', _speculativeCpu));
    tearDownAll(() => engine.unloadModel());

    test('reports the probed strategies', () async {
      final strategies = (await engine.backendGenerationCapabilities)
          .speculativeDecodingStrategies;
      report('strategies', strategies.map((s) => s.name).toList()..sort());
      expect(
        strategies,
        expectFeatures()
            ? SpeculativeDecodingStrategy.values.toSet().difference(
                <SpeculativeDecodingStrategy>{SpeculativeDecodingStrategy.mtp},
              )
            : isEmpty,
      );
    });

    test('rejects every strategy on assets without it', () async {
      if (expectFeatures()) return;
      final greedy = await generate(_ngramPrompt, _speculativeGreedy);
      for (final strategy in SpeculativeDecodingStrategy.values) {
        await expectLater(
          generate(
            _ngramPrompt,
            _speculativeGreedy.copyWith(
              speculativeDecodingConfig: SpeculativeDecodingConfig.mixed(
                strategies: <SpeculativeDecodingStrategy>[strategy],
                draftModelPath: 'draft.gguf',
              ),
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
          reason: '$strategy',
        );
      }
      await expectLater(
        generate(
          _ngramPrompt,
          _speculativeGreedy.copyWith(speculativeDecoding: true),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(await generate(_ngramPrompt, _speculativeGreedy), greedy);
    });

    test('n-gram strategies match greedy output', () async {
      if (!expectFeatures()) return;
      await expectTokenIdentical(
        _ngramPrompt,
        <String, SpeculativeDecodingConfig>{
          'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: 3,
            ngramSizeM: 8,
          ),
          'ngram-map-k': const SpeculativeDecodingConfig.ngramMapK(
            ngramSizeN: 3,
            ngramSizeM: 8,
          ),
          'ngram-map-k4v': const SpeculativeDecodingConfig.ngramMapK4v(
            ngramSizeN: 3,
            ngramSizeM: 8,
          ),
          'ngram-mod': const SpeculativeDecodingConfig.ngramMod(
            ngramMatch: 3,
            ngramTokenMin: 1,
            ngramTokenMax: 16,
          ),
          'ngram-cache': SpeculativeDecodingConfig.ngramCache(
            ngramCacheStaticPath: url('smollm2NgramCache'),
          ),
          'backendDefault': const SpeculativeDecodingConfig.backendDefault(),
        },
        drafts: const <String>{
          'ngram-simple',
          'ngram-map-k',
          'ngram-map-k4v',
          'ngram-mod',
          'ngram-cache',
        },
      );
    });

    test('draft-simple matches greedy output', () async {
      if (!expectFeatures()) return;
      await expectTokenIdentical(
        _draftPrompt,
        <String, SpeculativeDecodingConfig>{
          'draft-simple': SpeculativeDecodingConfig.draftSimple(
            draftModelPath: url('smollm2Draft'),
          ),
          'ngram-mod+draft-simple': SpeculativeDecodingConfig.mixed(
            strategies: const <SpeculativeDecodingStrategy>[
              SpeculativeDecodingStrategy.ngramMod,
              SpeculativeDecodingStrategy.draftSimple,
            ],
            draftModelPath: url('smollm2Draft'),
            ngramMatch: 3,
            ngramTokenMin: 1,
            ngramTokenMax: 16,
          ),
        },
        drafts: const <String>{'draft-simple', 'ngram-mod+draft-simple'},
      );
    });

    test('rejects draft-mtp without MTP layers', () async {
      if (!expectFeatures()) return;
      await expectLater(
        generate(
          _draftPrompt,
          _speculativeGreedy.copyWith(
            speculativeDecodingConfig: const SpeculativeDecodingConfig.mtp(),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });

    test('rejects an EAGLE3 draft for another hidden size', () async {
      if (!expectFeatures()) return;
      await expectLater(
        generate(
          _draftPrompt,
          _speculativeGreedy.copyWith(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftEagle3(
              draftModelPath: url('eagle3Draft'),
            ),
          ),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('hidden states'),
          ),
        ),
      );
    });
  });

  group('speculative decoding, Qwen3-0.6B EAGLE3', () {
    setUpAll(() async {
      if (expectFeatures()) await load('eagle3Model', _speculativeCpu);
    });
    tearDownAll(() => engine.unloadModel());

    test('draft-eagle3 matches greedy output', () async {
      if (!expectFeatures()) return;
      await expectTokenIdentical(
        _draftPrompt,
        <String, SpeculativeDecodingConfig>{
          'draft-eagle3': SpeculativeDecodingConfig.draftEagle3(
            draftModelPath: url('eagle3Draft'),
          ),
        },
        drafts: const <String>{'draft-eagle3'},
      );
      await expectLater(
        generate(
          _draftPrompt,
          _speculativeGreedy.copyWith(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
              draftModelPath: url('eagle3Draft'),
            ),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });

  group('speculative decoding, Qwen3.5-0.8B MTP', () {
    setUpAll(() async {
      if (!expectFeatures()) return;
      await load('mtpModel', _rollbackCpu.copyWith(loadMtp: true));
    });
    tearDownAll(() => engine.unloadModel());

    test('draft-mtp matches greedy output', () async {
      if (!expectFeatures()) return;
      expect(
        (await engine.backendGenerationCapabilities)
            .speculativeDecodingStrategies,
        contains(SpeculativeDecodingStrategy.mtp),
      );
      await expectTokenIdentical(
        _draftPrompt,
        <String, SpeculativeDecodingConfig>{
          'draft-mtp': const SpeculativeDecodingConfig.mtp(),
        },
        drafts: const <String>{'draft-mtp'},
      );
    });
  });

  group('speculative decoding, Qwen3.5-0.8B block drafts', () {
    setUpAll(() async {
      if (expectFeatures()) await load('reasoningModel', _rollbackCpu);
    });
    tearDownAll(() => engine.unloadModel());

    test('draft-dflash and draft-dspark match greedy output', () async {
      if (!expectFeatures()) return;
      await expectTokenIdentical(
        _draftPrompt,
        <String, SpeculativeDecodingConfig>{
          'draft-dflash': SpeculativeDecodingConfig.draftDflash(
            draftModelPath: url('dflashDraft'),
          ),
          'draft-dspark': SpeculativeDecodingConfig.draftDspark(
            draftTokenMax: 7,
            draftModelPath: url('dsparkDraft'),
          ),
        },
        drafts: const <String>{'draft-dflash', 'draft-dspark'},
      );
      await expectLater(
        generate(
          _draftPrompt,
          _speculativeGreedy.copyWith(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDflash(
              draftModelPath: url('dsparkDraft'),
            ),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });

  group('speculative decoding, Qwen3.5-0.8B without rollback', () {
    setUpAll(() async {
      if (expectFeatures()) await load('reasoningModel', _speculativeCpu);
    });
    tearDownAll(() => engine.unloadModel());

    test('n-gram decoding replays a recurrent model', () async {
      if (!expectFeatures()) return;
      final usages = await expectTokenIdentical(
        _ngramPrompt,
        <String, SpeculativeDecodingConfig>{
          'ngram-simple': const SpeculativeDecodingConfig.ngramSimple(
            ngramSizeN: 3,
            ngramSizeM: 8,
          ),
        },
        drafts: const <String>{'ngram-simple'},
      );
      expect(usages['ngram-simple']?['replayTokens'], greaterThan(0));
      await expectLater(
        generate(
          _draftPrompt,
          _speculativeGreedy.copyWith(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftDflash(
              draftModelPath: url('dflashDraft'),
            ),
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  });
}
