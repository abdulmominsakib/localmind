@TestOn('browser')
library;

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

import '../../../support/fake_webgpu_feature_bridge.dart';

void main() {
  late List<FakeFeatureBridge> bridges;
  late WebGpuLlamaBackend backend;

  setUp(() {
    bridges = <FakeFeatureBridge>[];
    backend = WebGpuLlamaBackend(
      bridgeFactory: ([config]) {
        final created = FakeFeatureBridge();
        bridges.add(created);
        return created.bridge;
      },
    );
  });

  tearDown(() => backend.dispose());

  for (final alias in ['./models/a.gguf', 'models/sub/../a.gguf']) {
    test('setLoraSource through the alias $alias only changes the scale of '
        'the applied adapter', () async {
      final engine = LlamaEngine(backend);
      await engine.loadModelFromUrl('https://example.com/model.gguf');

      await engine.setLoraSource(ModelSource.path('models/a.gguf'), scale: 1);
      await engine.setLoraSource(ModelSource.path(alias), scale: 0.5);

      expect(bridges.last.appliedAdapters.values, [0.5]);

      await engine.removeLoraSource(ModelSource.path(alias));
      expect(bridges.last.appliedAdapters, isEmpty);
    });
  }
}
