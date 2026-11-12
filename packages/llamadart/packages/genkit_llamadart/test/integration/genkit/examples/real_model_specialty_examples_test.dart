@TestOn('vm')
@Tags(['real-model', 'example-model'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

import '../../../../example/decision/triage_flow.dart';

Future<String?> _fixture(String variable, String digest) async {
  if (Platform.environment['LLAMADART_RUN_SPECIALTY_EXAMPLE_PROOF'] != '1') {
    markTestSkipped('Set LLAMADART_RUN_SPECIALTY_EXAMPLE_PROOF=1.');
    return null;
  }
  final path = Platform.environment[variable];
  if (path == null) {
    markTestSkipped('Set $variable to the pinned fixture. No downloads.');
    return null;
  }
  expect((await sha256.bind(File(path).openRead()).first).toString(), digest);
  return File(path).absolute.path;
}

Future<Directory> _output() async {
  final directory = await Directory.systemTemp.createTemp('genkit-specialty-');
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<String> _run(
  String name, {
  List<String> args = const [],
  Map<String, String> environment = const {},
}) async {
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'example/genkit_llamadart_${name}_example.dart',
    ...args,
  ], environment: environment);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  try {
    final code = await process.exitCode.timeout(const Duration(minutes: 10));
    expect(code, 0, reason: '$name: ${await output}\n${await errors}');
    // The Dart CLI writes build-hook progress to stdout before example output.
    return (await output).replaceAll('Running build hooks...', '').trim();
  } finally {
    process.kill();
    await process.exitCode;
  }
}

String _words(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[^a-z ]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  test(
    'LoRA CLI applies its pinned adapter then generates without it',
    () async {
      final base = await _fixture(
        'LLAMADART_TEST_LORA_BASE',
        'cd144ca9826a7b009f8b841c247de6cf6c982735a1d13e9830cdd27447cfac16',
      );
      if (base == null) return;
      final adapter = await _fixture(
        'LLAMADART_TEST_LORA_ADAPTER',
        'ecb2cbbbc49ad140b1be6c073a6221c785c4101aedc88e92e8029b67b7cbb50a',
      );
      if (adapter == null) return;
      final output = await _run('lora', args: [base, adapter]);
      final completions = RegExp(
        r'^With adapter: ([\s\S]+)\nBase model: ([\s\S]+)$',
      ).firstMatch(output);
      expect(completions, isNotNull, reason: output);
      expect(completions!.group(1)!.trim(), isNotEmpty);
      expect(completions.group(2)!.trim(), isNotEmpty);
      expect(completions.group(1), isNot(completions.group(2)));
    },
    timeout: const Timeout(Duration(minutes: 11)),
  );

  test('decision CLI returns valid billing/refund/urgency JSON', () async {
    final encoder = await _fixture(
      'GENKIT_DECISION_ENCODER',
      '37c331ded9b71542541692c877e60452f873f430ef405c5158257e130bd890d7',
    );
    if (encoder == null) return;
    final head = await _fixture(
      'GENKIT_DECISION_HEAD',
      'c1ec428e034614c9373ebcf3fdc255d8eafcc04be9b2f0c2ffeef92bb1361b83',
    );
    if (head == null) return;
    final result =
        jsonDecode(
              await _run(
                'decision',
                environment: {
                  'GENKIT_DECISION_ENCODER': encoder,
                  'GENKIT_DECISION_HEAD': head,
                },
              ),
            )
            as Map<String, dynamic>;
    expect(await triageOutputSchema.validate(result), isEmpty);
    expect(result['model'], 'laya-rl-agent');
    final answers = result['answers'] as Map;
    expect(answers['department']['choice'], 'billing');
    expect(answers['refund']['noul'], greaterThan(0.7));
    expect(answers['urgency']['score'], inInclusiveRange(0, 2));
    expect(result['usage']['input_tokens'], greaterThan(0));
    expect(result['usage']['output_tokens'], 0);
  }, timeout: const Timeout(Duration(minutes: 11)));

  test('transcription CLI reproduces the pinned JFK recording', () async {
    final model = await _fixture(
      'GENKIT_ASR_MODEL',
      'bca259818b50ca7c4c05e9bdb35a5dc04fa039653a6d6f3f0f331f96f6aa1971',
    );
    if (model == null) return;
    final projector = await _fixture(
      'GENKIT_ASR_PROJECTOR',
      '41a342b5e4c514e968cb756de6cd1b7be39eff43c44c57a2ef5fc6522e36603d',
    );
    if (projector == null) return;
    const audio = 'test/integration/genkit/media/fixtures/jfk.wav';
    expect(
      (await sha256.bind(File(audio).openRead()).first).toString(),
      '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e',
    );
    final text = await _run('transcription', args: [audio, model, projector]);
    expect(
      _words(text),
      'and so my fellow americans ask not what your country can do for you ask what you can do for your country',
    );
    expect(text, isNot(contains('<asr_text>')));
  }, timeout: const Timeout(Duration(minutes: 11)));

  test('speech CLI writes non-silent mono 24 kHz PCM WAV', () async {
    final model = await _fixture(
      'GENKIT_TTS_MODEL',
      '8d18c94acb2addd042f97da63c98be144eafa76d0d9495177eab65130cf85129',
    );
    if (model == null) return;
    final projector = await _fixture(
      'GENKIT_TTS_PROJECTOR',
      '6fd65188839bcd6ecc91b277ad471e22a0edfada4699a0fe82f1165c18cfcce2',
    );
    if (projector == null) return;
    final output = File('${(await _output()).path}/speech.wav');
    expect(
      await _run('speech', args: [output.path, model, projector]),
      'Saved WAV.',
    );
    final bytes = await output.readAsBytes();
    expect(bytes.length, greaterThan(44));
    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(bytes.sublist(8, 16)), 'WAVEfmt ');
    expect(ascii.decode(bytes.sublist(36, 40)), 'data');
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(4, Endian.little), bytes.length - 8);
    expect(header.getUint16(20, Endian.little), 1); // PCM
    expect(header.getUint16(22, Endian.little), 1); // Mono
    expect(header.getUint32(24, Endian.little), 24000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), bytes.length - 44);
    expect((bytes.length - 44).isEven, isTrue);
    expect(bytes.skip(44).any((byte) => byte != 0), isTrue);
  }, timeout: const Timeout(Duration(minutes: 11)));

  test('image-generation CLI writes a nonuniform 256x256 PNG', () async {
    final model = await _fixture(
      'GENKIT_IMAGE_MODEL',
      '409ab23582ee074c6b9d5395784fc0741b0599fb9d138686c69087c71678eb6a',
    );
    if (model == null) return;
    final output = File('${(await _output()).path}/image.png');
    expect(await _run('image', args: [output.path, model]), 'Saved PNG.');
    final bytes = await output.readAsBytes();
    expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final decoded = image.decodePng(bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 256);
    final first = decoded.getPixel(0, 0);
    final reference = (first.r, first.g, first.b);
    expect(decoded.any((p) => (p.r, p.g, p.b) != reference), isTrue);
  }, timeout: const Timeout(Duration(minutes: 11)));
}
