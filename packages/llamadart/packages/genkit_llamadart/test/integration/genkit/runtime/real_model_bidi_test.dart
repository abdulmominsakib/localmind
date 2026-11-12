@TestOn('vm')
@Tags(['real-model', 'bidi-model'])
// This proof explicitly opts into the experimental provider and Genkit API.
// ignore_for_file: experimental_member_use
library;

import 'dart:async';
import 'dart:io';

import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/experimental.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  test(
    'generateBidi runs two native text turns with complete isolated history',
    () async {
      if (Platform.environment['LLAMADART_RUN_BIDI_PROOF'] != '1') {
        markTestSkipped(
          'Set LLAMADART_RUN_BIDI_PROOF=1 for the bounded native bidi proof.',
        );
        return;
      }
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final observer = _Observer();
      final plugin = LlamaDartBidiPlugin(
        models: [
          LlamaModelDefinition(
            name: 'local',
            modelPath: path,
            modelParams: const ModelParams(
              device: ComputeDevice.cpu,
              contextSize: 1024,
              numberOfThreads: 1,
              numberOfThreadsBatch: 1,
            ),
          ),
        ],
        maxTurns: 2,
        observers: [observer],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final session = await ai.generateBidi(
        model: 'llamadart-bidi/local',
        config: const LlamaDartGenerationConfig(
          temperature: 0,
          maxTokens: 32,
          seed: 42,
        ),
      );
      final iterator = StreamIterator(session.stream);
      session.send('Say hello.');
      expect(await iterator.moveNext(), isTrue);
      final first = iterator.current.text;
      expect(first.trim(), isNotEmpty);
      session.send('What did I ask you to say?');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.text.trim(), isNotEmpty);
      expect(await iterator.moveNext(), isFalse);
      await session.close();
      expect(observer.turns, hasLength(2));
      expect(observer.turns.last.map((m) => m.content), [
        'Say hello.',
        first,
        'What did I ask you to say?',
      ]);
      final example = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/genkit_llamadart_bidi_example.dart',
        path,
      ]);
      expect(
        example.exitCode,
        0,
        reason: 'The experimental bidi CLI must complete successfully.',
      );
      expect('${example.stdout}'.trim(), isNotEmpty);
      print(
        'native bidi proof: real generateBidi registry resolution, two turns, complete prior answer and terminal cleanup pass',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

final class _Observer extends llama.LlamaEngineObserver {
  final List<List<llama.LlamaChatMessage>> turns = [];
  @override
  llama.LlamaOperationObserver? onStart(llama.LlamaOperation operation) {
    if (operation is llama.LlamaChatOperation) turns.add(operation.messages);
    return null;
  }
}
