import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/android_litert_qualification.dart';
import 'package:llamadart_validation/android_litert_qualification_io.dart';
import 'package:test/test.dart';

Map<String, dynamic> gpuObservation(String log) => {
  'backend_name': 'LiteRT-LM gpu',
  'reported_gpu_layers': ModelParams.maxGpuLayers,
  'native_finish': 'not_exposed_by_default_service',
  'native_settlement': 'settled',
  'input_tokens': 20,
  'output_tokens': 3,
  'public_process_pid': 123,
  'mapped_core_verified': true,
  'warnings': <String>[],
  'native_gpu_initialization': true,
  'native_gpu_initialization_backend': 'OpenCL',
  'native_stderr': {
    ...captureS24LiteRtBytes(utf8.encode(log)),
    'lifetime_id': 'auto-corrected.1',
    'empty_at_load': true,
  },
};

void main() {
  final log = File('test/fixtures/s24_opencl_stderr.txt').readAsStringSync();
  void validate(Map<String, dynamic> value) =>
      requireS24LiteRtGpuObservation(value, lifetimeId: 'auto-corrected.1');

  test('retained public CPU fallback cannot qualify corrected auto GPU', () {
    final value =
        jsonDecode(
              File(
                'test/fixtures/s24_public_auto_cpu_fallback.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(value['sequence'], 432);
    expect(value['backend_name'], 'LiteRT-LM cpu');
    requireS24LiteRtCpuObservation(
      value,
      automatic: true,
      lifetimeId: 'auto-corrected.1',
    );
    expect(() => validate(value), throwsFormatException);
    // Even forged placement flags cannot replace the failed native capture.
    final claimedGpu = {
      ...value,
      'backend_name': 'LiteRT-LM gpu',
      'reported_gpu_layers': ModelParams.maxGpuLayers,
      'native_gpu_initialization': true,
      'native_gpu_initialization_backend': 'Vulkan',
      'warnings': <String>[],
    };
    expect(() => validate(claimedGpu), throwsFormatException);
  });

  test(
    'GPU envelope requires fresh verified initialization and functionality',
    () {
      // Saved native OpenCL bytes exercise the parser with a synthetic public
      // envelope; this is a model-free control, not public/device qualification.
      validate(gpuObservation(log));
      for (final mutation in <void Function(Map<String, dynamic>)>[
        (value) => value['backend_name'] = 'LiteRT-LM cpu',
        (value) => value['reported_gpu_layers'] = 0,
        (value) => value['native_settlement'] = 'pending',
        (value) => value['native_finish'] = 'stop',
        (value) => value['input_tokens'] = 0,
        (value) => value['output_tokens'] = -1,
        (value) => value['output_tokens'] = '3',
        (value) => value['public_process_pid'] = 0,
        (value) => value['mapped_core_verified'] = false,
        (value) => value.remove('warnings'),
        (value) => value['warnings'] = [7],
        (value) => value['warnings'] = [
          'LiteRT-LM could not create a GPU engine under ComputeDevice.auto; '
              'retrying on the CPU.',
        ],
        (value) => value['native_gpu_initialization'] = false,
        (value) => value['native_gpu_initialization_backend'] = 'Vulkan',
        (value) => value.remove('native_stderr'),
        (value) => value['native_stderr']['lifetime_id'] = 'auto-corrected.2',
        (value) => value['native_stderr']['empty_at_load'] = false,
        (value) => value['native_stderr']['sha256'] = '0' * 64,
      ]) {
        final value = gpuObservation(log);
        mutation(value);
        expect(() => validate(value), throwsFormatException);
      }
      for (final invalid in [
        '',
        'GPU registered',
        '$log\nFalling back to CPU',
        '$log\nERROR: Failed to initialize kernel.',
        log.replaceFirst('1306 out of 1306', '1305 out of 1306'),
        '$log\n$log',
      ]) {
        expect(() => validate(gpuObservation(invalid)), throwsFormatException);
      }
    },
  );
}
