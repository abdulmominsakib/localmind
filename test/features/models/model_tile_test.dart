import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/models/components/model_tile.dart';

void main() {
  test('compactContext shortens round context sizes', () {
    expect(ModelTile.compactContext(128000), '128K');
    expect(ModelTile.compactContext(131072), '128K');
    expect(ModelTile.compactContext(262144), '256K');
    expect(ModelTile.compactContext(4096), '4K');
    expect(ModelTile.compactContext(4000), '4K');
    expect(ModelTile.compactContext(32768), '32K');
    expect(ModelTile.compactContext(1500), '1500');
  });
}
