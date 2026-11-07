import 'package:llamadart/src/core/models/config/kv_cache_type.dart';
import 'package:test/test.dart';

void main() {
  test('KvCacheType enum contains expected values', () {
    expect(KvCacheType.values, contains(KvCacheType.f16));
    expect(KvCacheType.values, contains(KvCacheType.q8_0));
    expect(KvCacheType.values, contains(KvCacheType.q4_0));
    expect(KvCacheType.values.length, 3);
  });
}
