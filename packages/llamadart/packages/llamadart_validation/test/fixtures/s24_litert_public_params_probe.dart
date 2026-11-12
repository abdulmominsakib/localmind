// Synthetic C API dispatch only; no model or device qualification.
import 'dart:convert';
import 'dart:ffi';

import 'package:llamadart/llamadart.dart';
// ignore: implementation_imports
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart_validation/src/s24_litert_params.dart';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args[1]);
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  final warnings = <String>[];
  await LlamaLogging.configure(
    level: LlamaLogLevel.info,
    handler: (entry) => warnings.add(entry.message),
  );
  final device = switch (args[0]) {
    'cpu' => ComputeDevice.cpu,
    'auto' => ComputeDevice.auto,
    _ => ComputeDevice.gpu,
  };
  var params = s24LiteRtPublicParams(device, cacheDir: args[3]);
  if (args[0] == 'old-gpu') params = params.copyWith(numberOfThreads: 4);
  final service = LiteRtLmService(useTempCacheDir: false);
  Object? failure;
  var tokens = 0;
  try {
    if (!service.reportsFinishReasons()) {
      throw StateError('Default discovery did not select the v1 fixture');
    }
    final model = await service.loadModel(args[2], params);
    tokens = (await service.tokenize(model, 'hello', false)).length;
  } on Object catch (error) {
    failure = error;
  } finally {
    service.dispose();
  }
  print(
    jsonEncode({
      'route': args[0],
      'threads': params.numberOfThreads,
      'typed_unsupported': failure is LlamaUnsupportedException,
      'error': failure?.toString(),
      'attempts': count('public_engine_attempts'),
      'gpu_refusals': count('public_gpu_refusals'),
      'cpu_creates': count('public_cpu_creates'),
      'tokens': tokens,
      'live': count('live'),
      'warnings': warnings,
    }),
  );
}
