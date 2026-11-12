@TestOn('vm && (mac-os || linux)')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 7))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

void main() {
  final systemTemp = useSuiteSystemTemp();
  test(
    'actual injected v1 service CPU chat, cancellation and reload qualify exact bytes',
    () async {
      String required(String name) {
        final value = Platform.environment[name]?.trim();
        if (value == null || value.isEmpty) fail('$name is required.');
        return value;
      }

      final schemaMode =
          Platform.environment['LITERT_LM_V1_SCHEMA_QUALIFICATION'] == '1';
      final library = required('LITERT_LM_V1_LIBRARY');
      final model = required('LITERT_LM_V1_MODEL');
      final librarySha = required('LITERT_LM_V1_LIBRARY_SHA256').toLowerCase();
      final modelSha = required('LITERT_LM_V1_MODEL_SHA256').toLowerCase();
      for (final hash in [librarySha, modelSha]) {
        expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      for (final path in [library, model]) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'Required local input is unavailable.',
        );
      }
      final status = await Process.run('git', ['status', '--porcelain']);
      expect(status.exitCode, 0);
      expect(
        '${status.stdout}'.trim(),
        isEmpty,
        reason: 'Qualification requires a clean exact checkout.',
      );
      final revision = await Process.run('git', ['rev-parse', 'HEAD']);
      final tree = await Process.run('git', ['rev-parse', 'HEAD^{tree}']);
      expect(revision.exitCode, 0);
      expect(tree.exitCode, 0);
      Future<bool> sourceUnchanged() async {
        final status = await Process.run('git', ['status', '--porcelain']);
        final current = await Process.run('git', ['rev-parse', 'HEAD']);
        return status.exitCode == 0 &&
            current.exitCode == 0 &&
            '${status.stdout}'.trim().isEmpty &&
            '${current.stdout}'.trim() == '${revision.stdout}'.trim();
      }

      final output = Directory(
        Platform.environment['LITERT_LM_V1_LOG_DIR'] ??
            '.dart_tool/litert_lm_v1_service/${DateTime.now().toUtc().millisecondsSinceEpoch}',
      );
      await output.create(recursive: true);
      final executable = '${output.absolute.path}/v1_service';
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        'test/fixtures/litert_lm_v1_service_qualification.dart',
        '-o',
        executable,
      ]).timeout(const Duration(minutes: 2));
      await File(
        '${output.path}/compile.log',
      ).writeAsString('${compiled.stdout}\n${compiled.stderr}');
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      expect(
        await sourceUnchanged(),
        isTrue,
        reason: 'Source changed while compiling the owned qualifier.',
      );
      final executableSha =
          (await sha256.bind(File(executable).openRead()).first).toString();
      final process = await Process.start(executable, [
        library,
        model,
        librarySha,
        modelSha,
        systemTemp().path,
        '${revision.stdout}'.trim(),
        if (schemaMode) 'json-schema',
      ]);
      final stdout = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      var timedOut = false;
      int? code;
      try {
        code = await process.exitCode.timeout(const Duration(seconds: 240));
      } on TimeoutException {
        timedOut = true;
        process.kill(ProcessSignal.sigkill);
        code = await process.exitCode;
      }
      final text = await stdout, native = await stderr;
      final unchanged = await sourceUnchanged();
      await File('${output.path}/stdout.log').writeAsString(text);
      await File('${output.path}/native-stderr.log').writeAsString(native);
      final events = text
          .split('\n')
          .where((line) => line.startsWith('LITERT_V1_SERVICE_EVENT '))
          .map(
            (line) =>
                jsonDecode(line.substring('LITERT_V1_SERVICE_EVENT '.length))
                    as Map<String, dynamic>,
          )
          .toList();
      await File('${output.path}/receipt.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'source_revision': '${revision.stdout}'.trim(),
          'qualification_mode': schemaMode ? 'json-schema' : 'service',
          'source_tree': '${tree.stdout}'.trim(),
          'executable_sha256': executableSha,
          'library_sha256': librarySha,
          'model_sha256': modelSha,
          'requested_backend': 'cpu',
          'requested_threads': 2,
          'exit_code': code,
          'outer_timeout': timedOut,
          'source_unchanged': unchanged,
          'events': events,
        }),
      );
      expect(
        timedOut,
        isFalse,
        reason:
            'Owned child exceeded its deadline; no cleanup success is claimed. Evidence: ${output.path}',
      );
      expect(code, 0, reason: '$text\n$native');
      expect(unchanged, isTrue, reason: 'Source changed during qualification.');
      final stages = events
          .where(
            (event) =>
                event['stage'] != 'schema_observation' &&
                event['stage'] != 'cancel_observation',
          )
          .map((event) => event['stage'])
          .toList();
      expect(
        stages,
        schemaMode
            ? [
                'identity',
                'schema_control',
                'schema_chat',
                'schema_followup',
                'cancel',
                'schema_after_cancel',
                'reload_schema',
                'reload_followup',
                'cleanup',
                'run_end',
              ]
            : [
                'identity',
                'chat',
                'cancel',
                'reload_chat',
                'cleanup',
                'run_end',
              ],
      );
      expect(events.last['success'], isTrue);
      if (schemaMode) {
        expect(events.first['qualification_mode'], 'json-schema');
        expect(
          events
              .where((event) => event['stage'] == 'schema_observation')
              .map((event) => event['request']),
          [
            'schema_control',
            'schema_chat',
            'schema_followup',
            'schema_after_cancel',
            'reload_schema',
            'reload_followup',
          ],
        );
        expect(
          events
              .where((event) => event['stage'] == 'cancel_observation')
              .length,
          1,
        );
        expect(
          events
              .where(
                (event) => [
                  'schema_control',
                  'schema_followup',
                  'reload_followup',
                ].contains(event['stage']),
              )
              .map((event) => (event['answer'] as String).trim()),
          ['BANANA', 'BANANA', 'BANANA'],
        );
        expect(
          events
              .where(
                (event) => [
                  'schema_chat',
                  'schema_after_cancel',
                  'reload_schema',
                ].contains(event['stage']),
              )
              .map((event) => event['decoded']),
          List.filled(3, {
            'café': '日本 😊',
            'count': 3,
            'active': true,
            'empty': null,
          }),
        );
      } else {
        expect(
          events
              .where(
                (event) =>
                    event['stage'] == 'chat' || event['stage'] == 'reload_chat',
              )
              .map((event) => event['answer']),
          ['4', '4'],
        );
      }
    },
  );
}
