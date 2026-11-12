@Tags(['real-model', 'decision-model'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../../example/decision/triage_flow.dart';

Future<String> _fixture(String variable, String hash) async {
  final path = Platform.environment[variable]!;
  expect((await sha256.bind(File(path).openRead()).first).toString(), hash);
  return path;
}

Future<File> _mismatchedHead(String path, Directory directory) async {
  final target = File('${directory.path}/mismatched.safetensors');
  await File(path).copy(target.path);
  final file = await target.open(mode: FileMode.append);
  try {
    await file.setPosition(0);
    final length = ByteData.sublistView(
      await file.read(8),
    ).getUint64(0, Endian.little);
    final header =
        jsonDecode(utf8.decode(await file.read(length)))
            as Map<String, dynamic>;
    header['head.layers.0.norm1.weight']['shape'] = [512, 2];
    final json = utf8.encode(jsonEncode(header));
    expect(json.length, lessThanOrEqualTo(length));
    final bytes = Uint8List(length)
      ..fillRange(0, length, 32)
      ..setRange(0, json.length, json);
    await file.setPosition(8);
    await file.writeFrom(bytes);
  } finally {
    await file.close();
  }
  return target;
}

void main() {
  test(
    'pinned Laya runs all three decision tasks through the typed Genkit flow',
    () async {
      if (!Platform.environment.containsKey('GENKIT_DECISION_ENCODER') ||
          !Platform.environment.containsKey('GENKIT_DECISION_HEAD')) {
        markTestSkipped(
          'Set GENKIT_DECISION_ENCODER and GENKIT_DECISION_HEAD.',
        );
        return;
      }
      final encoder = await _fixture(
        'GENKIT_DECISION_ENCODER',
        '37c331ded9b71542541692c877e60452f873f430ef405c5158257e130bd890d7',
      );
      final head = await _fixture(
        'GENKIT_DECISION_HEAD',
        'c1ec428e034614c9373ebcf3fdc255d8eafcc04be9b2f0c2ffeef92bb1361b83',
      );
      final decisions = await llama.DecisionEngine.load(
        llama.DecisionModel(
          encoder: llama.ModelSource.path(encoder),
          head: llama.ModelSource.path(head),
        ),
        params: const llama.DecisionModelParams(
          device: llama.ComputeDevice.cpu,
          threads: 4,
        ),
      );
      final ai = Genkit(isDevEnv: false);
      addTearDown(() async {
        try {
          await decisions.dispose();
        } finally {
          await ai.shutdown();
        }
      });
      expect((await decisions.capabilities).isSupported, isTrue);
      expect(decisions.info.deviceName.toLowerCase(), contains('cpu'));
      final triage = defineDecisionTriageFlow(ai, decisions);
      final chunks = <void>[];
      final result = (await triage.runRaw(
        'We were billed twice for March. Please refund the duplicate today.',
        onChunk: chunks.add,
      )).result;
      expect(chunks, isEmpty);
      expect(result['model'], 'laya-rl-agent');
      expect(result.toString(), isNot(contains(encoder)));
      expect(result.toString(), isNot(contains(head)));
      expect(await triageOutputSchema.validate(result), isEmpty);
      final answers = result['answers'] as Map;
      expect(answers['department']['choice'], 'billing');
      expect(answers['refund']['noul'], greaterThan(0.7));
      expect(answers['urgency']['score'], inInclusiveRange(0, 2));
      expect(result['usage']['input_tokens'], greaterThan(0));
      expect(result['usage']['output_tokens'], 0);
      for (final answer in answers.values) {
        expect((answer['confidence'] as num).isFinite, isTrue);
        if (answer['probabilities'] case final Map probabilities) {
          expect(
            probabilities.values.cast<num>().fold<num>(0, (a, b) => a + b),
            closeTo(1, 1e-6),
          );
        }
      }
      await expectLater(
        triage('  '),
        throwsA(
          isA<GenkitException>().having(
            (error) => error.status,
            'status',
            StatusCode.invalidArgument,
          ),
        ),
      );
      await expectLater(
        triage('invalid\u0000ticket'),
        throwsA(
          isA<GenkitException>()
              .having(
                (error) => error.status,
                'status',
                StatusCode.invalidArgument,
              )
              .having(
                (error) => error.message,
                'safe message',
                isNot(contains('invalid\u0000ticket')),
              )
              .having(
                (error) => error.toString(),
                'safe diagnostic',
                isNot(contains(encoder)),
              ),
        ),
      );
      final cancelled = CancellationController()..cancel();
      await expectLater(
        triage('refund', cancel: cancelled.token),
        throwsA(isA<CancelledException>()),
      );
      await expectLater(triage.runRaw(42), throwsA(isA<TypeError>()));
      await decisions.dispose();
      await expectLater(
        triage('refund'),
        throwsA(
          isA<GenkitException>().having(
            (error) => error.status,
            'status',
            StatusCode.failedPrecondition,
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'attached decision flow preserves its encoder and rejects unloaded capability',
    () async {
      if (!Platform.environment.containsKey('GENKIT_DECISION_ENCODER') ||
          !Platform.environment.containsKey('GENKIT_DECISION_HEAD')) {
        markTestSkipped(
          'Set GENKIT_DECISION_ENCODER and GENKIT_DECISION_HEAD.',
        );
        return;
      }
      final encoderPath = await _fixture(
        'GENKIT_DECISION_ENCODER',
        '37c331ded9b71542541692c877e60452f873f430ef405c5158257e130bd890d7',
      );
      final headPath = await _fixture(
        'GENKIT_DECISION_HEAD',
        'c1ec428e034614c9373ebcf3fdc255d8eafcc04be9b2f0c2ffeef92bb1361b83',
      );
      final encoder = await llama.LlamaEngine.load(
        llama.LlamaModel(llama.ModelSource.path(encoderPath)),
        params: const llama.DecisionModelParams(
          device: llama.ComputeDevice.cpu,
          threads: 4,
        ).encoderModelParams,
      );
      addTearDown(encoder.dispose);
      expect(
        (await llama.DecisionEngine.capabilitiesFor(encoder)).isSupported,
        isTrue,
      );
      final malformed = await Directory.systemTemp.createTemp(
        'genkit-decision-head-',
      );
      addTearDown(() => malformed.delete(recursive: true));
      final badHead = File('${malformed.path}/bad.safetensors');
      await badHead.writeAsString('not a safetensors head');
      await expectLater(
        llama.DecisionEngine.attach(
          encoder,
          head: llama.ModelSource.path(badHead.path),
        ),
        throwsA(isA<llama.LlamaException>()),
      );
      expect(encoder.isReady, isTrue);
      final mismatched = await _mismatchedHead(headPath, malformed);
      await expectLater(
        llama.DecisionEngine.attach(
          encoder,
          head: llama.ModelSource.path(mismatched.path),
        ),
        throwsA(
          isA<llama.LlamaModelException>().having(
            (error) => error.message,
            'encoder/head dimension validation',
            allOf(
              contains('head.layers.0.norm1.weight'),
              contains('[512, 2]'),
              contains('[1024]'),
            ),
          ),
        ),
      );
      expect(encoder.isReady, isTrue);
      final decisions = await llama.DecisionEngine.attach(
        encoder,
        head: llama.ModelSource.path(headPath),
      );
      addTearDown(decisions.dispose);
      final ai = Genkit(isDevEnv: false);
      addTearDown(ai.shutdown);
      final triage = defineDecisionTriageFlow(ai, decisions);
      final results = await Future.wait([
        triage('We were billed twice. Please refund the duplicate.'),
        triage('The server is down and reports an internal error.'),
      ]);
      expect(results[0]['answers']['department']['choice'], 'billing');
      expect(results[1]['answers']['department']['choice'], 'technical');
      await decisions.dispose();
      expect(encoder.isReady, isTrue);
      final attachedAgain = await llama.DecisionEngine.attach(
        encoder,
        head: llama.ModelSource.path(headPath),
      );
      addTearDown(attachedAgain.dispose);
      final secondAi = Genkit(isDevEnv: false);
      addTearDown(secondAi.shutdown);
      final unavailable = defineDecisionTriageFlow(secondAi, attachedAgain);
      await encoder.dispose();
      await expectLater(
        unavailable('refund'),
        throwsA(
          isA<GenkitException>().having(
            (error) => error.status,
            'status',
            StatusCode.unimplemented,
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
