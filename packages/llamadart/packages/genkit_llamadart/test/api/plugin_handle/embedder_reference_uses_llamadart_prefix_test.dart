import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('llamaDart.embedder uses the llamadart prefix', () {
    final embedder = llamaDart.embedder('local');

    expect(embedder.name, 'llamadart/local');
  });
}
