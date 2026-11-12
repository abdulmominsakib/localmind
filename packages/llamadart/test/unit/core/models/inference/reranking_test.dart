import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('classifier metadata and scores snapshot caller collections', () {
    final scores = <double>[1, 2];
    final labels = <String?>['yes', 'no'];
    final result = LlamaRerankResult(
      index: 2,
      score: 1,
      classifierScores: scores,
      classifierLabels: labels,
    );
    final support = LlamaRerankingCapabilities(
      isSupported: true,
      classifierLabels: labels,
    );
    scores.clear();
    labels.clear();
    expect(result.classifierScores, [1, 2]);
    expect(result.classifierLabels, ['yes', 'no']);
    expect(support.classifierLabels, ['yes', 'no']);
    expect(() => result.classifierScores.add(3), throwsUnsupportedError);
    expect(() => support.classifierLabels.clear(), throwsUnsupportedError);
  });
}
