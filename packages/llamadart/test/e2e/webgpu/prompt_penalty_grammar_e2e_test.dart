/// Exact-asset prompt-penalty controls; CPU Wasm, not hardware GPU qualification.
@TestOn('browser')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show window;

void main() {
  final configUrl = Uri.base.resolve(
    '../../../build/web_lazy_grammar/config.json',
  );
  late Map<String, dynamic> config;
  late JSFunction constructor;
  Uri fixture(String key) => configUrl.resolve(config[key] as String);
  String asset(String name) => fixture('assets').resolve(name).toString();
  setUpAll(() async {
    final response = await window.fetch(configUrl.toString().toJS).toDart;
    expect(response.ok, isTrue, reason: 'Missing $configUrl');
    config =
        jsonDecode((await response.text().toDart).toDart)
            as Map<String, dynamic>;
    final module = await importModule(
      asset('llama_webgpu_bridge.js').toJS,
    ).toDart;
    constructor = module['LlamaWebGpuBridge']! as JSFunction;
  });

  for (final memory64 in [false, true]) {
    for (final worker in [false, true]) {
      final mode =
          '${memory64 ? 'wasm64' : 'wasm32'} ${worker ? 'worker' : 'direct'}';
      test('$mode seeds penalties without activating the grammar', () async {
        final backend = WebGpuLlamaBackend(
          bridgeFactory: ([_]) =>
              constructor.callAsConstructor<LlamaWebGpuBridge>(
                JSObject()
                  ..['disableWorker'] = (!worker).toJS
                  ..['preferMemory64'] = memory64.toJS
                  ..['workerUrl'] = asset('llama_webgpu_bridge_worker.js').toJS
                  ..['coreModuleUrl'] = asset('llama_webgpu_core.js').toJS
                  ..['wasmUrl'] = asset('llama_webgpu_core.wasm').toJS
                  ..['coreModuleUrlMem64'] = asset(
                    'llama_webgpu_core_mem64.js',
                  ).toJS
                  ..['wasmUrlMem64'] = asset(
                    'llama_webgpu_core_mem64.wasm',
                  ).toJS,
              ),
        );
        final engine = LlamaEngine(backend);
        try {
          await engine.loadModelFromUrl(
            fixture('model').toString(),
            modelParams: const ModelParams(
              contextSize: 512,
              gpuLayers: 0,
              preferredBackend: GpuBackend.cpu,
              numberOfThreads: 1,
            ),
          );
          final metadata = await engine.getMetadata();
          expect(
            metadata['llamadart.webgpu.execution'],
            worker ? 'worker' : 'main-thread',
          );
          expect(
            metadata['llamadart.webgpu.core_variant'],
            memory64 ? 'wasm64' : 'wasm32',
          );
          expect(metadata['llamadart.webgpu.worker_fallback_reason'], isNull);
          expect(backend.supportsPromptPenaltiesWithGrammar, isTrue);
          const base = GenerationParams(
            maxTokens: 1,
            temp: 0,
            topK: 1,
            topP: 1,
            penalty: 1,
            seed: 11,
          );
          var prompt = 'Here is a long list of animals, colors, and cities:';
          var exercised = false;
          for (var step = 0; step < 32; step++) {
            final scores = await engine.scoreNextToken(prompt, topK: 80);
            final tokens = await engine.tokenize(prompt);
            final windowTokens = tokens
                .skip(tokens.length > 64 ? tokens.length - 64 : 0)
                .toSet();
            final outside = scores.top
                .where((entry) => !windowTokens.contains(entry.token))
                .toList();
            bool clear(List<LlamaTokenLogprob> entries) =>
                entries.length < 2 ||
                entries[0].logprob - entries[1].logprob > 0.005;
            final best = scores.top.first.text;
            final other = outside.isEmpty ? '' : outside.first.text;
            if (windowTokens.contains(scores.top.first.token) &&
                clear(scores.top) &&
                clear(outside) &&
                best.isNotEmpty &&
                other.isNotEmpty &&
                best != other &&
                !best.contains('\uFFFD') &&
                !other.contains('\uFFFD')) {
              Future<String> regular(GenerationParams params) =>
                  engine.generate(prompt, params: params).join();
              Future<String> opted(GenerationParams params) => utf8.decoder
                  .bind(backend.generateWithPromptPenalties(1, prompt, params))
                  .join();
              final penalized = base.copyWith(presencePenalty: 1000);
              final expected = await regular(penalized);
              if (expected.isNotEmpty) {
                expect(await regular(base), best);
                expect(expected, other);
                for (final grammar in ['', r'root ::= [^\x00]*']) {
                  expect(
                    await regular(penalized.copyWith(grammar: grammar)),
                    best,
                  );
                  expect(
                    await opted(penalized.copyWith(grammar: grammar)),
                    expected,
                  );
                }
                expect(
                  await opted(
                    penalized.copyWith(
                      grammar:
                          'root ::= ${jsonEncode(prompt)} "__prompt_trigger_fired__"',
                      grammarLazy: true,
                      grammarTriggers: [
                        GenerationGrammarTrigger.typed(
                          type: GrammarTriggerType.word,
                          value: prompt,
                        ),
                      ],
                    ),
                  ),
                  expected,
                );
                exercised = true;
                break;
              }
            }
            prompt += best;
          }
          expect(
            exercised,
            isTrue,
            reason: 'No decisive prompt-penalty window found for $mode',
          );
        } finally {
          await engine.dispose();
        }
      });
    }
  }
}
