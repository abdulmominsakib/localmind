@TestOn('browser')
library;

import 'package:llamadart/src/backends/webgpu/webgpu_url.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' show HTMLBaseElement, document, window;

void main() {
  void useBaseHref(String href) {
    final base = document.createElement('base') as HTMLBaseElement..href = href;
    document.head!.append(base);
    addTearDown(() => base.remove());
  }

  test('resolves a path against the document base, not the page URL', () {
    final origin = window.location.origin;
    useBaseHref('$origin/app/nested/');

    expect(
      webGpuDocumentUrl('models/tiny.gguf'),
      '$origin/app/nested/models/tiny.gguf',
    );
    expect(
      webGpuDocumentUrl('../shared/mmproj.gguf?v=2'),
      '$origin/app/shared/mmproj.gguf?v=2',
    );
    expect(webGpuDocumentUrl('/models/root.gguf'), '$origin/models/root.gguf');
  });

  test('returns a URL with a scheme or a host as written', () {
    useBaseHref('${window.location.origin}/app/');

    for (final url in const [
      'https://EXAMPLE.com/a b/model.gguf?sig=a%2Fb#part',
      'http://127.0.0.1:8080/model.gguf',
      'blob:https://app.example/3f2a',
      'data:application/octet-stream;base64,AA==',
      '//cdn.example/model.gguf',
      '',
    ]) {
      expect(webGpuDocumentUrl(url), url);
    }
  });
}
