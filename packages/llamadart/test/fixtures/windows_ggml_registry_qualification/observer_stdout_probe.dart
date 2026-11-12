import 'dart:convert';
import 'dart:io';

import 'payload/passive_modules.dart';

Future<void> main(List<String> arguments) async {
  final mode = arguments.single;
  final failedModel = mode == 'exception';
  final outcome = failedModel ? 'exception emitter-only control' : 'success';
  print('MODEL_OUTCOME $outcome');
  List<Map<String, Object?>> rows(String checkpoint, bool getters) => [
    for (var index = 0; index < 64; index++)
      {
        'checkpoint': checkpoint,
        'registryGettersCalled': getters,
        'index': index,
        'emitterOnlyPadding': 'x' * 16384,
      },
  ];

  final first = rows(
    'after-stock-model-${failedModel ? 'exception' : 'success'}',
    false,
  );
  stderr.writeln('OBSERVER_STDOUT_READY');
  await stderr.flush();
  if (mode == 'unawaited-flush') {
    for (final observation in first) {
      stdout.writeln('PASSIVE_MODULE ${jsonEncode(observation)}');
    }
    stdout.flush();
  } else {
    await emitPassiveSnapshot(first);
  }
  stderr.writeln('NATIVE_STDERR emitter-only cadence');
  print('REGISTRY_IDENTITY {"emitterOnlyControl":true}');
  await emitPassiveSnapshot(rows('after-registry-observation', true));
  await stderr.flush();
  if (failedModel) exitCode = 7;
}
