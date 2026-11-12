// Root-scheduled, model-backed child; the outer process owns its deadline.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver_io.dart';

import '../../tool/litert_lm_asr_smoke.dart' as smoke;

Future<String> digest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

LiteRtLmRuntimeClientContract _createClient(String? libraryPath) =>
    LiteRtLmV1RuntimeClient(DynamicLibrary.open(libraryPath!));

Future<void> main(List<String> supplied) async {
  final child = supplied.isNotEmpty && supplied.first == '--child';
  final args = child ? supplied.sublist(1) : supplied;
  if (args.length != 10 ||
      [1, 3, 5, 7].any((i) => !RegExp(r'^[0-9a-f]{64}$').hasMatch(args[i]))) {
    throw ArgumentError(
      'Expected library/SHA256, model/SHA256, tokenizer/SHA256, WAV/SHA256, preset and expected transcript.',
    );
  }
  for (final (index, label) in [
    (0, 'library'),
    (2, 'model'),
    (4, 'tokenizer'),
    (6, 'audio'),
  ]) {
    if (await digest(args[index]) != args[index + 1]) {
      throw StateError('$label SHA256 mismatch before native loading.');
    }
  }
  if (Platform.isMacOS) {
    final version = await Process.run('/usr/bin/sw_vers', ['-productVersion']);
    final major = int.tryParse('${version.stdout}'.trim().split('.').first);
    if (version.exitCode != 0 || major == null || major < 14) {
      throw StateError(
        'The prepared LiteRT v1 macOS artifact requires macOS14+.',
      );
    }
  }
  if (child) {
    debugLiteRtLmSpeechToTextDriverOverride =
        createLiteRtLmSpeechToTextDriverWithRuntime(_createClient);
    try {
      await smoke.runLiteRtLmAsrSmoke(
        [args[2], args[4], args[6], args[8], args[9]],
        libraryPath: args[0],
        numberOfThreads: 2,
      );
      stdout.writeln('LITERT_V1_ASR_CHILD_COMPLETED');
    } finally {
      debugLiteRtLmSpeechToTextDriverOverride = null;
    }
    return;
  }
  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', arguments);
    if (result.exitCode != 0) {
      throw StateError('Cannot identify qualification source.');
    }
    return '${result.stdout}'.trim();
  }

  if ((await git(['status', '--porcelain'])).isNotEmpty) {
    throw StateError('ASR qualification requires a clean committed checkout.');
  }
  final revision = await git(['rev-parse', 'HEAD']);
  final tree = await git(['rev-parse', 'HEAD^{tree}']);
  Future<bool> unchanged() async =>
      (await git(['status', '--porcelain'])).isEmpty &&
      await git(['rev-parse', 'HEAD']) == revision;
  final output = await Directory.systemTemp.createTemp(
    'litert_v1_asr_qualification_',
  );
  final executable = '${output.path}/v1_asr';
  final compiled = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'test/fixtures/litert_lm_v1_asr_qualification.dart',
    '-o',
    executable,
  ]);
  await File(
    '${output.path}/compile.log',
  ).writeAsString('${compiled.stdout}\n${compiled.stderr}');
  if (compiled.exitCode != 0 || !await unchanged()) {
    throw StateError(
      'ASR child compilation failed or source changed. Evidence: ${output.path}',
    );
  }
  final executableSha = await digest(executable);
  final childTemp = await Directory('${output.path}/system-temp').create();
  final process = await Process.start(
    executable,
    ['--child', ...args],
    environment: {'TMPDIR': childTemp.path},
  );
  final stdoutFuture = utf8.decoder.bind(process.stdout).join();
  final stderrFuture = utf8.decoder.bind(process.stderr).join();
  var timedOut = false;
  final code = await process.exitCode.timeout(
    const Duration(minutes: 4),
    onTimeout: () async {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return process.exitCode;
    },
  );
  final outputText = await stdoutFuture;
  final errorText = await stderrFuture;
  await File('${output.path}/stdout.log').writeAsString(outputText);
  await File('${output.path}/native-stderr.log').writeAsString(errorText);
  final sourceUnchanged = await unchanged();
  final passed =
      code == 0 &&
      !timedOut &&
      sourceUnchanged &&
      outputText.contains('RESULT litert_lm_asr ') &&
      outputText.contains('LITERT_V1_ASR_CHILD_COMPLETED');
  final receipt = {
    'passed': passed,
    'sourceRevision': revision,
    'sourceTree': tree,
    'sourceUnchanged': sourceUnchanged,
    'executableSha256': executableSha,
    'librarySha256': args[1],
    'modelSha256': args[3],
    'tokenizerSha256': args[5],
    'audioSha256': args[7],
    'requestedBackend': 'cpu',
    'requestedThreads': 2,
    'injectedV1SpeechWorker': true,
    'timeoutSeconds': 240,
    'timedOut': timedOut,
    'exitCode': code,
    'evidenceDirectory': output.path,
  };
  await File(
    '${output.path}/receipt.json',
  ).writeAsString('${jsonEncode(receipt)}\n');
  stdout.writeln(jsonEncode(receipt));
  if (!passed) exitCode = 1;
}
