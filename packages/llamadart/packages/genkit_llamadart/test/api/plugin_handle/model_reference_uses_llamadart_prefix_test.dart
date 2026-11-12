import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('llamaDart.model uses the llamadart prefix', () {
    final model = llamaDart.model('local');

    expect(model.name, 'llamadart/local');
  });
}
