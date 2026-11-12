import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args[0]);
  final client = LiteRtLmV1RuntimeClient(library);
  await client.initialize(
    modelPath: args[2],
    backend: 'cpu',
    cacheDir: '/secret/cache',
    speculativeDecoding: false,
  );
  client.createConversation();
  void call(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  int get(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  late LiteRtLmNativeSettlement expected;
  if (args[1] == 'failed-drain') {
    final output = client
        .generateMessageJson(
          '{"role":"user","content":"reason"}',
          thinkingTokenBudget: 4,
        )
        .drain<void>()
        .then<void>(
          (_) => throw StateError('failed drain succeeded'),
          onError: (Object error) {
            if (error is! LlamaModelException) throw error;
          },
        );
    call('fail', 19);
    call('emit', 2);
    await output;
    expected = LiteRtLmNativeSettlement.quarantined;
  } else {
    final subscription = client
        .generateMessageJson(
          '{"role":"user","content":"reason"}',
          thinkingTokenBudget: 4,
        )
        .listen((_) {});
    var finished = false;
    subscription.cancel().then((_) {
      finished = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 25));
    if (finished) throw StateError('missing final completed cancellation');
    expected = LiteRtLmNativeSettlement.pending;
  }
  if (client.nativeSettlement != expected ||
      get('live') != 2 ||
      get('proxies') != 1 ||
      get('thinking_live') != 0 ||
      get('args_live') != 0) {
    throw StateError('unsettled client released or misreported native owners');
  }
  for (final operation in <void Function()>[
    client.dispose,
    () => client.createConversation(),
    () => client.tokenize('unsafe'),
    () => client.detokenize([]),
    () => client.bundleCapabilities('/model'),
  ]) {
    try {
      operation();
      throw StateError('unsettled native owner was reused');
    } on LlamaStateException {
      /* Retention is intentional until process exit. */
    }
  }
  if (get('deleted') != 0 || get('proxies') != 1 || get('live') != 2) {
    throw StateError('lifetime refusals freed retained native owners');
  }
  stdout.writeln('${args[1]} thinking lifetime controls passed');
  exit(0);
}
