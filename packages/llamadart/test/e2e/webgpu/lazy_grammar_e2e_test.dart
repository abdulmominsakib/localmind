/// Real pinned-asset lazy-grammar checks in direct and worker CPU Wasm runtimes.
///
/// Stage build/web_lazy_grammar/config.json with {"assets":"bridge/",
/// "model":"models/stories15M.gguf"}. Copy or hard-link the pinned bridge
/// files and existing model there, then run the web-lazy-grammar scenario.
/// These controls qualify transport/activation, not tool accuracy or WebGPU.
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

const _greedy = GenerationParams(
  maxTokens: 48,
  temp: 0,
  topK: 1,
  topP: 1,
  penalty: 1,
  seed: 7,
);

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

  for (final worker in [false, true]) {
    final mode = worker ? 'worker' : 'direct';
    group(mode, () {
      late LlamaEngine engine;
      late LlamaWebGpuBridge bridge;
      late String before;
      late String word;
      late String through;
      late int throughTokens;
      String grammar() => 'root ::= ${jsonEncode(word)} ("x" | "y")';
      Future<String> run(GenerationParams params) =>
          engine.generate('Once upon a time', params: params).join();

      Future<void> expectRuntime() async {
        final metadata = await engine.getMetadata();
        expect(
          metadata['llamadart.webgpu.execution'],
          worker ? 'worker' : 'main-thread',
        );
        expect(metadata['llamadart.webgpu.worker_fallback_reason'], isNull);
      }

      setUpAll(() async {
        engine = LlamaEngine(
          WebGpuLlamaBackend(
            bridgeFactory: ([_]) {
              bridge = constructor.callAsConstructor<LlamaWebGpuBridge>(
                JSObject()
                  ..['disableWorker'] = (!worker).toJS
                  ..['workerUrl'] = asset('llama_webgpu_bridge_worker.js').toJS
                  ..['coreModuleUrl'] = asset('llama_webgpu_core.js').toJS
                  ..['wasmUrl'] = asset('llama_webgpu_core.wasm').toJS,
              );
              return bridge;
            },
          ),
        );
        await engine.loadModelFromUrl(
          fixture('model').toString(),
          modelParams: const ModelParams(
            contextSize: 512,
            gpuLayers: 0,
            preferredBackend: GpuBackend.cpu,
            numberOfThreads: 1,
          ),
        );
        expect((await engine.capabilities).supportsLazyGrammar, isTrue);
        var found = false;
        for (var count = 3; count <= 12; count++) {
          before = await run(_greedy.copyWith(maxTokens: count));
          through = await run(_greedy.copyWith(maxTokens: count + 2));
          if (!through.startsWith(before)) continue;
          word = through.substring(before.length);
          if (word.isNotEmpty &&
              through.indexOf(word) == before.length &&
              !through.contains('\uFFFD')) {
            throughTokens = count + 2;
            found = true;
            break;
          }
        }
        expect(
          found,
          isTrue,
          reason: 'Need a new, visible two-token trigger window.',
        );
        print(
          '[$mode lazy] before=${jsonEncode(before)} trigger=${jsonEncode(word)}',
        );
        await expectRuntime();
      });
      tearDownAll(() => engine.dispose());

      for (final type in [
        GrammarTriggerType.word,
        GrammarTriggerType.pattern,
        GrammarTriggerType.patternFull,
      ]) {
        test(
          '${type.name} activates after visible unconstrained text',
          () async {
            final literal = RegExp.escape(word);
            final value = switch (type) {
              GrammarTriggerType.word => word,
              GrammarTriggerType.pattern => literal,
              _ => '[\\s\\S]*?($literal)',
            };
            final output = await run(
              _greedy.copyWith(
                grammar: grammar(),
                grammarLazy: true,
                grammarTriggers: [
                  GenerationGrammarTrigger.typed(type: type, value: value),
                ],
              ),
            );
            expect(output, anyOf('$before${word}x', '$before${word}y'));
            final strict = await run(_greedy.copyWith(grammar: grammar()));
            expect(strict, anyOf('${word}x', '${word}y'));
            await expectRuntime();
          },
        );
      }

      test('token trigger and numeric-token compatibility activate', () async {
        final scores = await engine.scoreNextToken('Once upon a time', topK: 2);
        final first = scores.top.first;
        final tokenGrammar = 'root ::= ${jsonEncode(first.text)} ("x" | "y")';
        expect(first.text, isNotEmpty);
        final output = await run(
          _greedy.copyWith(
            grammar: tokenGrammar,
            grammarLazy: true,
            grammarTriggers: [
              GenerationGrammarTrigger.typed(
                type: GrammarTriggerType.token,
                value: '${first.token}',
              ),
            ],
          ),
        );
        expect(output, anyOf('${first.text}x', '${first.text}y'));
        await expectRuntime();
      });

      test(
        'custom root, argument and grammar errors leave the runtime usable',
        () async {
          expect(
            await run(
              _greedy.copyWith(
                grammar: 'root ::= "wrong"\nanswer ::= "x"',
                grammarRoot: 'answer',
              ),
            ),
            'x',
          );
          await expectLater(
            run(_greedy.copyWith(grammar: grammar(), grammarLazy: true)),
            throwsA(isA<LlamaArgumentException>()),
          );
          await expectLater(
            run(
              _greedy.copyWith(grammar: 'root ::= "x"', grammarRoot: 'missing'),
            ),
            throwsA(isA<LlamaInferenceException>()),
          );
          await expectLater(
            run(
              _greedy.copyWith(
                grammar: 'root ::= "x"',
                grammarLazy: true,
                grammarTriggers: [
                  GenerationGrammarTrigger.typed(
                    type: GrammarTriggerType.word,
                    value: word,
                  ),
                ],
              ),
            ),
            throwsA(
              isA<LlamaInferenceException>().having(
                (error) => error.toString(),
                'replay rejection',
                contains('lazy grammar rejected'),
              ),
            ),
          );
          expect(
            await run(_greedy.copyWith(maxTokens: throughTokens)),
            through,
          );
          await expectRuntime();
        },
      );
    });
  }
}
