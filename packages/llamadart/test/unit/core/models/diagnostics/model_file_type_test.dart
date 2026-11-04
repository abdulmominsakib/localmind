import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  group('ModelFileType', () {
    test('uses value equality', () {
      expect(
        const ModelFileType(id: 15, name: 'Q4_K - Medium'),
        const ModelFileType(id: 15, name: 'Q4_K - Medium'),
      );
      expect(
        const ModelFileType(id: 15, name: 'Q4_K - Medium'),
        isNot(const ModelFileType(id: 7, name: 'Q8_0')),
      );
    });

    test('formats useful diagnostics', () {
      expect(
        const ModelFileType(id: 7, name: 'Q8_0').toString(),
        'ModelFileType(id: 7, name: Q8_0)',
      );
    });
  });
}
