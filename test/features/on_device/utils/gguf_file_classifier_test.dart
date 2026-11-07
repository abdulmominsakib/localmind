import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/gguf_file_classifier.dart';

void main() {
  group('gguf_file_classifier', () {
    test('split part detected', () => expect(isSplitModelFile('model-00001-of-00004.gguf'), isTrue));
    test('non-split', () => expect(isSplitModelFile('model.gguf'), isFalse));
    test('projector detected', () => expect(isProjectorFile('mmproj-model.gguf'), isTrue));
    test('primary model file', () => expect(isPrimaryModelFile('model.gguf'), isTrue));
    test('primary excludes projector', () => expect(isPrimaryModelFile('mmproj-model.gguf'), isFalse));
    test('primary excludes split', () => expect(isPrimaryModelFile('model-00001-of-00004.gguf'), isFalse));
  });
}
