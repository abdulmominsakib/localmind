import 'package:web/web.dart' show URL, document;

final RegExp _absolute = RegExp(r'^(?:[A-Za-z][A-Za-z0-9+.-]*:|//)');

/// [url] as the bridge fetches it: a path resolved against the document
/// base, and a URL with a scheme, such as `https:` or `blob:`, or with a host
/// (`//host/model.gguf`), unchanged.
///
/// The bridge runs in a worker by default, which resolves a path against its
/// own script, not the page that named it.
String webGpuDocumentUrl(String url) {
  if (url.isEmpty || _absolute.hasMatch(url)) return url;
  try {
    return URL(url, document.baseURI).href;
  } catch (_) {
    return url;
  }
}
