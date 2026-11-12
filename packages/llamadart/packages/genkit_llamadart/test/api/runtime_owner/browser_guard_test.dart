@TestOn('browser')
library;

import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Web rejects isolated native owners before allocating or loading',
    () async {
      var allocations = 0;
      final pool = LlamaDartRuntimePool(
        model: const LlamaModelDefinition(
          name: 'local',
          modelPath: '/missing/model.gguf',
        ),
        runtimeFactory: () {
          allocations++;
          throw StateError('must not allocate');
        },
        enablePromptCache: true,
      );
      await expectLater(pool.open(), throwsA(isA<LlamaUnsupportedException>()));
      expect(allocations, 0);
      await pool.close();
    },
  );
}
