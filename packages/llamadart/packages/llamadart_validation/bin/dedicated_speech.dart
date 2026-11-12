import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/src/runtime_environment.dart';
import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  Directory? owned;
  try {
    final options = parseOptions(args, {
      'pack',
      'backend',
      'model',
      'tokenizer',
      'out',
      'cache',
    });
    if (options['pack'] != 'litert-asr' || options['backend'] != 'cpu') {
      throw ArgumentError('Dedicated speech requires litert-asr and cpu');
    }
    requireValidationRuntimeEnvironment();
    final output = Directory(
      options['out'] ?? (throw ArgumentError('--out required')),
    );
    if (output.existsSync()) throw StateError('Output must be new');
    output.createSync(recursive: true);
    File(p.join(output.path, '.speech-owner')).createSync(exclusive: true);
    owned = output;
    final assets = p.join(
      File.fromUri(Platform.script).parent.parent.path,
      'assets',
      'speech',
    );
    final lock =
        jsonDecode(File(p.join(assets, 'litert-asr.json')).readAsStringSync())
            as Map<String, dynamic>;
    for (final name in ['model', 'tokenizer']) {
      final file = File(
        options[name] ?? (throw ArgumentError('--$name required')),
      );
      if (await file.length() != lock[name]['bytes'] ||
          (await sha256.bind(file.openRead()).first).toString() !=
              lock[name]['sha256']) {
        throw FormatException('Locked $name mismatch');
      }
    }
    final fixture = lock['fixture'] as Map<String, dynamic>;
    final wav = await File(
      p.join(assets, fixture['filename'] as String),
    ).readAsBytes();
    if (wav.length != fixture['bytes'] ||
        sha256.convert(wav).toString() != fixture['sha256']) {
      throw const FormatException('Fixture mismatch');
    }
    final result = await runSpeechValidation(
      PublicDedicatedSpeechAdapter(
        model: SpeechToTextModel(
          ModelSource.path(options['model']!),
          tokenizer: ModelSource.path(options['tokenizer']!),
          adapter: const LiteRtLmAsrAdapter(
            LiteRtLmAsrModelPreset.moonshineTiny,
          ),
        ),
        wav: wav,
        reference: fixture['reference'] as String,
      ),
      operatingSystem: Platform.operatingSystem,
      backend: 'cpu',
    );
    result.addAll({
      'pack': 'litert-asr',
      'backend': 'cpu',
      'model_lock': lock,
      'os': Platform.operatingSystem,
      'sample_rate_hz': 16000,
      'pcm_push_samples': 1600,
    });
    await File(
      p.join(output.path, 'speech-results.json'),
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
    stdout.writeln(
      'Speech report: ${p.join(output.path, 'speech-results.json')}',
    );
    if (result['functional_pass'] != true) exitCode = 1;
  } catch (error) {
    stderr.writeln('Dedicated speech validation failed: ${error.runtimeType}');
    if (owned != null) {
      await File(p.join(owned.path, 'failure.json')).writeAsString(
        jsonEncode({'qualified': false, 'error_type': '${error.runtimeType}'}),
      );
    }
    exitCode = 1;
  }
}
