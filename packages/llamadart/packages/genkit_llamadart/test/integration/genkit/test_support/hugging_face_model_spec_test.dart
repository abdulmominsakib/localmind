import 'package:test/test.dart';

import 'real_model_test_support.dart';

void main() {
  test('real-model specs pin immutable revisions and checksums', () {
    for (final spec in <HuggingFaceModelSpec>[
      integrationChatModel,
      integrationEmbedModel,
      integrationToolModel,
      integrationQwen35Model,
    ]) {
      expect(spec.revision, hasLength(40));
      expect(spec.expectedSha256, hasLength(64));
      expect(spec.downloadUrl, contains('/resolve/${spec.revision}/'));
      expect(spec.downloadUrl, isNot(contains('/resolve/main/')));
      expect(spec.cacheFileName, contains(spec.revision));
    }
  });
}
