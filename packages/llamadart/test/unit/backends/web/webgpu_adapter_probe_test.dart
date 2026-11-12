@TestOn('browser')
library;

import 'package:llamadart/src/backends/web/webgpu_adapter_probe.dart';
import 'package:test/test.dart';

import '../../../support/fake_navigator_gpu.dart';

void main() {
  for (final (gpu, available) in [
    (FakeWebGpu.missing, false),
    (FakeWebGpu.noAdapter, false),
    (FakeWebGpu.failingAdapter, false),
    (FakeWebGpu.adapter, true),
  ]) {
    test('reports ${available ? '' : 'no '}adapter for ${gpu.name}', () async {
      addTearDown(fakeNavigatorGpu(gpu));

      expect(await webGpuAdapterAvailable(), available);
    });
  }
}
