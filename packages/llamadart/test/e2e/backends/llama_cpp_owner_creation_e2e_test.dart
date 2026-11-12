@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'package:llamadart/src/backends/llama_cpp/native_owner_api.dart';

import '../../support/suite_system_temp.dart';
import '../../fixtures/llama_cpp_owner_creation_worker.dart';

void main() {
  useSuiteSystemTemp();
  final libraryPath = Platform.environment['OWNER_TEST_LIBRARY'];
  final gatePath = Platform.environment['OWNER_TEST_GATE'];
  final modelPath = Platform.environment['OWNER_TEST_MODEL'];
  for (final (phase, separateGroup) in [
    ('model', false),
    ('context', false),
    ('context', true),
  ]) {
    test(
      'pending kill after owned $phase creator returns (separate group: $separateGroup)',
      () async {
        if (libraryPath == null || gatePath == null || modelPath == null) {
          markTestSkipped(
            'Set OWNER_TEST_LIBRARY, OWNER_TEST_GATE and OWNER_TEST_MODEL.',
          );
          return;
        }
        final library = DynamicLibrary.open(libraryPath);
        final api = NativeOwnerApi.tryResolve(symbol: library.lookup)!;
        final count = library.lookupFunction<Int32 Function(), int Function()>(
          'llama_dart_exit_tracked_count',
        );
        final owners = library.lookupFunction<Int32 Function(), int Function()>(
          'llama_dart_owner_count',
        );
        final gate = DynamicLibrary.open(gatePath);
        gate.lookupFunction<Void Function(), void Function()>(
          'owner_gate_reset',
        )();
        final waiting = gate.lookupFunction<Bool Function(), bool Function()>(
          'owner_gate_waiting',
        );
        final resume = gate.lookupFunction<Void Function(), void Function()>(
          'owner_gate_resume',
        );
        expect(count(), 0);
        expect(owners(), 0);
        // The parent owns the pending control token before spawning the worker.
        final token = api.create();
        final exited = ReceivePort();
        final ended = exited.first;
        final reports = ReceivePort();
        final messages = <Object?>[];
        final subscription = reports.listen(messages.add);
        final arguments = <Object?>[
          libraryPath,
          gatePath,
          modelPath,
          phase,
          token.address,
          reports.sendPort,
        ];
        final worker = separateGroup
            ? await Isolate.spawnUri(
                Directory.current.uri.resolve(
                  'test/fixtures/llama_cpp_owner_creation_worker.dart',
                ),
                [libraryPath, gatePath, modelPath, phase, '${token.address}'],
                reports.sendPort,
                packageConfig: Directory.current.uri.resolve(
                  '.dart_tool/package_config.json',
                ),
                onExit: exited.sendPort,
                onError: reports.sendPort,
                errorsAreFatal: true,
              )
            : await Isolate.spawn(
                runOwnerCreationWorker,
                arguments,
                onExit: exited.sendPort,
                onError: reports.sendPort,
                errorsAreFatal: true,
              );
        try {
          final deadline = Stopwatch()..start();
          while (!waiting() && deadline.elapsed < const Duration(seconds: 30)) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          expect(
            waiting(),
            isTrue,
            reason:
                'The real native creator must finish before the kill is queued: $messages',
          );
          expect(count(), phase == 'model' ? 1 : 2);
          worker.kill(priority: Isolate.immediate);
          resume();
          await ended.timeout(const Duration(seconds: 30));
          // Same native registry drain used by the production parent's onExit.
          if (separateGroup) {
            // NativeFinalizer guarantees cleanup at orderly isolate-group shutdown.
            // This control deliberately omits the parent's explicit drain first.
            final deadline = Stopwatch()..start();
            while (owners() != 0 &&
                deadline.elapsed < const Duration(seconds: 10)) {
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            expect(
              owners(),
              0,
              reason:
                  'The stable worker finalizer must drain without parent cleanup.',
            );
            expect(count(), 0);
          }
          api.releaseAddress.asFunction<void Function(Pointer<Void>)>()(token);
          expect(count(), 0);
          expect(owners(), 0);
          expect(
            messages,
            isEmpty,
            reason:
                'The pending kill must land before Dart handles the result.',
          );
        } finally {
          resume();
          worker.kill(priority: Isolate.immediate);
          await ended.timeout(const Duration(seconds: 30));
          api.releaseAddress.asFunction<void Function(Pointer<Void>)>()(token);
          exited.close();
          await subscription.cancel();
          reports.close();
        }
      },
    );
  }
}
