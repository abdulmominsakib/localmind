import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' show URL, WorkerLocation, document;

import '../../core/cache_policy.dart';

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

/// Returns the browser-resolved HTTP(S) URL if it can be stored in Cache Storage.
String? webGpuPersistentCacheUrl(String reference) {
  if (reference.isEmpty) return null;
  try {
    final documentBase = globalContext.has('document') ? document.baseURI : '';
    final base = documentBase.isNotEmpty
        ? documentBase
        : globalContext.getProperty<WorkerLocation?>('location'.toJS)?.href;
    final url = base == null ? URL(reference) : URL(reference, base);
    final parsed = Uri.tryParse(url.href);
    if ((url.protocol == 'http:' || url.protocol == 'https:') &&
        url.host.isNotEmpty &&
        parsed != null &&
        parsed.host.isNotEmpty &&
        !hasPersistentCacheSensitiveUrlParts(url.href)) {
      return url.href;
    }
  } catch (_) {
    return null;
  }
  return null;
}
