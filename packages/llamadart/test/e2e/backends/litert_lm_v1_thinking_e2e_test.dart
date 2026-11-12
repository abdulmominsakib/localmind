@TestOn('vm && mac-os')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 14))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../support/litert_lm_v1_thinking_qualification.dart';
import '../../support/suite_system_temp.dart';
import '../../support/owned_qualification_process.dart';

void main() {
  final systemTemp = useSuiteSystemTemp();
  test(
    'exact Gemma CPU thinking bounds, no-budget isolation, cancellation and reload',
    () async {
      String required(String name) {
        final value = Platform.environment[name]?.trim();
        if (value == null || value.isEmpty) fail('$name is required.');
        return value;
      }

      final library = required('LITERT_LM_V1_LIBRARY');
      final model = required('LITERT_LM_V1_MODEL');
      final librarySha = required('LITERT_LM_V1_LIBRARY_SHA256').toLowerCase();
      final modelSha = required('LITERT_LM_V1_MODEL_SHA256').toLowerCase();
      final manifest = required('LITERT_LM_V1_RUNTIME_MANIFEST');
      final manifestSha = required(
        'LITERT_LM_V1_RUNTIME_MANIFEST_SHA256',
      ).toLowerCase();
      expect(
        modelSha,
        thinkingModelSha256,
        reason:
            'Fixed maintained Gemma model required; no outcome-based substitution.',
      );
      for (final hash in [librarySha, modelSha, manifestSha]) {
        expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      for (final path in [library, model, manifest]) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'Required local input unavailable.',
        );
      }
      final revision =
          '${(await Process.run('git', ['rev-parse', 'HEAD'])).stdout}'.trim();
      final tree =
          '${(await Process.run('git', ['rev-parse', 'HEAD^{tree}'])).stdout}'
              .trim();
      expect(revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(tree, matches(RegExp(r'^[0-9a-f]{40}$')));
      Future<bool> sourceUnchanged() async {
        final status = await Process.run('git', ['status', '--porcelain']);
        final head = await Process.run('git', ['rev-parse', 'HEAD']);
        return status.exitCode == 0 &&
            head.exitCode == 0 &&
            '${status.stdout}'.trim().isEmpty &&
            '${head.stdout}'.trim() == revision;
      }

      expect(
        await sourceUnchanged(),
        isTrue,
        reason: 'Qualification requires clean exact source.',
      );
      final base = Directory(
        Platform.environment['LITERT_LM_V1_LOG_DIR'] ??
            '.dart_tool/litert_lm_v1_thinking',
      )..createSync(recursive: true);
      final output = await base.createTemp('run-');
      print('Thinking qualification evidence: ${output.path}');
      final executable = '${output.absolute.path}/v1_thinking';
      final compiled =
          await runOwnedQualificationProcess(Platform.resolvedExecutable, [
            'compile',
            'exe',
            'test/fixtures/litert_lm_v1_thinking_qualification.dart',
            '-o',
            executable,
          ], seconds: 120);
      await File(
        '${output.path}/compile-stdout.log',
      ).writeAsBytes(compiled.stdout);
      await File(
        '${output.path}/compile-stderr.log',
      ).writeAsBytes(compiled.stderr);
      if (compiled.exitCode != 0 ||
          compiled.timedOut ||
          !compiled.outputComplete) {
        await File('${output.path}/receipt.json').writeAsString(
          jsonEncode({
            'source_revision': revision,
            'source_tree': tree,
            'phase': 'compile',
            'exit_code': compiled.exitCode,
            'outer_timeout': compiled.timedOut,
            'output_complete': compiled.outputComplete,
            'success': false,
          }),
        );
      }
      expect(compiled.timedOut, isFalse);
      expect(compiled.outputComplete, isTrue);
      expect(
        compiled.exitCode,
        0,
        reason: utf8.decode(compiled.stderr, allowMalformed: true),
      );
      expect(await sourceUnchanged(), isTrue);
      final executableSha =
          (await sha256.bind(File(executable).openRead()).first).toString();
      final child = await runOwnedQualificationProcess(executable, [
        library,
        model,
        librarySha,
        modelSha,
        manifest,
        manifestSha,
        systemTemp().path,
        revision,
      ], seconds: 600);
      await File('${output.path}/stdout.log').writeAsBytes(child.stdout);
      await File('${output.path}/native-stderr.log').writeAsBytes(child.stderr);
      final text = utf8.decode(child.stdout, allowMalformed: true);
      final events = <Map<String, dynamic>>[];
      String? eventParseError;
      try {
        for (final line
            in text
                .split('\n')
                .where((line) => line.startsWith(thinkingEventPrefix))) {
          events.add(
            jsonDecode(line.substring(thinkingEventPrefix.length))
                as Map<String, dynamic>,
          );
        }
      } on Object catch (error) {
        eventParseError = error.runtimeType.toString();
      }
      final unchanged = await sourceUnchanged();
      await File('${output.path}/receipt.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'source_revision': revision,
          'source_tree': tree,
          'executable_sha256': executableSha,
          'library_sha256': librarySha,
          'model_sha256': modelSha,
          'runtime_manifest_sha256': manifestSha,
          'stdout_sha256': sha256.convert(child.stdout).toString(),
          'native_stderr_sha256': sha256.convert(child.stderr).toString(),
          'exit_code': child.exitCode,
          'outer_timeout': child.timedOut,
          'output_complete': child.outputComplete,
          'source_unchanged': unchanged,
          'events': events,
          'event_parse_error': eventParseError,
        }),
      );
      expect(
        child.timedOut,
        isFalse,
        reason:
            'Owned child exceeded 600s; retained work was killed without a cleanup-success claim.',
      );
      expect(
        child.exitCode,
        0,
        reason: '$text\n${utf8.decode(child.stderr, allowMalformed: true)}',
      );
      expect(unchanged, isTrue);
      expect(child.outputComplete, isTrue);
      expect(eventParseError, isNull);
      expect(events.map((event) => event['stage']), thinkingSuccessStages);
      expect(events.last['success'], isTrue);
    },
  );
}
