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
  final failed = turn.done.then<void>(
    (_) => throw StateError('failed drain succeeded unexpectedly'),
    onError: (Object error) {
      if (error is! LlamaModelException) throw error;
    },
  );
  final chunks = turn.chunks.drain<void>().then<void>(
    (_) {},
    onError: (Object error) {
      if (error is! LlamaModelException) throw error;
    },
  );
  call('fail', 19);
  call('emit', 2);
  await failed;
  await chunks;
  if (runtime.nativeSettlement != LiteRtLmNativeSettlement.quarantined) {
    throw StateError('failed drain did not quarantine native work');
  }
  for (final operation in <void Function()>[
    () => runtime.tokenize('unsafe'),
    () => runtime.detokenize([1]),
    () => runtime.detokenize([]),
  ]) {
    try {
      operation();
      throw StateError('tokenizer entered quarantined engine');
    } on LlamaStateException {
      // Quarantined native work still owns the engine and callbacks.
    }
  }
  final calls = library.lookupFunction<Int Function(Int), int Function(int)>(
    'fixture_token_calls',
  );
  if (calls(1) != 0 || calls(8) != 0) {
    throw StateError('quarantine refusal called native tokenizer');
  }
  stdout.writeln('tokenizer quarantine controls passed');
  exit(0);
}
