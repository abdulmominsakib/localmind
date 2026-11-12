@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/ggml_graph_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

@Native<Void Function()>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'llamadart_test_missing_ggml_symbol',
)
external void _missingSymbol();

void main() {
  setUpAll(() => LlamaCppService().initializeBackend());

  test('withGgmlGraphSymbols reports an unresolved symbol as unsupported', () {
    expect(
      () => withGgmlGraphSymbols(_missingSymbol),
      throwsA(
        isA<LlamaUnsupportedException>().having(
          (error) => error.message,
          'message',
          contains('llamadart_test_missing_ggml_symbol'),
        ),
      ),
    );
    expect(withGgmlGraphSymbols(() => 7), 7);
    expect(
      () => withGgmlGraphSymbols(() => throw ArgumentError('bad input')),
      throwsA(
        isA<ArgumentError>().having((e) => e.message, 'message', 'bad input'),
      ),
    );
    expect(
      () => withGgmlGraphSymbols(() => [1][2]),
      throwsA(isA<RangeError>()),
    );
  });

  test('computes a graph through every entry on the CPU backend', () {
    final api = GgmlGraphApi.current;
    final f32 = ggml_type.GGML_TYPE_F32.value;
    const a = [1.0, -2.0, 0.5, 3.0, 0.0, -1.0];
    const b = [0.5, -1.0, 2.0];
    const w = [0.25, 1.0, -0.5, 2.0, 0.0, 1.5];

    final cpuDevice = api.devByType(
      ggml_backend_dev_type.GGML_BACKEND_DEVICE_TYPE_CPU.value,
    );
    expect(cpuDevice, isNot(nullptr));
    final backend = api.devInit(cpuDevice, nullptr);
    expect(backend, isNot(nullptr));
    addTearDown(() => api.backendFree(backend));
    expect(api.backendName(backend).cast<Utf8>().toDartString(), 'CPU');
    expect(api.backendGetDevice(backend), cpuDevice);
    final name = 'ggml_backend_set_n_threads'.toNativeUtf8();
    final setThreads = api.regGetProcAddress(
      api.devBackendReg(cpuDevice),
      name.cast(),
    );
    malloc.free(name);
    expect(setThreads, isNot(nullptr));
    setThreads
        .cast<NativeFunction<Void Function(ggml_backend_t, Int)>>()
        .asFunction<void Function(ggml_backend_t, int)>()(backend, 2);

    Pointer<ggml_context> context(int tensors) {
      final params = calloc<ggml_init_params>();
      params.ref
        ..mem_size =
            api.tensorOverhead() * tensors + api.graphOverheadCustom(64, false)
        ..mem_buffer = nullptr
        ..no_alloc = true;
      final ctx = api.init(params.ref);
      calloc.free(params);
      addTearDown(() => api.free(ctx));
      return ctx;
    }

    final staging = malloc<Float>(16);
    addTearDown(() => malloc.free(staging));
    void upload(Pointer<ggml_tensor> tensor, List<double> values) {
      staging.asTypedList(values.length).setAll(0, values);
      api.tensorSet(tensor, staging.cast(), 0, values.length * 4);
    }

    List<double> download(Pointer<ggml_tensor> tensor, int count) {
      api.tensorGet(tensor, staging.cast(), 0, count * 4);
      return List.of(staging.asTypedList(count));
    }

    final weights = context(1);
    final weight = api.newTensor2d(weights, f32, 3, 2);
    final buffer = api.allocCtxTensors(weights, backend);
    expect(buffer, isNot(nullptr));
    addTearDown(() => api.bufferFree(buffer));
    api.bufferSetUsage(
      buffer,
      ggml_backend_buffer_usage.GGML_BACKEND_BUFFER_USAGE_WEIGHTS.value,
    );
    upload(weight, w);

    final g = context(64);
    final x = api.newTensor2d(g, f32, 3, 2);
    final bias = api.newTensor1d(g, f32, 3);
    final rows = api.newTensor1d(g, ggml_type.GGML_TYPE_I32.value, 1);
    for (final input in [x, bias, rows]) {
      api.setInput(input);
    }
    final outputs = {
      'mulMat': api.mulMat(g, weight, x),
      'add': api.add(g, x, bias),
      'mul': api.mul(g, x, bias),
      'norm': api.norm(g, x, 1e-5),
      'relu': api.relu(g, x),
      'geluErf': api.geluErf(g, x),
      'softMaxExt': api.softMaxExt(g, x, nullptr, 0.5, 0),
      'getRows': api.getRows(g, x, rows),
      'transpose': api.cont(g, api.transpose(g, x)),
      'permute': api.cont2d(
        g,
        api.permute(g, api.reshape3d(g, x, 1, 3, 2), 0, 2, 1, 3),
        2,
        3,
      ),
    };
    final graph = api.newGraphCustom(g, 64, false);
    for (final output in outputs.values) {
      api.setOutput(output);
      api.buildForwardExpand(graph, output);
    }

    final backends = calloc<ggml_backend_t>(1)..value = backend;
    final sched = api.schedNew(backends, nullptr, 1, 2048, false, false);
    calloc.free(backends);
    expect(sched, isNot(nullptr));
    addTearDown(() => api.schedFree(sched));
    api.schedReset(sched);
    expect(api.schedAllocGraph(sched, graph), isTrue);
    upload(x, a);
    upload(bias, b);
    staging.cast<Int32>().value = 1;
    api.tensorSet(rows, staging.cast(), 0, 4);
    expect(
      api.schedGraphCompute(sched, graph),
      ggml_status.GGML_STATUS_SUCCESS.value,
    );
    api.schedSynchronize(sched);

    List<double> rowNorm(List<double> row) {
      final mean = row.reduce((s, v) => s + v) / row.length;
      final variance =
          row.map((v) => (v - mean) * (v - mean)).reduce((s, v) => s + v) /
          row.length;
      return [for (final v in row) (v - mean) / math.sqrt(variance + 1e-5)];
    }

    List<double> rowSoftmax(List<double> row) {
      final exps = [for (final v in row) math.exp(0.5 * v)];
      final sum = exps.reduce((s, v) => s + v);
      return [for (final v in exps) v / sum];
    }

    double dot(int wRow, int aRow) => [
      for (var i = 0; i < 3; i++) w[wRow * 3 + i] * a[aRow * 3 + i],
    ].reduce((s, v) => s + v);
    final expected = {
      'mulMat': [dot(0, 0), dot(1, 0), dot(0, 1), dot(1, 1)],
      'add': [1.5, -3.0, 2.5, 3.5, -1.0, 1.0],
      'mul': [0.5, 2.0, 1.0, 1.5, 0.0, -2.0],
      'norm': [...rowNorm(a.sublist(0, 3)), ...rowNorm(a.sublist(3))],
      'relu': [1.0, 0.0, 0.5, 3.0, 0.0, 0.0],
      'geluErf': [
        0.8413447460685429,
        -0.04550026389635842,
        0.3457312306370065,
        2.99595030590511,
        0.0,
        -0.15865525393145707,
      ],
      'softMaxExt': [
        ...rowSoftmax(a.sublist(0, 3)),
        ...rowSoftmax(a.sublist(3)),
      ],
      'getRows': [3.0, 0.0, -1.0],
      'transpose': [1.0, 3.0, -2.0, 0.0, 0.5, -1.0],
      'permute': [1.0, 3.0, -2.0, 0.0, 0.5, -1.0],
    };
    for (final MapEntry(key: op, value: values) in expected.entries) {
      final actual = download(outputs[op]!, values.length);
      for (var i = 0; i < values.length; i++) {
        expect(actual[i], closeTo(values[i], 1e-5), reason: '$op[$i]');
      }
    }
  });
}
