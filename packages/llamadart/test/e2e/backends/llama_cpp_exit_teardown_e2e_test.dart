@TestOn('mac-os || linux')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Ends a child process in each way that leaves llama.cpp objects alive on
/// Metal, where ggml-metal aborts at exit while a buffer is still allocated
/// (issues #613 and #813).
///
/// Set `EXIT_TEARDOWN_MODEL` to a GGUF chat model; `EXIT_TEARDOWN_RUNS`
/// repeats each scenario (default 3). `EXIT_TEARDOWN_MMPROJ`, that model's
/// projector, adds the projector scenario; `EXIT_TEARDOWN_DECISION_MODEL` and
/// `EXIT_TEARDOWN_DECISION_HEAD`, an encoder GGUF and its decision head, add
/// the decision scenario; `EXIT_TEARDOWN_TTS_MODEL`, `EXIT_TEARDOWN_TTS_MMPROJ`
/// and `EXIT_TEARDOWN_TTS_ADAPTER` (`qwen3-tts`, `lfm3-audio`, `soprano`,
/// `chatterbox` or `pocket-tts`)
/// add the scenario that exits during synthesis.
void main() {
  final environment = Platform.environment;
  final model = environment['EXIT_TEARDOWN_MODEL'];
  final projector = environment['EXIT_TEARDOWN_MMPROJ'];
  final decisionModel = environment['EXIT_TEARDOWN_DECISION_MODEL'];
  final decisionHead = environment['EXIT_TEARDOWN_DECISION_HEAD'];
  final ttsModel = environment['EXIT_TEARDOWN_TTS_MODEL'];
  final ttsProjector = environment['EXIT_TEARDOWN_TTS_MMPROJ'];
  final ttsAdapter = environment['EXIT_TEARDOWN_TTS_ADAPTER'];
  final runs = int.parse(environment['EXIT_TEARDOWN_RUNS'] ?? '3');

  // A scenario of test/fixtures/llama_cpp_exit_probe.dart with its remaining
  // arguments (null skips it), the exit code of a clean end, and the backend
  // it must report when it reports one.
  for (final (scenario, arguments, exitCode, backend)
      in <(String, List<String?>, int, String?)>[
        if (Platform.isLinux) ...[
          (
            'host-shutdown-loaded',
            [model],
            0,
            environment['EXIT_TEARDOWN_BACKEND'] ?? 'CPU',
          ),
          (
            'host-shutdown-generating',
            [model],
            0,
            environment['EXIT_TEARDOWN_BACKEND'] ?? 'CPU',
          ),
          (
            'host-shutdown-loading',
            [model],
            0,
            environment['EXIT_TEARDOWN_BACKEND'] ?? 'CPU',
          ),
        ] else ...[
          ('quit-loaded', [model], 0, 'Metal'),
          ('quit-generating', [model], 0, 'Metal'),
          ('quit-loading', [model], 0, null),
          ('quit-projector', [model, projector], 0, 'Metal'),
          ('quit-disposing', [model, projector], 0, null),
          ('quit-decision', [decisionModel, decisionHead], 0, 'MTL'),
          ('quit-speaking', [ttsModel, ttsProjector, ttsAdapter], 0, null),
          ('throw-generating', [model], 255, 'Metal'),
          ('throw-loading', [model], 255, null),
          ('kill-loading', [model], 0, null),
          ('return-loaded', [model], 0, null),
        ],
      ]) {
    test('$scenario ends with exit code $exitCode', () async {
      // Not `skip:`, which --run-skipped (needed for `local-only`) overrides.
      if (arguments.contains(null)) {
        markTestSkipped(
          'Set the EXIT_TEARDOWN_ variables of $scenario to run it.',
        );
        return;
      }
      final codes = <int>[];
      for (var run = 0; run < runs; run++) {
        final process = await Process.start('dart', [
          'run',
          'test/fixtures/llama_cpp_exit_probe.dart',
          scenario,
          ...arguments.nonNulls,
        ]);
        final stdout = process.stdout.transform(utf8.decoder).join();
        final stderr = process.stderr.transform(utf8.decoder).join();
        final int code;
        try {
          code = await process.exitCode.timeout(const Duration(minutes: 3));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          fail('$scenario run $run did not exit: ${await stderr}');
        }
        final output = await stdout;
        final errors = await stderr;
        expect(
          output,
          contains('EXIT_PROBE_REACHED $scenario'),
          reason: errors,
        );
        if (backend != null) {
          expect(
            output,
            matches(
              RegExp(
                'EXIT_PROBE_BACKEND ${RegExp.escape(backend)}',
                caseSensitive: false,
              ),
            ),
          );
        }
        if (scenario.startsWith('host-shutdown-')) {
          expect(output, contains('EXIT_PROBE_HOST_SHUTDOWN_COMPLETE'));
        }
        expect(errors, isNot(contains('GGML_ASSERT')));
        expect(errors, isNot(contains('GetFfiCallbackMetadata')));
        codes.add(code);
      }
      // ignore: avoid_print
      print('EXIT_TEARDOWN_E2E ${jsonEncode({scenario: codes})}');
      expect(codes, everyElement(exitCode));
    });
  }
}
