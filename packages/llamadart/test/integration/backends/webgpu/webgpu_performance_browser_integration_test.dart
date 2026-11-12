@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

import '../../../support/fake_webgpu_feature_bridge.dart';

void main() {
  for (final batch in [false, true]) {
    test('Web null-diagnostics contract after generation, early cancel '
        'and embedding: batch=$batch', () async {
      final bridge = FakeFeatureBridge();
      var embeddings = 0;
      bridge.object.setProperty(
        'embed'.toJS,
        ((String text, JSObject? options) {
          embeddings++;
          return Future<JSArray<JSNumber>>.value([1.toJS].toJS).toJS;
        }).toJS,
      );
      final engine = LlamaEngine(
        WebGpuLlamaBackend(bridgeFactory: ([config]) => bridge.bridge),
      );
      addTearDown(engine.dispose);
      await engine.loadModelFromUrl('https://example.com/model.gguf');
      await engine.generate('first').drain<void>();
      expect(bridge.completionCalls, 1);
      expect(await engine.getPerformanceContext(), isNull);
      final cancelled = engine.generate('cancelled').toList();
      engine.cancelGeneration();
      await cancelled;
      expect(bridge.completionCalls, 1);
      expect(await engine.getPerformanceContext(), isNull);

      if (batch) {
        expect(await engine.embedBatch(['hello', 'world']), [
          [1.0],
          [1.0],
        ]);
      } else {
        expect(await engine.embed('hello'), [1.0]);
      }
      expect(embeddings, batch ? 2 : 1);
      expect(await engine.getPerformanceContext(), isNull);
      await engine.generate('next').drain<void>();
      expect(bridge.completionCalls, 2);
      expect(await engine.getPerformanceContext(), isNull);
    });
  }
}
