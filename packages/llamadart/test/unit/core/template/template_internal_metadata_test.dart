import 'package:llamadart/src/core/template/template_internal_metadata.dart';
import 'package:test/test.dart';

void main() {
  group('template internal metadata keys', () {
    test('expose stable key names for engine-handler coordination', () {
      expect(
        internalToolChoiceMetadataKey,
        equals('llamadart.internal.tool_choice'),
      );
      expect(
        internalParallelToolCallsMetadataKey,
        equals('llamadart.internal.parallel_tool_calls'),
      );
    });

    test('keys are distinct and namespaced', () {
      expect(
        internalToolChoiceMetadataKey,
        isNot(equals(internalParallelToolCallsMetadataKey)),
      );
      expect(internalToolChoiceMetadataKey, startsWith('llamadart.internal.'));
      expect(
        internalParallelToolCallsMetadataKey,
        startsWith('llamadart.internal.'),
      );
    });
  });
}
