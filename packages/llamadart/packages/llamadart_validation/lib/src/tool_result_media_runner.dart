part of 'runner.dart';

/// Optional public tool-result media boundary; reference adapters without a
/// vision projector or capability report leave the case NOT_RUN.
abstract interface class ToolResultMediaValidationEngine {
  /// Whether the host loaded the profile's locked vision projector.
  bool get hasVisionProjector;

  /// Media kinds the public capability report accepts in tool results.
  Future<List<String>> toolResultMediaKinds();
}

mixin _PublicToolResultMediaValidation
    implements ToolResultMediaValidationEngine {
  String? get projector;
  LlamaEngine get _engine;
  @override
  bool get hasVisionProjector => projector != null;
  @override
  Future<List<String>> toolResultMediaKinds() async => [
    for (final kind in (await _engine.capabilities).toolResultMedia) kind.name,
  ]..sort();
}

extension _ToolResultMediaValidation on ValidationRunner {
  Future<Map<String, dynamic>> _toolResultMediaCase(String id) async {
    final Object media = engine;
    if (media is! ToolResultMediaValidationEngine ||
        !media.hasVisionProjector) {
      return {
        'status': 'NOT_RUN',
        'reason': 'Host did not load the locked vision projector',
      };
    }
    const fixture = toolResultMediaFixture;
    final toolName = fixture['tool'] as String;
    final question = fixture['question'] as String;
    final maxTokens = fixture['max_tokens'] as int;
    final tool = ToolDefinition(
      name: toolName,
      description: fixture['tool_description'] as String,
      parameters: const [],
    );
    _operationPhase = 'tool_result_media.capabilities';
    final kinds = await _checked(media.toolResultMediaKinds);
    final evidence = <String, dynamic>{'tool_result_media': kinds};
    _partialCaseEvidence = evidence;

    _operationPhase = 'tool_result_media.call';
    final call = await _checked(
      () => engine.generate(
        question,
        profile,
        tools: [tool],
        toolChoice: ToolChoice.required,
        enableThinking: false,
        maxTokens: fixture['call_max_tokens'] as int,
      ),
    );
    final name = StringBuffer();
    for (final delta in (call['tool_call_deltas'] as List).cast<Map>()) {
      name.write((delta['function'] as Map?)?['name'] ?? '');
    }
    evidence['call'] = {...call, 'reconstructed_name': name.toString()};

    final trials = <Map<String, dynamic>>[];
    evidence['trials'] = trials;
    for (final color in toolResultMediaColors) {
      _operationPhase = 'tool_result_media.$color';
      final image = toolResultMediaImage(color);
      final output = await _checked(
        () => engine.generate(
          question,
          profile,
          enableThinking: false,
          maxTokens: maxTokens,
          history: [
            LlamaChatMessage.fromText(role: LlamaChatRole.user, text: question),
            LlamaChatMessage.withContent(
              role: LlamaChatRole.assistant,
              content: [
                LlamaToolCallContent(
                  id: fixture['call_id'] as String,
                  name: toolName,
                  arguments: const {},
                  rawJson: '{}',
                ),
              ],
            ),
            LlamaChatMessage.withContent(
              role: LlamaChatRole.tool,
              content: [
                LlamaToolResultContent(
                  id: fixture['call_id'] as String,
                  name: toolName,
                  result: const {'ok': true},
                  content: [
                    LlamaImageContent(
                      bytes: base64Decode(image['png_base64'] as String),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
      trials.add({...output, 'color': color, 'image_sha256': image['sha256']});
    }
    final result = await _withDiagnostics({
      ...evidence,
      'expected':
          'The model calls the tool, then names the color of each photo a tool '
          'result carries and not the other photo\'s color',
    });
    return {
      ...result,
      'status':
          result['status'] == 'PASS' &&
              validToolResultMediaCaseEvidence(id, evidence, profile)
          ? 'PASS'
          : result['status'] == 'PASS'
          ? 'FAIL'
          : result['status'],
    };
  }
}
