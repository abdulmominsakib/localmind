import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Checks adjacent-text equivalence, optionally interleaved with qualified media.
///
/// Runtime lanes can pass their loaded engine's content method and media parts.
/// Use deterministic inference and the same normalization setting for both calls.
Future<void> expectAdjacentTextEmbeddingEquivalence(
  Future<List<double>> Function(LlamaEmbeddingInput input) embed, {
  List<LlamaContentPart> before = const [],
  List<LlamaContentPart> after = const [],
  double tolerance = 1e-6,
}) async {
  final combined = await embed(
    LlamaEmbeddingInput([
      ...before,
      const LlamaTextContent('first \nsecondé'),
      ...after,
    ]),
  );
  final split = await embed(
    LlamaEmbeddingInput([
      ...before,
      const LlamaTextContent('first '),
      const LlamaTextContent(''),
      const LlamaTextContent('\nsecondé'),
      ...after,
    ]),
  );
  expect(split, hasLength(combined.length));
  for (var i = 0; i < combined.length; i++) {
    expect(split[i], closeTo(combined[i], tolerance));
  }
}
