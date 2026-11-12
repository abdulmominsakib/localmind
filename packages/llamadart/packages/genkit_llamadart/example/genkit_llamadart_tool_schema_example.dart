import 'package:genkit/genkit.dart';
import 'package:genkit/plugin.dart' as api;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:schemantic/schemantic.dart';

import 'support/model_downloads.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1) throw ArgumentError('Supply at most one model source.');
  final prepared = await llamaDart.prepareModel(
    name: 'rich-tools',
    source: ModelSource.parse(
      args.firstOrNull ??
          'hf://unsloth/Qwen3-1.7B-GGUF/Qwen3-1.7B-Q4_K_M.gguf?revision=d7f544eead698dbd1f15126ef60b45a1e1933222',
    ),
    downloadManager: exampleDownloads,
    modelParams: const ModelParams(
      contextSize: 4096,
      device: ComputeDevice.cpu,
    ),
  );
  final ai = prepared.createGenkit(isDevEnv: false);
  var calls = 0;
  final lookup = ai.defineTool<Map<String, dynamic>, String>(
    name: 'lookup_demo_code',
    description: 'Retrieve a demo code. Use region null and tier 2.',
    inputSchema: SchemanticType.from(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'region': {
            'type': ['string', 'null'],
          },
          'tier': {
            'type': 'integer',
            'enum': [1, 2],
          },
        },
        'required': ['region', 'tier'],
        'additionalProperties': false,
      },
      parse: (value) => (value as Map).cast<String, dynamic>(),
    ),
    outputSchema: SchemanticType.string(),
    fn: (_, _) async {
      calls++;
      return ToolResult.response('NORTHSTAR-74261 (demo code)');
    },
  );
  final finish = ai.defineGenerateMiddleware<void>(
    name: 'finishAfterLookup',
    create: (_, _) => _FinishAfterLookup(),
  );
  try {
    final result = await ai.generate(
      system:
          'Call lookup_demo_code once with region null and tier 2. After the result, reply with the exact demo code.',
      prompt: 'Retrieve the current demo code. Do not guess.',
      tools: [lookup],
      toolChoice: ToolChoice.required,
      maxTurns: 3,
      use: [finish()],
      config: const LlamaDartGenerationConfig(
        temperature: 0,
        maxTokens: 256,
        seed: 42,
      ),
    );
    if (result.finishReason != FinishReason.stop || calls != 1) {
      throw result.cause ?? StateError('The demo tool loop did not complete.');
    }
    print(result.text);
  } finally {
    try {
      await prepared.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}

// Genkit retains required on later turns; the app permits a final answer after
// receiving the result instead of requesting another tool call.
class _FinishAfterLookup extends GenerateMiddleware {
  @override
  Future<ModelResponse> model(
    ModelRequest request,
    api.ActionFnArg<ModelResponseChunk, ModelRequest, void> ctx,
    Future<ModelResponse> Function(
      ModelRequest,
      api.ActionFnArg<ModelResponseChunk, ModelRequest, void>,
    )
    next,
  ) {
    if (request.messages.any((message) => message.role == Role.tool)) {
      request = ModelRequest(
        messages: request.messages,
        config: request.config,
        tools: request.tools,
        toolChoice: ToolChoice.none,
        output: request.output,
      );
    }
    return next(request, ctx);
  }
}
