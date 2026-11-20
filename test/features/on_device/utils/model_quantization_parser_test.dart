import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/model_quantization_parser.dart';

void main() {
  group('parseQuantization', () {
    test('Q4_K_M', () => expect(parseQuantization('model-Q4_K_M.gguf'), 'Q4_K_M'));
    test('Q8_0', () => expect(parseQuantization('model-q8_0.gguf'), 'Q8_0'));
    test('IQ2', () => expect(parseQuantization('model-IQ2_XS.gguf'), 'IQ2_XS'));
    test('null for no quant', () => expect(parseQuantization('readme.txt'), isNull));
  });
}
