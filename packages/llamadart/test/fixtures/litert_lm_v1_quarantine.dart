import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args.first);
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  final runtime = LiteRtLmV1Runtime(library);
  runtime.load('/secret/models/m.litertlm', cacheDir: '/secret/cache');
  final conversation = runtime.openConversation();
  final turn = conversation.sendText(
    'quarantine',
    settings: args.length == 2
        ? const LiteRtLmV1TurnSettings(
            maxOutputTokens: 7,
            repetitionPenalty: 1.2,
            presencePenalty: -0.3,
          )
        : null,
  );
  if (count('args_live') != 0 || count('penalty_live') != 0) {
    throw StateError('native turn retained copied option temporaries');
  }
  final failure = turn.done.then<void>(
    (_) => throw StateError('drain succeeded unexpectedly'),
    onError: (Object error) {
      if (error is! LlamaModelException) throw error;
    },
  );
  final reads = count('loss_reads');
  call('fail_copies', 3);
  call('fail', 19);
  call('emit', 4);
  await failure;
  if (runtime.nativeSettlement != LiteRtLmNativeSettlement.quarantined ||
      conversation.nativeSettlement != LiteRtLmNativeSettlement.quarantined) {
    throw StateError('failed drain did not expose native quarantine');
  }
  if (count('loss_reads') != reads || count('failed_copies') != 2) {
    throw StateError(
      'failed drain read loss status or missed injected copy loss',
    );
  }
  call('fail_copies', 0);
  for (final operation in <void Function()>[
    conversation.close,
    () => conversation.sendText('reuse'),
    runtime.dispose,
    () => runtime.load('/model', cacheDir: '/cache'),
    runtime.openConversation,
  ]) {
    try {
      operation();
      throw StateError('quarantine escaped');
    } on LlamaStateException {
      /* expected */
    }
  }
  // Even an unexpected callback after failed drain must find a live callback
  // and free both strings. This is why no timeout can close its resources.
  call('emit', 4);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  if (count('live') != 2 ||
      count('proxies') != 1 ||
      count('copies') != 0 ||
      count('deleted') != 0 ||
      count('loss_reads') != reads) {
    throw StateError('quarantine lifetime counters failed');
  }
  stdout.writeln('quarantine controls passed');
  exit(
    0,
  ); // The quarantined native callback intentionally keeps its isolate alive.
}
