import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args.single);
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  final runtime = LiteRtLmV1Runtime(library);
  runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
  final conversation = runtime.openConversation();
  final turn = conversation.sendText('quarantine');
  final done = turn.done.then<void>(
    (_) => throw StateError('unexpected success'),
    onError: (Object error) {
      if (error is! LlamaModelException) throw error;
    },
  );
  final chunks = turn.chunks.drain<void>();
  call('fail', 19);
  call('emit', 2);
  await done;
  await chunks;
  if (runtime.nativeSettlement != LiteRtLmNativeSettlement.quarantined) {
    throw StateError('failed drain did not retain family');
  }
  for (final operation in <void Function()>[
    () => runtime.bundleCapabilities('/model'),
    () => conversation.renderMessageToString({'role': 'user', 'content': 'Hi'}),
    () => conversation.readMetrics(wallMilliseconds: 0),
  ]) {
    try {
      operation();
      throw StateError('quarantine inspection succeeded');
    } on LlamaStateException {
      /* The quarantined family still owns callbacks. */
    }
  }
  final calls = library.lookupFunction<Int Function(Int), int Function(int)>(
    'fixture_metadata_calls',
  );
  if (calls(1) != 0 || calls(6) != 0 || calls(7) != 0) {
    throw StateError('quarantined inspection called native');
  }
  stdout.writeln('metadata quarantine controls passed');
  exit(0);
}
