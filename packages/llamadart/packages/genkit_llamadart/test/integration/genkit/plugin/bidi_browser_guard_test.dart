@TestOn('browser')
// This guard deliberately tests the opt-in experimental transport on Web.
// ignore_for_file: experimental_member_use
library;

import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/experimental.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Web bidi rejects before native runtime allocation and closes cleanly',
    () async {
      var allocations = 0;
      final plugin = LlamaDartBidiPlugin(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/missing.gguf'),
        ],
        runtimeFactory: () {
          allocations++;
          throw StateError('must not allocate');
        },
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final session = await ai.generateBidi(model: 'llamadart-bidi/local');
      await expectLater(
        session.stream.toList(),
        throwsA(
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.unimplemented,
          ),
        ),
      );
      await session.close();
      expect(allocations, 0);
    },
  );
}
