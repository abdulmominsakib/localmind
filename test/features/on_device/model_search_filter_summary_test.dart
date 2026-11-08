import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/utils/filter_summary.dart';

void main() {
  test('formatFilterSummary includes framework + modality + size', () {
    final s = formatFilterSummary(
      litertEnabled: true,
      ggufEnabled: false,
      modalityLabel: 'Vision',
      minParamBillions: 1,
      maxParamBillions: 7,
    );
    expect(s, 'LiteRT · Vision · 1-7B');
  });

  test('formatFilterSummary none framework', () {
    final s = formatFilterSummary(
      litertEnabled: false,
      ggufEnabled: false,
      modalityLabel: null,
      minParamBillions: null,
      maxParamBillions: 10,
    );
    expect(s, 'No framework · <=10B');
  });
}