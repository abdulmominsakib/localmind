import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  test(
    'wrapped media errors stay redacted before runtime initialization',
    () async {
      var factories = 0;
      final runtime = FakeRuntime()
        ..createChunks = [textChunk('ok'), stopChunk()];
      final plugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/unused'),
        ],
        runtimeFactory: () {
          factories++;
          return runtime;
        },
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final result = await ai.generate(
        model: llamaDart.model('local'),
        messages: [
          Message(
            role: Role.user,
            content: [
              MediaPart(
                media: Media(
                  url:
                      'https://USER_SENTINEL:PASS_SENTINEL@example.invalid/PATH_SENTINEL.wav?signature=QUERY_SENTINEL#FRAGMENT_SENTINEL',
                  contentType: 'audio/wav',
                ),
              ),
            ],
          ),
        ],
      );
      expect(result.finishReason, FinishReason.failed);
      expect('${result.error} ${result.cause}', isNot(contains('SENTINEL')));
      expect(
        result.cause,
        isA<GenkitException>().having(
          (e) => e.status,
          'status',
          StatusCode.invalidArgument,
        ),
      );
      expect(factories, 0);
      expect(runtime.initializeCount, 0);
      final recovered = await ai.generate(
        model: llamaDart.model('local'),
        prompt: 'hello',
      );
      expect(recovered.text, 'ok');
      expect(runtime.createCallCount, 1);
    },
  );

  test(
    'unsupported tool schemas cannot initialize a runtime or dispatch a handler',
    () async {
      var factories = 0;
      var calls = 0;
      final runtime = FakeRuntime();
      final plugin = LlamaDartPlugin(
        models: const [
          LlamaModelDefinition(name: 'local', modelPath: '/unused'),
        ],
        runtimeFactory: () {
          factories++;
          return runtime;
        },
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      for (final inputSchema in <Map<String, dynamic>>[
        for (final property in <Map<String, dynamic>>[
          {'type': 'string', 'pattern': '^a'},
          {'type': 'integer', 'minimum': 1},
          {'type': 'array'},
        ])
          {
            'type': 'object',
            'properties': {'value': property},
          },
        {
          r'$ref': '#/definitions/Input',
          r'$defs': {
            'Input': {'type': 'object'},
          },
        },
      ]) {
        final tool = ai.defineTool<Map<String, dynamic>, String>(
          name: 'lookup${ai.hashCode}${inputSchema.hashCode}',
          description: 'Lookup',
          inputSchema: SchemanticType.from(
            jsonSchema: inputSchema,
            parse: (v) => (v as Map).cast<String, dynamic>(),
          ),
          outputSchema: SchemanticType.string(),
          fn: (_, _) async {
            calls++;
            return ToolResult.response('done');
          },
        );
        final result = await ai.generate(
          model: llamaDart.model('local'),
          prompt: 'lookup',
          tools: [tool],
        );
        expect(result.finishReason, FinishReason.failed);
        expect(
          result.cause,
          isA<GenkitException>().having(
            (e) => e.status,
            'status',
            StatusCode.invalidArgument,
          ),
        );
      }
      expect(factories, 0);
      expect(runtime.createCallCount, 0);
      expect(calls, 0);
    },
  );

  for (final valid in [true, false]) {
    test(
      'Genkit owns ${valid ? 'valid null' : 'invalid non-null'} tool input handling',
      () async {
        final runtime = FakeRuntime()
          ..createScripts.addAll([
            [
              toolCallChunk(
                id: 'call',
                name: 'inspect',
                arguments: valid ? '{"value":null}' : '{"value":"wrong"}',
              ),
            ],
            [textChunk('verified'), stopChunk()],
          ]);
        final plugin = LlamaDartPlugin(
          models: const [
            LlamaModelDefinition(name: 'local', modelPath: '/unused'),
          ],
          runtimeFactory: () => runtime,
        );
        final ai = Genkit(plugins: [plugin], isDevEnv: false);
        addTearDown(() async {
          await plugin.dispose();
          await ai.shutdown();
        });
        var calls = 0;
        final tool = ai.defineTool<Map<String, dynamic>, String>(
          name: 'inspect',
          description: 'Inspect a required null',
          inputSchema: SchemanticType.from(
            jsonSchema: {
              'type': 'object',
              'properties': {
                'value': {'type': 'null'},
              },
              'required': ['value'],
            },
            parse: (v) {
              final input = (v as Map).cast<String, dynamic>();
              if (!input.containsKey('value') || input['value'] != null) {
                throw const FormatException('Expected required null.');
              }
              return input;
            },
          ),
          outputSchema: SchemanticType.string(),
          fn: (input, _) async {
            expect(input, {'value': null});
            calls++;
            return ToolResult.response('accepted');
          },
        );
        final result = await ai.generate(
          model: llamaDart.model('local'),
          prompt: 'inspect',
          tools: [tool],
          maxTurns: 2,
        );
        expect(runtime.lastTools!.single.toJsonSchema(), {
          'type': 'object',
          'properties': {
            'value': {'type': 'null'},
          },
          'required': ['value'],
        });
        expect(calls, valid ? 1 : 0);
        expect(
          result.finishReason,
          valid ? FinishReason.stop : FinishReason.failed,
        );
        expect(runtime.createCallCount, valid ? 2 : 1);
      },
    );
  }
}
