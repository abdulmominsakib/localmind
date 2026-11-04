import 'package:llamadart/src/core/models/config/lora_config.dart';
import 'package:test/test.dart';

void main() {
  test('LoraAdapterConfig stores path and scale', () {
    const config = LoraAdapterConfig(path: 'adapter.gguf', scale: 0.75);
    expect(config.path, 'adapter.gguf');
    expect(config.scale, 0.75);
  });
}
