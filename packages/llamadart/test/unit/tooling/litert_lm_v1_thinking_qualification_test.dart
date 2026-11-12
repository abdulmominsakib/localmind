@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

import '../../support/litert_lm_v1_thinking_qualification.dart';
import '../../support/litert_lm_v1_thinking_owner.dart';
import '../../support/owned_qualification_process.dart';

final class _ObservedClient implements LiteRtLmRuntimeClientContract {
  _ObservedClient(this.lastFinishReason, this.nativeSettlement);
  @override
  final LiteRtLmFinishReason? lastFinishReason;
  @override
  final LiteRtLmNativeSettlement nativeSettlement;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'model identity and prompt match the maintained profile and existing oracle',
    () {
      final profile =
          jsonDecode(
                File(
                  'packages/llamadart_validation/assets/profiles/gemma4-litert-cpu.json',
                ).readAsStringSync(),
              )
              as Map;
      expect((profile['model'] as Map)['sha256'], thinkingModelSha256);
      expect((profile['model'] as Map)['bytes'], thinkingModelBytes);
      expect(
        thinkingPrompt,
        'A train leaves at 9:40 and arrives at 13:05. How long is the trip? Think it through carefully before answering.',
      );
    },
  );
  void result(
    int count, {
    int? budget,
    String content = '3 hours 25 minutes',
    String? finish = 'stop',
    String settlement = 'settled',
  }) => requireThinkingResult(
    reasoningTokens: count,
    finalContent: content,
    finish: finish,
    settlement: settlement,
    budget: budget,
  );
  test(
    'unchanged reasoning thresholds accept meaningful positive controls',
    () {
      result(25);
      result(14, budget: 12);
    },
  );
  test(
    'ineffective budget, weak baseline and incomplete final/finish fail',
    () {
      for (final operation in <void Function()>[
        () => result(24),
        () => result(15, budget: 12),
        () => result(12, budget: 12, content: ' '),
        () => result(12, budget: 12, finish: 'length'),
        () => result(12, budget: 12, finish: null),
        () => result(12, budget: 12, settlement: 'pending'),
      ]) {
        expect(operation, throwsStateError);
      }
    },
  );
  test('reasoning split keeps exact whitespace and Unicode', () {
    expect(splitThinkingOutput('$thinkingStart考える\n $thinkingEnd答え'), (
      reasoning: '考える\n ',
      content: '答え',
    ));
    expect(
      () => splitThinkingOutput('${thinkingStart}partial'),
      throwsStateError,
    );
    expect(
      () => splitThinkingOutput(
        '$thinkingStart x$thinkingEnd$thinkingStart y$thinkingEnd',
      ),
      throwsStateError,
    );
  });
  test('sticky override and changed reload bytes cannot pass reuse', () {
    requireThinkingReuse('考える\n答え', '考える\n答え');
    expect(
      () => requireThinkingReuse('long thinking', 'short bounded'),
      throwsStateError,
    );
  });
  test(
    'cancellation requires real output, actual cancelled cause and settlement',
    () {
      requireThinkingCancelled(
        requested: true,
        receivedBytes: 1,
        finish: 'cancelled',
        settlement: 'settled',
      );
      for (final operation in <void Function()>[
        () => requireThinkingCancelled(
          requested: false,
          receivedBytes: 1,
          finish: 'cancelled',
          settlement: 'settled',
        ),
        () => requireThinkingCancelled(
          requested: true,
          receivedBytes: 0,
          finish: 'cancelled',
          settlement: 'settled',
        ),
        () => requireThinkingCancelled(
          requested: true,
          receivedBytes: 1,
          finish: 'stop',
          settlement: 'settled',
        ),
        () => requireThinkingCancelled(
          requested: true,
          receivedBytes: 1,
          finish: 'cancelled',
          settlement: 'quarantined',
        ),
      ]) {
        expect(operation, throwsStateError);
      }
    },
  );
  test(
    'runtime manifest rejects traversal, duplicates and incomplete identities',
    () {
      final entry = {
        'name': 'libLiteRtLm.dylib',
        'bytes': 16,
        'sha256': 'a' * 64,
      };
      expect(
        thinkingRuntimeManifest(jsonEncode([entry])).single.name,
        'libLiteRtLm.dylib',
      );
      for (final bad in <Object>[
        [],
        [entry, entry],
        [
          {...entry, 'name': '../libLiteRtLm.dylib'},
        ],
        [
          {...entry, 'name': '/libLiteRtLm.dylib'},
        ],
        [
          {...entry, 'sha256': 'abc'},
        ],
        [
          {...entry, 'bytes': 0},
        ],
        [
          {...entry, 'bytes': 1.5},
        ],
      ]) {
        expect(
          () => thinkingRuntimeManifest(jsonEncode(bad)),
          throwsFormatException,
        );
      }
    },
  );
  for (final (name, reason, settlement) in [
    ('NULL', null, LiteRtLmNativeSettlement.settled),
    ('LENGTH', LiteRtLmFinishReason.length, LiteRtLmNativeSettlement.settled),
    (
      'CANCELLED',
      LiteRtLmFinishReason.cancelled,
      LiteRtLmNativeSettlement.settled,
    ),
    (
      'QUARANTINED',
      LiteRtLmFinishReason.stop,
      LiteRtLmNativeSettlement.quarantined,
    ),
  ]) {
    test('old STOP cannot supply new owner $name evidence', () {
      final owners = ThinkingOwnerTracker();
      owners.engineCreated(
        _ObservedClient(
          LiteRtLmFinishReason.stop,
          LiteRtLmNativeSettlement.settled,
        ),
      );
      final old = owners.capture();
      final current = _ObservedClient(reason, settlement);
      owners.engineCreated(current);
      final turn = owners.capture();
      final observation = owners.observe(turn);
      expect(identical(turn.client, current), isTrue);
      expect(observation.engineEpoch, greaterThan(old.engineEpoch));
      expect(() => owners.observe(old), throwsStateError);
      expect(
        () => requireThinkingResult(
          reasoningTokens: 25,
          finalContent: 'answer',
          finish: observation.finish,
          settlement: observation.settlement,
        ),
        throwsStateError,
      );
    });
  }
  test(
    'compiled native reload owner NULL cannot borrow disposed old STOP',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thinking_owner_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final libraries = <DynamicLibrary>[];
      for (final abi in [1, 2]) {
        final path =
            '${directory.path}/finish$abi.${Platform.isMacOS ? 'dylib' : 'so'}';
        final compiled = await Process.run('cc', [
          '-shared',
          '-fPIC',
          '-pthread',
          '-DFINISH_ABI=$abi',
          'test/fixtures/litert_lm/c_api_v1_thinking.c',
          '-o',
          path,
        ]);
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
        libraries.add(DynamicLibrary.open(path));
      }
      final owners = ThinkingOwnerTracker();
      final clients = <LiteRtLmV1RuntimeClient>[];
      addTearDown(() {
        for (final client in clients) {
          client.dispose();
        }
      });
      expect(owners.capture, throwsStateError);
      final old = createTrackedThinkingClient(libraries.first, owners);
      clients.add(old);
      expect(
        owners.capture,
        throwsStateError,
        reason: 'Constructing a metadata probe is not engine creation.',
      );
      Future<void> answer(
        LiteRtLmV1RuntimeClient client,
        DynamicLibrary library,
      ) async {
        client.createConversation();
        final output = client.generate('reason').toList();
        final text =
            '{"role":"assistant","content":[{"type":"text","text":"answer"}]}'
                .toNativeUtf8(allocator: calloc);
        try {
          library.lookupFunction<
            Void Function(Pointer<Utf8>, Bool, Int),
            void Function(Pointer<Utf8>, bool, int)
          >('fixture_client_emit')(text, true, 1);
        } finally {
          calloc.free(text);
        }
        expect((await output).join(), 'answer');
      }

      await old.initialize(
        modelPath: '/fixture/model.litertlm',
        backend: 'cpu',
        speculativeDecoding: false,
      );
      await answer(old, libraries.first);
      final oldTurn = owners.capture();
      expect(owners.observe(oldTurn).finish, 'stop');
      old.dispose();
      expect(old.lastFinishReason, LiteRtLmFinishReason.stop);
      final current = createTrackedThinkingClient(libraries.last, owners);
      clients.add(current);
      await current.initialize(
        modelPath: '/fixture/reload.litertlm',
        backend: 'cpu',
        speculativeDecoding: false,
      );
      final currentTurn = owners.capture();
      await answer(current, libraries.last);
      final observation = owners.observe(currentTurn);
      expect(identical(currentTurn.client, current), isTrue);
      expect(observation.finish, isNull);
      expect(observation.settlement, 'settled');
      expect(
        () => requireThinkingResult(
          reasoningTokens: 25,
          finalContent: 'answer',
          finish: observation.finish,
          settlement: observation.settlement,
        ),
        throwsStateError,
      );
      expect(() => owners.observe(oldTurn), throwsStateError);
    },
  );
  group('compiled pre-load identity refusal', () {
    late Directory directory;
    late String executable;
    setUpAll(() async {
      directory = await Directory.systemTemp.createTemp('thinking_identity_');
      executable = '${directory.path}/child';
      final compiled =
          await runOwnedQualificationProcess(Platform.resolvedExecutable, [
            'compile',
            'exe',
            'test/fixtures/litert_lm_v1_thinking_qualification.dart',
            '-o',
            executable,
          ], seconds: 120);
      expect(compiled.timedOut, isFalse);
      expect(compiled.outputComplete, isTrue);
      expect(
        compiled.exitCode,
        0,
        reason: utf8.decode(compiled.stderr, allowMalformed: true),
      );
    });
    tearDownAll(() => directory.delete(recursive: true));
    for (final mode in [
      'model-identity',
      'core-digest',
      'manifest-digest',
      'companion-digest',
      'model-bytes',
    ]) {
      test('$mode fails before runtime loading', () async {
        final folder = await directory.createTemp('case_');
        final library = File('${folder.path}/libLiteRtLm.dylib')
          ..writeAsStringSync('Not a loadable dylib.');
        final coreSha = sha256.convert(library.readAsBytesSync()).toString();
        final companion = File('${folder.path}/libLiteRt.dylib')
          ..writeAsStringSync('Companion sentinel.');
        final manifest = File('${folder.path}/manifest.json')
          ..writeAsStringSync(
            jsonEncode([
              {
                'name': 'libLiteRtLm.dylib',
                'bytes': library.lengthSync(),
                'sha256': coreSha,
              },
              {
                'name': 'libLiteRt.dylib',
                'bytes': companion.lengthSync(),
                'sha256': mode == 'companion-digest'
                    ? 'f' * 64
                    : sha256.convert(companion.readAsBytesSync()).toString(),
              },
            ]),
          );
        final input = File('${folder.path}/model.litertlm')
          ..writeAsStringSync('Model sentinel.');
        final child = await runOwnedQualificationProcess(executable, [
          library.path,
          input.path,
          mode == 'core-digest' ? 'f' * 64 : coreSha,
          mode == 'model-identity' ? 'f' * 64 : thinkingModelSha256,
          manifest.path,
          mode == 'manifest-digest'
              ? 'f' * 64
              : sha256.convert(manifest.readAsBytesSync()).toString(),
          folder.path,
          'model-free-control',
        ], seconds: 10);
        expect(child.timedOut, isFalse);
        expect(child.outputComplete, isTrue);
        expect(child.exitCode, 1);
        final events = utf8
            .decode(child.stdout)
            .split('\n')
            .where((line) => line.startsWith(thinkingEventPrefix))
            .map(
              (line) =>
                  jsonDecode(line.substring(thinkingEventPrefix.length)) as Map,
            )
            .toList();
        expect(events.map((event) => event['stage']), [
          'failure',
          'cleanup',
          'run_end',
        ]);
        final detail = events.first['detail'] as String;
        expect(
          detail,
          contains(switch (mode) {
            'model-identity' => 'fixed maintained Gemma',
            'core-digest' => 'Core library SHA256',
            'manifest-digest' => 'Runtime manifest SHA256',
            'companion-digest' => 'Runtime payload identity mismatch',
            _ => 'Fixed model bytes',
          }),
        );
        expect(events.last['success'], isFalse);
      });
    }
  });
  test(
    'owned child deadline retains binary output and kills only that process',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'thinking_timeout_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final script = File('${directory.path}/hang.dart')
        ..writeAsStringSync(
          "import 'dart:io'; import 'dart:async'; void main() { stdout.add([255,0,65]); Timer.periodic(Duration(seconds:10), (_) {}); }",
        );
      final child = await runOwnedQualificationProcess(
        Platform.resolvedExecutable,
        [script.path],
        seconds: 2,
      );
      expect(child.timedOut, isTrue);
      expect(child.outputComplete, isTrue);
      expect(child.exitCode, isNot(0));
      expect(child.stdout, [255, 0, 65]);
    },
  );
}
