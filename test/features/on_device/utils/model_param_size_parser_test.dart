import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/model_param_size_parser.dart';

void main() {
  group('parseParameterSizeBillions', () {
    test('parses B', () => expect(parseParameterSizeBillions('model-7B'), 7.0));
    test('parses M', () => expect(parseParameterSizeBillions('model-135M'), closeTo(0.135, 1e-9)));
    test('parses MoE 8x7B', () => expect(parseParameterSizeBillions('Mixtral-8x7B'), 56.0));
    test('parses from repo id', () => expect(parseParameterSizeBillions('org/Qwen2.5-1.5B-Instruct'), 1.5));
    test('returns null for Qwen-Image-2.1', () => expect(parseParameterSizeBillions('Qwen-Image-2.1'), isNull));
    test('returns null for Q4_K_M', () => expect(parseParameterSizeBillions('Q4_K_M'), isNull));
    test('E2B parses to 2.0', () => expect(parseParameterSizeBillions('gemma-4-E2B-it'), 2.0));
    test('empty returns null', () => expect(parseParameterSizeBillions(''), isNull));
  });

  group('formatParameterSize', () {
    test('formats billions', () => expect(formatParameterSize(7.0), '7B'));
    test('formats millions', () => expect(formatParameterSize(0.135), '135M'));
  });
}
