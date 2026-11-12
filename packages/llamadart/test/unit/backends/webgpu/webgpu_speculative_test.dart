@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_speculative.dart';
import 'package:test/test.dart';

import '../../../support/fake_webgpu_feature_bridge.dart';

void main() {
  group('webGpuSpeculativeStrategiesFrom', () {
    JSObject flags(Map<String, Object?> values) {
      final object = JSObject();
      for (final MapEntry(:key, :value) in values.entries) {
        object.setProperty(key.toJS, value.jsify());
      }
      return object;
    }

    test('names every strategy but backendDefault as llama.cpp does', () {
      expect(
        webGpuSpeculativeStrategyNames.keys.toSet(),
        SpeculativeDecodingStrategy.values.toSet()
          ..remove(SpeculativeDecodingStrategy.backendDefault),
      );
      expect(
        webGpuSpeculativeStrategyNames.values.toSet(),
        fakeSpeculativeStrategies.toSet(),
      );
    });

    test('reports nothing for a missing or malformed probe', () {
      for (final value in <JSAny?>[
        null,
        true.toJS,
        'ngram-mod'.toJS,
        flags(<String, Object?>{'ngram-mod': 'true', 'ngram-simple': 1}),
      ]) {
        expect(
          webGpuSpeculativeStrategiesFrom(value, hasDraftModelApi: true),
          isEmpty,
        );
      }
    });

    test('needs a reported n-gram strategy before any other', () {
      expect(
        webGpuSpeculativeStrategiesFrom(
          flags(<String, Object?>{
            'draft-mtp': true,
            'draft-simple': true,
            'ngram-mod': false,
          }),
          hasDraftModelApi: true,
        ),
        isEmpty,
      );
    });

    test('counts a draft strategy reported as a flag', () {
      expect(
        webGpuSpeculativeStrategiesFrom(
          flags(<String, Object?>{
            'ngram-cache': true,
            'draft-mtp': false,
            'draft-simple': false,
            'draft-eagle3': true,
            'draft-dflash': 'false',
          }),
          hasDraftModelApi: true,
        ),
        <SpeculativeDecodingStrategy>{
          SpeculativeDecodingStrategy.ngramCache,
          SpeculativeDecodingStrategy.draftSimple,
          SpeculativeDecodingStrategy.draftEagle3,
        },
      );
    });
  });

  group('resolveWebGpuSpeculativeRequest', () {
    WebGpuSpeculativeRequest? resolve(SpeculativeDecodingConfig config) =>
        resolveWebGpuSpeculativeRequest(
          GenerationParams(speculativeDecodingConfig: config),
          hasMediaParts: false,
        );

    test('returns null without speculative decoding', () {
      expect(
        resolveWebGpuSpeculativeRequest(
          const GenerationParams(),
          hasMediaParts: true,
        ),
        isNull,
      );
    });

    test('bounds draftTokenMin by the native draft maximum', () {
      expect(
        () => resolve(
          const SpeculativeDecodingConfig.draftSimple(
            draftTokenMin: 4,
            draftModelPath: 'draft.gguf',
          ),
        ),
        throwsA(isA<RangeError>()),
      );
      final mixed = resolve(
        const SpeculativeDecodingConfig.mixed(
          strategies: <SpeculativeDecodingStrategy>[
            SpeculativeDecodingStrategy.ngramMod,
            SpeculativeDecodingStrategy.draftSimple,
          ],
          draftTokenMin: 64,
          draftModelPath: 'draft.gguf',
        ),
      )!;
      expect((mixed.options.dartify()! as Map)['draftTokenMin'], 64);
      expect(mixed.draftStrategy, SpeculativeDecodingStrategy.draftSimple);
      expect(mixed.draftModelUrl, 'draft.gguf');
    });

    test('rejects a draft micro-batch size the bridge cannot apply', () {
      expect(
        () => resolve(
          const SpeculativeDecodingConfig.mtp(draftMicroBatchSize: 8),
        ),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('draftMicroBatchSize'),
          ),
        ),
      );
    });

    test('names the draft and cache URLs for redaction', () {
      final request = resolve(
        const SpeculativeDecodingConfig.mixed(
          strategies: <SpeculativeDecodingStrategy>[
            SpeculativeDecodingStrategy.ngramCache,
            SpeculativeDecodingStrategy.draftEagle3,
          ],
          draftModelPath: 'eagle3.gguf',
          ngramCacheStaticPath: 'static.lcs',
          ngramCacheDynamicPath: 'dynamic.lcs',
        ),
      )!;
      expect(request.sourceUrls, <String>[
        'eagle3.gguf',
        'static.lcs',
        'dynamic.lcs',
      ]);
      expect(
        resolve(const SpeculativeDecodingConfig.mtp())!.sourceUrls,
        isEmpty,
      );
    });
  });

  group('webGpuSpeculativeCompletionError', () {
    test('passes a LlamaException through', () {
      final error = LlamaStateException('busy');
      expect(webGpuSpeculativeCompletionError(error, const <String>[]), error);
    });
  });

  group('WebGpuDraftModel', () {
    test('rejects a draft when the probe fails after the load', () async {
      final fake = FakeFeatureBridge();
      await fake.bridge.loadModelFromUrl('model.gguf')!.toDart;
      final draft = WebGpuDraftModel();
      fake.completionProbeError = 'Bridge has been disposed.';

      await expectLater(
        draft.prepare(
          fake.bridge,
          'draft.gguf',
          SpeculativeDecodingStrategy.draftSimple,
        ),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(fake.calls, <String>[
        'load',
        'draft:load',
        'probe',
        'draft:unload',
      ]);
    });
  });
}
