@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

// The parent test must not import the adapter. A broken public declaration is
// diagnosed by the standalone consumer, rather than preventing test startup.
const _consumers = <String, String>{
  'public': r'''
import 'package:genkit_llamadart/genkit_llamadart.dart' as api;

void main() {
  const definition = api.LlamaModelDefinition(name: 'chat', modelPath: 'fixture.gguf');
  const generation = api.LlamaDartGenerationConfig(maxTokens: 7);
  const embedding = api.LlamaDartEmbedConfig(normalize: false);
  final handle = api.llamaDart(models: [definition]);
  if (definition.name != 'chat' || definition.modelPath != 'fixture.gguf' || !definition.supportsTools || !definition.supportsEmbeddings || !definition.supportsConstrainedOutput) {
    throw StateError('Model registration defaults changed.');
  }
  if (generation.toJson()['maxTokens'] != 7 || embedding.toJson()['normalize'] != false) {
    throw StateError('Public request configuration was lost.');
  }
  api.llamaDart.model('chat');
  if (handle.name.isEmpty) throw StateError('Plugin name was lost.');
  print('consumer-contract-ok');
}
''',
  'experimental': r'''
import 'package:genkit_llamadart/experimental.dart';

Future<void> main() async {
  final plugin = LlamaDartBidiPlugin(models: []);
  await plugin.dispose();
  print('consumer-contract-ok');
}
''',
  'runtime_spi': r'''
import 'package:genkit_llamadart/genkit_llamadart.dart' as api;
import 'package:llamadart/llamadart.dart' as llama;

abstract class CustomRuntimeContract extends api.LlamaDartRuntime {
  CustomRuntimeContract() : super();
}

Future<void> request(api.LlamaDartRuntime runtime) async {
  await runtime.chatTemplate([], addAssistant: false, tools: [],
      toolChoice: llama.ToolChoice.none, parallelToolCalls: false,
      enableThinking: false, responseFormat: {'type': 'json_object'},
      sourceLangCode: 'en', targetLangCode: 'fr', includeTokenCount: true,
      chatTemplateKwargs: {'consumer': true});
  final stream = runtime.create([], tools: [], toolChoice: llama.ToolChoice.none,
      parallelToolCalls: false, enableThinking: false,
      sourceLangCode: 'en', targetLangCode: 'fr', chatTemplateKwargs: {});
  final subscription = stream.listen((_) {});
  await subscription.cancel();
  await runtime.generate('prompt', params: const llama.GenerationParams(), parts: []).drain<void>();
  await runtime.embedBatch(['text'], normalize: false);
  runtime.cancelGeneration();
  await runtime.dispose();
}

Future<void> probes(api.LlamaRuntimeCapabilityProvider capabilities,
    api.LlamaRuntimeInspectionProvider inspection,
    api.LlamaRuntimeEmbeddingProvider embedding,
    api.LlamaRuntimeScoringProvider scoring,
    api.LlamaRuntimeLoraProvider lora) async {
  await capabilities.capabilities;
  await inspection.contextSize;
  await inspection.tokenize('raw', addSpecial: true);
  await embedding.embeddingCapabilities;
  await embedding.embedContentBatch([], normalize: false);
  await scoring.scoreNextToken('raw', candidates: [1], topK: 2, reusePromptPrefix: false);
  await lora.supportsLiveLora;
  await lora.setLoraSource(llama.ModelSource.path('adapter.gguf'), scale: 0.5);
  await lora.removeLoraSource(llama.ModelSource.path('adapter.gguf'));
  await lora.clearLoras();
}

void factories(api.LlamaDartRuntimeFactory factory) {
  final api.LlamaDartRuntime runtime = factory();
  runtime.cancelGeneration();
}

void main() { print('consumer-contract-ok'); }
''',
};

void main() {
  test(
    'public entrypoints and runtime SPI retain standalone consumer compatibility',
    () async {
      final directory = await Directory(
        '.dart_tool',
      ).createTemp('public-consumer-');
      addTearDown(() => directory.delete(recursive: true));
      for (final entry in _consumers.entries) {
        final file = File('${directory.path}/${entry.key}.dart');
        await file.writeAsString(entry.value);
        final valid = await _analyzeConsumer(file);
        expect(
          valid.exitCode,
          0,
          reason: '${entry.key}: ${valid.stdout}\n${valid.stderr}',
        );
        final run = await Process.run(Platform.resolvedExecutable, [
          'run',
          file.path,
        ]);
        expect(
          run.exitCode,
          0,
          reason: '${entry.key}: ${run.stdout}\n${run.stderr}',
        );
        expect(run.stdout, contains('consumer-contract-ok'));

        final invalid = File('${directory.path}/${entry.key}_invalid.dart');
        await invalid.writeAsString(
          "${entry.value}\nContractMissingApi missingContractApi;\n",
        );
        final rejected = await _analyzeConsumer(invalid);
        expect(rejected.exitCode, isNot(0));
        expect(
          '${rejected.stdout}${rejected.stderr}',
          contains('ContractMissingApi'),
        );
        expect(
          '${rejected.stdout}${rejected.stderr}',
          contains('UNDEFINED_CLASS'),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<ProcessResult> _analyzeConsumer(File file) => Process.run(
  Platform.resolvedExecutable,
  ['analyze', '--format=machine', file.path],
);
