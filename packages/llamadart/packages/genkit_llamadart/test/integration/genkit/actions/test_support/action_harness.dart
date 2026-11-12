import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:genkit_llamadart/src/core/runtime/engine_registry.dart';
import 'package:genkit_llamadart/src/integration/genkit/actions/embedder_action.dart';
import 'package:genkit_llamadart/src/integration/genkit/actions/model_action.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';

LlamaModelDefinition testModelDefinition({
  String name = 'local',
  String modelPath = '/tmp/model.gguf',
  bool supportsEmbeddings = true,
  bool supportsTools = true,
  bool supportsConstrainedOutput = true,
}) {
  return LlamaModelDefinition(
    name: name,
    modelPath: modelPath,
    supportsEmbeddings: supportsEmbeddings,
    supportsTools: supportsTools,
    supportsConstrainedOutput: supportsConstrainedOutput,
  );
}

EngineRegistry testRegistry({
  LlamaModelDefinition? definition,
  FakeRuntime? runtime,
}) {
  final resolvedDefinition = definition ?? testModelDefinition();
  final resolvedRuntime = runtime ?? FakeRuntime();

  return EngineRegistry(
    models: <LlamaModelDefinition>[resolvedDefinition],
    runtimeFactory: () => resolvedRuntime,
  );
}

genkit.Model<LlamaDartGenerationConfig> testModelAction({
  LlamaModelDefinition? definition,
  FakeRuntime? runtime,
}) {
  final resolvedDefinition = definition ?? testModelDefinition();
  final resolvedRuntime = runtime ?? FakeRuntime();

  return buildModelAction(
    definition: resolvedDefinition,
    registry: testRegistry(
      definition: resolvedDefinition,
      runtime: resolvedRuntime,
    ),
  );
}

genkit.Embedder<LlamaDartEmbedConfig> testEmbedderAction({
  LlamaModelDefinition? definition,
  FakeRuntime? runtime,
}) {
  final resolvedDefinition = definition ?? testModelDefinition();
  final resolvedRuntime = runtime ?? FakeRuntime();

  return buildEmbedderAction(
    definition: resolvedDefinition,
    registry: testRegistry(
      definition: resolvedDefinition,
      runtime: resolvedRuntime,
    ),
  );
}
