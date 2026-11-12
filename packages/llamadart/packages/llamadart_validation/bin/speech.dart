import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/runtime_environment.dart';
import 'package:llamadart_validation/src/speech_edge_fixtures.dart';
import 'package:llamadart_validation/src/speech_runner.dart';
import 'package:path/path.dart' as p;

/// Runs locked GGUF speech packs; output is explicitly diagnostic qualification.
Future<void> main(List<String> args) async {
  Directory? output;
  var ownsOutput = false;
  try {
    final options = parseOptions(args, {
      'pack',
      'backend',
      'model',
      'projector',
      'out',
      'cache',
    });
    final pack = options['pack'];
    if (!['stt', 'tts'].contains(pack)) {
      throw ArgumentError('--pack must be stt or tts');
    }
    final backend = GpuBackend.values.byName(options['backend'] ?? 'cpu');
    if (!['cpu', 'metal', 'vulkan', 'cuda', 'opencl'].contains(backend.name)) {
      throw ArgumentError('Select an explicit supported native backend');
    }
    requireValidationRuntimeEnvironment();
    output = Directory(
      options['out'] ?? (throw ArgumentError('--out is required')),
    );
    if (output.existsSync()) throw StateError('Output must be a new directory');
    output.createSync(recursive: true);
    File(p.join(output.path, '.speech-owner')).createSync(exclusive: true);
    ownsOutput = true;
    final assets = Directory(
      p.join(
        File.fromUri(Platform.script).parent.parent.path,
        'assets',
        'speech',
      ),
    );
    final lock =
        jsonDecode(File(p.join(assets.path, '$pack.json')).readAsStringSync())
            as Map<String, dynamic>;
    final prepared = <String, ({String path, Map<String, dynamic> evidence})>{};
    for (final name in ['model', 'projector']) {
      final profile = ValidationProfile.fromJson({
        'schema_version': 1,
        'id': 'speech-$pack-$name',
        'runtime': 'gguf',
        'backend': backend.name,
        'model': lock[name],
        'context_size': 4096,
        'max_tokens': 512,
      });
      prepared[name] = await prepareModel(
        profile,
        Directory(
          options['cache'] ??
              p.join(
                Directory.current.path,
                '.dart_tool',
                'validation',
                'model-cache',
              ),
        ),
        suppliedPath: options[name],
      );
    }
    final fixture = pack == 'stt'
        ? lock['fixture'] as Map<String, dynamic>
        : null;
    final audio = fixture == null
        ? null
        : await File(
            p.join(assets.path, fixture['filename'] as String),
          ).readAsBytes();
    if (audio != null &&
        (audio.length != fixture!['bytes'] ||
            sha256.convert(audio).toString() != fixture['sha256'])) {
      throw const FormatException('Speech fixture lock mismatch');
    }
    var outputIndex = 0;
    final adapter = PublicSpeechValidationAdapter(
      model: prepared['model']!.path,
      projector: prepared['projector']!.path,
      backend: backend,
      pack: pack!,
      audio: audio,
      audioSeconds: audio == null ? null : speechFixtureSeconds(audio),
      audioPath: fixture == null
          ? null
          : p.join(assets.path, fixture['filename'] as String),
      reference: fixture?['reference'] as String?,
      saveAudio: (bytes) async {
        await File(
          p.join(output!.path, 'speech-${outputIndex++}.wav'),
        ).writeAsBytes(bytes);
      },
    );
    final edgeFixtures = audio == null
        ? const <SpeechEdgeFixture>[]
        : buildSpeechEdgeFixtures(audio);
    final result = await runSpeechValidation(
      adapter,
      checkBytes: pack == 'stt',
      edgeFixtures: edgeFixtures,
      checkTranscriptLimits: pack == 'stt',
      checkSynthesisInterrupts: pack == 'tts',
      operatingSystem: Platform.operatingSystem,
      backend: backend.name,
    );
    result.addAll({
      'edge_fixtures': [
        for (final fixture in edgeFixtures)
          {
            'id': fixture.id,
            'bytes': fixture.bytes.length,
            'sha256': sha256.convert(fixture.bytes).toString(),
            'sample_rate_hz': fixture.sampleRateHz,
            'channels': fixture.channelCount,
            'audio_seconds': fixture.seconds,
            'contract': fixture.contract.name,
            'reference_repeats': fixture.referenceRepeats,
            'rationale': fixture.rationale,
          },
      ],
      'pack': pack,
      'requested_backend': backend.name,
      'accelerator_execution_verified': false,
      'runtime_observations': adapter.observedRuntime,
      'os': Platform.operatingSystem,
      'dart': Platform.version,
      'model_lock': lock,
      'model_lock_hash': jsonHash(lock),
      'preparation': {
        for (final entry in prepared.entries) entry.key: entry.value.evidence,
      },
      'config': {
        'context_size': 4096,
        'stt_max_tokens': 512,
        'tts_seed': 1,
        'tts_max_frames': 384,
        'stt_truncation_context_size': speechTruncationContextSize,
        'tts_decode_cancel_frame_cap': speechDecodeCancelFrameCap,
        'tts_text': 'Hello from llamadart. The answer is forty two.',
        'language': 'English',
      },
    });
    await File(
      p.join(output.path, 'speech-results.json'),
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
    stdout.writeln(
      'Speech report: ${p.join(output.path, 'speech-results.json')}',
    );
    if (result['functional_pass'] != true) exitCode = 1;
  } catch (error) {
    // Do not expose URLs or caller paths through raw native error strings.
    stderr.writeln('Speech validation failed: ${error.runtimeType}');
    if (ownsOutput && output != null && output.existsSync()) {
      await File(p.join(output.path, 'failure.json')).writeAsString(
        jsonEncode({'qualified': false, 'error_type': '${error.runtimeType}'}),
      );
    }
    exitCode = 1;
  }
}
