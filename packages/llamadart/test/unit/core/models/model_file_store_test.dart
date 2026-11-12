import 'package:test/test.dart';

import 'package:llamadart/llamadart.dart';

void main() {
  test('a store defaults to the default resolver and download manager', () {
    final store = ModelFileStore();

    expect(store.resolver, isA<DefaultModelResolver>());
    expect(store.downloadManager, isA<DefaultModelDownloadManager>());
  });
}
