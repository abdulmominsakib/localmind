// Model-free subprocess: the parent bounds blocked or retained native scopes.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_blocking_call.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_cache.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_blocking_call.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

Future<LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult>> _lostBefore(
  LiteRtLmV1CreateRequest request,
) => Future.error(StateError('lost native completion receipt'));

Future<LiteRtLmBlockingCallResult<LiteRtLmV1CreateResult>> _lostAfter(
  LiteRtLmV1CreateRequest request,
) async {
  await runLiteRtLmV1Create(request);
  throw StateError('lost native completion receipt after returned owner');
}

void require(bool value, String detail) {
  if (!value) throw StateError(detail);
}

void refused(void Function() operation) {
  var rejected = false;
  try {
    operation();
  } on LlamaStateException {
    rejected = true;
  }
  require(rejected, 'unsettled disposal was allowed');
}

void report(Map<String, Object?> values) =>
    stdout.writeln('ASYNC_CREATION ${jsonEncode(values)}');

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args[0]), mode = args[1];
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void set(String name, int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_$name',
      )(value);
  if (mode == 'service-lost') {
    debugLiteRtLmAbiOverride = Abi.macosArm64;
    final root = Directory(args[2]);
    final links = Directory('${root.path}/links')..createSync();
    final cache = Directory('${root.path}/cache')..createSync();
    final model = File('${root.path}/model.data')
      ..writeAsStringSync('LITERTLM model-free fixture');
    var factoryCalls = 0;
    final service = LiteRtLmService(
      runtimeClientFactory: () {
        factoryCalls++;
        return LiteRtLmV1RuntimeClient(library, createRunner: _lostAfter);
      },
      linkParentDirectory: links,
      readBundleFirstChannel: (_) => null,
      readBundleChatTemplate: (_) => null,
    );
    final params = ModelParams(contextSize: 64, liteRtLmCacheDir: cache.path);
    final handle = await service.loadModel(model.path, params);
    service.createContext(handle, params);
    final pending = service.tokenize(handle, 'fixture', false);
    require(
      service.nativeSettlement == LiteRtLmNativeSettlement.pending,
      'service hid pending creation',
    );
    refused(service.dispose);
    var rejected = false;
    try {
      await pending;
    } on LlamaStateException {
      rejected = true;
    }
    require(rejected, 'service accepted a lost receipt');
    require(
      service.nativeSettlement == LiteRtLmNativeSettlement.quarantined,
      'service lost quarantine',
    );
    refused(service.dispose);
    final leases = cache
        .listSync()
        .where(
          (e) => e.uri.pathSegments.last.startsWith(liteRtLmCacheLeasePrefix),
        )
        .length;
    require(
      leases == 2 && links.listSync().isNotEmpty,
      'unsettled model/cache owners released',
    );
    require(factoryCalls == 1, 'retried an unsettled native family');
    report({
      'mode': mode,
      'state': service.nativeSettlement.name,
      'live': count('live'),
      'settingsDeleted': count('async_settings_deleted'),
      'engineCalls': count('async_calls'),
      'factoryCalls': factoryCalls,
      'leaseFiles': leases,
      'modelLinkRetained': true,
    });
    await Future<void>.delayed(const Duration(days: 1));
    return;
  }
  final client = LiteRtLmV1RuntimeClient(
    library,
    createRunner: mode == 'lost-before'
        ? _lostBefore
        : mode == 'lost-after'
        ? _lostAfter
        : null,
  );
  if (mode.startsWith('lost-')) {
    var rejected = false;
    try {
      await client.initialize(
        modelPath: '/secret/models/m.litertlm',
        backend: 'cpu',
        numberOfThreads: 2,
        speculativeDecoding: false,
      );
    } on LlamaStateException {
      rejected = true;
    }
    require(
      rejected &&
          client.nativeSettlement == LiteRtLmNativeSettlement.quarantined,
      'lost scope was not quarantined',
    );
    refused(client.dispose);
    report({
      'mode': mode,
      'state': client.nativeSettlement.name,
      'live': count('live'),
      'settingsDeleted': count('async_settings_deleted'),
      'engineCalls': count('async_calls'),
    });
    await Future<void>.delayed(const Duration(days: 1));
    return;
  }
  set('async_hold', 1);
  final pending = client.initialize(
    modelPath: '/secret/models/m.litertlm',
    backend: 'cpu',
    cacheDir: '/secret/cache',
    numberOfThreads: 2,
    speculativeDecoding: false,
  );
  require(
    client.nativeSettlement == LiteRtLmNativeSettlement.pending,
    'creation did not expose pending',
  );
  refused(client.dispose);
  var ticked = false;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (timer) {
    if (count('async_entered') == 0) return;
    require(
      count('async_settings_deleted') == 0,
      'settings released during native creation',
    );
    ticked = true;
    set('async_hold', 0);
    timer.cancel();
  });
  try {
    await pending;
  } finally {
    timer.cancel();
    set('async_hold', 0);
  }
  require(
    ticked && client.nativeSettlement == LiteRtLmNativeSettlement.settled,
    'creation blocked event loop or failed settlement',
  );
  client.dispose();
  require(count('live') == 0, 'native owners leaked');
  report({
    'mode': mode,
    'state': 'settled',
    'timerProgressed': ticked,
    'live': count('live'),
    'settingsDeleted': count('async_settings_deleted'),
    'engineCalls': count('async_calls'),
  });
}
