import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

void main() {
  test('LoraAdapterConfig keeps a deprecated path as written', () {
    const config = LoraAdapterConfig(path: 'adapter.gguf', scale: 0.75);
    expect(config.path, 'adapter.gguf');
    expect(config.source, isNull);
    expect(config.scale, 0.75);
  });

  test('LoraAdapterConfig.source loads a local source by its path', () {
    final source = ModelSource.path('/models/adapter.gguf');
    final config = LoraAdapterConfig.source(source);
    expect(config.source, same(source));
    expect(config.path, '/models/adapter.gguf');
    expect(config.scale, 1.0);
  });

  test('LoraAdapterConfig.source names a remote source by its URL', () {
    final config = LoraAdapterConfig.source(
      ModelSource.parse('hf://owner/repo/adapter.gguf'),
      scale: 0.5,
    );
    expect(
      config.path,
      'https://huggingface.co/owner/repo/resolve/main/adapter.gguf'
      '?download=true',
    );
  });
}
