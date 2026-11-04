@TestOn('browser')
library;

import 'package:llamadart/src/backends/webgpu/interop.dart';
import 'package:test/test.dart';

void main() {
  test('WebGPU interop types are available', () {
    expect(LlamaWebGpuBridge, isNotNull);
    expect(WebGpuBridgeConfig, isNotNull);
    expect(WebGpuLoadModelOptions, isNotNull);
    expect(WebGpuCompletionOptions, isNotNull);
  });
}
