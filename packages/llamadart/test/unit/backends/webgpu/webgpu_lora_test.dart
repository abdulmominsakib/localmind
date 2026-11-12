@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_lora.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show document;

import '../../../support/fake_webgpu_feature_bridge.dart';

void main() {
  late FakeFeatureBridge fake;
  late WebGpuLoraAdapters adapters;

  Future<void> loadModel() async {
    await fake.bridge.loadModelFromUrl('model.gguf')!.toDart;
  }

  setUp(() async {
    fake = FakeFeatureBridge();
    adapters = WebGpuLoraAdapters();
    await loadModel();
    fake.calls.clear();
  });

  Matcher unsupported(Object reason) => throwsA(
    isA<UnsupportedError>().having(
      (error) => '${error.message}',
      'message',
      allOf(
        contains('WebGPU LoRA adapters need bridge assets'),
        contains('native llama.cpp'),
        contains(reason),
      ),
    ),
  );

  Future<void> expectEveryCall(FakeFeatureBridge? bridge, Object reason) async {
    final target = bridge?.bridge;
    await expectLater(
      adapters.set(target, 'adapter.gguf', 0.5),
      unsupported(reason),
    );
    await expectLater(
      adapters.remove(target, 'adapter.gguf'),
      unsupported(reason),
    );
    await expectLater(adapters.clear(target), unsupported(reason));
  }

  group('support probe', () {
    test('rejects every call without a bridge', () async {
      await expectEveryCall(null, 'no model is loaded');
      expect(fake.calls, isEmpty);
    });

    test('rejects every call on bridge assets without the LoRA API', () async {
      fake = FakeFeatureBridge(withLoraApi: false);
      await loadModel();
      await expectEveryCall(fake, 'lack the LoRA methods');
      expect(fake.loraLoads, isEmpty);
    });

    test('rejects bridge assets missing one LoRA method', () async {
      fake.object.delete('clearLoraAdapters'.toJS);
      await expectEveryCall(fake, 'lack the LoRA methods');
      expect(fake.calls, isEmpty);
    });

    test('rejects with the reason of an unsupported probe', () async {
      fake.loraCapabilitiesResult = JSObject()
        ..setProperty('apiVersion'.toJS, 1.toJS)
        ..setProperty('supported'.toJS, false.toJS)
        ..setProperty(
          'reason'.toJS,
          'This WebGPU core build does not include LoRA adapters.'.toJS,
        );
      await expectEveryCall(
        fake,
        'This WebGPU core build does not include LoRA adapters.',
      );
      expect(fake.calls, everyElement('lora:probe'));
    });

    test('rejects before a model load, as the bridge reports', () async {
      fake = FakeFeatureBridge();
      await expectEveryCall(fake, 'WebGPU core is not initialized');
      expect(fake.loraLoads, isEmpty);
    });

    test('rejects another LoRA API version', () async {
      fake.loraApiVersion = 2;
      await expectEveryCall(fake, 'LoRA API version 2, not 1');
    });

    test('rejects a malformed or failed probe', () async {
      fake.loraCapabilitiesResult = 'yes'.toJS;
      await expectEveryCall(fake, 'the probe response is invalid');

      fake.loraCapabilitiesResult = JSObject()
        ..setProperty('apiVersion'.toJS, 1.toJS)
        ..setProperty('supported'.toJS, 'true'.toJS);
      await expectEveryCall(fake, 'the bridge reports it unsupported');

      fake.loraCapabilitiesResult = null;
      fake.loraProbeError = 'Bridge has been disposed.';
      await expectEveryCall(
        fake,
        'the probe failed: Bridge has been disposed.',
      );
      expect(fake.loraLoads, isEmpty);
    });
  });

  group('supported bridge', () {
    test('loads a path once and applies it at each scale', () async {
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      await adapters.set(fake.bridge, 'adapter.gguf', 0.25);
      await adapters.set(fake.bridge, 'other.gguf', 1.5);

      expect(fake.calls, <String>[
        'lora:probe',
        'lora:load',
        'lora:set 7 0.5',
        'lora:probe',
        'lora:set 7 0.25',
        'lora:probe',
        'lora:load',
        'lora:set 8 1.5',
      ]);
      expect(fake.appliedAdapters, <int, double>{7: 0.25, 8: 1.5});
      expect(fake.loraLoads.map((load) => load.source), <String>[
        '${Uri.parse(document.baseURI).resolve('adapter.gguf')}',
        '${Uri.parse(document.baseURI).resolve('other.gguf')}',
      ]);
    });

    test('loads concurrent sets of one path once', () async {
      await Future.wait(<Future<void>>[
        adapters.set(fake.bridge, 'adapter.gguf', 0.5),
        adapters.set(fake.bridge, 'adapter.gguf', 0.75),
      ]);

      expect(fake.loraLoads, hasLength(1));
      expect(fake.appliedAdapters, <int, double>{7: 0.75});
    });

    test('caches only URLs without credentials', () async {
      await adapters.set(fake.bridge, 'https://example.com/a.gguf', 1);
      await adapters.set(
        fake.bridge,
        'https://example.com/b.gguf?X-Amz-Signature=secret',
        1,
      );

      expect(fake.loraLoads.map((load) => load.useCache), <bool?>[true, false]);
    });

    test('removes a set path and ignores other paths', () async {
      await adapters.remove(fake.bridge, 'adapter.gguf');
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      await adapters.remove(fake.bridge, 'adapter.gguf');

      expect(fake.calls, <String>[
        'lora:probe',
        'lora:probe',
        'lora:load',
        'lora:set 7 0.5',
        'lora:probe',
        'lora:remove 7',
      ]);
      expect(fake.appliedAdapters, isEmpty);

      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      expect(fake.loraLoads, hasLength(1), reason: 'removal keeps it loaded');
    });

    test('clears every adapter and keeps them loaded', () async {
      await adapters.set(fake.bridge, 'a.gguf', 0.5);
      await adapters.set(fake.bridge, 'b.gguf', 0.5);
      await adapters.clear(fake.bridge);

      expect(fake.appliedAdapters, isEmpty);
      expect(fake.calls.last, 'lora:clear');

      await adapters.set(fake.bridge, 'a.gguf', 0.5);
      expect(fake.loraLoads, hasLength(2));
      expect(fake.appliedAdapters, <int, double>{7: 0.5});
    });

    test('loads a path again after forget', () async {
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      await loadModel();
      adapters.forget();
      await adapters.remove(fake.bridge, 'adapter.gguf');
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);

      expect(fake.loraLoads, hasLength(2));
      expect(fake.appliedAdapters, <int, double>{8: 0.5});
    });
  });

  group('error mapping', () {
    test('rejects an aLoRA adapter as unsupported', () async {
      fake.loraLoadError =
          'Failed to load LoRA adapter: the adapter is an aLoRA adapter (3 '
          'invocation token(s)). LoRA adapters apply from the start of '
          'generation.';

      await expectLater(
        adapters.set(fake.bridge, 'alora.gguf', 1),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('aLoRA adapter (3 invocation token(s))'),
          ),
        ),
      );
      expect(fake.appliedAdapters, isEmpty);
    });

    test('reports a wrong base model as a model error and retries', () async {
      fake.loraLoadError =
          "Failed to load LoRA adapter: tensor 'blk.0.attn_k.weight' has "
          'incorrect shape (hint: maybe wrong base model?)';

      await expectLater(
        adapters.set(fake.bridge, 'adapter.gguf', 1),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('maybe wrong base model?'),
          ),
        ),
      );

      fake.loraLoadError = null;
      await adapters.set(fake.bridge, 'adapter.gguf', 1);
      expect(fake.loraLoads, hasLength(2));
      expect(fake.appliedAdapters, <int, double>{7: 1});
    });

    test('keeps URL credentials out of load errors', () async {
      const url = 'https://user:pa55word@example.com/a.gguf?token=abcdef123456';
      fake.loraLoadError = 'Failed to fetch LoRA adapter $url: 404 Not Found';

      await expectLater(
        adapters.set(fake.bridge, url, 1),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('example.com/a.gguf'),
              isNot(contains('pa55word')),
              isNot(contains('abcdef123456')),
            ),
          ),
        ),
      );
    });

    test('rejects a malformed load result', () async {
      fake.loraLoadResult = JSObject()..setProperty('handle'.toJS, 0.toJS);

      await expectLater(
        adapters.set(fake.bridge, 'adapter.gguf', 1),
        throwsA(isA<LlamaModelException>()),
      );
      expect(fake.calls, isNot(contains(startsWith('lora:set'))));
    });

    test('reports a stale handle as a state error and reloads', () async {
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      await loadModel();

      await expectLater(
        adapters.set(fake.bridge, 'adapter.gguf', 0.5),
        throwsA(
          isA<LlamaStateException>().having(
            (error) => error.message,
            'message',
            contains('its model was unloaded or replaced'),
          ),
        ),
      );

      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      expect(fake.loraLoads, hasLength(2));
      expect(fake.appliedAdapters, <int, double>{8: 0.5});
    });

    test('reports calls during generation as state errors', () async {
      await adapters.set(fake.bridge, 'adapter.gguf', 0.5);
      const busy =
          'Failed to apply LoRA adapter: LoRA adapters cannot change during '
          'active generation or text-to-speech synthesis';
      fake
        ..loraSetError = busy
        ..loraRemoveError = busy
        ..loraClearError = busy;

      await expectLater(
        adapters.set(fake.bridge, 'adapter.gguf', 1),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        adapters.remove(fake.bridge, 'adapter.gguf'),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        adapters.clear(fake.bridge),
        throwsA(isA<LlamaStateException>()),
      );
    });

    test('rejects scales outside float32 before loading an adapter', () async {
      for (final scale in [
        double.infinity,
        double.negativeInfinity,
        1e40,
        -1e40,
      ]) {
        await expectLater(
          adapters.set(fake.bridge, 'adapter.gguf', scale),
          throwsA(isA<LlamaArgumentException>()),
        );
      }
      expect(fake.loraLoads, isEmpty);
      await adapters.set(fake.bridge, 'adapter.gguf', -3.4028234663852886e38);
      await adapters.set(fake.bridge, 'adapter.gguf', 0);
      await adapters.set(fake.bridge, 'adapter.gguf', 3.4028234663852886e38);
    });

    test('rejects a non-finite scale as an argument error', () async {
      fake.loraSetError =
          'LoRA adapter scale must be a finite number, got NaN.';

      await expectLater(
        adapters.set(fake.bridge, 'adapter.gguf', double.nan),
        throwsA(
          isA<LlamaArgumentException>().having(
            (error) => error.name,
            'name',
            'scale',
          ),
        ),
      );
    });
  });
}
