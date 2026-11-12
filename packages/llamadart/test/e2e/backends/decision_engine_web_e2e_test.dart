/// Real-model Web check of `DecisionEngine` through
/// `LlamaEngine(LlamaBackend())`, the `WebAutoBackend` to
/// `WebGpuLlamaBackend` path, against the Laya 0.3.5 reference with the
/// tolerances of `decision-model-smoke`.
///
/// Run it with `dart run tool/testing/run_local_e2e.dart --scenario
/// decision-model-web-smoke`, which fetches the pinned bridge assets into
/// `build/decision_web_e2e/bridge/` and selects the `chrome-webgpu` platform
/// of `dart_test.yaml`. The test page is not cross-origin isolated and the
/// bridge's core module and worker must be same-origin, so the assets sit
/// under the package root the test runner serves. The bridge fetches the
/// encoder and head from Hugging Face.
@TestOn('browser')
@Tags(['local-only', 'e2e'])
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/web/web_backend.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show Response, window;

import '../../support/decision_fixture.dart';

// The `decision-gguf-webgpu` validation profile's files: Q8_0, because each
// F16 load takes 45 to 51 s in the browser.
const _laya =
    'https://huggingface.co/fr0stbit3/laya-gguf/resolve/'
    'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c';
const _modelUrl = '$_laya/laya-Q8_0.gguf';
const _modelBytes = '421407968';
const _headUrl = '$_laya/laya-head.safetensors';

void main() {
  test(
    'matches the Laya 0.3.5 reference on WebGPU in the bridge worker',
    () async {
      final bridgeDir = Uri.base.resolve('../../../build/decision_web_e2e/');
      String bridgeUrl(String file) =>
          bridgeDir.resolve('bridge/$file').toString();
      await _fetch(
        bridgeUrl('manifest.json'),
        'Bridge assets missing; run the decision-model-web-smoke scenario.',
      );
      final module = await importModule(
        bridgeUrl('llama_webgpu_bridge.js').toJS,
      ).toDart;
      // The globals the chat app bootstrap sets (doc/webgpu_bridge.md).
      globalContext['LlamaWebGpuBridge'] = module.getProperty<JSFunction>(
        'LlamaWebGpuBridge'.toJS,
      );
      for (final (name, file) in [
        ('CoreModuleUrl', 'llama_webgpu_core.js'),
        ('WasmUrl', 'llama_webgpu_core.wasm'),
        ('CoreModuleUrlMem64', 'llama_webgpu_core_mem64.js'),
        ('WasmUrlMem64', 'llama_webgpu_core_mem64.wasm'),
        ('WorkerUrl', 'llama_webgpu_bridge_worker.js'),
      ]) {
        globalContext['__llamadartBridge$name'] = bridgeUrl(file).toJS;
      }

      final fixtureResponse = await _fetch(
        Uri.base.resolve('../../../$decisionFixturePath').toString(),
        'Decision fixture missing.',
      );
      final fixture = DecisionFixture.fromJson(
        jsonDecode((await fixtureResponse.text().toDart).toDart)
            as Map<String, Object?>,
      );
      final parity = DecisionParity();

      final backend = LlamaBackend();
      expect(backend, isA<WebAutoBackend>());
      final engine = LlamaEngine(backend);
      try {
        // ComputeDevice.gpu fails the load instead of falling back to the
        // WASM CPU, whose Q8_0 path misses the tolerances on one row.
        await engine.loadModel(
          _modelUrl,
          modelParams: const DecisionModelParams(
            device: ComputeDevice.gpu,
          ).encoderModelParams,
        );
        final metadata = await engine.getMetadata();
        expect(metadata['llamadart.webgpu.model_bytes'], _modelBytes);
        expect(
          metadata['llamadart.webgpu.execution'],
          'worker',
          reason: 'A main-thread fallback does not count as the worker path.',
        );

        final run = await runDecisionFixture(
          engine,
          fixture,
          parity,
          headPath: _headUrl,
        );
        final engineBackend = run.capabilities.backendName ?? '';
        if (!engineBackend.contains('WebGPU')) {
          parity.failures.add('the model runs on $engineBackend, not WebGPU');
        }
        if (!run.headDeviceName.contains('WebGPU')) {
          parity.failures.add('head device ${run.headDeviceName}, not WebGPU');
        }
        print(
          'RESULT decision_engine_web '
          'core=${metadata['llamadart.webgpu.core_variant']} '
          'execution=${metadata['llamadart.webgpu.execution']} '
          '${run.describe(parity)}',
        );
        expect(parity.failures, isEmpty, reason: parity.failures.join('\n'));
      } finally {
        await engine.dispose();
      }
    },
  );
}

Future<Response> _fetch(String url, String missing) async {
  final response = await window.fetch(url.toJS).toDart;
  expect(response.ok, isTrue, reason: '$missing ($url: ${response.status})');
  return response;
}
