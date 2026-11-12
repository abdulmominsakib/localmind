import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/runtime_environment.dart';
import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:llamadart_validation/src/voice_runner.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  Directory? ownedOutput;
  try {
    final options = parseOptions(args, {
      'out',
      'cache',
      'chat-model',
      'chat-profile',
    });
    requireValidationRuntimeEnvironment();
    final output = Directory(
      options['out'] ?? (throw ArgumentError('--out required')),
    );
    if (output.existsSync()) throw StateError('Output must be new');
    output.createSync(recursive: true);
    File(p.join(output.path, '.speech-owner')).createSync(exclusive: true);
    ownedOutput = output;
    final assets = p.join(
      File.fromUri(Platform.script).parent.parent.path,
      'assets',
    );
    final cache = Directory(
      options['cache'] ??
          p.join(
            Directory.current.path,
            '.dart_tool',
            'validation',
            'model-cache',
          ),
    );
    final locks = <String, Map<String, dynamic>>{};
    final prepared = <String, ({String path, Map<String, dynamic> evidence})>{};
    for (final pack in ['stt', 'tts']) {
      final lock = locks[pack] =
          jsonDecode(
                File(p.join(assets, 'speech', '$pack.json')).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final name in ['model', 'projector']) {
        prepared['$pack-$name'] = await prepareModel(
          ValidationProfile.fromJson({
            'schema_version': 1,
            'id': 'voice-$pack-$name',
            'runtime': 'gguf',
            'backend': 'cpu',
            'model': lock[name],
          }),
          cache,
        );
      }
    }
    final chatId = options['chat-profile'] ?? 'gemma4-gguf-cpu';
    if (![
      'gemma4-gguf-cpu',
      'chat-gguf-cpu',
      'gemma4-litert-cpu',
      'qwen35-litert-cpu',
    ].contains(chatId)) {
      throw ArgumentError('Voice baseline requires a primary CPU chat profile');
    }
    final profile = ValidationProfile.fromJson(
      jsonDecode(
            File(p.join(assets, 'profiles', '$chatId.json')).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    prepared['chat'] = await prepareModel(
      profile,
      cache,
      suppliedPath: options['chat-model'],
    );
    final fixture = locks['stt']!['fixture'] as Map<String, dynamic>;
    final path = p.join(assets, 'speech', fixture['filename'] as String);
    final audio = await File(path).readAsBytes();
    if (audio.length != fixture['bytes'] ||
        sha256.convert(audio).toString() != fixture['sha256']) {
      throw const FormatException('Voice fixture hash/size mismatch');
    }
    final promptPrefix = 'Summarize this transcript in one short sentence: ';
    final result = await runVoiceRoundTrip(
      recognizer: PublicSpeechValidationAdapter(
        model: prepared['stt-model']!.path,
        projector: prepared['stt-projector']!.path,
        backend: GpuBackend.cpu,
        pack: 'stt',
        audio: audio,
        audioPath: path,
        audioSeconds: speechFixtureSeconds(audio),
        reference: fixture['reference'] as String,
        saveAudio: (_) async {},
      ),
      respond: (transcript) async {
        final chat = PublicValidationEngine();
        try {
          await chat.load(prepared['chat']!.path, profile);
          final response = await chat.generate(
            '$promptPrefix$transcript',
            profile,
          );
          return response['content'] as String;
        } finally {
          await chat.dispose();
        }
      },
      synthesizer: (response) => PublicSpeechValidationAdapter(
        model: prepared['tts-model']!.path,
        projector: prepared['tts-projector']!.path,
        backend: GpuBackend.cpu,
        pack: 'tts',
        text: response,
        saveAudio: (bytes) async {
          await File(p.join(output.path, 'response.wav')).writeAsBytes(bytes);
        },
      ),
    );
    result.addAll({
      'os': Platform.operatingSystem,
      'requested_backend': 'cpu',
      'model_locks': locks,
      'chat_profile': profile.toJson(),
      'prompt_prefix': promptPrefix,
      'preparation': {
        for (final entry in prepared.entries) entry.key: entry.value.evidence,
      },
    });
    await File(
      p.join(output.path, 'voice-results.json'),
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
    stdout.writeln(
      'Voice report: ${p.join(output.path, 'voice-results.json')}',
    );
    if (result['functional_pass'] != true) exitCode = 1;
  } catch (error) {
    stderr.writeln('Voice validation failed: ${error.runtimeType}');
    if (ownedOutput != null) {
      await File(p.join(ownedOutput.path, 'failure.json')).writeAsString(
        jsonEncode({'qualified': false, 'error_type': '${error.runtimeType}'}),
      );
    }
    exitCode = 1;
  }
}
