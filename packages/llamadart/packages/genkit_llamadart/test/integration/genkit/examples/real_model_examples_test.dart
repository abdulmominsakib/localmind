@Tags(['real-model', 'example-model'])
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  test(
    'runnable chat, stream, tools, JSON, inspection and retrieval use pinned Qwen3.5',
    () async {
      if (Platform.environment['LLAMADART_RUN_EXAMPLE_PROOF'] != '1') {
        markTestSkipped(
          'Set LLAMADART_RUN_EXAMPLE_PROOF=1 and supply/download the pinned Qwen3.5 fixture.',
        );
        return;
      }
      final path = await resolveIntegrationQwen35ModelPath();
      if (path == null) return;
      Future<String> run(String name, [List<String> args = const []]) async {
        final result = await Process.run(
          Platform.resolvedExecutable,
          ['run', 'example/genkit_llamadart_${name}_example.dart', ...args],
          environment: {
            'LLAMADART_MODEL_SOURCE': path,
            'LLAMADART_PROMPT': name == 'agent'
                ? 'What is the demo temperature in Seoul? Use the lookup tool.'
                : 'Summarize this review: The battery lasts all day, but the speakers are weak.',
          },
        );
        expect(
          result.exitCode,
          0,
          reason: '$name: ${result.stdout}\n${result.stderr}',
        );
        return result.stdout.toString().trim();
      }

      final chat = await Process.run(Platform.resolvedExecutable, [
        'run',
        'example/genkit_llamadart_example.dart',
        path,
      ]);
      expect(chat.exitCode, 0, reason: '${chat.stdout}\n${chat.stderr}');
      expect(chat.stdout.toString().trim(), isNotEmpty);
      expect(await run('streaming'), isNotEmpty);
      expect(await run('inspection'), contains('Raw text tokens'));
      final resources = await run('resources');
      expect(resources, contains('30'));
      expect(resources.toLowerCase(), contains('days'));
      final agent = await run('agent');
      expect(agent, contains('Tool: lookup_demo_temperature(Seoul)'));
      expect(agent, contains('19'));
      final jsonOutput = await run('json');
      const marker = 'Parsed output: ';
      expect(jsonOutput, contains(marker));
      final review = jsonDecode(jsonOutput.split(marker).last) as Map;
      expect(review.keys, unorderedEquals(['summary', 'sentiment']));
      expect(
        review['summary'],
        isA<String>().having((s) => s.trim(), 'text', isNotEmpty),
      );
      expect(
        review['sentiment'],
        isA<String>().having((s) => s.trim(), 'text', isNotEmpty),
      );
      final retrieval = jsonDecode(await run('retrieval')) as Map;
      expect(retrieval['answer'], contains('17'));
      expect(retrieval['sources'], ['returns']);
      final unknown =
          jsonDecode(await run('retrieval', ['What is the CEO salary?']))
              as Map;
      expect(unknown['sources'], isEmpty);
      expect(unknown['answer'], contains("don't know"));
      final missingFact =
          jsonDecode(
                await run('retrieval', ['What is the returns manager salary?']),
              )
              as Map;
      expect(
        missingFact['answer'].toString().toLowerCase(),
        matches(
          r"not contain|not provided|not mentioned|no information|don't know|do not know",
        ),
      );
      expect(missingFact['answer'], isNot(matches(r'\d')));
      expect(missingFact['sources'], everyElement('returns'));
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
