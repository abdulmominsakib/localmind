@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

import '../../../support/fake_webgpu_feature_bridge.dart';

@JS('Error')
external JSObject _jsError(String message);

@JS('Promise.reject')
external JSPromise<JSAny?> _rejectPromise(JSAny? error);

void main() {
  late FakeFeatureBridge fake;
  late WebGpuLlamaBackend backend;
  late LlamaEngine engine;

  setUp(() {
    fake = FakeFeatureBridge()..completionCapabilities = {'lazyGrammar': true};
    backend = WebGpuLlamaBackend(bridgeFactory: ([_]) => fake.bridge);
    engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
  });

  Future<void> load() =>
      engine.loadModelFromUrl('https://example.com/tiny.gguf');
  Future<void> generate(GenerationParams params) =>
      engine.generate('Once', params: params).drain<void>();
  const lazy = GenerationParams(
    grammar: 'start ::= "a"',
    grammarRoot: 'start',
    grammarLazy: true,
    grammarTriggers: [
      GenerationGrammarTrigger.typed(type: GrammarTriggerType.word, value: 'a'),
    ],
  );

  test(
    'reports support only after a successful strict probe and clears it',
    () async {
      expect(backend.supportsLazyGrammar, isFalse);
      await load();
      expect((await engine.capabilities).supportsLazyGrammar, isTrue);
      await generate(lazy);
      expect(fake.completionOption('grammar'), lazy.grammar);
      expect(fake.completionOption('grammarLazy'), isTrue);
      expect(fake.completionOption('grammarRoot'), 'start');
      expect(fake.calls.where((call) => call == 'probe'), hasLength(1));
      await engine.unloadModel();
      expect(backend.supportsLazyGrammar, isFalse);
      fake.completionCapabilities = {};
      await load();
      expect((await engine.capabilities).supportsLazyGrammar, isFalse);
      await expectLater(
        generate(lazy),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );

  test(
    'maps trigger names explicitly and accepts numeric token values',
    () async {
      await load();
      await generate(
        lazy.copyWith(
          grammarTriggers: const [
            GenerationGrammarTrigger(type: 0, value: 'a.b'),
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.token,
              value: 'ignored',
              token: 42,
            ),
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.token,
              value: '43',
            ),
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.pattern,
              value: r'a+',
            ),
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.patternFull,
              value: r'a+',
            ),
            GenerationGrammarTrigger.typed(
              type: GrammarTriggerType.patternFull,
              value: '',
            ),
          ],
        ),
      );
      final triggers = fake.completionOption('grammarTriggers') as List;
      expect(triggers, [
        {'type': 'word', 'value': 'a.b'},
        {'type': 'token', 'token': 42},
        {'type': 'token', 'token': 43},
        {'type': 'pattern', 'value': 'a+'},
        {'type': 'pattern-full', 'value': 'a+'},
        {'type': 'pattern-full', 'value': r'^$'},
      ]);
    },
  );

  test(
    'rejects invalid token ids and unknown trigger types before dispatch',
    () async {
      await load();
      for (final trigger in const [
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: 'no-id',
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: '',
          token: -1,
        ),
        GenerationGrammarTrigger.typed(
          type: GrammarTriggerType.token,
          value: '',
          token: 0x80000000,
        ),
      ]) {
        await expectLater(
          generate(lazy.copyWith(grammarTriggers: [trigger])),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      await expectLater(
        generate(
          lazy.copyWith(
            grammarTriggers: const [
              GenerationGrammarTrigger(type: 7, value: 'a'),
            ],
          ),
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(fake.completionCalls, 0);
    },
  );

  test(
    'custom eager root uses the same capability without lazy triggers',
    () async {
      await load();
      await generate(lazy.copyWith(grammarLazy: false));
      expect(fake.completionOption('grammarRoot'), 'start');
      expect(fake.completionOption('grammarLazy'), isFalse);
      expect(fake.completionOption('grammarTriggers'), isNull);
    },
  );

  test(
    'missing, failed and malformed probes reject before bridge dispatch',
    () async {
      final cases = <FakeFeatureBridge>[
        FakeFeatureBridge(withCompletionProbe: false),
        FakeFeatureBridge()..completionProbeError = 'probe failed',
        FakeFeatureBridge()..completionCapabilitiesResult = 'true'.toJS,
        for (final flag in <JSAny?>[null, false.toJS, 'true'.toJS, 1.toJS])
          FakeFeatureBridge()
            ..completionCapabilitiesResult = (JSObject()
              ..setProperty('lazyGrammar'.toJS, flag)),
      ];
      for (final candidate in cases) {
        fake = candidate;
        await load();
        expect(backend.supportsLazyGrammar, isFalse);
        for (final params in [lazy, lazy.copyWith(grammarLazy: false)]) {
          await expectLater(
            generate(params),
            throwsA(
              isA<LlamaUnsupportedException>().having(
                (error) => error.message,
                'capability',
                contains('lazyGrammar'),
              ),
            ),
          );
        }
        expect(fake.completionCalls, 0);
        await generate(const GenerationParams(grammar: 'root ::= "a"'));
        expect(fake.completionOption('grammarLazy'), isNull);
        expect(fake.completionOption('grammarRoot'), isNull);
        await engine.unloadModel();
      }
    },
  );

  test('capability loss after probe remains a typed unsupported error', () async {
    await load();
    fake.object.setProperty(
      'createCompletion'.toJS,
      ((JSAny? _, JSAny? _) => _rejectPromise(
        _jsError(
          'The loaded WebGPU core does not support CompletionOptions.grammarLazy or CompletionOptions.grammarRoot.',
        ),
      )).toJS,
    );
    await expectLater(
      generate(lazy),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
}
