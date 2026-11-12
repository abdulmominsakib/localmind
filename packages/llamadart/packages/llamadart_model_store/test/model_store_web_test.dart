@TestOn('browser')
library;

import 'package:llamadart/llamadart.dart';
import 'package:llamadart_model_store/llamadart_model_store.dart';
import 'package:test/test.dart';

void main() {
  test('open reports that browsers have no shared model store', () async {
    await expectLater(
      ModelStore.open(directory: '/models', appId: 'app'),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });

  test('entry ids match the on-disk ids native stores use', () {
    final model = LlamaModel(
      ModelSource.parse('hf://owner/repo/model.gguf'),
      projector: ModelSource.parse('hf://owner/repo/mmproj.gguf'),
    );

    expect(
      ModelStore.entryIdFor(model),
      '292ebbecf6ab9efd5fa017606e35fd223d39fdce0fa1c489c9613884f8944820',
    );
  });
}
