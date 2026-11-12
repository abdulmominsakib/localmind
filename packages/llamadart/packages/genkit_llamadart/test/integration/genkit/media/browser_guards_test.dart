import 'package:genkit/genkit.dart' as genkit;
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

import '../../../core/runtime/test_support/fake_runtime.dart';
import '../actions/test_support/action_harness.dart';

void main() {
  test(
    'LiteRT and unverified custom runtimes reject combined constraints before generation',
    () async {
      for (final runtimeKind in [null, llama.LlamaRuntime.liteRtLm]) {
        final runtime = FakeRuntime()
          ..capabilitySnapshot = llama.LlamaEngineCapabilities(
            isSupported: true,
            runtime: runtimeKind,
            supportsMultiTurnChat: true,
            supportsToolCalling: true,
            supportsStructuredOutput: true,
            supportsGrammar: true,
          );
        await expectLater(
          testModelAction(runtime: runtime)(_constrainedRequest()),
          throwsA(
            isA<genkit.GenkitException>().having(
              (e) => e.status,
              'status',
              genkit.StatusCode.unimplemented,
            ),
          ),
        );
        expect(runtime.chatTemplateCallCount, 0);
        expect(runtime.generateCallCount, 0);
      }
    },
  );

  if (!const bool.fromEnvironment('dart.library.io')) {
    test('Web rejects native media models before capability probes', () async {
      final engine = _ImageEngine();
      final plugin = LlamaDartMediaPlugin(
        models: [LlamaDartImageModel(name: 'image', engine: engine)],
      );
      addTearDown(plugin.dispose);
      final action =
          (await plugin.init()).single as api.Model<Map<String, dynamic>>;
      await expectLater(
        action(
          genkit.ModelRequest(
            messages: [
              genkit.Message(
                role: genkit.Role.user,
                content: [genkit.TextPart(text: 'An apple')],
              ),
            ],
          ),
        ),
        throwsA(
          isA<genkit.GenkitException>().having(
            (e) => e.status,
            'status',
            genkit.StatusCode.unimplemented,
          ),
        ),
      );
      expect(engine.probes, 0);
    });
    test(
      'Web rejects combined tools even if a custom runtime reports llama.cpp support',
      () async {
        final runtime = FakeRuntime()
          ..capabilitySnapshot = const llama.LlamaEngineCapabilities(
            isSupported: true,
            runtime: llama.LlamaRuntime.llamaCpp,
            supportsMultiTurnChat: true,
            supportsToolCalling: true,
            supportsStructuredOutput: true,
            supportsGrammar: true,
          );
        await expectLater(
          testModelAction(runtime: runtime)(_constrainedRequest()),
          throwsA(isA<genkit.GenkitException>()),
        );
        expect(runtime.chatTemplateCallCount, 0);
        expect(runtime.generateCallCount, 0);
      },
    );
  }
}

genkit.ModelRequest _constrainedRequest() => genkit.ModelRequest(
  messages: [
    genkit.Message(
      role: genkit.Role.user,
      content: [genkit.TextPart(text: 'Answer')],
    ),
  ],
  tools: [
    genkit.ToolDefinition(
      name: 'lookup',
      description: 'Lookup',
      inputSchema: {'type': 'object', 'properties': <String, dynamic>{}},
    ),
  ],
  output: genkit.OutputConfig(format: 'json', constrained: true),
);

class _ImageEngine implements llama.ImageGenerationEngine {
  int probes = 0;
  @override
  Future<llama.ImageGenerationCapabilities> get capabilities async {
    probes++;
    throw StateError('Must not probe');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
